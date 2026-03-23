# Knowledge Graph Foundation Plan

Bu belge, SportsApp icin tam kapsamli knowledge graph altyapisinin hedef mimarisini, fazlarini ve kabul kriterlerini tanimlar.

Bu bir implementasyon dokumani degildir. Amaci, daha sonra yapilacak migration, worker, edge function, personalization, AI context ve entity resolution islerinin ayni teknik cercevede ilerlemesini saglamaktir.

Bu planin uygulanabilir epic ve issue dagilimi ayri olarak `docs/knowledge-graph-epics-and-issues.md` icinde tutulur.

Temel ilke sabittir:

- Transactional source of truth olarak Supabase/Postgres kalir.
- Knowledge graph, uygulamanin ana veritabaninin yerine gecmez.
- KG; projection, iliski analizi, relevance scoring ve AI context katmani olarak konumlanir.
- K-Coin balance ve ledger gibi guvenlik kritik alanlar graph'a tasinmaz.

## Hedef

Bu altyapi uc urun hedefini ayni temel uzerinden destekleyecek:

1. Kisisellestirilmis feed, mac siralama ve akilli bildirimler
2. AI insight ve soru-cevap icin guvenilir iliski baglami
3. Spor verisi icin canonical entity modeli ve provider bagimsiz veri birlestirme

Canliya cikis sirasi sabitlenmistir:

1. Kisisellestirme
2. AI context
3. Entity resolution ve risk graph senaryolari

## Ana Mimari Kararlari

### 1. Kaynak sistemler

- Kullanici, auth, wallet, ledger, bildirim, profile, bet, chat ve operational tablolarin source of truth'u Supabase/Postgres olur.
- Managed Neo4j AuraDB day-1 graph store olarak kullanilir.
- Mobil uygulama graph veritabanina dogrudan baglanmaz.
- Tum graph erisimi backend fonksiyonlari veya worker katmani uzerinden yapilir.

### 2. Yazma modeli

- Uygulama aksiyonlari once Postgres tarafinda kaydedilir.
- Ilgili aksiyonlar `kg_event_outbox` uzerinden projection pipeline'a aktarilir.
- `kg-sync-worker` bu event'leri Neo4j'ye yazar.
- Event isleme modeli idempotent olacaktir.
- Basarisiz projection denemeleri `kg_failed_events` icinde tutulur.

### 3. Tazelik hedefi

- Hedef, near-real-time projection'dir.
- Event olusumundan graph projection'a gecikme p95 en fazla 15 saniye olmalidir.
- Graph ulasilamazsa sistem degrade modda calismalidir; feed ve bildirim akislari Postgres snapshot fallback ile devam etmelidir.

### 4. Guvenlik siniri

- K-Coin bakiyesi, harcanabilirlik, odeme ve ledger akislari graph'a authoritative veri olarak yazilmaz.
- Graph, yalnizca katilim, affinity, ilgi ve baglam cikarimi icin kullanilir.
- K-Coin ile ilgili tum kesin muhasebe islemleri RPC/ledger tarafinda kalir.

## Mevcut Durumdan Kaynaklanan On Kosullar

Uygulama tarafinda schema drift oldugu icin graph isine gecmeden once bir reconciliation asamasi zorunludur.

Ozellikle asagidaki alanlar tek semantic modele indirilecektir:

- `k_coin_balance` ve `virtual_currency_balance`
- `insight_text` ve `text`
- `vote_type` ve `vote`
- prediction alan isimleri ile istemci beklentileri
- migration'da gorunmeyip kodda kullanilan tablolar

Bu asama tamamlanmadan KG production altyapisi acilmayacaktir.

## Canonical Veri Modeli

### Dondurulacak temel tablolar

Postgres tarafinda asagidaki canonical varliklar netlestirilir:

- `users`
- `teams`
- `team_aliases`
- `leagues`
- `seasons`
- `players`
- `matches`
- `user_favorite_matches`
- `user_follow_entities`
- `match_insights`
- `predictions`
- `user_bets`
- `chat_messages`
- `notifications`
- `user_devices`
- `badges`
- `k_coin_transactions`

### Ortak entity kimligi

Tum entity tiplerinde asagidaki ortak alan mantigi kullanilacaktir:

- `entity_uid`
- `entity_type`
- `canonical_id`
- `provider`
- `provider_id`
- `display_name`
- `valid_from`
- `valid_to`
- `confidence`
- `metadata`

Bu kimlik modeli, farkli provider'lardan gelen ayni takim/mac/oyuncu kaydini tek canonical dugumde toplamayi saglar.

## Graph Veri Modeli

### Node tipleri

Day-1 graph label seti:

- `User`
- `Team`
- `League`
- `Season`
- `Match`
- `Player`
- `Insight`
- `Prediction`
- `ChatRoom`
- `NotificationTopic`
- `Badge`
- `Device`

### Edge tipleri

Day-1 relation seti:

- `FOLLOWS`
- `FAVORITED`
- `PLAYS_IN`
- `BELONGS_TO_LEAGUE`
- `PARTICIPATES_IN`
- `HAS_INSIGHT`
- `VOTED_ON`
- `PLACED_BET_ON`
- `MESSAGED_IN`
- `PREFERS_NOTIFICATION`
- `RIVAL_OF`
- `SIMILAR_TO`
- `MENTIONED_IN`
- `USES_DEVICE`

### Tum node ve edge'lerde zorunlu alanlar

- `uid`
- `weight`
- `source_system`
- `first_seen_at`
- `last_seen_at`
- `valid_from`
- `valid_to`
- `version`
- `metadata`

`uid` icin unique constraint, alias ve esleme isleri icin de uygun index yapisi acilacaktir.

## Event Pipeline

### KG'ye yazilacak minimum event seti

Ilk production fazinda su event'ler standartlastirilir:

- `match_opened`
- `match_favorited`
- `match_unfavorited`
- `chat_message_sent`
- `prediction_placed`
- `insight_voted`
- `notification_opened`
- `onboarding_team_selected`
- `onboarding_competition_selected`
- `badge_unlocked`

### Projection akisi

1. Uygulama veya backend action'u Postgres source tabloda gerceklesir.
2. Ayni transaction sinirinda `kg_event_outbox` kaydi uretilir.
3. `kg-sync-worker` yeni event'leri batch halinde ceker.
4. Worker, canonical entity registry uzerinden dogru node/edge eslemesini yapar.
5. Neo4j projection yazilir.
6. Basarili event checkpoint edilir.
7. Basarisiz event retry edilir; ust limite ulasirsa dead-letter kaydina alinir.

### Fallback kurali

Neo4j veya projection pipeline gecici olarak kullanilamazsa:

- feed siralama Postgres `kg_user_affinity_snapshot` uzerinden calisir
- bildirim relevance hesaplari simplified affinity ile devam eder
- AI context derin graph traversal yerine relation snapshot kullanir

## Backend Arayuzleri

Mobil uygulama veya AI katmani graph'a dogrudan sorgu gondermez. Kullanilacak backend arayuzleri sunlardir:

- `kg-get-personalized-matches(user_id, date, limit)`
- `kg-get-notification-candidates(user_id, event_type, entity_uid, limit)`
- `kg-build-ai-context(match_id, user_id?)`
- `kg-get-related-entities(entity_uid, relation_types, depth, limit)`
- `kg-resolve-entity(provider, provider_id)`

Bu arayuzlerin hepsi edge function veya backend service katmaninda korunur.

## Fazlar

### Phase 0 - Foundations and Reconciliation

Amac:

- mevcut schema drift'i kapatmak
- canonical entity registry kurmak
- onboarding, favorite ve behavioral source'lari kalici hale getirmek
- historical backfill'i hazirlamak

Teslimatlar:

- canonical tablo semalari
- `kg_entity_registry`
- `kg_event_outbox`
- `kg_failed_events`
- `kg_projection_checkpoint`
- `kg_user_affinity_snapshot`
- onboarding secimlerinin auth metadata yerine relation tablosuna yazilmasi
- mevcut production benzeri datadan historical replay stratejisi

### Phase 1 - Personalization Graph

Amac:

- ana feed ve bildirim relevance motorunu production seviyesinde graph destekli hale getirmek

Skor mantigi sabitlenmistir:

- `%35` explicit follows
- `%25` recent behavior
- `%15` league affinity
- `%10` related-team expansion
- `%10` live-state boost
- `%5` editorial priority

Bildirim relevance mantigi:

- event severity
- user affinity
- freshness
- opt-in durumu

Ayni topic icin 30 dakika duplicate suppression uygulanir.

### Phase 2 - AI Context Graph

Amac:

- AI insight ve soru-cevap akisina deterministic, explainable context saglamak

Kurallar:

- `generate-insights` dogrudan ham tablo okumak yerine `kg-build-ai-context` kullanir
- AI'ya giden baglam; match, team, league, rivalry, recent trend, prediction, vote ve chat sinyallerinden olusur
- mümkün oldugunca graph-backed fact kullanilir
- hallucination riskini azaltmak icin source metadata korunur

### Phase 3 - Entity Resolution and Risk Graph

Amac:

- provider bagimsiz entity esleme
- ayni takim/mac/oyuncunun farkli isimlerini tek canonical yapida toplamak
- device ve davranissal iliskilerden risk/fraud sinyalleri cikarmak

Bu fazda su yetenekler eklenir:

- alias resolution
- benzer kullanici cluster'lari
- device bazli baglantilar
- coordinated behavior detection
- graph tabanli "users like you" ve komsu mac onerileri

## Test ve Kabul Kriterleri

### Database ve migration testleri

- canonical schema constraint'leri dogru calismali
- migration'lar ile istemci beklentileri uyumlu olmali
- K-Coin authoritative state graph'a kaymamis olmali
- outbox append-only mantigi bozulmamali

### Worker testleri

- event replay idempotent olmali
- ayni event ikinci kez islenince duplicate node/edge uretilmemeli
- batch retry ve dead-letter davranisi deterministik olmali
- checkpoint'ten devam edebilme dogrulanmali

### Contract testleri

- KG backend fonksiyonlari stabil response shape donmeli
- auth gereksinimleri korunmali
- graph kapaliyken fallback cevaplari calismali

### Product testleri

- onboarding secimleri feed siralamasini etkilemeli
- mac detayina giris affinity uretmeli
- favorite alma bildirim relevance'i degistirmeli
- bet ve insight vote davranislari graph'a yansimali
- AI context graph kapaliyken degrade modda calismali

### Performans hedefleri

- projection lag p95 <= 15s
- personalized match query p95 <= 200ms
- AI context query p95 <= 400ms
- 90 gunluk historical replay duplicate uretmemeli

## Varsayimlar

- Supabase/Postgres uzun sure source of truth olarak kalacak
- Managed Neo4j AuraDB ilk graph deployment secenegi olacak
- Highlightly benzeri kaynaklar provider olarak degisebilse bile canonical kimlik modeli korunacak
- onboarding tercihleri kalici relation tablosuna yazilacak
- mevcut hafif `user_events / user_interests / entity_relations` denemesi nihai production KG mimarisi sayilmayacak

## Not

Bu belge geri donulecek temel referans planidir. Uygulamaya gecmeden once:

- schema reconciliation
- event sozlesmeleri
- projection worker
- edge function arayuzleri
- fallback davranislari

ayri implementasyon gorevlerine bolunmelidir.
