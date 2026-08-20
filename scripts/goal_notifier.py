"""Gol / maç başlangıcı bildirimi üreticisi (AI Sport Agent -> Supabase).

NEDEN VAR
---------
Depoda gol bildirimi için bir Postgres trigger'ı var
(`trg_match_events_notifications`, `supabase/migrations/20260322000000_...`),
ama `public.matches` tablosundaki skor değişimini dinliyor. Uygulama artık
maçları AI Sport Agent'tan okuduğu için o tablo güncellenmiyor ve trigger hiç
ateşlenmiyor. Ayrıca favoriler agent maç kimliğiyle saklanıyor, trigger ise
Supabase kimlikleriyle eşleştirme yapıyor — iki taraf hiç buluşmuyor.

Bu script o boşluğu kapatır: agent'ın canlı skorlarını izler, değişimi yakalar
ve `notifications` tablosuna yazar. `fcm-push-trigger` edge function'ı bu
INSERT'i görüp push gönderir.

TASARIM NOTLARI
---------------
* Kimlik: `external_match_id` = agent maç UUID'si, `source` = 'agent'.
  `notifications` üzerindeki (user_id, source, external_match_id, event_key)
  tekillik indeksi sayesinde aynı gol iki kez yazılamaz - script yeniden
  başlasa veya durum dosyası kaybolsa bile mükerrer bildirim gitmez.
* `match_id` kolonu `public.matches`'e FK'li; agent kimliği oraya YAZILAMAZ,
  bu yüzden NULL bırakılır ve dış kimlik ayrı kolonda tutulur.
* Kullanıcı tercihi (`notify_goals` / `notify_match_start`) kontrol edilir.
  Eski trigger bunu hiç okumuyordu: kullanıcı "Goals" kapatsa bile bildirim
  gidiyordu.
* Skor DÜŞÜŞLERİ yok sayılır (sağlayıcı düzeltmesi olabilir); sadece artış gol
  sayılır.
* Bir maç ilk kez görüldüğünde bildirim üretilmez, sadece referans alınır.
  Aksi halde script her başladığında o ana kadarki tüm goller bildirim olurdu.

KULLANIM
--------
    python scripts/goal_notifier.py            # tek tur
    python scripts/goal_notifier.py --loop 60  # 60 sn aralikla surekli
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys
import time
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import httpx

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bulletin_bridge import _service_key_from_cli  # noqa: E402

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://nigatikzsnxdqdwwqewr.supabase.co")
AGENT_API = os.environ.get("AGENT_API_URL", "http://127.0.0.1:8001/api/v1")
STATE_FILE = pathlib.Path(__file__).parent / ".goal_notifier_state.json"
TZ = ZoneInfo("Europe/Istanbul")


def _log(msg: str) -> None:
    print("[{:%Y-%m-%d %H:%M:%S}] {}".format(datetime.now(TZ), msg), flush=True)


def _load_state() -> dict:
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def _save_state(state: dict) -> None:
    # Durum dosyasi sadece hizlandirma amacli; kaybolursa tekillik indeksi korur.
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state), encoding="utf-8")
    tmp.replace(STATE_FILE)


def _fetch_agent_matches(client: httpx.Client) -> list[dict]:
    """Bugun ve dun: gece yarisini asan maclar icin dunu de tariyoruz."""
    seen: dict[str, dict] = {}
    today = datetime.now(TZ).date()
    for offset in (0, -1):
        day = (today + timedelta(days=offset)).isoformat()
        try:
            resp = client.get(
                AGENT_API + "/mobile/matches/live", params={"date": day}, timeout=60
            )
            resp.raise_for_status()
        except httpx.HTTPError as exc:
            _log("uyari: agent {} okunamadi: {}".format(day, exc))
            continue
        for match in resp.json().get("matches") or []:
            if match.get("id"):
                seen[match["id"]] = match
    return list(seen.values())


def _team_names(match: dict) -> tuple[str, str]:
    home = match.get("home_team") or match.get("homeTeam") or {}
    away = match.get("away_team") or match.get("awayTeam") or {}
    home_name = home.get("name") if isinstance(home, dict) else str(home)
    away_name = away.get("name") if isinstance(away, dict) else str(away)
    return home_name or "Ev sahibi", away_name or "Deplasman"


def _score(match: dict) -> tuple[int | None, int | None]:
    def num(*keys: str) -> int | None:
        for key in keys:
            value = match.get(key)
            if isinstance(value, bool):
                continue
            if isinstance(value, int):
                return value
            if isinstance(value, str) and value.isdigit():
                return int(value)
        return None

    return num("home_score", "homeScore"), num("away_score", "awayScore")


def _favorites(client: httpx.Client, headers: dict, match_id: str) -> list[str]:
    resp = client.get(
        SUPABASE_URL + "/rest/v1/user_favorite_matches",
        params={"select": "user_id", "match_id": "eq." + match_id},
        headers=headers,
        timeout=30,
    )
    resp.raise_for_status()
    return [row["user_id"] for row in resp.json() if row.get("user_id")]


def _prefs(client: httpx.Client, headers: dict, user_ids: list[str]) -> dict[str, dict]:
    if not user_ids:
        return {}
    joined = ",".join('"{}"'.format(uid) for uid in user_ids)
    resp = client.get(
        SUPABASE_URL + "/rest/v1/user_notification_preferences",
        params={
            "select": "user_id,notify_goals,notify_match_start",
            "user_id": "in.({})".format(joined),
        },
        headers=headers,
        timeout=30,
    )
    resp.raise_for_status()
    return {row["user_id"]: row for row in resp.json()}


def _insert(client: httpx.Client, headers: dict, rows: list[dict]) -> int:
    if not rows:
        return 0
    # Tekillik indeksine takilanlari sessizce atla: ayni gol tekrar yazilmasin.
    # "Prefer: resolution=ignore-duplicates" TEK BASINA yetmez; PostgREST bunu
    # yalnizca on_conflict verildiginde uygular. Aksi halde 409 doner ve her
    # tekrarda log'a gereksiz HATA satiri duser.
    post_headers = dict(headers)
    post_headers["Prefer"] = "resolution=ignore-duplicates,return=representation"
    resp = client.post(
        SUPABASE_URL + "/rest/v1/notifications",
        headers=post_headers,
        params={"on_conflict": "user_id,source,external_match_id,event_key"},
        json=rows,
        timeout=60,
    )
    if resp.status_code >= 400:
        _log("HATA: bildirim yazilamadi {}: {}".format(resp.status_code, resp.text[:200]))
        return 0
    try:
        return len(resp.json())
    except ValueError:
        return len(rows)


def run_once(client: httpx.Client, headers: dict, state: dict) -> None:
    matches = _fetch_agent_matches(client)
    if not matches:
        _log("agent'tan mac gelmedi")
        return

    events: list[tuple[dict, str, str, str]] = []

    for match in matches:
        match_id = match["id"]
        home, away = _team_names(match)
        home_score, away_score = _score(match)
        status = (match.get("status") or "").lower()
        prev = state.get(match_id) or {}

        if home_score is not None and away_score is not None:
            prev_home = prev.get("home_score")
            prev_away = prev.get("away_score")
            # Ilk gorus: referans al, bildirim uretme.
            if prev_home is not None and prev_away is not None:
                if home_score > prev_home:
                    events.append((
                        match,
                        "goal:{}-{}:home".format(home_score, away_score),
                        "🚨 GOL! " + home,
                        "{} golü buldu! Skor: {} - {} ({})".format(
                            home, home_score, away_score, away
                        ),
                    ))
                if away_score > prev_away:
                    events.append((
                        match,
                        "goal:{}-{}:away".format(home_score, away_score),
                        "🚨 GOL! " + away,
                        "{} golü buldu! Skor: {} - {} ({})".format(
                            away, home_score, away_score, home
                        ),
                    ))

        if prev.get("status") not in (None, "live") and status == "live":
            events.append((
                match,
                "match_start",
                "⚽ Maç Başladı!",
                "{} - {} maçı an itibariyle başladı.".format(home, away),
            ))

        state[match_id] = {
            "home_score": home_score,
            "away_score": away_score,
            "status": status,
        }

    if not events:
        _log("{} mac tarandi, yeni olay yok".format(len(matches)))
        _save_state(state)
        return

    written = 0
    for match, event_key, title, message in events:
        match_id = match["id"]
        users = _favorites(client, headers, match_id)
        if not users:
            continue
        prefs = _prefs(client, headers, users)
        kind = "MATCH_START" if event_key == "match_start" else "GOAL"
        pref_col = "notify_match_start" if kind == "MATCH_START" else "notify_goals"

        rows = []
        for uid in users:
            # Tercih satiri yoksa varsayilan acik (uygulamadaki varsayilan da bu).
            if prefs.get(uid, {}).get(pref_col, True) is False:
                continue
            rows.append({
                "user_id": uid,
                "match_id": None,
                "title": title,
                "message": message,
                "type": kind,
                "source": "agent",
                "external_match_id": match_id,
                "event_key": event_key,
            })
        written += _insert(client, headers, rows)
        if rows:
            _log("  {} -> {} kullanici".format(title, len(rows)))

    _log("{} mac, {} olay, {} bildirim yazildi".format(len(matches), len(events), written))
    _save_state(state)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--loop", type=int, default=0, help="saniye cinsinden aralik; 0 ise tek tur"
    )
    args = parser.parse_args()

    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip() or _service_key_from_cli()
    if not key:
        print("HATA: Supabase servis anahtari alinamadi.", file=sys.stderr)
        sys.exit(1)
    headers = {
        "apikey": key,
        "Authorization": "Bearer " + key,
        "Content-Type": "application/json",
    }

    state = _load_state()
    with httpx.Client() as client:
        while True:
            try:
                run_once(client, headers, state)
            except Exception as exc:  # noqa: BLE001 - dongu olmemeli
                _log("HATA: {}".format(exc))
            if args.loop <= 0:
                break
            time.sleep(args.loop)


if __name__ == "__main__":
    main()
