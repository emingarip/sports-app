# SportsApp zamanlanmis gorevlerini kurar (yonetici GEREKMEZ).
#   powershell -ExecutionPolicy Bypass -File scripts\register_scheduled_tasks.ps1
# Kaldirmak icin:
#   powershell -ExecutionPolicy Bypass -File scripts\register_scheduled_tasks.ps1 -Remove
#
# Kurulan gorevler:
#   SportsApp - Iddaa Bulletin Sync    saatlik    bulletin_sync_runner.ps1
#   SportsApp - Schedule Matches       gunde 1    schedule_sync_runner.ps1 -Scope matches
#   SportsApp - Schedule Lineups       saatlik    schedule_sync_runner.ps1 -Scope match-lineups
#   SportsApp - Simulation Engine      oturumda   simulation_runner.ps1  (SUREKLI calisir)
#
# Simulation Engine digerlerinden farkli: periyodik degil, surekli calisan bir
# surec. Bu yuzden /SC ONLOGON ile kuruluyor (ONSTART yonetici isterdi, bu
# script ise yonetici gerektirmiyor); zaman siniri yok ve surec olurse yeniden
# baslatiliyor. Onkosullari icin scripts\simulation_runner.ps1 basligina bak.
#
# Program/kadro islerinin saglayicisi sportsapipro-football-v2. Sofascore
# bilerek kullanilmiyor - gerekcesi schedule_sync_runner.ps1 basliginda.
#
# Her gorevin ciktisi scripts\logs\ altina yazilir; zamanlanmis gorevler
# gorunmez calistigi icin log olmadan hata tespiti mumkun degil.

param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$scripts  = Join-Path $repoRoot 'scripts'
$logDir   = Join-Path $scripts 'logs'

$tasks = @(
    @{
        Name     = 'SportsApp - Iddaa Bulletin Sync'
        TaskArg  = 'bulletin'
        Schedule = @('/SC', 'HOURLY')
    },
    @{
        Name     = 'SportsApp - Schedule Matches'
        TaskArg  = 'matches'
        # Sabah erken: gunun kanonik programi bulten senkronundan once hazir olsun.
        # 06:30 DEGIL: kadro isi de saat basi :30'da kosuyor, ikisi ayni anda
        # sportsapipro'ya yuklenince saglayici 429 donuyor. 10 dakika ayirdik.
        Schedule = @('/SC', 'DAILY', '/ST', '06:10')
    },
    @{
        Name     = 'SportsApp - Schedule Lineups'
        TaskArg  = 'lineups'
        # Kadrolar mac saatine yakin aciklanir; saatlik, bulten isiyle
        # cakismamasi icin yarim saat kaydirildi.
        Schedule = @('/SC', 'HOURLY', '/ST', '00:30')
    }
)

$simTaskName = 'SportsApp - Simulation Engine'

if ($Remove) {
    foreach ($t in $tasks) {
        schtasks /Delete /TN $t.Name /F 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Host "silindi: $($t.Name)" -ForegroundColor Yellow }
        else { Write-Host "zaten yok: $($t.Name)" }
    }
    schtasks /Delete /TN $simTaskName /F 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Host "silindi: $simTaskName" -ForegroundColor Yellow }
    else { Write-Host "zaten yok: $simTaskName" }
    return
}

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

$runner = Join-Path $scripts 'run_task.ps1'
if (-not (Test-Path $runner)) { throw "script bulunamadi: $runner" }
if ($runner -match '\s') {
    throw "Repo yolu bosluk iceriyor ($runner). schtasks /TR tirnak yonetimi bozulur; repoyu bosluksuz bir yola tasi."
}

foreach ($t in $tasks) {
    # /TR degerinde TIRNAK KULLANMA: schtasks ic ice tirnaklari bozuyor.
    # Log devretme ve yonlendirme run_task.ps1 icinde yapiliyor.
    $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Task $($t.TaskArg)"

    $argList = @('/Create', '/TN', $t.Name, '/TR', $cmd, '/F') + $t.Schedule
    schtasks @argList | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "gorev olusturulamadi: $($t.Name)" }

    # schtasks bu ikisini ayarlayamiyor, ScheduledTasks modulunden veriyoruz:
    #  - MultipleInstances=IgnoreNew: kadro senkronu 10+ dakika surebiliyor,
    #    saatlik tetikte onceki kosu bitmeden ikincisi baslamasin.
    #  - ExecutionTimeLimit: takilan bir kosu gorevi sonsuza kadar mesgul etmesin.
    try {
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
            -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
            -StartWhenAvailable -DontStopOnIdleEnd
        Set-ScheduledTask -TaskName $t.Name -Settings $settings -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "  UYARI: gorev ayarlari guncellenemedi ($($_.Exception.Message))" -ForegroundColor Yellow
    }

    Write-Host "kuruldu: $($t.Name)" -ForegroundColor Green
}

# --- Simulation Engine: surekli calisan surec, ayri ele aliniyor ------------
# Digerleri gibi run_task.ps1 uzerinden gitmiyor cunku periyodik degil.
$simRunner = Join-Path $scripts 'simulation_runner.ps1'
if (-not (Test-Path $simRunner)) {
    Write-Host "UYARI: $simRunner yok, Simulation Engine gorevi atlandi." -ForegroundColor Yellow
} else {
    # schtasks /SC ONLOGON tetikleyiciyi TUM kullanicilar icin kurmaya calisir
    # ve yonetici ister ("Access is denied"). ScheduledTasks modulu ile yalnizca
    # mevcut kullaniciya kaydetmek yetki gerektirmiyor.
    $me = "$env:USERDOMAIN\$env:USERNAME"
    try {
        $simAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$simRunner`""
        $simTrigger = New-ScheduledTaskTrigger -AtLogOn -User $me
        $simPrincipal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive

        # ExecutionTimeLimit Zero = sinirsiz: surec bilerek surekli calisiyor.
        # RestartCount/RestartInterval: Ollama yeniden baslarsa veya surec
        # oldurulurse motor kendini toparlasin.
        $simSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
            -ExecutionTimeLimit ([TimeSpan]::Zero) `
            -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
            -StartWhenAvailable -DontStopOnIdleEnd

        Register-ScheduledTask -TaskName $simTaskName -Action $simAction `
            -Trigger $simTrigger -Principal $simPrincipal -Settings $simSettings `
            -Force -ErrorAction Stop | Out-Null

        Write-Host "kuruldu: $simTaskName (oturum acilisinda, surekli)" -ForegroundColor Green
        Write-Host "  Onkosul: Ollama ayakta olmali. Dogrulama: cd simulation_engine; node diagnose.js" -ForegroundColor DarkGray
    } catch {
        Write-Host "UYARI: $simTaskName kurulamadi ($($_.Exception.Message))" -ForegroundColor Yellow
        Write-Host "  Motor elle baslatilabilir: powershell -File scripts\simulation_runner.ps1" -ForegroundColor DarkGray
    }
}

Write-Host "`nKurulan gorevler:" -ForegroundColor Cyan
schtasks /Query /TN 'SportsApp - Iddaa Bulletin Sync' /FO LIST | Select-String 'TaskName|Next Run|Sonraki'
Write-Host "`nLoglar: $logDir" -ForegroundColor Cyan
Write-Host "Elle test: schtasks /Run /TN `"SportsApp - Schedule Matches`"" -ForegroundColor Cyan
