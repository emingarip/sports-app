# Bülten senkron koşucusu (yerel/geçici barındırma).
# Zincir: Nesine bülteni -> sports_api kanonik DB -> (opsiyonel) Supabase köprüsü.
# Kullanım:  powershell -ExecutionPolicy Bypass -File scripts\bulletin_sync_runner.ps1
# Saatte bir otomatik çalıştırmak için (yönetici olmayan PowerShell yeterli):
#   schtasks /Create /TN "SportsApp Bulletin Sync" /SC HOURLY /F `
#     /TR "powershell -ExecutionPolicy Bypass -File d:\Projects\SportsApp\scripts\bulletin_sync_runner.ps1"

$ErrorActionPreference = "Stop"
$apiPort = 8010
$apiBase = "http://127.0.0.1:$apiPort/api/v1"
$repoRoot = Split-Path -Parent $PSScriptRoot
$sportsApi = Join-Path $repoRoot "sports_api"
$today = (Get-Date).ToString("yyyy-MM-dd")

function Write-Log($msg) { Write-Host "[$(Get-Date -Format HH:mm:ss)] $msg" }

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

# docker/compose ilerleme satirlarini STDERR'e yazar. $ErrorActionPreference='Stop'
# altinda PowerShell native stderr'i terminating error'a cevirdigi icin
# "docker compose up -d" basarili olsa bile script oluyordu. Bu sarmalayici
# stderr'i stdout'a katip hata tercihini gecici olarak gevsetiyor.
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

# 1) Postgres container ayakta mi?
$dbUp = (Invoke-Docker -Arguments @('ps', '--format', '{{.Names}}')) -match 'sports-api-db'
if (-not $dbUp) {
    Write-Log "sports-api-db container baslatiliyor..."
    Invoke-Docker -Arguments @('compose', 'up', '-d', 'db') -WorkingDir $sportsApi | Out-Null
    Start-Sleep -Seconds 8
}

# 2) API ayakta mi? Degilse baslat.
# Zamanlanmis gorev oturumunda ilk HTTP cagrisi .NET/proxy isinmasi yuzunden
# yavas olabiliyor; 5 saniye yetmiyordu. Ucuz olan /health'i ve daha uzun
# zaman asimini kullaniyoruz.
$apiUp = $false
try {
    Invoke-RestMethod -Uri "$apiBase/health" -Method GET -TimeoutSec 30 | Out-Null
    $apiUp = $true
} catch { $apiUp = $false }
if (-not $apiUp) {
    # sports_api artik container'da calisiyor (deploy/README.md). Host'taki
    # "python" baska bir projenin venv'ine cozunuyor ve uygulama bagimliliklarini
    # icermiyor; o yuzden uvicorn'u elle baslatmak yerine compose kullaniyoruz.
    Write-Log "sports_api container baslatiliyor (port $apiPort)..."
    Invoke-Docker -Arguments @('compose', 'up', '-d') -WorkingDir $sportsApi | Out-Null
    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        try {
            Invoke-RestMethod -Uri "$apiBase/health" -TimeoutSec 5 | Out-Null
            $apiUp = $true; break
        } catch { }
    }
    if (-not $apiUp) { throw "sports_api 120 saniyede ayaga kalkmadi." }
    Write-Log "sports_api hazir."
}

# 2b) AI Sport Agent iddaa eslestirmesi (ana ekran filtresi bu veriye dayanir):
#     gunun iddaa programi cekilir ve Sofascore maclariyla eslestirilir.
try {
    $job = Invoke-RestMethod -Method POST -TimeoutSec 30 `
        -Uri "http://127.0.0.1:8001/api/v1/internal/iddaa-sync-jobs/" `
        -ContentType "application/json" `
        -Body (@{ start_date = $today; end_date = $today; include_sofascore = $true } | ConvertTo-Json)
    Write-Log "AI Sport Agent iddaa eslestirme isi kuyrukta: $($job.id)"
} catch {
    Write-Log "AI Sport Agent eslestirme atlandi (servis kapali olabilir): $($_.Exception.Message)"
}

# 3) Senkron zinciri: program -> oranlar -> tahminler.
Write-Log "Program senkronu..."
$r1 = Invoke-RestMethod -Method POST -TimeoutSec 300 `
    -Uri "$apiBase/internal/sync/providers/iddaa-bulletin?scope=matches&target_date=$today" `
    -Headers $internalHeaders
Write-Log ("  maclar: {0} yazildi (durum: {1})" -f $r1.stats.matches_upserted, $r1.status)

Write-Log "Oran senkronu..."
$r2 = Invoke-RestMethod -Method POST -TimeoutSec 300 `
    -Uri "$apiBase/internal/sync/providers/iddaa-bulletin?scope=market-backfill&target_date=$today" `
    -Headers $internalHeaders
Write-Log ("  oranlar: {0}/{1} mac (durum: {2})" -f $r2.stats.matches_synced, $r2.stats.matches_total, $r2.status)

Write-Log "Tahmin uretimi..."
$r3 = Invoke-RestMethod -Method POST -TimeoutSec 600 `
    -Uri "$apiBase/internal/predictions/run?target_date=$today" `
    -Headers $internalHeaders
Write-Log ("  tahmin: {0} uretildi, {1} atlandi (gecmis yetersiz), {2} value pick" -f `
    $r3.predicted, $r3.skipped_no_model, $r3.value_picks)

# 4) Supabase koprusu: bulten verisini yerelden canli Supabase'e yazar.
#    Servis anahtarini ARTIK BURADA OKUMUYORUZ - bulletin_bridge.py Supabase
#    CLI'yi kendisi cagiriyor. Anahtari PowerShell uzerinden gecirmek iki ayri
#    hataya yol acmisti: (1) CLI'nin surum uyarisi stderr'e gittigi icin
#    $ErrorActionPreference='Stop' altinda kopru her saat dusuyordu,
#    (2) zamanlanmis gorev oturumunda konsol kod sayfasi cikisi bozup anahtari
#    517 karakterlik cope ceviriyordu. Kabugu aradan cikarmak ikisini de bitirdi.
Write-Log "Supabase koprusu (bulletin_bridge.py)..."
try {
    Push-Location $repoRoot
    try {
        $outFile = [IO.Path]::GetTempFileName()
        $errFile = [IO.Path]::GetTempFileName()
        $proc = Start-Process -FilePath 'python' `
            -ArgumentList 'scripts/bulletin_bridge.py' `
            -WorkingDirectory $repoRoot -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile

        foreach ($f in @($outFile, $errFile)) {
            if (Test-Path $f) {
                Get-Content $f | Where-Object { $_ -and $_.Trim() } |
                    ForEach-Object { Write-Log "  $_" }
            }
        }
        if ($proc.ExitCode -ne 0) { throw "bulletin_bridge.py cikis kodu $($proc.ExitCode)" }
    } finally {
        Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Log "  Kopru HATA: $($_.Exception.Message)"
} finally {
    # Hata durumunda da dizin yiginini bosalt (eskiden sadece basarida yapiliyordu).
    Pop-Location -ErrorAction SilentlyContinue
}

Write-Log "Bitti."
