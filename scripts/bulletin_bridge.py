"""Yerel bülten köprüsü: sports_api -> Supabase.

sync-bulletin / sync-predictions edge function'larının yaptığı işi yerelden yapar,
böylece sports_api internete açılmadan uygulama bülteni görebilir (geçici barındırma).

Servis anahtarı diske yazılmaz. Anahtar şu sırayla aranır:

1. SUPABASE_SERVICE_ROLE_KEY ortam değişkeni
2. stdin'e verilen `supabase projects api-keys ... -o json` çıktısı
3. Supabase CLI'nin doğrudan buradan çağrılması (varsayılan yol)

3. yol tercih edilir: CLI çıktısını PowerShell üzerinden geçirmek iki ayrı
hataya yol açıyordu — native stderr'in terminating error'a dönmesi ve
zamanlanmış görev oturumunda konsol kod sayfasının çıktıyı bozması (anahtar
517 karakterlik çöpe dönüşüyordu). CLI'yi burada çağırınca baytları doğrudan
okuyoruz, kabuk araya girmiyor.

    python scripts/bulletin_bridge.py
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, UTC
from zoneinfo import ZoneInfo

import httpx

SUPABASE_URL = "https://nigatikzsnxdqdwwqewr.supabase.co"
SPORTS_API = os.environ.get("SPORTS_API_LOCAL_URL", "http://127.0.0.1:8010")
SPORTS_API_DB = os.environ.get(
    "SPORTS_API_DB_URL", "postgresql://postgres:postgres@localhost:5432/sports_api"
)
AGENT_DB = os.environ.get(
    "AGENT_DB_URL", "postgresql://postgres:postgres@localhost:5434/ai_sport_agent"
)
CHUNK = 300


def _agent_match_links(today: str) -> dict[str, str]:
    """sports_api maç UUID'si -> AI Sport Agent maç id eşlemesi.

    Ortak anahtar resmi iddaa program kodudur: ajan tarafında günün
    fixture staging satırları (source_event_id), sports_api tarafında
    iddaa-bulletin sağlayıcı eşlemeleri (provider_entity_id) bu kodu tutar.
    Yerel DB'lerden biri kapalıysa köprü bağlantısız devam eder.
    """
    try:
        import psycopg

        with psycopg.connect(AGENT_DB, connect_timeout=5) as conn:
            rows = conn.execute(
                """
                SELECT fsr.source_event_id, fsr.matched_match_id
                FROM fixture_stage_rows fsr
                JOIN fixture_stage_batches fsb ON fsb.id = fsr.batch_id
                WHERE fsb.source = 'iddaa' AND fsb.target_date = %s
                  AND fsr.matched_match_id IS NOT NULL
                """,
                (today,),
            ).fetchall()
        agent_by_code = {str(code): str(match_id) for code, match_id in rows}
        if not agent_by_code:
            return {}

        with psycopg.connect(SPORTS_API_DB, connect_timeout=5) as conn:
            rows = conn.execute(
                """
                SELECT pem.provider_entity_id, m.id
                FROM provider_entity_mappings pem
                JOIN providers p ON p.id = pem.provider_id
                JOIN matches m ON m.entity_uid = pem.canonical_entity_uid
                WHERE p.slug = 'iddaa-bulletin' AND pem.entity_type = 'match'
                  AND pem.provider_entity_id = ANY(%s)
                """,
                (list(agent_by_code),),
            ).fetchall()
        return {str(match_id): agent_by_code[str(code)] for code, match_id in rows}
    except Exception as exc:  # köprü ana işini engellemesin
        print(f"uyari: agent eslemesi atlandi ({exc})", file=sys.stderr)
        return {}


JWT_RE = re.compile(r"^[A-Za-z0-9._\-]+$")


def _pick_service_role(payload: str) -> str | None:
    """CLI JSON'undan service_role anahtarını çıkarır, biçimini doğrular."""
    payload = payload.lstrip("﻿").strip()
    start = payload.find("[")
    if start > 0:
        # CLI sürüm uyarısı JSON'dan önce gelebiliyor.
        payload = payload[start:]
    try:
        entries = json.loads(payload)
    except json.JSONDecodeError as exc:
        print(f"UYARI: CLI JSON okunamadi: {exc}", file=sys.stderr)
        return None
    for entry in entries if isinstance(entries, list) else []:
        if isinstance(entry, dict) and entry.get("name") == "service_role":
            key = str(entry.get("api_key") or "").strip()
            # Bozuk kodlamayla gelen anahtari sessizce kullanmak yerine reddet:
            # JWT yalnizca base64url + nokta icerir.
            if key and JWT_RE.match(key) and len(key) <= 400:
                return key
            print(
                f"UYARI: service_role anahtari gecersiz gorunuyor (uzunluk {len(key)}).",
                file=sys.stderr,
            )
            return None
    return None


def _service_key_from_cli() -> str | None:
    """Supabase CLI'yi doğrudan çağırır; kabuk kodlaması araya girmez."""
    ref = SUPABASE_URL.split("//", 1)[-1].split(".", 1)[0]
    cmd = ["supabase", "projects", "api-keys", "--project-ref", ref, "-o", "json"]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=120, shell=True)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"UYARI: Supabase CLI cagrilamadi: {exc}", file=sys.stderr)
        return None
    # Baytlari kendimiz cozuyoruz; CLI surum uyarisi stderr'e gider ve onemsiz.
    out = proc.stdout.decode("utf-8", errors="replace")
    key = _pick_service_role(out)
    if key is None and proc.returncode != 0:
        err = proc.stderr.decode("utf-8", errors="replace").strip()
        print(f"UYARI: Supabase CLI cikis kodu {proc.returncode}: {err[:200]}", file=sys.stderr)
    return key


def _service_key() -> str:
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if key:
        return key
    if not sys.stdin.isatty():
        raw = sys.stdin.read()
        # PowerShell 5.1 native bir komuta boru yaparken metnin basina UTF-8 BOM
        # ekliyor; json.load bunu "Unexpected UTF-8 BOM" ile reddediyordu ve
        # asagidaki except sessizce yutup "anahtar yok" diyordu. Sonuc: bulten
        # Supabase'e hic gitmiyor, uygulamada maclar gorunmuyordu.
        if raw.strip():
            key = _pick_service_role(raw)
            if key:
                return key

    # Varsayilan yol: CLI'yi buradan cagir.
    key = _service_key_from_cli()
    if key:
        return key

    print("HATA: servis anahtarı alınamadı. 'supabase login' ile oturumu yenileyin "
          "ya da SUPABASE_SERVICE_ROLE_KEY tanımlayın.", file=sys.stderr)
    sys.exit(1)


def _rest(client: httpx.Client, method: str, path: str, **kwargs) -> httpx.Response:
    resp = client.request(method, f"{SUPABASE_URL}/rest/v1/{path}", **kwargs)
    if resp.status_code >= 400:
        raise RuntimeError(f"{method} {path} -> {resp.status_code}: {resp.text[:300]}")
    return resp


def main() -> None:
    key = _service_key()
    today = datetime.now(ZoneInfo("Europe/Istanbul")).date().isoformat()
    now_iso = datetime.now(UTC).isoformat()

    bulletin = httpx.get(
        f"{SPORTS_API}/api/v1/bulletin", params={"date": today, "tz": "Europe/Istanbul"},
        timeout=60,
    ).raise_for_status().json()
    matches = bulletin.get("matches") or []
    print(f"yerel bulten: {len(matches)} mac ({today})")
    if not matches:
        return

    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }
    client = httpx.Client(headers=headers, timeout=60)

    agent_links = _agent_match_links(today)
    match_rows = [
        {
            "sports_api_match_id": m["match_id"],
            "agent_match_id": agent_links.get(m["match_id"]),
            "event_date": today,
            "kickoff_at": m["kickoff_at"],
            "status": m.get("status") or "scheduled",
            "competition_name": m.get("competition_name"),
            "home_team": m.get("home_team"),
            "away_team": m.get("away_team"),
            "mbs": m.get("mbs"),
            "updated_at": now_iso,
        }
        for m in matches
    ]
    for i in range(0, len(match_rows), CHUNK):
        _rest(client, "POST", "bulletin_matches?on_conflict=sports_api_match_id",
              content=json.dumps(match_rows[i:i + CHUNK]))
    linked = sum(1 for row in match_rows if row["agent_match_id"])
    print(f"bulletin_matches: {len(match_rows)} upsert ({linked} agent eslesmesi)")

    id_by_api: dict[str, str] = {}
    api_ids = [m["match_id"] for m in matches]
    for i in range(0, len(api_ids), 100):
        chunk = ",".join(f'"{x}"' for x in api_ids[i:i + 100])
        rows = _rest(
            client, "GET",
            f"bulletin_matches?select=id,sports_api_match_id&sports_api_match_id=in.({chunk})",
        ).json()
        id_by_api.update({r["sports_api_match_id"]: r["id"] for r in rows})

    odds_rows = []
    for m in matches:
        bid = id_by_api.get(m["match_id"])
        if not bid:
            continue
        for market in m.get("markets") or []:
            for sel in market.get("selections") or []:
                odds_rows.append({
                    "bulletin_match_id": bid,
                    "market_code": market.get("market_code"),
                    "market_type": market.get("market_type"),
                    "market_name_tr": market.get("name_tr"),
                    "line_value": market.get("line_value"),
                    "selection_key": sel.get("selection_key"),
                    "selection_label_tr": sel.get("label_tr"),
                    "odds": sel.get("odds"),
                    "opening_odds": sel.get("opening_odds"),
                    "movement_pct": sel.get("movement_pct"),
                    "is_dropping": sel.get("is_dropping") or False,
                    "implied_prob": sel.get("implied_prob"),
                    "normalized_prob": sel.get("normalized_prob"),
                    "suspended": sel.get("suspended") or False,
                    "last_tick_at": market.get("last_tick_at"),
                    "updated_at": now_iso,
                })
    for i in range(0, len(odds_rows), CHUNK):
        _rest(client, "POST",
              "bulletin_odds?on_conflict=bulletin_match_id,market_code,selection_key",
              content=json.dumps(odds_rows[i:i + CHUNK]))
    print(f"bulletin_odds: {len(odds_rows)} upsert")

    predictions = httpx.get(
        f"{SPORTS_API}/api/v1/bulletin/predictions",
        params={"date": today, "tz": "Europe/Istanbul"}, timeout=60,
    ).raise_for_status().json()
    pred_rows = [
        {
            "bulletin_match_id": id_by_api[p["match_id"]],
            "sports_api_match_id": p["match_id"],
            "model_version": p.get("model_version"),
            "generated_at": p.get("generated_at"),
            "lambda_home": p.get("lambda_home"),
            "lambda_away": p.get("lambda_away"),
            "rho": p.get("rho"),
            "market_probs": p.get("market_probs") or {},
            "value_picks": p.get("value_picks") or [],
            "updated_at": now_iso,
        }
        for p in predictions
        if p.get("match_id") in id_by_api
    ]
    for i in range(0, len(pred_rows), CHUNK):
        _rest(client, "POST", "bulletin_predictions?on_conflict=bulletin_match_id",
              content=json.dumps(pred_rows[i:i + CHUNK]))
    print(f"bulletin_predictions: {len(pred_rows)} upsert")


if __name__ == "__main__":
    main()
