# simulation_engine'i calistirir ve loglar.
#
# Diger sync isleri periyodiktir (run_task.ps1); bu ise SUREKLI calisan bir
# surectir, o yuzden ayri bir runner'i var. Zamanlanmis gorev /SC ONSTART ile
# kurulur ve surec olurse Windows yeniden baslatir.
#
# Elle calistirmak icin:
#   powershell -ExecutionPolicy Bypass -File scripts\simulation_runner.ps1
#
# Kuru mod (uretir ama DB'ye yazmaz):
#   powershell -ExecutionPolicy Bypass -File scripts\simulation_runner.ps1 -DryRun
#
# Onkosullar:
#   - Ollama ayakta ve .env'deki OLLAMA_MODEL kurulu  (node diagnose.js ile dogrula)
#   - supabase/migrations/20260820120000_simulation_engine_v2.sql uygulanmis

param(
    [switch]$DryRun,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$engineDir = Join-Path $repoRoot 'simulation_engine'
$logDir = Join-Path $PSScriptRoot 'logs'

if (-not (Test-Path $engineDir)) { throw "simulation_engine bulunamadi: $engineDir" }
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

$logFile = Join-Path $logDir 'simulation_engine.log'

# Log devretme: 20 MB'i asinca .1 olarak arsivle. Surec aylarca calisabilir.
if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 20MB)) {
    $archive = Join-Path $logDir 'simulation_engine.1.log'
    if (Test-Path $archive) { Remove-Item $archive -Force }
    Move-Item $logFile $archive
}

if ($DryRun) { $env:SIM_DRY_RUN = 'true' }

Push-Location $engineDir
try {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logFile -Value "=== $stamp simulation_engine baslatiliyor (dryRun=$($DryRun.IsPresent)) ===" -Encoding utf8

    # NOT: native exe'nin stderr'ini PowerShell icinde 2>&1 ile yakalamak
    # Windows PowerShell 5.1'de her satiri ErrorRecord'a sarar ve exit kodu 0
    # olsa bile $? degerini $false yapar. Bu depoda daha once sessiz arizalara
    # yol acti. Bu yuzden yonlendirmeyi cmd'ye birakiyoruz ve TEK olcut
    # cikis kodu.
    & cmd /c "node index.js >> `"$logFile`" 2>&1"
    $exitCode = $LASTEXITCODE

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logFile -Value "=== $stamp surec sonlandi, cikis kodu=$exitCode ===" -Encoding utf8

    if ($exitCode -ne 0) {
        Write-Host "simulation_engine hata ile sonlandi (kod $exitCode). Log: $logFile" -ForegroundColor Red
    }
    exit $exitCode
}
finally {
    Pop-Location
}
