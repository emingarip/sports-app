# Saatlik iddaa toplama (Sofascore'suz) - schtasks girisi.
# Gerekce: Nesine prebulteni baslamis maclari listeden dusurur; gunde tek
# cekimde gunun buyuk kismi kaydedilmeden kaybolur. Ayrinti:
# scripts/run_agent_ingest.ps1 basligi.
$ErrorActionPreference = 'Stop'
$log = Join-Path $PSScriptRoot 'logs\agent_ingest.log'
if (-not (Test-Path (Split-Path $log))) { New-Item -ItemType Directory -Path (Split-Path $log) | Out-Null }
if ((Test-Path $log) -and (Get-Item $log).Length -gt 5MB) { Move-Item $log "$log.1" -Force }
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& (Join-Path $PSScriptRoot 'run_agent_ingest.ps1') *>&1 | Out-String -Stream | Out-File -FilePath $log -Encoding utf8 -Append
$code = $LASTEXITCODE
$ErrorActionPreference = $prev
exit $code
