# AI Sport Agent veri toplama isi (iddaa bulteni + opsiyonel Sofascore).
#
# NEDEN SAATLIK CALISIYOR
# -----------------------
# Nesine prebulteni PRE-MATCH bir feed'dir: bir mac baslayinca listeden DUSER.
# Gunde tek sefer cekilirse o ana kadar oynanmis maclar hic kaydedilmez ve
# uygulamanin ana ekraninda gunun maclarinin buyuk kismi eksik gorunur
# (2026-08-20'de olculdu: agent 74 mac, bulten 280 mac).
#
# sports_api ayni feed'i saatlik cekip UPSERT ettigi icin gun boyunca birikiyor;
# agent tarafinda ayni birikimi saatlik calistirarak sagliyoruz. Staging
# batch'leri eklemeli oldugu ve listeleme sorgusu gunun TUM batch'lerini
# birlestirdigi icin her kosu kapsami genisletir.
#
# Kullanim:
#   powershell -File scripts/run_agent_ingest.ps1                    # bugun, Sofascore'suz (saatlik)
#   powershell -File scripts/run_agent_ingest.ps1 -IncludeSofascore -DaysAhead 1
#
# Sofascore hiz notu: gunun programi ~700 istek gerektiriyor. Saatlik iste
# Sofascore KAPALI; eslestirme zaten veritabanindaki mevcut Sofascore
# maclarina karsi yapiliyor. Sofascore yalnizca gunluk iste cekilir.

param(
    [switch]$IncludeSofascore,
    [int]$DaysAhead = 0
)

$ErrorActionPreference = 'Stop'
$api = 'http://127.0.0.1:8001/api/v1'

function Write-Log($m) { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" }

# API ayakta mi? Degilse gozetmen gorevi birazdan baslatir; burada bekleyelim.
$up = $false
$deadline = (Get-Date).AddMinutes(6)
while ((Get-Date) -lt $deadline) {
    try { Invoke-RestMethod -Uri "$api/mobile/matches/live?date=$((Get-Date).ToString('yyyy-MM-dd'))" -TimeoutSec 30 | Out-Null; $up = $true; break }
    catch { if ($_.Exception.Response) { $up = $true; break } }
    Start-Sleep -Seconds 20
}
if (-not $up) { throw "agent API ayaga kalkmadi (8001)." }

$failed = 0
foreach ($offset in 0..$DaysAhead) {
    $d = (Get-Date).AddDays($offset).ToString('yyyy-MM-dd')
    Write-Log ("is kuyruga aliniyor: {0} (sofascore={1})" -f $d, [bool]$IncludeSofascore)
    try {
        $job = Invoke-RestMethod -Method POST -TimeoutSec 60 -Uri "$api/internal/iddaa-sync-jobs/" `
            -ContentType 'application/json' `
            -Body (@{ start_date = $d; end_date = $d; include_sofascore = [bool]$IncludeSofascore } | ConvertTo-Json)
    } catch { $failed++; Write-Log "  kuyruga alinamadi: $($_.Exception.Message)"; continue }

    $jobDeadline = (Get-Date).AddMinutes(25)
    while ((Get-Date) -lt $jobDeadline) {
        Start-Sleep -Seconds 20
        try { $s = Invoke-RestMethod -TimeoutSec 30 -Uri "$api/internal/iddaa-sync-jobs/$($job.id)" } catch { continue }
        if ($s.status -in @('succeeded','completed')) {
            Write-Log ("  {0} tamam: sofascore={1} eklenen={2} iddaa_published={3}" -f `
                $d, $s.summary.sofascore_fixtures_seen, $s.summary.sofascore_inserted_matches, $s.summary.iddaa_published_rows)
            break
        }
        if ($s.status -in @('failed','error')) {
            $failed++
            $msg = if ($s.error_message) { $s.error_message.Substring(0, [Math]::Min(200, $s.error_message.Length)) } else { '(mesaj yok)' }
            Write-Log "  $d BASARISIZ: $msg"
            break
        }
    }
    # Gunler arasi nefes payi: Sofascore ardisik yuklenmeye duyarli.
    if ($offset -lt $DaysAhead) { Start-Sleep -Seconds 60 }
}

Write-Log "Bitti. Basarisiz gun: $failed"
if ($failed -gt 0) { exit 1 }
