# Gol bildirimi ureticisini calistirir (zamanlanmis gorev girisi).
# Ayrintili gerekce: scripts/goal_notifier.py basligi.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$log = Join-Path $PSScriptRoot 'logs\goal_notifier.log'
if (-not (Test-Path (Split-Path $log))) { New-Item -ItemType Directory -Path (Split-Path $log) | Out-Null }
if ((Test-Path $log) -and (Get-Item $log).Length -gt 5MB) { Move-Item $log "$log.1" -Force }

$env:PYTHONIOENCODING = 'utf-8'
Set-Location $root
# python stderr'e yazdiginda $ErrorActionPreference='Stop' scripti oldurmesin:
# basari olcutu YALNIZCA cikis kodu (bkz. README "PowerShell native stderr tuzagi").
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& python scripts/goal_notifier.py *>&1 | Out-String -Stream | Out-File -FilePath $log -Encoding utf8 -Append
$code = $LASTEXITCODE
$ErrorActionPreference = $prev
exit $code
