# Kanonik program/kadro senkron kosucusu (yerel barindirma).
#
# Kullanim:
#   powershell -ExecutionPolicy Bypass -File scripts\schedule_sync_runner.ps1 -Scope matches
#   powershell -ExecutionPolicy Bypass -File scripts\schedule_sync_runner.ps1 -Scope match-lineups
#
# Zamanlanmis gorevleri kurmak icin: scripts\register_scheduled_tasks.ps1
#
# SAGLAYICI SECIMI (2026-08-17'de olcerek dogrulandi):
#   sportsapipro-football-v2   -> CALISIYOR. Program 214 mac, kadro 81 mac / 0 hata.
#   sofascore-football         -> BOZUK. Sofascore iki yerden birden engelliyor:
#        * /api/v1/sport/football/scheduled-events/{tarih} endpoint'i KALDIRILMIS (404).
#          Yerine gunun turnuva listesi + turnuva basina ayri istek geldi (~700 istek/gun).
#        * /api/v1/event/{id} artik 403 Forbidden donuyor.
#   Bu yuzden varsayilan saglayici sportsapipro; sofascore'u bilerek kullanmiyoruz.
#   Hybrid slug (sportsapipro-then-sofascore) da sofascore yedegine dustugu icin
#   tek bir 403 tum senkronu dusuruyor - zamanlanmis iste kullanma.

param(
    [ValidateSet('matches', 'match-lineups')]
    [string]$Scope = 'matches',

    [string]$Provider = 'sportsapipro-football-v2',

    # Kac gun ileriyi senkronlasin (0 = sadece bugun).
    [int]$DaysAhead = 0
)

$ErrorActionPreference = 'Stop'
$apiBase   = 'http://127.0.0.1:8010/api/v1'
$repoRoot  = Split-Path -Parent $PSScriptRoot
$sportsApi = Join-Path $repoRoot 'sports_api'

function Write-Log($msg) { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" }

# Internal uclar (sync / predictions / ui) artik token istiyor. Token
# sports_api\.env icinde yasar; PowerShell ortam degiskeni olarak tutulmaz ki
# zamanlanmis gorev oturumunda kod sayfasi bozmasin.
function Get-InternalHeaders {
    param([string]$SportsApiDir)
    $envPath = Join-Path $SportsApiDir '.env'
    if (-not (Test-Path $envPath)) { return @{} }
    $line = Select-String -Path $envPath -Pattern '^\s*SPORTS_API_INTERNAL_API_TOKEN\s*=\s*(\S+)' |
        Select-Object -First 1
    if (-not $line) { return @{} }
    return @{ 'X-Internal-Token' = $line.Matches[0].Groups[1].Value }
}

$internalHeaders = Get-InternalHeaders -SportsApiDir $sportsApi

# docker/compose ilerlemeyi STDERR'e yazar; $ErrorActionPreference='Stop' altinda
# bu terminating error'a donusup basarili bir "compose up"ta bile scripti oldururdu.
function Invoke-Docker {
    param([string[]]$Arguments, [string]$WorkingDir)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($WorkingDir) { Push-Location $WorkingDir }
        $out = & docker @Arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally {
        if ($WorkingDir) { Pop-Location -ErrorAction SilentlyContinue }
        $ErrorActionPreference = $prev
    }
    if ($code -ne 0) { throw "docker $($Arguments -join ' ') basarisiz (kod $code): $($out.Trim())" }
    return $out
}

Write-Log "Senkron basliyor (provider=$Provider, scope=$Scope, daysAhead=$DaysAhead)"

# 1) API ayakta mi? Degilse container'i baslat.
# Zamanlanmis gorev oturumunda ilk HTTP cagrisi yavas olabiliyor; 30 sn veriyoruz.
$apiUp = $false
try {
    Invoke-RestMethod -Uri "$apiBase/health" -TimeoutSec 30 | Out-Null
    $apiUp = $true
} catch { $apiUp = $false }

if (-not $apiUp) {
    Write-Log 'sports_api ayakta degil, container baslatiliyor...'
    Invoke-Docker -Arguments @('compose', 'up', '-d') -WorkingDir $sportsApi | Out-Null
    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        try { Invoke-RestMethod -Uri "$apiBase/health" -TimeoutSec 5 | Out-Null; $apiUp = $true; break } catch { }
    }
    if (-not $apiUp) { throw 'sports_api 120 saniyede ayaga kalkmadi.' }
    Write-Log 'sports_api hazir.'
}

# 2) Gun gun senkron.
$failed = 0
foreach ($offset in 0..$DaysAhead) {
    $target = (Get-Date).AddDays($offset).ToString('yyyy-MM-dd')
    try {
        $r = Invoke-RestMethod -Method POST -TimeoutSec 900 `
            -Uri "$apiBase/internal/sync/providers/$Provider`?scope=$Scope&target_date=$target" `
            -Headers $internalHeaders
        if ($r.status -eq 'succeeded') {
            Write-Log ("  {0} -> {1}  {2}" -f $target, $r.status, ($r.stats | ConvertTo-Json -Compress))
        } else {
            $failed++
            Write-Log ("  {0} -> BASARISIZ durum={1} hata={2}" -f $target, $r.status, $r.error)
        }
    } catch {
        $failed++
        Write-Log ("  {0} -> HATA {1}" -f $target, $_.Exception.Message)
    }
    if ($offset -lt $DaysAhead) { Start-Sleep -Seconds 5 }
}

Write-Log "Bitti. Basarisiz gun sayisi: $failed"
if ($failed -gt 0) { exit 1 }
