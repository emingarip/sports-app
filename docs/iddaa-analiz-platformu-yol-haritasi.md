# İddaa Analiz Platformu — Yol Haritası ve Takip Dokümanı

> **Amaç:** SportsApp'i, Türkiye iddaa bültenine bahis yapmak isteyen kullanıcının ihtiyaç duyduğu
> tüm analiz altyapısını barındıran, bilimsel temellere dayanan ve güçlü community duygusu taşıyan
> bir analiz platformuna dönüştürmek.
>
> **Bu doküman canlı takip dokümanıdır.** Her iş kalemi tamamlandığında `[ ]` → `[x]` yapılır ve
> "Durum Özeti" tablosu güncellenir. Tasarım kararları ilgili fazın altına not düşülür.

- Oluşturulma: 2026-07-10
- Son güncelleme: 2026-07-11
- Durum etiketi anahtarı: ⬜ başlamadı · 🟨 devam ediyor · ✅ tamamlandı · ⏸️ bekliyor/bloklu

---

## Durum Özeti

| Faz | Kapsam | Durum |
|---|---|---|
| Faz 0 | Temel hijyen: puan durumu, takım profili, takım bildirimleri, H2H | ⬜ |
| Faz 1 | İddaa bülteni + market taksonomisi (veri temeli) | ✅ (canlı kaynak 2026-07-11'de doğrulandı: Nesine CDN, 231 maç / 4.962 tick) |
| Faz 2 | Tahmin motoru (Dixon-Coles + kalibrasyon + value tespiti) | ✅ (GBM ⏸️; 2.5 bilimsel genişletmeler 🟨: Shin + harmanlama ✅, backtest çekirdeği ✅, walk-forward + xG ⏸️) |
| Faz 3 | Analiz UX (bülten ekranı, maç analiz merkezi, kupon oluşturucu, bankroll) | ✅ (sparkline + canlı maç eşleştirmesi ⏸️) |
| Faz 4 | Community (tipster sicili, kupon paylaşımı, ROI/CLV lider tablosu) | ✅ çekirdek (bildirim, topluluk yüzdesi, Wilson sıralama, oda kartı ⏸️) |

---

## 0. İlkeler ve Çerçeve

### 0.1 Bilimsel ilkeler (pazarlama değil, mühendislik taahhüdü)

1. **Kalibrasyon > isabet.** Model "%60" dediğinde uzun vadede gerçekten ~%60 tutmalı.
   Ölçüm: Brier score, log-loss, reliability diagram. Kalibrasyon metrikleri kullanıcıya da gösterilir (şeffaflık = güven).
2. **Değer (+EV) odaklılık.** "Kazanacak maçı bilmek" değil, *model olasılığı × oran > 1 + eşik*
   olan seçimleri işaretlemek. Value yoksa "oynanmaz" demek de bir analiz çıktısıdır.
3. **Tek kaynak model:** Skor dağılımı modeli (Dixon-Coles) tüm marketlerin olasılığını tek tutarlı
   kaynaktan türetir (MS, Alt/Üst, KG, İY/MS, handikap). Market başına ayrı ad-hoc model yok.
4. **CLV (Closing Line Value)** hem modelin hem tipster'ların uzun vadeli yetenek ölçüsüdür; kâr/zarar
   kısa vadede gürültüdür.
5. **Bankroll disiplini:** Kelly kriteri (kesirli Kelly) tabanlı öneri; kullanıcıya kupon başına
   risk yüzdesi önerilir, asla "hepsini bas" tipi çıktı üretilmez.
6. **Bilim motorun dilidir, arayüzün dili değil.** Standart kullanıcı EV/CLV/Kelly bilmez;
   varsayılan sunum basit ("değerli oran ✅ / oynama ⚠️", yüzdeler, form dizileri), bilimsel
   ayrıntı isteğe bağlı katmanda yaşar. *(2026-07-11 persona analizi çıktısı.)*

### 0.2 Yasal / etik çerçeve

- Türkiye'de sabit ihtimalli bahis yalnızca Spor Toto lisanslı operatörler (iddaa bayileri, Nesine, Misli vb.) üzerinden oynanabilir.
  **Bu uygulama bahis oynatmaz, para akışı barındırmaz** — analiz, içerik ve topluluk platformudur.
- Kupon oluşturucu **"analiz kuponu"**dur: seçim + olasılık + EV hesabı üretir; oynama işlemi kullanıcının
  lisanslı operatöründe gerçekleşir. Lisanssız sitelere yönlendirme/entegrasyon yapılmaz.
- Sorumlu oyun: kayıp kovalama uyarıları, seri kayıp sonrası soğuma önerisi, 18+ ibaresi. (Faz 3'te iş kalemi.)
- Mevcut K-Coin ekonomisi **sanal kalır**; gerçek para ile hiçbir noktada birleşmez.

### 0.3 Mevcut mimari (özet)

| Katman | Teknoloji | Rol |
|---|---|---|
| `sports_api/` | Python, FastAPI, SQLAlchemy 2 async, Alembic, PostgreSQL | Veri/ML çekirdeği: sağlayıcı ingestion, kanonik şema, feature pipeline |
| `supabase/` | Postgres + RLS, Deno Edge Functions, Realtime | Ürün backend'i: kullanıcı, sosyal, K-Coin, bildirim |
| `lib/` | Flutter + Riverpod 3 (codegen) | Mobil/web istemci |
| `admin_dashboard/` | React + Vite + TS | Operasyon paneli |
| `simulation_engine/` | Node, Puppeteer, LLM | Bot swarm / topluluk canlılığı |

**Bu pivot için üzerine inşa edilen mevcut varlıklar:**

- `sports_api/app/db/models/domain.py` — `MatchMarketTick` (oran zaman serisi: `market_type`,
  `selection_key`, `line_value`, `odds_decimal`, `implied_prob`, `normalized_prob`, `bookmaker_key`, faz),
  `MatchFeatureSnapshot` (~100 kolon feature + hazır etiketler: `label_home_win`, `label_over25_from_snapshot`,
  `label_final_result_1x2`, `label_next_goal_team`), `TeamRatingDaily` (ELO, form, xG/xGA formu),
  `PlayerRatingDaily`, `MatchLiveStatFrame`.
- `sports_api/app/services/feature_math.py` — `implied_probability`, `normalize_implied_probabilities`,
  `parse_formation`, `lineup_strength`.
- `sports_api/app/services/feature_rating_service.py` — ELO motoru (base 1500, K 20, ev avantajı 55).
- `sports_api/app/providers/base.py` — `ProviderClient` sözleşmesi + `ProviderMatchMarketTickSeed`.
- Flutter: `lib/models/match_lineup.dart` (`FormationPairStatistics`), maç detay sekmeleri,
  `prediction_market_screen.dart` (K-Coin sanal market), LiveKit sesli odalar, takip/rozet/lider tablosu.

---

## Faz 0 — Temel Hijyen (Fan Deneyimi)

**Hedef:** Standart futbol tutkununun bir skor uygulamasından beklediği temel içerik eksiksiz;
analiz katmanının üzerine oturacağı güven zemini hazır. *(2026-07-11 persona analizi: puan durumu
ve takım profili placeholder'ken analiz katmanı tutunma yaratmaz — önce hijyen.)*

**DoD:** Lig profili puan durumu + fikstür gösteriyor; takım profili fikstür + form + kadro
gösteriyor; kullanıcı favori takımı için bildirim aboneliği seçebiliyor; maç detayında H2H var.

### 0.A Puan durumu ve lig profili

- [ ] `sports_api`: puan durumu üretimi (kanonik `Match` geçmişinden hesap ya da sağlayıcı
      standings verisi) + `GET /api/v1/leagues/{id}/standings`; Supabase senkronu
      (Flutter'ın tek kaynaktan okuma deseni korunur).
- [ ] `league_profile_screen.dart` doldurulması (şu an placeholder): puan durumu tablosu
      (G-B-M form şeridiyle), fikstür listesi.
- [ ] "Bu maç kazanılırsa X. sıraya çıkar" bağlam verisi — analiz ekranına besleme (3.2/3.5).

### 0.B Takım profili

- [ ] `team_profile_screen.dart` doldurulması (şu an placeholder): fikstür, son 5 maç form
      şeridi, kadro, temel sezon istatistikleri; ELO/form/xG trendi `TeamRatingDaily`'den.
- [ ] Takım favorileme — mevcut maç favorileme ve takip altyapısıyla bütünleşme.

### 0.C Takım bazlı bildirimler

- [ ] `NotificationPreferences` genişletmesi: favori takım bazlı opt-in — maç başlangıcı, gol,
      **kadro açıklandı** (lineup verisi + FCM altyapısı mevcut). Global aç/kapa yerine
      takım seçimli abonelik.
- [ ] Push tıklama yönlendirmesi: `onMessageOpenedApp` şu an boş — bildirimden ilgili maç
      detayına deep-link.

### 0.D Maç detayına H2H

- [ ] Maç detayına H2H bölümü: son karşılaşmalar + skorlar (AI sihirbazındaki "hızlı bağlam"
      H2H verisi yeniden kullanılır; ayrı sekme ya da OVERVIEW içinde kart).

---

## Faz 1 — İddaa Bülteni ve Market Taksonomisi

**Hedef:** Türkiye iddaa bültenindeki maçlar ve oranlar, kanonik şemaya (iddaa market taksonomisiyle)
akıyor; API üzerinden "günün bülteni" servis ediliyor.

**Tamamlanma kriteri (DoD):** `GET /api/v1/bulletin?date=...` iddaa program bilgisi + temel marketlerin
(MS, Çifte Şans, Alt/Üst, KG, İY/MS, Handikap) güncel oranlarını döner; oran değişim geçmişi
`MatchMarketTick` üzerinden sorgulanabilir; birim testleri fixture'larla geçer.

### 1.1 İddaa market taksonomisi ✅

- [x] `sports_api/app/domain/iddaa_markets.py`: 13 market tanımı (MS, CS, AU_1_5/2_5/3_5, KG,
      IY_MS, H_MS_1, H_MS_MINUS_1, IY, IY_AU_0_5, IY_AU_1_5, TG) — TR adlar, seçim etiketleri,
      `market_type`/`line_value` eşlemesi. `get_market_by_code`, `get_market_for_tick`,
      `selection_label_tr` yardımcıları.
- [x] Sağlayıcı normalizasyonu: `normalize_provider_market` / `normalize_provider_selection` —
      Türkçe diakritik katlama (`_fold_text`) ile hem TR hem EN market adları eşleniyor;
      mevcut jenerik değerler (`1x2`, `totals`, `next_goal`) aynen korunuyor.
- [x] Birim testleri: `tests/test_iddaa_markets.py` (10 test) — round-trip tutarlılık,
      bilinmeyen market → `unmapped`.

### 1.2 Bülten sağlayıcısı (provider) ✅

- [x] `sports_api/app/providers/iddaa_bulletin.py`: `IddaaBulletinClient` (slug `iddaa-bulletin`).
      Alan-adı toleranslı JSON parser (Nesine/Misli tarzı kısaltmalar dahil), Istanbul→UTC saat
      dönüşümü, market cache'i ile `get_prematch_markets`. Config: `SPORTS_API_IDDAA_BULLETIN_*`
      (base URL, path, api key, timeout, retry).
- [x] `providers/registry.py`'ye kayıt. *(Karar: `hybrid.py` kompozisyonuna dahil edilmedi —
      mevcut `matches` + `market-backfill` scope'ları bu provider ile doğrudan çalışıyor,
      ayrı senkron job'a gerek kalmadı.)*
- [x] Fixture testleri: `tests/test_iddaa_bulletin_provider.py` + `tests/fixtures/*.json` (6 test).
- [x] *Canlı kaynak doğrulaması (2026-07-11):* `https://cdnbulten.nesine.com/api/bulten/getprebultenfull`
      canlı test edildi (HTTP 200, gzip; httpx otomatik açıyor) — gerçek payload parser'dan uçtan uca
      geçirildi: **231 futbol maçı, 4.962 oran tick'i, 9 kanonik market tipinin tamamı** doğru üretildi
      (kickoff UTC dönüşümü, lig çözümü, MBS dahil). 12 MTID eşlemesinin tamamı iddaa.com'un resmi
      market sözlüğüyle (`sportsbookv2.iddaa.com/sportsbook/get_market_config`) çapraz doğrulandı —
      örn. MTID 7→"1. Yarı Sonucu" (MST 88), 43→"Toplam Gol" (MST 4), 268→"Handikaplı MS" (MST 100).
      Dikkat: MST 36 "**2.** Yarı Sonucu" ve MST 603/604 "**Ev Sahibi/Deplasman** Alt/Üst" — bunlar
      bilinçli olarak eşleme dışı (yanlış markete yazılmamalı).
- *Not — alternatif/ek kaynaklar (2026-07-11 keşfi):*
  - `sportsbookv2.iddaa.com/sportsbook/events?st=1` (iddaa.com resmi bülteni, aynı MST kodları,
    seçim adları gömülü; ayrıca **korner/kart marketleri** var → Ar-Ge v2 için hazır kaynak).
  - `sportsbookv2.iddaa.com/sportsbook/outcome-play-percentages?sportType=1` (HTTP 200) —
    **resmi "halkın yüzdesi" verisi**; Faz 4.2'deki topluluk yüzdesi işine K-Coin verisinden daha
    güçlü bir kaynak (ikisi yan yana da gösterilebilir).

### 1.3 Bülten senkron işi ve API ✅

- [x] *(Karar — ADR 5)* Ayrı `bulletin_sync_job.py` yazılmadı: mevcut
      `POST /internal/sync/providers/iddaa-bulletin?scope=matches` (program) ve
      `scope=market-backfill` (oranlar) uçları bu işi görüyor; oran tazeleme sıklığı
      çağıran zamanlayıcının (cron) sorumluluğunda.
- [x] `GET /api/v1/bulletin` (tarih/lig/market filtreli) — `app/api/routes/bulletin.py`,
      `app/schemas/bulletin.py`, `app/services/bulletin_service.py`.
- [x] `GET /api/v1/matches/{id}/odds` — marketler + seçim bazlı oran değişim geçmişi.
- [x] Oran hareketi türetimleri: açılış/güncel oran, `movement_pct`, `is_dropping` —
      `build_market_views` / `build_selection_histories` saf fonksiyonları (DB'siz test edilebilir),
      `tests/test_bulletin_service.py` (6 test).

### 1.4 Supabase köprüsü ✅

- [x] Migration `supabase/migrations/20260711090000_bulletin_infrastructure.sql`:
      `bulletin_matches` + `bulletin_odds` (RLS: herkese okuma, yazma yalnız service role;
      realtime publication'a ekli).
- [x] Edge function `supabase/functions/sync-bulletin/index.ts`: sports_api
      `GET /api/v1/bulletin` → Supabase upsert (secrets: `SPORTS_API_BASE_URL`,
      opsiyonel `SPORTS_API_TOKEN`).

---

## Faz 2 — Tahmin Motoru

**Hedef:** Her bülten maçı için kalibre edilmiş olasılıklar, tüm ana marketlere türetilmiş
olasılık seti ve value işaretleri üretiliyor; kalibrasyon sürekli ölçülüyor.

**DoD:** `GET /api/v1/matches/{id}/prediction` model olasılıkları + market karşılaştırması + EV döner;
backtest raporu (Brier, log-loss, kalibrasyon eğrisi) üretilebiliyor; günlük batch skorlama çalışıyor.

### 2.1 Taban model: Dixon-Coles ✅

- [x] `app/ml/dixon_coles.py`: zaman ağırlıklı (exponential decay, yarı ömür 240 gün) Dixon-Coles;
      hücum/savunma güçleri + ev avantajı; rho düşük skor düzeltmesi. Saf Python (numpy'sız).
      Fit: kapalı-form gradyanlı ağırlıklı Poisson MLE + rho için 1-B profil grid araması.
      Min. 30 maç şartı; bilinmeyen takım → lig ortalaması fallback; JSON serileştirme.
- [x] `app/ml/score_matrix.py`: λ'lar → 0-10 gol skor matrisi (DC tau düzeltmeli, normalize).
- [x] `app/ml/market_derivations.py`: tüm 13 iddaa marketi tek matristen türetiliyor
      (İY marketleri yarı-bölüşüm yaklaşımı: ilk yarı gol payı 0.45; İY/MS bağımsız yarılar
      varsayımıyla birleşik dağılım).
- [x] Eğitim verisi: kanonik `Match` geçmişi (lig bazlı, son 3 yıl) — `PredictionService` içinde.
- [x] Birim testleri: `tests/test_ml_dixon_coles.py` (12 test) — sentetik veriden parametre
      geri kazanımı, olasılık tutarlılığı, rho'nun beraberlik olasılığına etkisi.

### 2.2 Kalibrasyon + value katmanı ✅ / ⏸️

- [x] `app/ml/calibration.py`: Brier (ikili + çok sınıflı), log-loss, reliability bin'leri, ECE.
- [x] `app/ml/value_detection.py`: EV = p×oran − 1 (eşik %5), min. olasılık filtresi (%10),
      çeyrek Kelly (`kelly_fraction`), `find_value_picks` (EV'ye göre sıralı).
- [x] Testler: `tests/test_ml_value_and_calibration.py` (8 test).
- [ ] ⏸️ *Opsiyonel üst katman:* `MatchFeatureSnapshot` üzerinde GBM stacking (`feature_model.py`,
      `train_pipeline.py`) — DC taban modeli üretimde veri biriktirdikten ve kalibrasyon raporu
      gerçek örneklem gösterdikten sonra eklenecek (etiketler hazır).

### 2.3 Value tespiti ve servis katmanı ✅

- [x] DB: `MatchPrediction` modeli (`app/db/models/domain.py`) + alembic migration
      `20260711_000007_match_predictions.py` — market olasılıkları + value_picks JSONB,
      model sürümü (`dc-v1`), faz, benzersizlik (match, version, phase).
- [x] `services/prediction_service.py`: lig başına DC fit (run içinde cache), tüm marketlerin
      türetimi, bülten oranlarıyla çapraz value tespiti, upsert. Tetikleme:
      `POST /internal/predictions/run?target_date=` (token korumalı).
- [x] API: `GET /api/v1/matches/{id}/prediction` (model vs oran karşılaştırmalı),
      `GET /api/v1/bulletin/value-picks`, `GET /api/v1/bulletin/predictions` (köprü için toplu),
      `GET /api/v1/model/calibration` (şeffaflık panosu verisi).
- [x] Testler: `tests/test_prediction_routes.py`.

### 2.4 Supabase köprüsü ✅

- [x] Migration `20260711091000_bulletin_predictions_bridge.sql`: `bulletin_predictions`
      (RLS herkese okuma, realtime'a ekli).
- [x] Edge function `supabase/functions/sync-predictions/index.ts`:
      `GET /api/v1/bulletin/predictions` → tek istekle upsert (sync-bulletin'den sonra çalıştırılır).

### 2.5 Bilimsel genişletmeler (EV güvenilirliği) 🟨

*2026-07-11 bilimsel yaklaşım analizi — üçü de EV işaretlerinin güvenilirliğini doğrudan etkiler,
maliyetleri düşük; DC üretimde veri biriktirirken paralel alınabilir.*

- [x] **Shin yöntemi ile marj arındırma:** `feature_math.py`'ye `shin_probabilities` eklendi —
      z (insider payı) bisection ile çözülüyor; <2 geçerli oran / marjsız kitap / dejenere kök
      durumlarında orantısal normalizasyona düşüyor. Testler: favori/sürpriz asimetrisi,
      3-yollu market, marjsız kitap, None girdiler (`tests/test_ml_shin_and_blend.py`). *(ADR 9)*
- [x] **Piyasa harmanlama (market-as-prior):** `app/ml/market_blend.py` —
      `blend_probabilities` (logit uzayında ağırlıklı harman + renormalizasyon) ve
      `blend_markets` (yalnız tam kapsanan marketler harmanlanır; eksik/askıya alınmış seçimli
      market saf model olasılığıyla geçer). `PredictionService.generate_for_date` value tespitini
      artık harmanlanmış olasılıkla yapıyor (`blend_model_weight`, varsayılan 0.5 —
      **ağırlık öğrenimi backtest verisi biriktikçe ⏸️**). Saklanan `market_probs` saf DC kalıyor
      (kalibrasyon geçmişi karşılaştırılabilir); her value pick `dc_probability` +
      `market_probability` alanlarıyla şeffaf. *(ADR 10)*
- [ ] 🟨 **Bahis simülasyonu backtest'i:** çekirdek hazır — `app/ml/backtest.py`
      (`simulate_bets`: kesirli Kelly ya da flat stake, ROI, isabet, maksimum drawdown;
      `compare_stakings`). **Bekleyen:** walk-forward veri montajı (sonuçlanan tahmin + kapanış
      oranı geçmişinden `SettledBet` üretimi) ve kalibrasyon raporuna ek bölüm — üretim verisi
      biriktikçe servis katmanına bağlanacak.
- [ ] **xG-hibrit takım gücü:** DC eğitiminde ham skorun yanına xG/xGA sinyali (skor 90 dakikada
      ~2.7 gollük seyrek örneklem; xG aynı maçtan daha fazla bilgi taşır — `TeamRatingDaily`'de
      mevcut). Salt-skor varyantına karşı backtest'te ölçülür; GBM stacking'den (2.2 ⏸️) bağımsız.

---

## Faz 3 — Analiz UX (Flutter)

**Hedef:** Kullanıcı bülteni geziyor, maç analiz merkezinde "oynanır mı?" sorusunun cevabını görüyor,
analiz kuponu kuruyor, bankroll disiplini asistanla öğreniyor.

**DoD:** Bülten ekranı → maç analiz merkezi → kupon oluşturucu akışı uçtan uca çalışıyor;
sorumlu oyun öğeleri yerinde.

### 3.1 Bülten ekranı ✅

- [x] `lib/models/bulletin.dart` + `lib/services/bulletin_service.dart` +
      `lib/providers/bulletin_provider.dart` (family provider'lar, gün bazlı cache,
      market/lig/value filtre state'i).
- [x] `lib/screens/bulletin_screen.dart`: tarih seçici (±3 gün), market/lig/"Sadece Value"
      filtreleri, lig gruplu maç kartları, "düşen oran ↓" ve "VALUE" rozetleri, 18+ /
      sorumlu oyun dipnotu. Navigasyon: `custom_bottom_nav.dart`'a "Bülten" sekmesi +
      `main_layout.dart` IndexedStack.
- [ ] ⏸️ Oran değişim mini grafiği (kartta sparkline) — analiz ekranındaki hareket görünümü
      şimdilik yeterli; sparkline ileriye ertelendi.

### 3.2 Maç analiz merkezi ✅

- [x] *(Karar — ADR 8)* `match_detail_screen.dart` sekmesi yerine ayrı
      `lib/screens/bulletin_match_analysis_screen.dart`: canlı skor `matches` tablosu ile
      bülten kayıtları farklı kimlik uzaylarında; eşleştirme ayrı iş kalemi olarak 4.4'e bağlı.
- [x] "Model Görüşü" kartı (λ'lar, en iyi 3 value pick ya da "value yok"), Model vs Piyasa
      karşılaştırma tablosu (model % | oran | implied % | EV rozeti), oran hareketi bölümü
      (açılış → güncel, % değişim). Widget'lar: `lib/widgets/bulletin/`.
- [ ] ⏸️ ELO/form/xG trendi ve diziliş istatistiklerinin aynı ekrana taşınması — mevcut
      `FormationPairStatistics` maç detayında yaşıyor; bülten-canlı maç eşleştirmesi
      yapılınca birleştirilecek.

### 3.3 Kupon oluşturucu (analiz kuponu) ✅

- [x] `lib/models/coupon.dart`: `CouponSelection`/`CouponDraft` — kombine oran, kombine model
      olasılığı, implied, EV, çeyrek Kelly, korelasyon tespiti (aynı maçtan seçim), başlamış
      maç kontrolü; `AnalysisCoupon` (saklanan kupon).
- [x] `lib/screens/coupon_builder_screen.dart`: seçim listesi, canlı özet kartı, **dürüst EV
      hükmü** ("modele göre bu kupon uzun vadede kaybettirir" dahil 4 durum), K-Coin miktarı +
      başlık + herkese açık anahtarı, `share_coupon` RPC ile paylaşım.
- [x] Bülten entegrasyonu: oran kutusuna dokun → kupona ekle/çıkar (seçili durum vurgusu),
      FAB'da seçim sayısı + toplam oran.

### 3.4 Bankroll / Kelly asistanı ✅

- [x] `lib/screens/bankroll_screen.dart` + `lib/providers/bankroll_provider.dart`:
      K-Coin bankroll kartı, performans metrikleri (sonuçlanan, isabet, **flat-stake ROI**,
      ort. CLV; <10 örneklem uyarısı), son kuponlar listesi, çeyrek Kelly hesaplayıcı.
- [x] Sorumlu oyun: ≥3 seri kayıp uyarısı, stake artışı (kayıp kovalama) deseni tespiti,
      **24 saatlik soğuma modu** (SharedPreferences kalıcı; aktifken kupon paylaşımı kilitli),
      18+ dipnotu tüm bahis ekranlarında.

### 3.5 Analiz UX derinleştirmeleri (persona analizi) ⬜

*2026-07-11 persona analizi — standart bahisçinin ilk aradığı, model gerektirmeyen ya da mevcut
çıktıları onun diline çeviren özellikler.*

- [ ] **Basit yüzde istatistikleri (bahisçinin dili):** "son 10 maçın 8'i 2.5 üst", "bu ikili
      son 6 maçta 5 kez KG Var", iç saha/deplasman form dizileri, gol dakika dağılımı —
      kanonik `Match` geçmişinden üretilir, model gerektirmez; analiz ekranına ve maç kartlarına.
- [ ] **"Düşen oranlar" görünümü:** bültende ayrı liste/filtre — açılıştan bugüne en çok düşen
      oranlar (mevcut rozetin listelenebilir hali; standart bahisçinin yerleşik alışkanlığı).
- [ ] **Ortak-dağılım kombine olasılığı:** aynı maçtan seçimlerde kombine olasılık, bağımsızlık
      varsayımıyla çarpım yerine **skor matrisinin ortak dağılımından** (2.1 matrisi mevcut) —
      3.3'teki korelasyon uyarısının sayısallaştırılmış hali; rakiplerde olmayan özellik.
- [ ] **"Kuponum" canlı takip ekranı:** kupondaki maçların canlı skorları tek ekranda, seçim
      bazında tutuyor/yatıyor renk kodu, kupon yattığında/kazandığında push; kupondaki maçta
      kadro sürprizi bildirimi (0.C altyapısı). Maç akşamı retention motoru. *(Ön koşul: canlı
      maç ↔ bülten kimlik eşleştirmesi — bkz. ADR 8 / 4.4.)*
- [ ] **Eşzamanlı çoklu bahis riski:** aynı gün birden fazla value seçimde stake'ler bağımsız
      Kelly ile toplanamaz — eşzamanlı Kelly yaklaşımı ya da günlük toplam risk tavanı
      (3.4 asistanına ek).
- [ ] **Model görüşü basit dil katmanı:** varsayılan sunum "değerli oran ✅ / oynama ⚠️" +
      yüzdeler; EV/λ ayrıntısı isteğe bağlı genişletmede (ilke 0.1.6).

---

## Faz 4 — Community: Doğrulanabilir Tipster Ekonomisi

**Hedef:** K-Coin sanal ekonomisi üzerinde gerçek itibar sistemi — kupon paylaşımı, kopyalama,
ROI+CLV bazlı lider tablosu, maç odaları. Para yok, kanıtlanabilir sicil var.

**DoD:** Kupon paylaş → takip et → kopyala akışı çalışıyor; tipster profili doğrulanmış
metriklerle (ROI, CLV, örneklem) görünüyor; lider tablosu kâr değil beceri sıralıyor.

### 4.1 Tipster sicili (Supabase) ✅

- [x] Migration `20260711093000_tipster_infrastructure.sql`: `analysis_coupons`
      (seçimler JSONB, oranlar paylaşım anında **sunucu tarafında doğrulanıp kilitleniyor** —
      istemci oranı güncel orandan >%10 sapıyorsa red), `coupon_likes`, `coupon_comments`,
      `tipster_stats` (dönem: 'all' + 'YYYY-MM'; ROI, ort. CLV, örneklem, market kırılımı),
      `tipster_leaderboard` view (min. 10 sonuçlanmış kupon), `share_coupon` +
      `resolve_coupon_selections` + `recompute_tipster_stats` RPC'leri (SECURITY DEFINER;
      doğrudan INSERT/UPDATE yetkileri kaldırıldı). İzole Postgres 15'te 27 doğrulama
      senaryosuyla test edildi.
- [x] Sonuçlandırma: `supabase/functions/resolve-coupons/index.ts` — sports_api'den biten
      maç skorları → market kurallarıyla seçim sonuçları (İY marketleri HT skoru yoksa iptal) →
      kapanış oranı `bulletin_odds`'tan → seçim başına CLV = paylaşım/kapanış oranı − 1 →
      kupon durumu + `tipster_stats` yeniden hesabı (idempotent).
- [x] Anti-gaming: kickoff sonrası paylaşım reddi; paylaşım sonrası seçim/oran değişikliği
      trigger ile kilitli (sahip yalnız başlık + görünürlük değiştirebilir); kullanıcı silme
      politikası yok; aynı maç+market'ten mükerrer seçim reddi; <10 örneklem "yetersiz veri".
- [x] *(Not — K-Coin)* Mevcut cüzdan RPC'leri yalnız **kredi** tarafını sunuyor
      (`credit_k_coins_server`); genel harcama fonksiyonu yok. Stake şimdilik kayıt olarak
      tutuluyor, coin düşülmüyor (`TODO(k-coin)` yorumu ile hazır); kazanç ödemesi yalnız
      eşleşen stake debit'i varsa yapılıyor (yoktan coin basmayı engelleyen koruma).

### 4.2 Sosyal akış ✅ (çekirdek) / ⏸️ (genişletmeler)

- [x] Kupon paylaşım kartı: `lib/screens/coupon_feed_screen.dart` ("Topluluk Kuponları",
      bülten ekranından erişim) + `lib/widgets/tipster/coupon_feed_card.dart` — seçim satırları
      (sonuçlanınca ✓/✗/–), toplam oran, durum rozeti, EV + ort. CLV, beğeni (optimistic toggle)
      ve yorum (bottom sheet, `coupon_comment_sheet.dart`).
- [x] "Kuponu Kopyala": migration `20260711100000_copy_coupon.sql` — `copy_coupon` RPC
      (SECURITY DEFINER): kaynak kupon public+pending+başlamamış olmalı; seçimler **güncel**
      `bulletin_odds` oranlarıyla sunucu tarafında yeniden kurulur; `origin_coupon_id` izlenir.
      *(Karar: `place_bet` genişletmesi yerine analiz kuponu kopyası — K-Coin debit fonksiyonu
      eklendiğinde stake düşümü `share_coupon` ile aynı TODO noktasından bağlanacak.)*
- [ ] ⏸️ Topluluk yüzdesi: maç/market kartında seçim dağılımı ("kullanıcıların %64'ü MS1") —
      paylaşılan kupon verisi biriktikçe anlamlı; aggregate view + kart rozeti olarak eklenecek.
      *(2026-07-11 keşfi: iddaa.com `outcome-play-percentages` ucu resmi Türkiye geneli yüzdeyi
      veriyor — bkz. 1.2 notu; iç veri beklemeden bu kaynakla başlanabilir.)*
- [ ] ⏸️ Takip edilen tipster'ların yeni kuponları için bildirim (FCM altyapısı hazır;
      `analysis_coupons` INSERT trigger'ı + `fcm-push-trigger` bağlanacak).

### 4.3 Lider tablosu ve profiller ✅ (çekirdek) / ⏸️ (istatistiksel sağlamlaştırma)

- [x] `leaderboard_screen.dart`: "Genel / Tipster" segment kontrolü;
      `lib/widgets/tipster/tipster_leaderboard_tab.dart` — **CLV birincil** sıralama, ROI ve
      sonuçlanan kupon sayısı, dönem seçici (Tümü / Bu Ay), min. 10 örneklem şartı ve
      "sıralama kâra değil CLV becerisine dayanır" dipnotu.
- [x] Tipster profil sayfası (`lib/screens/tipster_profile_screen.dart`): ROI / ort. CLV /
      isabet / sonuçlanan metrik kartları, "Yetersiz veri" rozeti, market kırılımı chip'leri,
      herkese açık kupon geçmişi.
- [ ] ⏸️ Sıralamada güven aralığı alt sınırı (Wilson/shrinkage) ve profilde aralık gösterimi —
      gerçek örneklem birikince eklenecek; şu an min-10 eşiği ilk savunma hattı. *(ADR 11)*
- [ ] ⏸️ Kalibrasyon grafiği ("bu kullanıcı %60 dediğinde...") — kupon başına model/kullanıcı
      olasılığı ayrımı gerektirir; veri birikimine bağlı.
- [ ] ⏸️ Tipster rozetleri (badge sistemine ek).

### 4.4 Maç odaları entegrasyonu

- [ ] ⏸️ LiveKit sesli odalar + canlı sohbete "maç analiz kartı" pinleme — canlı maç
      (`matches`) ↔ bülten (`bulletin_matches`) kimlik eşleştirmesi ön koşul (bkz. ADR 8);
      eşleştirme yapılınca `live_chat_panel`'e analiz kartı eklenecek.
- [x] Bot swarm'ın bahis-analiz diline uyarlanması (`simulation_engine/index.js`):
      `fetchIddaaContext` botun konuştuğu maç için gerçek bülten oranlarını (`bulletin_odds`) ve
      model value seçimlerini (`bulletin_predictions`) çekip prompt'a enjekte ediyor; oran
      düşüşü/kupon/value konu başlıkları eklendi. Korkuluklar: uydurma oran yasak, teşvik/"kesin"
      dili yasak, kişisel görüş çerçevesi zorunlu.

---

## Çapraz Konular

- [ ] **Gözlemlenebilirlik:** her sync/skorlama job'ı `SyncRun` kaydı düşer; model sürümü her
      tahminde saklanır (denetlenebilirlik).
- [ ] **Test stratejisi:** Python katmanı fixture + birim test; market türetimleri property-based
      tutarlılık testleri; Flutter için model/serialization testleri.
- [ ] **Performans:** bülten endpoint'i sayfalama + cache (oran tazeleme sıklığıyla uyumlu TTL).
- [ ] **Admin:** `admin_dashboard`'a bülten senkron durumu + model kalibrasyon paneli sayfası. *(opsiyonel, fazların sonunda)*

## Ar-Ge Backlog (V2)

Mevcut çekirdeğe (DC; ileride +GBM) karşı backtest'te **yarıştırılarak** alınacak iyileştirmeler —
varsayılan olarak değil, ölçülerek:

- [ ] **Dinamik takım gücü:** state-space / Bayesyen Dixon-Coles (Rue & Salvesen 2000;
      Koopman & Lit 2015) — takım güçleri zamanla rastgele yürüyüş yapar; sezon içi form
      kırılmalarını (hoca değişimi, transfer) sabit exponential decay'den daha iyi yakalar.
- [ ] **Bivariate Poisson** (Karlis & Ntzoufras 2003): ev-deplasman gol korelasyonunun DC'nin
      rho yamasından daha ilkeli modeli; özellikle KG ve toplam gol marketlerinde test edilir.
- [ ] **Gol zamanlaması modeli:** inhomojen Poisson süreci (gol yoğunluğu dakikaya bağlı, son
      15 dakikada artar) — canlı bahis marketleri açılırsa temel taş; 3.5'teki "gol dakika
      dağılımı" istatistiğinin ilkeli hali. İY marketlerindeki sabit 0.45 yarı-bölüşüm
      yaklaşımının (2.1) yerini de alabilir.
- [ ] **Monte Carlo / sezon simülasyonu:** analitik türetimi zor bileşik marketler ve
      "şampiyonluk/küme olasılığı" içeriği (Faz 0 lig profiline fan içeriği olarak besleme).
- [ ] **Market taksonomisi v2:** korner ve kart marketleri (güncel iddaa bülteninde mevcut;
      standart oyuncunun kullanımı artıyor) — taksonomi + veri kaynağı + model türetimi.

## Karar Kaydı (ADR-lite)

| # | Karar | Gerekçe | Tarih |
|---|---|---|---|
| 1 | Skor modeli olarak Dixon-Coles (+GBM stacking) | Tek modelden tüm marketler; literatürde kanıtlı; mevcut feature şemasıyla uyumlu | 2026-07-10 |
| 2 | Bülten kaynağı provider-agnostik, taksonomi sabit | Kaynak (Nesine/Misli/lisanslı sağlayıcı) değişebilir; iç şema değişmemeli | 2026-07-10 |
| 3 | Gerçek para yok; K-Coin sanal sicil ekonomisi | Yasal çerçeve + mevcut altyapının yeniden kullanımı | 2026-07-10 |
| 4 | Lider tablosu kâr değil CLV/ROI + örneklem sıralar | Şans-beceri ayrımı; bilimsel ilke 0.1.4 | 2026-07-10 |
| 5 | Ayrı bülten sync job'u yok; mevcut sync scope'ları kullanılıyor | `matches` + `market-backfill` scope'ları provider-agnostik; tekrar yazmak gereksiz | 2026-07-11 |
| 6 | DC fit saf Python (numpy/scipy yok) | Bağımlılık eklemeden her ortamda çalışır; lig ölçeğinde performans yeterli | 2026-07-11 |
| 7 | GBM üst katmanı ertelendi (DC önce üretime) | Kalibrasyon raporu gerçek örneklemle DC taban çizgisini ölçmeden stacking prematüre | 2026-07-11 |
| 8 | Analiz merkezi ayrı ekran (`match_detail` sekmesi değil) | Canlı skor `matches` tablosu ile bülten kayıtları ayrı kimlikler; eşleştirme ayrı iş kalemi | 2026-07-11 |
| 9 | Marj arındırma Shin yöntemiyle (orantısal değil) | Favorite-longshot bias; EV referans olasılığının doğruluğu her tahmine dokunur | 2026-07-11 |
| 10 | Model olasılığı piyasa ile logit uzayında harmanlanır | Kapanış oranları ~etkin; saf model piyasayı zor yener, harman kalibrasyonu iyileştirir ve aşırı iddialı EV'yi törpüler | 2026-07-11 |
| 11 | Tipster sıralaması güven aralığı alt sınırıyla | Küçük örneklem şişmesini engeller; ADR 4'ün istatistiksel ayağı | 2026-07-11 |
| 12 | Faz 0 (temel hijyen) yol haritasına eklendi | Persona analizi: puan durumu/takım profili/takım bildirimleri olmadan analiz katmanı izleyici bulamaz | 2026-07-11 |

## Günlük (Changelog)

- **2026-07-10** — Doküman oluşturuldu; mimari envanter çıkarıldı; fazlar ve DoD'lar tanımlandı.
- **2026-07-11** — Faz 1 tamamlandı (taksonomi, provider, bülten API, Supabase köprüsü).
  Faz 2 tamamlandı (Dixon-Coles + kalibrasyon + value tespiti + tahmin API + köprü; GBM ertelendi).
  sports_api test durumu: 147 geçiyor. Faz 3 ve Faz 4.1 implementasyonu başladı.
- **2026-07-11 (devam)** — Faz 3 tamamlandı: bülten ekranı + navigasyon, maç analiz merkezi,
  kupon oluşturucu (dürüst EV hükmü, korelasyon uyarısı), bankroll asistanı (flat-ROI/CLV,
  çeyrek Kelly, seri kayıp/kayıp kovalama uyarıları, soğuma modu). Faz 4 çekirdeği tamamlandı:
  tipster altyapısı (kilitli oranlar, CLV'li sonuçlandırma, anti-gaming; izole Postgres'te 27
  senaryo doğrulandı), topluluk kupon akışı (beğeni/yorum/`copy_coupon` RPC), CLV-öncelikli
  tipster lider tablosu + profil, bot swarm'ın gerçek oran/model verisiyle konuşması.
  Doğrulama: `flutter analyze` 0 hata (35 eski info-lint, dokunulmamış dosyalarda);
  `sports_api` 147/147 test; `simulation_engine` syntax OK.
  **Açık manuel adımlar:** (1) canlı bülten kaynağı seçimi + `.env` (`SPORTS_API_IDDAA_BULLETIN_*`),
  (2) Supabase migration'larının uygulanması + edge function deploy + secrets
  (`SPORTS_API_BASE_URL`, `SPORTS_API_TOKEN`), (3) alembic migration (`match_predictions`),
  (4) K-Coin debit fonksiyonu eklenince stake düşümünün bağlanması (TODO(k-coin) noktaları),
  (5) zamanlayıcı kurulumu: bülten sync → oran tazeleme → `predictions/run` → `sync-bulletin` →
  `sync-predictions` → `resolve-coupons` zinciri.
- **2026-07-11 (persona + bilim güncellemesi)** — Fan/bahisçi persona analizi ve bilimsel yaklaşım
  envanteri işlendi: **Faz 0 (Temel Hijyen)** eklendi (puan durumu, takım profili, takım bazlı
  bildirimler, H2H); ilke 0.1.6 (basit arayüz dili). Faz 2'ye **2.5 Bilimsel genişletmeler**
  (Shin marj arındırma, piyasa harmanlama, bahis simülasyonu backtest'i, xG-hibrit); Faz 3'e
  **3.5 Analiz UX derinleştirmeleri** (basit yüzde istatistikleri, düşen oranlar görünümü,
  ortak-dağılım kombine olasılığı, "Kuponum" canlı takibi, eşzamanlı Kelly, basit dil katmanı);
  Faz 4'e topluluk yüzdesi + güven aralığı bazlı sıralama/shrinkage. **Ar-Ge Backlog (V2)**
  oluşturuldu (dinamik takım gücü, bivariate Poisson, gol zamanlaması, Monte Carlo/sezon
  simülasyonu, korner/kart marketleri). ADR 9-12 eklendi.
- **2026-07-11 (2.5 implementasyonu)** — Shin marj arındırma (`shin_probabilities`,
  bisection'lı z çözümü, güvenli fallback'ler) ve logit-uzayı piyasa harmanlama
  (`app/ml/market_blend.py`; yalnız tam kapsanan marketler, varsayılan ağırlık 0.5) kodlandı;
  `PredictionService` value tespitini harmanlanmış olasılıkla yapıyor, pick payload'ına
  `dc_probability` + `market_probability` eklendi (şema geriye uyumlu). Bahis simülasyonu
  çekirdeği `app/ml/backtest.py` (Kelly/flat, ROI, max drawdown). 13 yeni test
  (`test_ml_shin_and_blend.py`); sports_api toplamı 160 geçiyor.
- **2026-07-11 (canlı kaynak doğrulaması)** — Nesine CDN bülteni canlı test edildi ve gerçek
  payload mevcut parser'dan uçtan uca geçirildi (231 maç, 4.962 tick, 9 market tipi; bugünün
  bülteni filtresi 123 maç). 12 MTID eşlemesi iddaa.com resmi market sözlüğüyle çapraz doğrulandı;
  1.2'deki ⏸️ manuel doğrulama maddesi kapatıldı. Keşif: iddaa.com `sportsbookv2` API'si
  (korner/kart marketli alternatif kaynak) ve resmi `outcome-play-percentages` ucu (topluluk
  yüzdesi için) — notlar 1.2 ve 4.2'ye düşüldü.
- **2026-07-11 (senkron E2E + deploy)** — Senkron zinciri yerelde uçtan uca canlı çalıştırıldı:
  `sports-api-db` + migration'lar + API → program senkronu (112 maç/39 lig/224 takım) → oran
  senkronu (112/112) → bülten API (111 maç oranlı) → tahmin batch'i (yeni liglerde geçmiş <30 maç
  olduğundan beklendiği gibi atlandı; veri biriktikçe devreye girer). `scripts/bulletin_sync_runner.ps1`
  eklendi (DB+API ayağa kaldırma + üçlü senkron + opsiyonel Supabase köprü tetikleme; schtasks
  komutu başlıkta). **Supabase:** `sync-bulletin`, `sync-predictions`, `resolve-coupons` canlı
  projeye deploy edildi (ACTIVE). ⏸️ **Bekleyen (kullanıcı onayı/aksiyonu):** migration geçmişi
  yerelde yeniden adlandırılmış olduğundan 33 sürümün `migration repair --status applied` ile
  eşlenmesi + `db push --include-all` (8 gerçek bekleyen: 3 güvenlik düzeltmesi [idempotent hale
  getirildi] + bildirim kolonları + 4 bülten/tipster). 59 remote sürümü için placeholder dosyaları
  `supabase/migrations/`e eklendi. Köprünün çalışması için sports_api'nin internetten erişilebilir
  olması gerekiyor (geçici tercih: kendi makine + zamanlanmış görev).
- **2026-07-11 (canlıya çıkış tamam)** — Kullanıcı onayıyla migration geçmişi onarıldı (33 sürüm
  `repair --status applied`) ve **8 bekleyen migration canlı Supabase'e uygulandı** — bülten/tipster
  tabloları + güvenlik düzeltmeleri üretimde. `scripts/bulletin_bridge.py` yazıldı: edge function
  beklemeden yerel sports_api'den canlı Supabase'e doğrudan upsert (servis anahtarı diske yazılmaz,
  CLI'dan boru ile geçer); ilk koşu: **112 maç + 2.329 oran** `bulletin_matches`/`bulletin_odds`'a
  yazıldı, uygulamanın anon anahtarıyla okunduğu doğrulandı. Runner script köprüyü içerecek şekilde
  güncellendi. Ayrıca: ana ekran maç kaynağının ayrı "AI Sport Agent" servisi (port 8001) olduğu
  tespit edildi; kapalı kalan servis + DB ayağa kaldırıldı, CORS uyumu için Flutter web 62500
  portunda çalıştırılıyor.
- **2026-07-11 (kimlik köprüsü + kartlarda oran)** — ADR 8'deki canlı maç ↔ bülten eşleştirmesi
  kuruldu: ortak anahtar **resmi iddaa program kodu** (ajan `fixture_stage_rows.source_event_id`
  ↔ sports_api `provider_entity_mappings.provider_entity_id`, Gwangju-Pohang örneğiyle doğrulandı).
  Supabase `bulletin_matches.agent_match_id` kolonu eklendi (migration canlıya uygulandı);
  köprü script'i eşlemeyi dolduruyor (bugün: 112 bülten maçından **93 eşleşme**). Flutter:
  `BulletinMatch.agentMatchId`, `bulletinByAgentMatchIdProvider` ve ana ekran maç kartlarına
  **MS (1X2) oran şeridi** (`_BulletinOddsStrip`) — düşen oran kırmızı+ok ile işaretli, dokununca
  maçın analiz ekranı açılıyor. Bu köprü "Kuponum canlı takibi" (3.5) ve oda analiz kartı (4.4)
  ön koşulunu da karşılıyor.
- **2026-07-11 (Kupon ekranı sadeleştirme)** — Kullanıcı geri bildirimi ("karışık ve kullanımı
  zor") üzerine bülten ekranı yoğun liste düzenine geçirildi: büyük kartlar yerine kompakt satır
  (saat+MBS | alt alta takımlar | sabit genişlik oran kutuları; 4+ seçimli marketler yatay kayar),
  lig çipleri yerine **sayaçlı lig seçim sheet'i**, tek filtre satırı, "Orana dokun: kupona ekle ·
  Maça dokun: analiz" ipucu satırı, FAB yerine alt navigasyon üstünde **sabit kupon çubuğu**
  (seçim sayısı + toplam oran + KUPONU GÖR). VALUE rozeti yıldız ikonuna küçültüldü.
- **2026-07-11 (navigasyon sadeleştirme)** — Kullanıcı kararıyla: BÜLTEN alt menüden kaldırıldı
  (ana ekran zaten bülten maçlarını gösteriyor). **MARKET sekmesinin içeriği bülten/kupon aracıyla
  değiştirildi** (etiket "Kupon") — K-Coin sanal marketi üretimde boştu (`predictions` 0 kayıt) ve
  kupon akışı bahisçinin ana aracı; `PredictionMarketScreen` kodda duruyor, Faz 4.2'de
  ("kuponu K-Coin ile kopyala") kupon deneyimiyle birleşecek. Alt bar: Matches · Insights ·
  Kupon · Ranking · tarih.
- **2026-07-11 (ana ekran = bülten maçları)** — Ürün kararı işlendi: ana sayfa yalnızca iddaa
  bültenindeki maçları gösterir. AI Sport Agent'ta scope kuralı sıkılaştırıldı
  (`catalog_service._build_match_query` + `mobile_service._mobile_match_scope_clause`): gün için
  iddaa eşleşmesi varsa **yalnız bülten maçları**; manuel izinli ligler yalnız iddaa verisi
  olmayan günlerde devreye giren yedek. Bugünün iddaa eşleştirme işi çalıştırıldı (117 satır,
  106 eşleşme); mobil uç 552 → **105 bülten maçına** indi. Agent testleri: 171 geçti (takılan
  4'ü izole tekrar koşuda geçti — eşzamanlı canlı senkron kaynaklı). Runner script'e günlük
  iddaa eşleştirme tetikleyicisi eklendi. *(Riverpod debug-assert kilitlenmesi nedeniyle Flutter
  web şimdilik profile modda; kalıcı çözüm: Riverpod sürüm yükseltme.)*
