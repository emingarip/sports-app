"""Uygulamada gorunen maclar ile iddaa bulteni ayni mi? — dogrulama araci.

Boskale bir bahis yardimci aracidir: ana ekranda gorunen mac listesi iddaa
bulteniyle BIREBIR ayni olmali. Fazla mac kullaniciyi oynayamayacagi maca
yonlendirir, eksik mac ise oynayabilecegi maci gizler.

Bu script uc kaynagi karsilastirir:

  1. Supabase `bulletin_matches`  -> Kupon sekmesinin gosterdigi bulten
                                     (sports_api saatlik toplar, birikir)
  2. Agent iddaa staging          -> agent'in kendi topladigi bulten
  3. Agent mobil endpoint         -> ana ekranda GERCEKTEN gorunen liste

Cikti: her ikili icin eksik/fazla sayilari ve ornekler.

Kullanim:
    python scripts/verify_bulletin_sync.py            # bugun
    python scripts/verify_bulletin_sync.py 2026-08-21
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.request
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bulletin_bridge import _service_key_from_cli, SUPABASE_URL  # noqa: E402

AGENT_API = os.environ.get("AGENT_API_URL", "http://127.0.0.1:8001/api/v1")
AGENT_DB_CONTAINER = os.environ.get("AGENT_DB_CONTAINER", "boskale-agent-db")
TZ = ZoneInfo("Europe/Istanbul")

# Takim adlari kaynaklar arasinda farkli yazilir ("Atl Mineiro" / "Atletico
# Mineiro", "Cerro Porteno" / "Cerro Porteño"). Karsilastirma icin sadelestir.
_TR = str.maketrans("çğıöşüâîûéíóáñ", "cgiosuaiueiaan")


def norm(value: str) -> str:
    text = (value or "").lower().translate(_TR)
    return re.sub(r"[^a-z0-9]", "", text)


def name_tokens(value: str) -> set[str]:
    """Anlamsiz ekleri atarak kelime kumesi cikarir.

    Kaynaklar ayni takimi farkli yazar: "Marathon" / "CD Marathon",
    "Alianza" / "Alianza FC". Sabit uzunlukta prefix almak bunlari AYRI
    sayiyordu (ilk surumde 5 sahte "fazla" uretti). Kelime kumesi kesisimi
    daha saglam.
    """
    stop = {"fc", "cd", "sc", "cf", "ac", "sk", "fk", "afc", "cs", "club", "csd",
            "sv", "if", "bk", "us", "as", "ss", "ssc", "the", "united", "utd"}
    words = {w for w in re.split(r"[^a-z0-9]+", (value or "").lower().translate(_TR)) if w}
    core = {w for w in words if w not in stop and len(w) > 2}
    return core or words


def match_key(home: str, away: str) -> tuple[frozenset[str], frozenset[str]]:
    return frozenset(name_tokens(home)), frozenset(name_tokens(away))


def similar(a: tuple, b: tuple) -> bool:
    """Iki tarafta da en az bir ortak anlamli kelime varsa ayni mac say."""
    return bool(a[0] & b[0]) and bool(a[1] & b[1])


def pair_key(home: str, away: str) -> str:
    return f"{norm(home)}|{norm(away)}"


def supabase_bulletin(day: str) -> dict[str, dict]:
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip() or _service_key_from_cli()
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    url = (
        f"{SUPABASE_URL}/rest/v1/bulletin_matches"
        f"?select=home_team,away_team,kickoff_at,status&event_date=eq.{day}"
    )
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=90) as response:
        rows = json.loads(response.read())
    return {pair_key(r["home_team"], r["away_team"]): r for r in rows}


def agent_staging(day: str) -> dict[str, dict]:
    sql = (
        "select distinct r.home_team_name, r.away_team_name, r.stage_status "
        "from fixture_stage_rows r "
        "join fixture_stage_batches b on b.id = r.batch_id "
        f"where b.source='iddaa' and b.target_date=date '{day}';"
    )
    # Takim adlari Turkce/Latin aksanli; Windows varsayilan kod sayfasi
    # cozemeyip patliyordu. Baytlari alip UTF-8 olarak kendimiz cozuyoruz.
    completed = subprocess.run(
        ["docker", "exec", AGENT_DB_CONTAINER, "psql", "-U", "postgres",
         "-d", "ai_sport_agent", "-t", "-A", "-F", "|", "-c", sql],
        capture_output=True, timeout=120,
    )
    out = (completed.stdout or b"").decode("utf-8", errors="replace")
    rows = {}
    for line in out.strip().splitlines():
        parts = line.split("|")
        if len(parts) >= 3:
            rows[pair_key(parts[0], parts[1])] = {
                "home_team": parts[0], "away_team": parts[1], "stage_status": parts[2],
            }
    return rows


def agent_mobile(day: str) -> dict[str, dict]:
    url = f"{AGENT_API}/mobile/matches/live?date={day}&limit=1000"
    with urllib.request.urlopen(url, timeout=180) as response:
        payload = json.loads(response.read())
    rows = {}
    for match in payload.get("matches") or []:
        home = (match.get("home_team") or {}).get("name") or ""
        away = (match.get("away_team") or {}).get("name") or ""
        rows[pair_key(home, away)] = {
            "home_team": home, "away_team": away, "status": match.get("status"),
        }
    return rows


def compare(label_a: str, a: dict, label_b: str, b: dict, *, sample: int = 5) -> int:
    # Once birebir ad eslesmesi, kalanlar icin kelime kumesi kesisimi.
    keys_b = dict(b)
    only_a = []
    for key, row in a.items():
        if key in keys_b:
            keys_b.pop(key)
            continue
        target = match_key(row.get("home_team", ""), row.get("away_team", ""))
        hit = None
        for other_key, other in keys_b.items():
            if similar(target, match_key(other.get("home_team", ""), other.get("away_team", ""))):
                hit = other_key
                break
        if hit is not None:
            keys_b.pop(hit)
        else:
            only_a.append(key)
    only_b = list(keys_b)
    print(f"\n{label_a} ({len(a)})  vs  {label_b} ({len(b)})")
    print(f"  {label_b} tarafinda EKSIK : {len(only_a)}")
    for k in only_a[:sample]:
        row = a[k]
        print(f"     - {row.get('home_team')} - {row.get('away_team')}")
    print(f"  {label_b} tarafinda FAZLA : {len(only_b)}")
    for k in only_b[:sample]:
        row = b[k]
        print(f"     + {row.get('home_team')} - {row.get('away_team')}")
    return len(only_a) + len(only_b)


def main() -> None:
    day = sys.argv[1] if len(sys.argv) > 1 else datetime.now(TZ).date().isoformat()
    print(f"=== BULTEN SENKRON DOGRULAMASI — {day} ===")
    print(f"(simdi: {datetime.now(TZ):%Y-%m-%d %H:%M} Europe/Istanbul)")

    bulletin = supabase_bulletin(day)
    staging = agent_staging(day)
    mobile = agent_mobile(day)

    total = 0
    total += compare("Supabase bulten", bulletin, "agent staging", staging)
    total += compare("agent staging", staging, "ana ekran", mobile)
    drift = compare("Supabase bulten", bulletin, "ana ekran", mobile)

    print("\n--- OZET ---")
    print(f"  bulten={len(bulletin)}  staging={len(staging)}  ana_ekran={len(mobile)}")
    print(f"  bulten <-> ana ekran toplam sapma: {drift}")
    if drift == 0:
        print("  SONUC: SENKRON")
    else:
        print("  SONUC: SENKRON DEGIL")
    sys.exit(0 if drift == 0 else 1)


if __name__ == "__main__":
    main()
