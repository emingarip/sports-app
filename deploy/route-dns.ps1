# boskale.com Cloudflare'de aktif olduktan SONRA calistir.
# Tunnel'a yonelen CNAME kayitlarini olusturur. Admin gerekmez.
#   powershell -ExecutionPolicy Bypass -File D:\Projects\SportsApp\deploy\route-dns.ps1
#
# ONKOSUL: cloudflared'in cert.pem'i boskale.com zone'unu KAPSAMALI.
# cert.pem, "cloudflared tunnel login" sirasinda secilen zone'lara gore duzenlenir.
# boskale.com hesaba sonradan eklendiyse eski cert onu tanimaz ve cloudflared
# adi digginalpha.com'un ALT ALANI sanip "boskale.com.digginalpha.com" gibi
# cop kayitlar olusturur. Bu script artik bunu yakalayip duruyor.
# Cozum:  cloudflared tunnel login   (tarayicida boskale.com'u sec)

$ErrorActionPreference = 'Stop'
$exe = 'C:\Program Files (x86)\cloudflared\cloudflared.exe'
$tunnel = 'digginalpha'   # boskale.com da bu tunnel uzerinden gidiyor

$hosts = @('boskale.com', 'www.boskale.com', 'games.boskale.com',
           'admin.boskale.com', 'api.boskale.com', 'sports-agent.boskale.com')

$ok = 0
foreach ($h in $hosts) {
    Write-Host "-> $h" -ForegroundColor Cyan
    $out = & $exe tunnel route dns --overwrite-dns $tunnel $h 2>&1 | Out-String

    # Yanlis zone'a yazma belirtisi: olusan ad bizim istedigimiz hostname degil.
    if ($out -match [regex]::Escape("$h.")) {
        Write-Host ""
        Write-Host "DURDURULDU: cloudflared kaydi '$h' yerine baska bir zone'un" -ForegroundColor Red
        Write-Host "alt alani olarak olusturdu. Cikti:" -ForegroundColor Red
        Write-Host $out.Trim()
        Write-Host ""
        Write-Host "Sebep: cert.pem boskale.com zone'unu kapsamiyor." -ForegroundColor Yellow
        Write-Host "Cozum:" -ForegroundColor Yellow
        Write-Host "  1) cloudflared tunnel login     (tarayicida boskale.com'u sec)" -ForegroundColor Yellow
        Write-Host "  2) Bu scripti tekrar calistir." -ForegroundColor Yellow
        Write-Host "  3) Cloudflare > digginalpha.com > DNS altinda olusmus" -ForegroundColor Yellow
        Write-Host "     '*.boskale.com.digginalpha.com' kayitlarini sil." -ForegroundColor Yellow
        exit 1
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "   BASARISIZ: $h" -ForegroundColor Red
        Write-Host $out.Trim()
        exit 1
    }

    $ok++
    Write-Host "   tamam" -ForegroundColor Green
}

Write-Host "`n$ok/$($hosts.Count) kayit olusturuldu." -ForegroundColor Green
Write-Host "Cloudflare > boskale.com > DNS altinda hepsinin <uuid>.cfargotunnel.com" -ForegroundColor Cyan
Write-Host "hedefli ve Proxied (turuncu bulut) oldugunu dogrula." -ForegroundColor Cyan
