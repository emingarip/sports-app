# Zamanlanmis gorev sarmalayicisi: log devretme + kosucuyu calistirma.
# schtasks /TR degeri ic ice tirnaklari bozdugu icin log yonlendirmesi
# komut satirinda degil BURADA yapiliyor.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_task.ps1 -Task bulletin

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('bulletin', 'matches', 'lineups')]
    [string]$Task
)

$ErrorActionPreference = 'Stop'
$scripts = $PSScriptRoot
$logDir  = Join-Path $scripts 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

# Args ADLANDIRILMIS parametre splat'i icin hashtable olmali. Dizi splat'i
# ("-Scope","matches") elemanlari konumsal arguman sayar ve "-Scope" metnini
# Scope parametresinin DEGERI olarak baglar.
$map = @{
    bulletin = @{ Script = 'bulletin_sync_runner.ps1';  Args = @{};                        Log = 'bulletin_sync.log' }
    matches  = @{ Script = 'schedule_sync_runner.ps1';  Args = @{ Scope = 'matches' };      Log = 'schedule_matches.log' }
    lineups  = @{ Script = 'schedule_sync_runner.ps1';  Args = @{ Scope = 'match-lineups' }; Log = 'schedule_lineups.log' }
}

$def     = $map[$Task]
$logPath = Join-Path $logDir $def.Log
$script  = Join-Path $scripts $def.Script

# Log sinirsiz buyumesin: 5 MB ustunu tek kusak devret.
if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 5MB) {
    Move-Item $logPath "$logPath.1" -Force
}

# Splat icin ayri degisken sart: "@($def.Args)" splat etmez, tek arguman gecirir.
$runnerArgs = $def.Args

# "*>> dosya" PowerShell 5.1'de UTF-16 yaziyor; log okunamaz hale geliyordu.
# Ciktiyi toplayip acikca UTF-8 olarak ekliyoruz.
# Out-String -Stream her nesneyi (hata kayitlari dahil) satir satir metne cevirir.
# Ternary (?:) Windows PowerShell 5.1'de YOK, kullanmiyoruz.
& $script @runnerArgs *>&1 |
    Out-String -Stream |
    Out-File -FilePath $logPath -Encoding utf8 -Append
exit $LASTEXITCODE
