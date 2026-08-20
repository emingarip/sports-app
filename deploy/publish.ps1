# boskale.com yayin scripti — uc frontend'i derler, container'lari ayaga kaldirir.
# Kullanim:  powershell -ExecutionPolicy Bypass -File deploy\publish.ps1
# Admin gerekmez.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

# Yapilandirma --dart-define ile geliyor. Bu satirda bir kez
# --dart-define-from-file unutuldugu icin derleme BASARILI olur ama uygulama
# Supabase'e hic baglanmaz (SupabaseService release modda bos default'a duser,
# Supabase.initialize hic calismaz, site sessizce olu acilir). Bu yuzden hem
# dart-define'lar burada sabit, hem de asagida derlenmis ciktinin icerigi
# dogrulaniyor.
$envFile = Join-Path $root '.env'
if (-not (Test-Path $envFile)) { throw ".env yok: $envFile" }

Step "Flutter web derleniyor"
Push-Location $root
flutter build web --wasm --base-href "/" --release `
  --dart-define-from-file=.env `
  --dart-define=AI_SPORT_AGENT_BASE_URL=https://sports-agent.boskale.com
if ($LASTEXITCODE -ne 0) { throw "flutter build web basarisiz" }
Pop-Location

Step "Web derlemesinde yapilandirma dogrulaniyor"
# .env'deki Supabase projesinin host'u ciktida gecmiyorsa dart-define
# uygulanmamis demektir. Yarim yapilandirilmis bir build'i yayina almaktansa
# burada durmak yeglenir.
$supabaseLine = Select-String -Path $envFile -Pattern '^\s*SUPABASE_URL\s*=\s*(\S+)' | Select-Object -First 1
if (-not $supabaseLine) { throw ".env icinde SUPABASE_URL bulunamadi." }
$supabaseHost = ([System.Uri]$supabaseLine.Matches[0].Groups[1].Value).Host
$webRoot = Join-Path $root 'build\web'
if (-not (Test-Path $webRoot)) { throw "derleme cikisi yok: $webRoot" }
$configured = Get-ChildItem -Path $webRoot -Recurse -File |
  Select-String -Pattern ([regex]::Escape($supabaseHost)) -List -ErrorAction SilentlyContinue |
  Select-Object -First 1
if (-not $configured) {
  throw "Derleme ciktisinda Supabase host'u ($supabaseHost) yok - dart-define uygulanmamis. Yayin durduruldu."
}
Write-Host ("  OK   Supabase yapilandirmasi ciktida bulundu ({0} -> {1})" -f $supabaseHost, $configured.Filename) -ForegroundColor Green

Step "sports_games_web derleniyor"
Push-Location (Join-Path $root 'sports_games_web')
npm run build
if ($LASTEXITCODE -ne 0) { throw "sports_games_web build basarisiz" }
Pop-Location

Step "admin_dashboard derleniyor"
Push-Location (Join-Path $root 'admin_dashboard')
npm run build
if ($LASTEXITCODE -ne 0) { throw "admin_dashboard build basarisiz" }
Pop-Location

Step "Derlenmis ciktilar yayin klasorune kopyalaniyor"
# Caddy build klasorlerini dogrudan sunmuyor: derleme dakikalar surdugu ve
# ciktiyi yerinde yazdigi icin canliya yarim site (yeni index.html + eski
# main.dart.js) gidiyordu. Kopyalama ancak TUM derlemeler basarili olunca
# yapiliyor, boylece basarisiz bir derleme canliyi bozmuyor.
$pairs = @(
  @{ Src = (Join-Path $root 'build\web');                Dst = (Join-Path $PSScriptRoot 'www\app') },
  @{ Src = (Join-Path $root 'sports_games_web\dist');     Dst = (Join-Path $PSScriptRoot 'www\games') },
  @{ Src = (Join-Path $root 'admin_dashboard\dist');      Dst = (Join-Path $PSScriptRoot 'www\admin') }
)
foreach ($p in $pairs) {
  if (-not (Test-Path $p.Src)) { throw "derleme cikisi yok: $($p.Src)" }
  if (-not (Test-Path $p.Dst)) { New-Item -ItemType Directory -Path $p.Dst -Force | Out-Null }
  # /MIR: hedefi kaynakla birebir esitle (silinen dosyalar da gider).
  robocopy $p.Src $p.Dst /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
  # robocopy 0-7 arasi kodlari BASARI sayar; 8+ gercek hata.
  if ($LASTEXITCODE -ge 8) { throw "kopyalama basarisiz: $($p.Src) -> $($p.Dst) (robocopy $LASTEXITCODE)" }
  Write-Host ("  {0,-28} -> {1}" -f (Split-Path $p.Src -Leaf), $p.Dst)
}

Step "Boskale yigini ayaga kaldiriliyor"
# Tek compose projesi: Caddy + sports_api + AI Sport Agent.
# Ayrintili gerekce ve volume notlari: deploy/docker-compose.yml basligi.
if (-not (Test-Path (Join-Path $root 'sports_api\.env'))) {
    throw "sports_api\.env yok. .env.example'dan kopyalayip doldur."
}
Push-Location $PSScriptRoot
docker compose up -d
if ($LASTEXITCODE -ne 0) { throw "deploy/docker-compose up basarisiz" }
Pop-Location

Step "Saglik kontrolu"
$targets = @(
  @{ Name = 'boskale.com (Flutter web)'; Url = 'http://127.0.0.1:8080/' },
  @{ Name = 'games.boskale.com';         Url = 'http://127.0.0.1:8081/' },
  @{ Name = 'admin.boskale.com';         Url = 'http://127.0.0.1:8082/' },
  @{ Name = 'sports_api (yerel)';        Url = 'http://127.0.0.1:8010/api/v1/health' },
  @{ Name = 'AI Sport Agent (yerel)';    Url = 'http://127.0.0.1:8001/api/v1/mobile/matches/live?date=2026-01-01' }
)
foreach ($t in $targets) {
  try {
    $r = Invoke-WebRequest $t.Url -UseBasicParsing -TimeoutSec 15
    Write-Host ("  OK   {0,-28} {1}" -f $t.Name, $r.StatusCode) -ForegroundColor Green
  } catch {
    Write-Host ("  FAIL {0,-28} {1}" -f $t.Name, $_.Exception.Message) -ForegroundColor Red
  }
}

Write-Host "`nBitti. Tunnel servisi calisiyorsa degisiklikler canlida." -ForegroundColor Cyan
