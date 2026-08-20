# Boskale — İddaa Analiz Platformu

Türkiye iddaa bültenine oynayan kullanıcı için analiz altyapısı: bülten ve oran
takibi, bilimsel temelli tahmin motoru, kupon oluşturucu, bankroll yönetimi ve
tipster topluluğu.

Canlı: **boskale.com** — kullanıcının kendi Windows makinesinden, Cloudflare
Tunnel üzerinden yayınlanıyor. Kurulum ve işletme: [`deploy/README.md`](deploy/README.md).

Ürün yol haritası ve faz durumları: [`docs/iddaa-analiz-platformu-yol-haritasi.md`](docs/iddaa-analiz-platformu-yol-haritasi.md).

> Bu depo tek bir uygulama değil, birlikte çalışan birkaç parçadır. Aşağıdaki
> tablo hangi parçanın ne işe yaradığını ve nerede yayınlandığını gösterir.

---

## Bileşenler

| Dizin | Teknoloji | Ne yapar | Yayın adresi |
| --- | --- | --- | --- |
| `lib/` + `android/` `ios/` `web/` | Flutter (Dart) | Ana uygulama. Mobil ve web aynı koddan derlenir. 167 dart dosyası. | `boskale.com`, `www` |
| `sports_api/` | FastAPI + Postgres | Kanonik spor verisi API'si + tahmin motoru. Sağlayıcıdan bağımsız veri modeli. | `api.boskale.com` (:8010) |
| `admin_dashboard/` | React + Vite + TS | Yönetim paneli: kullanıcılar, maçlar, ürünler, duyurular, geri bildirim, destek sohbeti, botlar, temalar. | `admin.boskale.com` |
| `sports_games_web/` | React + Vite + TS | Mini oyunlar: penaltı, kaleci refleksi, kafa vurma, top sektirme, gol ritmi, FlappyBall. | `games.boskale.com` |
| `supabase/` | Postgres + Deno | 104 migration, 15 edge function. Kimlik doğrulama, realtime, bildirim, mağaza, kupon çözümleme. | Supabase bulutu |
| `scripts/` | PowerShell + Python | Veri senkron koşucuları ve Supabase köprüsü. Zamanlanmış görevler bunları çağırır. | — (yerel) |
| `deploy/` | Caddy + Docker + cloudflared | Yayın altyapısı: statik sunucu, tunnel yapılandırması, yayın scriptleri. | — (yerel) |
| `simulation_engine/` | Node.js + Ollama | Bot swarm: olay güdümlü konuşma yönetmeni, Mackolik kazıyıcı, bge-m3 hafıza. Elle başlatılır (`npm start`); henüz zamanlanmış görev yok. | — |
| `test/` | flutter_test | 26 test dosyası, 114 test. | — |
| `docs/`, `stitch_assets/`, `design_system.md` | — | Yol haritası, UX stratejisi, tasarım referansları ve HTML mockup'lar. | — |

Depo dışında ama zorunlu bir bağımlılık:

| Proje | Ne yapar | Yayın adresi |
| --- | --- | --- |
| `D:\Projects\AI Sport Agent` | Uygulamanın maç listesi, kadro, istatistik ve analiz sihirbazı kaynağı. FastAPI + Postgres + Playwright. | `sports-agent.boskale.com` (:8001) |

---

## Mimari

```
                        ┌──────────────────────────────┐
   Kullanıcı ───────────>│  boskale.com (Flutter web)   │
                        └──────┬────────────────┬──────┘
                               │                │
                    Supabase (auth,             │  AI_SPORT_AGENT_BASE_URL
                    realtime, bülten,           │
                    mağaza, kupon)              ▼
                               │      ┌─────────────────────────┐
                               │      │ sports-agent.boskale.com│
                               │      │  maç / kadro / istatistik│
                               │      └──────────┬──────────────┘
                               │                 │
                               │                 ▼
                               │        Postgres (yerel, :5434)
                               │                 ▲
                               │                 │ Sofascore kazıma
                               │                 │ (bu makinenin IP'sinden)
                               │
                        ┌──────┴───────────────────────────┐
                        │ bulletin_bridge.py (bu makinede) │
                        └──────┬───────────────────────────┘
                               │
                        ┌──────▼──────────────┐
                        │ sports_api (:8010)  │──> Nesine (iddaa bülteni)
                        │ Postgres (:5432)    │──> sportsapipro (program/kadro)
                        └─────────────────────┘
```

Her şey kullanıcının makinesinde çalışır; dışarı açılan port yoktur, trafik
Cloudflare Tunnel üzerinden gelir. Sofascore kazımanın bu makineden yapılması
bilinçli bir tercihtir: veri merkezi IP'si yerine ev IP'si kullanılır.

---

## Veri akışları

Üç ayrı akış var; hangi ekranın hangi akıştan beslendiğini bilmek arıza
teşhisinde kritiktir.

### 1. İddaa bülteni → Kupon sekmesi

```
Nesine CDN → sports_api (:8010) → yerel Postgres
           → bulletin_bridge.py → Supabase (bulletin_matches / _odds / _predictions)
           → uygulama "Kupon" sekmesi
```

Saatlik zamanlanmış görev: program → oranlar → tahmin üretimi → Supabase köprüsü.
Koşucu: [`scripts/bulletin_sync_runner.ps1`](scripts/bulletin_sync_runner.ps1).

Servis anahtarı PowerShell'den geçmez; `bulletin_bridge.py` Supabase CLI'yi
kendisi çağırır. Gerekçesi scriptin başında yazılı.

### 2. Kanonik program ve kadrolar

```
sportsapipro-football-v2 → sports_api → yerel Postgres
```

Koşucu: [`scripts/schedule_sync_runner.ps1`](scripts/schedule_sync_runner.ps1)
(program günde 1, kadrolar saatlik). Ölçülmüş değerler: program 214 maç,
kadro 81 maç / 0 hata.

### 3. Ana ekran maç listesi

```
Sofascore (bu makinenin IP'sinden, Playwright) → AI Sport Agent → yerel Postgres (:5434)
                                                → sports-agent.boskale.com
                                                → uygulama "Matches" sekmesi
```

Agent Docker'da, **sanal ekran (Xvfb)** ile çalışır: kazıma başlı Chromium
açar ama masaüstünde pencere görünmez. Ayrıntı ve gerekçe:
[`deploy/README.md`](deploy/README.md). Günlük toplama işi:
[`scripts/run_agent_ingest.ps1`](scripts/run_agent_ingest.ps1) (05:00, bugün + yarın).

**Yedek kaynak:** Supabase `matches` tablosu da doludur; onu `sync-live-matches`
edge function'ı **Highlightly API**'den besler (Sofascore değil). Uygulama
`lib/providers/match_provider.dart` içindeki tek satır değiştirilerek bu kaynağa
alınabilir — Sofascore erişimi kesilirse kullanışlı bir kaçış yolu. Fonksiyonu
tetikleyen zamanlama bu depoda tanımlı değildir; Supabase panelinden
yönetiliyor olmalı.

---

## Yerel geliştirme

### Flutter uygulaması

```bash
flutter pub get
flutter run                     # cihaz/emülatör
flutter test                    # 114 test
flutter analyze
```

Yapılandırma `--dart-define` ile gelir; kök `.env` dosyasından okunur:

```bash
flutter run --dart-define-from-file=.env
```

Beklenen anahtarlar: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `LIVEKIT_URL`,
`GAMIFICATION_API_URL`, `GEMINI_API_KEY`, `CRISP_WEBSITE_ID`, `SUPPORT_EMAIL`,
sosyal medya bağlantıları. Ek olarak kodda `String.fromEnvironment` ile okunan
`AI_SPORT_AGENT_BASE_URL`, `FIREBASE_WEB_*`, `ADMOB_*`, `REVENUECAT_*`.

> `--dart-define-from-file` olmadan derleme **başarılı olur ama uygulama
> Supabase'e bağlanamaz.** Sessiz bir hata olduğu için kolayca gözden kaçar.

### sports_api

```bash
cd sports_api
cp .env.example .env            # doldur
pytest                          # 23 test dosyası
```

Container'lar tek yığında çalışır (compose projesi `boskale`): Caddy, sports_api
ve AI Sport Agent aynı dosyada tanımlıdır, ayrı ayrı kaldırılmaz.

```bash
docker compose -f deploy/docker-compose.yml up -d
```

Container'da Playwright + Chromium kuruludur (Sofascore sağlayıcısı için) ve
uygulama root olmayan bir kullanıcıyla çalışır — Chromium root altında
`--no-sandbox` olmadan açılmaz.

### React arayüzleri

```bash
cd admin_dashboard    # veya sports_games_web
npm install
npm run dev
npm run build
```

`.env` / `.env.local` içinde `VITE_SUPABASE_URL` ve `VITE_SUPABASE_ANON_KEY`.

### Supabase

```bash
supabase start                  # yerel yığın
supabase db push                # migration'ları uygula
supabase functions deploy <ad>
```

---

## Tahmin motoru

`sports_api/app/ml/` altında:

| Modül | İş |
| --- | --- |
| `dixon_coles.py` | Dixon-Coles gol modeli (Poisson + düşük skor düzeltmesi) |
| `score_matrix.py` | Skor olasılık matrisi |
| `market_derivations.py` | Matristen market olasılıkları (1X2, alt/üst, KG, handikap) |
| `calibration.py` | Olasılık kalibrasyonu |
| `market_blend.py` | Model ile piyasa oranlarının harmanlanması (Shin) |
| `value_detection.py` | Value pick tespiti |
| `backtest.py` | Geriye dönük test çekirdeği |

Tahmin üretimi `POST /api/v1/internal/predictions/run?target_date=YYYY-MM-DD`.

---

## Yayın

Tam runbook: [`deploy/README.md`](deploy/README.md). Kısaca:

```powershell
powershell -ExecutionPolicy Bypass -File deploy\publish.ps1
```

Üç frontend'i derler, çıktıları `deploy/www/` altına kopyalar, container'ları
yeniler ve sağlık kontrolü yapar. Derleme çıktıları Caddy'ye **doğrudan
bağlanmaz**: `flutter build web` çıktıyı dakikalar boyunca yerinde yazdığı için
bağlı klasör canlıya yarım site servis ediyordu.

Zamanlanmış veri senkronu:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\register_scheduled_tasks.ps1
```

### CI

`.github/workflows/verify.yml` her push ve PR'da `flutter analyze` +
`flutter test`, `sports_api` için `ruff` + `pytest`, iki React projesi için
`lint` + `build` koşar.

`deploy.yml` ve `sports-games-web.yml` artık var olmayan bir VPS'e deploy
ediyordu ve her push'ta hata veriyordu; tetikleyicileri `workflow_dispatch`'e
indirildi (referans olarak duruyorlar).

---

## Bilinen sorunlar ve tuzaklar

Bunlar aktif durumlardır; koda bakınca anlaşılmayan ama işletmede karşınıza
çıkacak şeyler.

**Sofascore hız sınırı — IP yakma riski.** Sofascore günün programını artık tek
endpoint'ten vermiyor; `scheduled-events/{tarih}` kaldırıldı (404). Yerine önce
`scheduled-tournaments/{tarih}/page/N`, sonra her turnuva için ayrı
`unique-tournament/{id}/scheduled-events/{tarih}` çağrısı geliyor — bir gün için
~700 istek. Sağlayıcı bunları paralel gruplar halinde, gruplar arası beklemesiz
atıyor. `.env`'deki varsayılan 12 eşzamanlılık ile IP **403'e düşüyor**
(2026-08-17'de yaşandı, ~2 gün sürdü). `run-agent-foreground.ps1` bunu 3'e
sabitler; düşürmeden çalıştırmayın. Kazıma ev IP'sinden çıktığı için yanan şey
ev IP'nizdir. Kalıcı çözüm kapsamı bültendeki turnuvalarla sınırlamak olur
(~700 yerine 20-40 istek).

**Gol bildirimi iki ayrı yoldan üretilir.** Depodaki Postgres trigger'ı
(`trg_match_events_notifications`) `public.matches` tablosunu dinler; orayı
Highlightly besler ve uygulamanın ana ekranı artık oradan okumadığı için bu yol
ikincildir. Agent kaynaklı bildirimleri `scripts/goal_notifier.py` üretir
(2 dakikada bir, `source='agent'` + `external_match_id`). Trigger'ın kullanıcı
tercihini okumaması ayrı bir hataydı;
`supabase/migrations/20260820043000_notification_prefs_respected.sql` bunu
düzeltir; 2026-08-20'de uygulandı ve migration geçmişine işlendi. Tüm birikmiş
migration'ları göndermek yerine (`db push`) yalnızca bu ifade
`supabase db query --linked` ile çalıştırıldı — depoda 104 migration ve birkaç
`remote_history_placeholder` var, yani şema kayması mevcut ve toplu push riskli.

**`AI Sport Agent/.env` içinde `PLAYWRIGHT_HEADLESS` iki kez tanımlı** (satır 20
`true`, satır 46 `false`). python-dotenv ilk değeri tuttuğu için dosyadaki
`false` tercihi sessizce yok sayılıyor ve tarayıcı headless açılıyor. Tekrarın
silinmesi gerekiyor.

**AI Sport Agent'ın `/ui/agent` arayüzü hâlâ korumasız.** `sports_api` tarafı
2026-08-20'de kapatıldı: `verify_internal_token` production'da fail-closed
(token yoksa 500), `/ui` router'ı guard altında, `SPORTS_API_DEBUG` varsayılanı
`false` olduğu için `/docs` de kapalı. Token `X-Internal-Token` ya da
`Authorization: Bearer` ile kabul ediliyor — Supabase edge fonksiyonları
ikincisini gönderiyor, eskiden bu uyuşmazlık token'ı fiilen etkisiz kılıyordu.
AI Sport Agent ayrı bir proje ve aynı düzeltmeyi almadı. 2026-08-20'de
tunnel ingress'inde beyaz liste uygulandı: `api.boskale.com` artık
yayınlanmıyor, `sports-agent.boskale.com`'da yalnızca `/api/v1/mobile/*` açık,
gerisi 404. Yeni bir uç yayınlarken bu kısıtı hatırlayın — beyaz listeye
eklenmeyen yol dışarıdan 404 döner. Detay: `deploy/README.md`.

**PowerShell native stderr tuzağı.** `$ErrorActionPreference='Stop'` altında
native bir komutun (docker, supabase, python) stderr'e yazması terminating
error'a dönüşür ve başarılı komutlar scripti öldürür. Bu depoda dört kez ayrı
arızaya yol açtı. Yeni script yazarken başarıyı **yalnızca çıkış kodundan**
belirleyin; örnek: `scripts/bulletin_sync_runner.ps1` içindeki `Invoke-Docker`.
Ayrıca PowerShell 5.1'de `>>` UTF-16 yazar — log dosyaları için
`Out-File -Encoding utf8` kullanın.

**Port çakışmaları.** Bu makinede `:8000` DigginAlpha backend'inde. `sports_api`
host'ta `:8010`, AI Sport Agent `:8001`, agent veritabanı `:5434`.

**`simulation_engine/` çalıştırma katmanı eksik.** Motor yeniden yazıldı
(olay güdümlü yönetmen, yoğunluk denetimi, `app_settings` üzerinden kill
switch) ve `npm test` ile 57 birim testi geçiyor; ama projedeki diğer job'lar
`scripts/register_scheduled_tasks.ps1` ile zamanlanmışken bu hâlâ elle
başlatılıyor. Servis/scheduled task kaydı yapılmalı.

Ön koşullar: yerel Ollama (`gemma4:12b` üretim, `bge-m3` embedding) ve
`supabase/migrations/20260820120000_simulation_engine_v2.sql`'in uygulanmış
olması. Durumu doğrulamak için `node diagnose.js`, kaliteyi görmek için
`node dryrun.js` (DB'ye yazmaz).

---

## Test

```bash
flutter test                      # 114 test
flutter analyze                   # info seviyesi lint uyarıları mevcut
cd sports_api && pytest           # 206 test
cd admin_dashboard && npm run lint
```

---

## Gereksinimler

- Flutter 3.41+ / Dart SDK >=3.0.0 <4.0.0
- Python >=3.12 (sports_api)
- Node.js 20+ (React arayüzleri, simulation_engine)
- Docker Desktop
- Supabase CLI (bülten köprüsü oturum gerektirir)
- cloudflared (yayın)
