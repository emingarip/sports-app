# Gunluk toplama: bugun + yarin, Sofascore DAHIL - schtasks girisi.
# Sofascore gunun programi icin ~700 istek gerektirdiginden gunde bir kez.
$ErrorActionPreference = 'Stop'
$log = Join-Path $PSScriptRoot 'logs\agent_ingest.log'
if (-not (Test-Path (Split-Path $log))) { New-Item -ItemType Directory -Path (Split-Path $log) | Out-Null }
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& (Join-Path $PSScriptRoot 'run_agent_ingest.ps1') -IncludeSofascore -DaysAhead 1 *>&1 | Out-String -Stream | Out-File -FilePath $log -Encoding utf8 -Append
$code = $LASTEXITCODE
$ErrorActionPreference = $prev
exit $code
