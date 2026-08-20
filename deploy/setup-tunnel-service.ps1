# cloudflared'i Windows servisi olarak kurar (YONETICI olarak calistir).
#   powershell -ExecutionPolicy Bypass -File D:\Projects\SportsApp\deploy\setup-tunnel-service.ps1
#
# NOT: Bu servis MEVCUT digginalpha tunnel'ini kullanir; hem digginalpha.com
# hem boskale.com ayni tunnel uzerinden gider.
#
# NEDEN DOSYA KOPYALIYORUZ: Windows'ta cloudflared servisi config'i
# LocalSystem profilinden okur:
#   C:\Windows\System32\config\systemprofile\.cloudflared\
# "cloudflared --config <yol> service install" bu surumde bayragi servis komut
# satirina ISLEMIYOR (event log'da arguments listesi bos kaliyor), o yuzden
# dosyalari oraya elle kopyalayip oyle kuruyoruz.
#
# CONFIG DEGISIRSE: ~/.cloudflared/config.yml duzenledikten sonra bu scripti
# tekrar calistir (ya da dosyayi systemprofile'a kopyalayip Restart-Service).

$ErrorActionPreference = 'Stop'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
      [Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw "Bu script yonetici haklari gerektirir. PowerShell'i 'Run as administrator' ile ac."
}

$exe     = 'C:\Program Files (x86)\cloudflared\cloudflared.exe'
$srcDir  = 'C:\Users\emin_\.cloudflared'
$dstDir  = 'C:\Windows\System32\config\systemprofile\.cloudflared'

if (-not (Test-Path $exe))    { throw "cloudflared bulunamadi: $exe" }
if (-not (Test-Path $srcDir)) { throw "kaynak config klasoru bulunamadi: $srcDir" }

Write-Host "=== Ingress dogrulaniyor ===" -ForegroundColor Cyan
& $exe tunnel ingress validate
if ($LASTEXITCODE -ne 0) { throw "config.yml ingress kurallari gecersiz. Servis kurulmadi." }

# Mevcut (hatali/eski) servisi kaldir.
# Config'siz kurulmus bir servis duzgun kapanamayip StopPending'de asili kalabiliyor;
# bu yuzden Stop-Service'i suresiz bekletmeyip sureci zorla dusuruyoruz.
if (Get-Service cloudflared -ErrorAction SilentlyContinue) {
  Write-Host "`n=== Mevcut servis kaldiriliyor ===" -ForegroundColor Cyan
  $oldPid = (Get-CimInstance Win32_Service -Filter "Name='cloudflared'").ProcessId

  Start-Job { Stop-Service cloudflared -Force -ErrorAction SilentlyContinue } |
    Wait-Job -Timeout 20 | Out-Null
  Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue

  $svc = Get-Service cloudflared -ErrorAction SilentlyContinue
  if ($svc -and $svc.Status -ne 'Stopped') {
    Write-Host "  servis $($svc.Status) durumunda takildi, process zorla kapatiliyor (PID $oldPid)" -ForegroundColor Yellow
    if ($oldPid -and $oldPid -ne 0) { Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 3
  }

  & $exe service uninstall 2>&1 | Out-Null
  Start-Sleep -Seconds 2
  if (Get-Service cloudflared -ErrorAction SilentlyContinue) {
    Write-Host "  service uninstall yetmedi, sc.exe delete deneniyor" -ForegroundColor Yellow
    sc.exe delete cloudflared | Out-Null
    Start-Sleep -Seconds 3
  }
  if (Get-Service cloudflared -ErrorAction SilentlyContinue) {
    throw "Eski servis kaldirilamadi. Makineyi yeniden baslatip scripti tekrar calistir."
  }
  Write-Host "  eski servis kaldirildi." -ForegroundColor Green
}

Write-Host "`n=== Config LocalSystem profiline kopyalaniyor ===" -ForegroundColor Cyan
if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }

# config.yml + cert.pem sart. Credentials JSON'un yolu config icinde MUTLAK
# oldugu icin zorunlu degil, yine de yaninda dursun.
foreach ($f in @('config.yml', 'cert.pem')) {
  $src = Join-Path $srcDir $f
  if (-not (Test-Path $src)) { throw "gerekli dosya yok: $src" }
  Copy-Item $src (Join-Path $dstDir $f) -Force
  Write-Host "  kopyalandi: $f"
}
Get-ChildItem $srcDir -Filter '*.json' | ForEach-Object {
  Copy-Item $_.FullName (Join-Path $dstDir $_.Name) -Force
  Write-Host "  kopyalandi: $($_.Name)"
}

Write-Host "`n=== Servis kuruluyor ===" -ForegroundColor Cyan

# Onceki kurulumdan kalan event-log anahtari varsa "service install" servisi
# olusturur, sonra "registry key already exists" hatasi verip GERI ALIR.
# Sonuc: "installed" yazar ama servis ortada yoktur. Anahtari once temizliyoruz.
$evtKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\Cloudflared'
if (Test-Path $evtKey) {
  Write-Host "  artik event-log anahtari siliniyor" -ForegroundColor Yellow
  Remove-Item $evtKey -Recurse -Force
}

& $exe service install
# Cikis koduna GUVENME: cloudflared kismi hatalarda da sifir disi donebiliyor.
# Tek gecerli olcut servisin gercekten var olmasi.
Start-Sleep -Seconds 3
if (-not (Get-Service cloudflared -ErrorAction SilentlyContinue)) {
  throw "Servis kurulamadi. Yukaridaki cloudflared ciktisina bak."
}
Write-Host "  servis olusturuldu." -ForegroundColor Green

# "service install" bu surumde servisi ARGUMANSIZ kaydediyor
# (event log: "arguments: [cloudflared.exe]"). Argumansiz cloudflared.exe
# tunnel calistirmaz; yardim metni basip cikar ve servis "baslatilamadi" verir.
# Bu yuzden calistirma komutunu acikca yaziyoruz.
$svcCfg = Join-Path $dstDir 'config.yml'
$imagePath = '"{0}" --config "{1}" tunnel run' -f $exe, $svcCfg
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Cloudflared' `
                 -Name ImagePath -Value $imagePath
Write-Host "  calistirma komutu ayarlandi:" -ForegroundColor Green
Write-Host "    $imagePath"

Start-Sleep -Seconds 3
Set-Service -Name cloudflared -StartupType Automatic
Start-Service -Name cloudflared
Start-Sleep -Seconds 8
Get-Service cloudflared | Select-Object Name, Status, StartType | Format-Table -AutoSize

Write-Host "=== Servis gercekten tunnel calistiriyor mu ===" -ForegroundColor Cyan
$svcPid = (Get-CimInstance Win32_Service -Filter "Name='cloudflared'").ProcessId
Write-Host "servis PID = $svcPid"
try {
  Get-EventLog -LogName Application -Source cloudflared -Newest 5 -ErrorAction Stop |
    Select-Object TimeGenerated, EntryType, @{n='Message';e={$_.Message.Substring(0, [Math]::Min(160, $_.Message.Length))}} |
    Format-List
} catch { Write-Host "event log okunamadi: $($_.Exception.Message)" -ForegroundColor Yellow }

Write-Host "`n=== Elle baslatilmis eski cloudflared process'leri ===" -ForegroundColor Cyan
$stray = Get-Process cloudflared -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $svcPid }
if ($stray) {
  Write-Host "UYARI: Asagidaki process'ler ayni tunnel'a bagli. Cloudflare istekleri" -ForegroundColor Yellow
  Write-Host "replikalar arasinda DAGITIR; eskisi boskale kurallarini bilmedigi icin" -ForegroundColor Yellow
  Write-Host "site araliksiz 404 verir. Kapatilmasi SART:" -ForegroundColor Yellow
  $stray | Select-Object Id, StartTime | Format-Table -AutoSize
  Write-Host "  Stop-Process -Id $($stray.Id -join ',') -Force" -ForegroundColor Yellow
} else {
  Write-Host "Temiz - baska cloudflared process'i yok." -ForegroundColor Green
}

Write-Host "`nConfig degisirse bu scripti tekrar calistir." -ForegroundColor Cyan
