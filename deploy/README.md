# boskale.com — kendi makinede yayin (Cloudflare Tunnel)

Bu klasor, SportsApp'i bu Windows makinesinden `boskale.com` uzerinde yayinlamak
icin gereken her seyi barindirir. Disari acilan port yok; trafik Cloudflare
Tunnel uzerinden geliyor.

## Mimari

| Hostname                    | Nereye                     | Ne                        |
| --------------------------- | -------------------------- | ------------------------- |
| `boskale.com`, `www.`       | `localhost:8080` (Caddy)   | Flutter web (`build/web`) |
| `games.boskale.com`         | `localhost:8081` (Caddy)   | `sports_games_web/dist`   |
| `admin.boskale.com`         | `localhost:8082` (Caddy)   | `admin_dashboard/dist`    |
| `api.boskale.com`           | `localhost:8010`           | sports_api (FastAPI)      |
| `sports-agent.boskale.com`  | `localhost:8001`           | AI Sport Agent (ayri proje: `D:\Projects\AI Sport Agent`) |

- **Tum container'lar tek compose projesi altinda: `boskale`** (`docker-compose.yml`).
  Docker Desktop'ta tek baslik altinda gorunurler.

| Container | Servis |
| --- | --- |
| `boskale-web` | Caddy — uc statik site |
| `sports-api-app` / `sports-api-db` | sports_api + Postgres |
| `boskale-agent-api` / `boskale-agent-db` | AI Sport Agent + Postgres (Xvfb ile) |

> Onceden uc ayri proje vardi (`boskale`, `sports_api`, `aisportagent`).
> Veri tasiyan dort volume ASIL ADLARIYLA `external` baglanir; proje adi
> degisince compose volume adini da degistirir ve yeni adla BOS bir volume
> olusturur. External tanim sayesinde tek bayt veri tasinmadi.
- Tunnel, **mevcut `digginalpha` tunnel'ini paylasiyor**. Ingress kurallari
  `C:\Users\emin_\.cloudflared\config.yml` icinde `boskale.com` bolumunde.
- Tum container portlari `127.0.0.1`'e bagli — LAN'dan bile erisilemez.

### Neden 8010?
Host'ta `8000` portunu DigginAlpha backend'i kullaniyor. `sports_api` container
icinde 8000'de kaliyor, host'a 8010 olarak aciliyor.

## Ilk kurulum

Asagidaki 1-2. adimlar **sende**; ben yapamam (Cloudflare panel erisimi ve
yonetici hakki gerekiyor).

### 1. Domain'i Cloudflare'e al
`boskale.com` su an Cloudflare'de **degil**.

1. Cloudflare > Add a site > `boskale.com` (Free plan yeterli).
2. Cloudflare'in verdigi iki nameserver'i registrar panelinde ayarla.
3. Zone "Active" olana kadar bekle (genelde 1-4 saat, en fazla 24 saat).

> **Temizlik:** Kurulum sirasinda zone aktif olmadigi icin `cloudflared`,
> `boskale.com`'u digginalpha.com'un alt alani sanip
> **`boskale.com.digginalpha.com`** adinda gereksiz bir CNAME olusturdu.
> Cloudflare > digginalpha.com > DNS altindan bu kaydi sil.

### 2. DNS kayitlarini olustur
Zone "Active" olduktan sonra:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Projects\SportsApp\deploy\route-dns.ps1
```

Alti hostname icin tunnel'a yonelen CNAME olusturur.

### 3. Tunnel'i Windows servisi yap
**Yonetici** PowerShell'de:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Projects\SportsApp\deploy\setup-tunnel-service.ps1
```

Su an tunnel elle baslatilmis bir process olarak calisiyor; bu script onu
servise cevirir, boylece makine yeniden baslatilinca hem boskale.com hem
digginalpha.com otomatik geri gelir. Script sonunda eski process'i sana
gosterir — servisin trafigi tasidigini dogrulayip kapat.

Servis `--config C:\Users\emin_\.cloudflared\config.yml` ile kuruluyor, yani
config'i duzenleyip `Restart-Service cloudflared` demek yeterli.

### 4. Yonetim yuzeylerinin korunmasi (YAPILDI)

`sports_api`'nin `/ui` router'i ve AI Sport Agent'in `/ui/agent` arayuzu **hicbir
kimlik dogrulamasi icermiyor**; disaridan acik olmalari sync tetiklenmesine izin
veriyordu.

Cozum icin Cloudflare Access'e gerek olmadi: tunnel ingress'inde **beyaz liste**
uygulandi. Kod tabaninda `api.boskale.com`'a hicbir referans yok ve uygulama
agent'ta yalnizca `/api/v1/mobile/*` yollarini kullaniyor (matches/live,
matches/{id}, matches/ws, logos/...).

| Adres | Durum |
| --- | --- |
| `sports-agent.boskale.com/api/v1/mobile/*` | acik (uygulama kullaniyor) |
| `sports-agent.boskale.com` diger tum yollar | `http_status:404` |
| `api.boskale.com` | yayinlanmiyor; yerelden `http://127.0.0.1:8010` |
| `admin.boskale.com` | acik ama React uygulamasi Supabase oturumu ile koruyor |

Dogrulandi (2026-08-20): `/ui`, `/ui/agent`, `/api/v1/internal/*` -> 404;
uygulamanin kullandigi uclar -> 200.

> `admin.boskale.com`'un guvenligi Supabase oturumuna ve RLS politikalarina
> dayaniyor. Daha sikisi istenirse Cloudflare Access (ucretsiz katman 50
> kullaniciya kadar) ya da Caddy'de basic auth eklenebilir.

## AI Sport Agent (ayri proje)

`sports-agent.boskale.com`'un arkasindaki servis: `D:\Projects\AI Sport Agent`.
Docker'da calisir, `restart: unless-stopped` ile yeniden baslatmada geri gelir.

Artik ayri calistirilmiyor; `deploy/docker-compose.yml` icindeki `agent-api` ve
`agent-db` servisleri olarak Boskale yigininin parcasi:

```powershell
docker compose -f deploy\docker-compose.yml up -d
```

Agent icin yapilan dort ozel ayar:

| Ayar | Neden |
| --- | --- |
| Port `127.0.0.1:8001` (`!override`) | Prod dosyasi 8000 kullaniyor, orada DigginAlpha backend'i var. `!override` sart: compose port listelerini birlestirir. |
| Xvfb sanal ekran + `DISPLAY=:99` | Kazima BASLI Chromium aciyor. Host'ta calisirken masaustunde surekli pencere aciliyordu; container'da X server olmadigi icin de aninda oluyordu. Xvfb ikisini de cozer: tarayici basli calisir, pencere gorunmez. |
| `SOFASCORE_SCHEDULE_FETCH_CONCURRENCY=3` | `.env` varsayilani 12; o hizda IP 403'e dusuyor. |
| Kalici tarayici profili (volume) | `.env`'deki `WHOSCORED_USER_DATA_DIR` bir Windows yolu; container'da yok, profilsiz cikiliyordu. |

> Veri volume'u **external**: `ai_sport_agent_postgres_data_runtime` (24 GB, gercek
> veri). Proje adiyla olusan volume BOS - override olmadan bos veritabani acilir.

> `xvfb-run` kullanilmadi: PID 1 olarak calistiginda Xvfb'yi aciyor ama komutu
> hic exec etmiyor (log bos kalir). Xvfb dogrudan baslatilip `DISPLAY` veriliyor.

## Veri senkronu (scraper'lar)

Zamanlanmis gorevler kuruludur (`scripts\register_scheduled_tasks.ps1`, yonetici
gerekmez). Kaldirmak icin ayni script `-Remove` ile.

| Gorev | Sıklık | Ne yapar |
| ----- | ------ | -------- |
| `SportsApp - Iddaa Bulletin Sync` | saatlik | Nesine bulteni -> program + oranlar + tahmin uretimi + Supabase koprusu |
| `SportsApp - Schedule Matches`    | gunde 1, 06:30 | Kanonik mac programi (sportsapipro-football-v2) |
| `SportsApp - Schedule Lineups`    | saatlik, :30 | Mac kadrolari (sportsapipro-football-v2) |
| `AI Sport Agent - Hourly Iddaa`   | saatlik, :15 | Iddaa programini biriktirir (Sofascore KAPALI). Nesine prebulteni baslamis maclari listeden dusurdugu icin gunde tek cekim gunun buyuk kismini kacirir. |
| `AI Sport Agent - Daily Ingest`   | gunde 1, 05:00 | Sofascore + iddaa toplama (bugun + yarin). Bu is olmadigi icin agent verisi 2026-07-12'de donmustu. |
| `SportsApp - Goal Notifier`       | 2 dakikada bir | Agent'taki skor degisimini yakalar, favorileyen kullanicilara gol / mac-basladi bildirimi yazar (`scripts/goal_notifier.py`). |

Supabase koprusu (`scripts/bulletin_bridge.py`) servis anahtarini Supabase
CLI'yi **kendisi cagirarak** aliyor; anahtar PowerShell'den gecmiyor ve diske
yazilmiyor. Bu bilincli bir tercih: anahtari kabuk uzerinden gecirmek iki ayri
sessiz hataya yol acmisti (CLI surum uyarisinin stderr'den terminating error'a
donmesi, ve zamanlanmis gorev oturumunda konsol kod sayfasinin anahtari
bozmasi). CLI oturumu duserse kopru adimi log'a hata yazar, zincirin geri
kalani calismaya devam eder; duzeltmek icin `supabase login`.


Loglar `scripts\logs\` altinda, 5 MB'ta tek kusak devrediyor. Gorevler
`MultipleInstances=IgnoreNew` ve 2 saat calisma siniri ile kurulu — kadro
senkronu 10+ dakika surebildigi icin saatlik tetikte ust uste binmemesi sart.

Elle calistirma:

```powershell
schtasks /Run /TN "SportsApp - Schedule Matches"
powershell -ExecutionPolicy Bypass -File scripts\schedule_sync_runner.ps1 -Scope matches
```

### Bulteni arayuzde nerede dogrularsin

Alt menude **"Bulten" diye bir sekme YOK**. `BulletinScreen`
(`lib/screens/main_layout.dart`, IndexedStack index 2) alt menude **"Kupon"**
etiketiyle duruyor (fis ikonu, soldan ucuncu). Bulteni dogrularken oraya bak.

Soldan birinci sekme **"Matches"** = `HomeDashboard` ve verisi bultenden DEGIL,
`AiSportAgentMatchProvider` uzerinden `AI_SPORT_AGENT_BASE_URL`
(`sports-agent.boskale.com`) servisinden geliyor. O servis kapaliysa bu sekme
bos gorunur; bu bultenle ilgili bir ariza degildir.

### Ana ekran neden bultenden az mac gosterebilir

Iki sekme farkli yollardan beslenir ve **ayni sayiyi gostermeleri beklenmez**:

- **Kupon** sekmesi: `sports_api` -> Nesine prebulteni -> Supabase. Saatlik
  calisip UPSERT ettigi icin gun boyunca BIRIKIR; oynanip biten maclar tabloda
  kalir.
- **Ana ekran (Matches)**: AI Sport Agent -> yalnizca iddaa ile eslesmis maclar
  (`iddaa_synced_only=True`).

Nesine prebulteni bir PRE-MATCH feed'idir: bir mac baslayinca listeden DUSER.
2026-08-20 saat 05:30'da olculdu — ayni anda:

| Kaynak | Bugun icin mac |
| --- | --- |
| Nesine prebulteni (canli cekim) | 74 |
| iddaa sportsbook API (`type=0`) | 74 |
| iddaa sportsbook API (`type=1`) | 72 (farki ileri gunlerde) |
| Supabase `bulletin_matches` (birikmis) | 280 |

Yani kaynaklar ayni fikirde; fark **birikimden** geliyordu.

Ayrica Nesine'nin AYRI bir canli feed'i var
(`bulten.nesine.com/api/bulten/getlivebultenfull`) ve icerigi prebultenle
ORTUSMUYOR: 2026-08-20 05:32'de canli feed'deki 12 futbol macinin **hicbiri**
prebultende yoktu (kod kesisimi 0). Agent artik ikisini birlestirip tekillestirerek
okuyor; olculdu: 74 -> 82 event, ana ekranda canli mac 5 -> 8. Agent gunde tek
sefer cektigi icin o ana kadar oynanmis maclari hic gormuyordu. Cozum: saatlik
`AI Sport Agent - Hourly Iddaa` isi. Staging batch'leri eklemeli oldugu ve
listeleme sorgusu gunun TUM batch'lerini birlestirdigi icin kapsam gun boyunca
genisler.

> `bulletin_matches.event_date` mac gunu DEGIL, **bulten gunudur**. Ayni
> event_date altinda kickoff'u onceki UTC gunune dusen satirlar bulunur
> (Istanbul gunu 21:00Z'de basladigi icin). Karsilastirma yaparken kickoff'a
> bakin.

### Sofascore durumu

`sports_api` icindeki `sofascore-football` saglayicisi **kullanilmiyor**; program
ve kadrolarin kaynagi `sportsapipro-football-v2`. Sofascore kazimasini yapan
taraf **AI Sport Agent**'tir ve 2026-08-20 itibariyla calisiyor (olculdu: 1811
fixture, 296 mac/gun).

Sofascore gunun programini artik tek endpoint'ten vermiyor:
`scheduled-events/{tarih}` kaldirildi (404). Yerine once
`scheduled-tournaments/{tarih}/page/N`, sonra her turnuva icin ayri
`unique-tournament/{id}/scheduled-events/{tarih}` cagrisi geliyor — bir gun icin
~700 istek. Agent bu yapiyi dogru kullaniyor.

> **IP yakma riski.** 2026-08-17'de yogun teshis trafigi bu IP'yi ~2 gun boyunca
> 403'e dusurdu. Kazima ev IP'sinden ciktigi icin yanan sey ev IP'sidir.
> Eszamanlilik `run-agent-foreground.ps1` icinde 3'e sabitli (.env varsayilani
> 12); dusurmeden calistirmayin ve senkronlari elle pes pese tetiklemeyin.

> **Rate limit:** sportsapipro da art arda cagrilarda 429 donuyor. Program
> senkronu 2026-08-19'da bu yuzden dustu ve zincir kirildi: mac yoksa kadro isi
> `no_mapped_matches` ile aninda duser, tahmin uretimi de 0 verir. Kadro veya
> tahmin bos geliyorsa **once program senkronunu** kontrol edin.

## Guncelleme yayinlama

Uc frontend'i derler, container'lari yeniler, saglik kontrolu yapar:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Projects\SportsApp\deploy\publish.ps1
```

Tunnel'a dokunmaz — statikler bind-mount oldugu icin yeni build aninda canliya
cikar.

## Dikkat: GitHub Actions workflow'u

`.github/workflows/deploy.yml` her `master` push'unda `boskale.com`'u **ayri bir
VPS'e** nginx + certbot ile deploy ediyor. DNS Cloudflare Tunnel'a dondukten
sonra bu workflow artik canliyi etkilemez ama bosuna calisir ve kafa karistirir.
Bu makineye tasindiktan sonra workflow'u devre disi birak (dosyayi sil ya da
`on:` kismini sadece `workflow_dispatch` yap).

## Sorun giderme

```powershell
Get-Service cloudflared                     # servis ayakta mi
Restart-Service cloudflared                 # config degistiyse
docker ps                                   # container'lar
docker logs sports-api-app --tail 50        # API hatalari
docker logs boskale-web --tail 50           # Caddy
& 'C:\Program Files (x86)\cloudflared\cloudflared.exe' tunnel ingress validate
```

Yerel saglik kontrolu (tunnel'i devre disi birakarak):

```powershell
foreach ($p in 8080,8081,8082,8010) {
  try { "$p -> $((Invoke-WebRequest "http://127.0.0.1:$p/" -UseBasicParsing -TimeoutSec 10).StatusCode)" }
  catch { "$p -> $($_.Exception.Message)" }
}
```

Config yedegi: `C:\Users\emin_\.cloudflared\config.yml.bak-20260817`
