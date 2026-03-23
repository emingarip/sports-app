# Knowledge Graph Agent Task Packets

Bu belge, KG backlog'unun AI agent'lara atanabilecek en uygun formatta yazilmis gorev paketlerini icerir.

Neden bu format:

- Epic cok buyuktur, agent scope kaydirir.
- Generic issue cogu zaman fazla soyut kalir.
- Task packet; scope, dosya baglami, teslimat, acceptance ve verify adimlarini tek yerde toplar.

Kullanim kurali:

- Bir agent'a ayni anda yalnizca bir packet ver.
- Packet disina cikma.
- Packet icinde acikca yazmayan mimari degisiklik yapma.
- Eger packet sirasinda baska bir sorun bulunursa cozmeye kalkma; not dus.

Global kurallar:

- `docs/knowledge-graph-foundation-plan.md` ana mimari referanstir.
- `docs/knowledge-graph-epics-and-issues.md` backlog referansidir.
- Source of truth her zaman Supabase/Postgres kalir.
- Knowledge graph projection katmanidir; transactional authority graph'a tasinmaz.
- K-Coin balance ve ledger authoritative olarak relational tarafta kalir.
- `.agents/rules/k-coin-economy.md`
- `.agents/rules/supabase-function.md`
- `.agents/rules/riverpod-state.md`
- `.agents/rules/pre-push.md`

## Onerilen Ilk Sprint Packet Seti

Bu sprint icin task packet seti:

1. KG-PKT-01
2. KG-PKT-02
3. KG-PKT-03
4. KG-PKT-04
5. KG-PKT-05
6. KG-PKT-06
7. KG-PKT-07
8. KG-PKT-08
9. KG-PKT-09

## Parallelism Rehberi

- `KG-PKT-01` once calismalidir.
- `KG-PKT-02` ve `KG-PKT-03`, `KG-PKT-01` ciktisina bakarak ilerlemelidir.
- `KG-PKT-04`, `KG-PKT-05` ve `KG-PKT-06` ayni anda paralel gidebilir.
- `KG-PKT-07`, `KG-PKT-08` ve `KG-PKT-09` onceki packet'lerin kararlarini kullanir.

---

## KG-PKT-01 - Source Schema Drift Inventory

Amaç:

- kodun kullandigi tablo, kolon, RPC ve payload alanlarini migration gercegi ile karsilastirip drift raporu cikarmak

Scope:

- Supabase migration'larini tara
- istemci kodunda kullanilan DB alanlarini tara
- farkli isimlendirmeleri tek listede topla
- action item seviyesinde drift raporu yaz

Scope disi:

- migration yazmak
- kod duzeltmek
- graph modeli degistirmek

Bakilacak yerler:

- `supabase/migrations`
- `supabase/seed.sql`
- `lib/services`
- `lib/providers`
- `lib/data/providers`
- `lib/data/repositories`

Ozellikle kontrol et:

- `users`
- `matches`
- `match_insights`
- `user_insight_votes`
- `predictions`
- `user_bets`
- `user_favorite_matches`
- `notifications`
- `user_devices`
- `k_coin_*`

Teslimat:

- drift raporu markdown dosyasi
- her drift icin etki alani
- her drift icin onerilen canonical isim

Done when:

- drift listesi sadece bulgu degil, duzeltme backlog'una donusturulebilir netlikte

Verify:

- raporda en az tablo, kolon, RPC ve payload seviyesinde ayri kategoriler olsun

---

## KG-PKT-02 - Canonical Sports Domain Contract

Amaç:

- KG ve source schema icin canonical spor veri modelini dondurmak

Scope:

- `teams`, `team_aliases`, `leagues`, `seasons`, `players`, `matches` icin canonical kolon seti belirle
- `entity_uid`, `canonical_id`, `provider`, `provider_id` mantigini netlestir
- provider bagimsiz match zorunlu alanlarini yaz

Scope disi:

- migration implementasyonu
- Neo4j relation tasarimi

Girdiler:

- KG-PKT-01 drift raporu
- `sync-live-matches` payload yapisi
- mevcut `Match` model ve provider mantigi

Teslimat:

- canonical sports domain spec markdown
- tablo bazli kolon listesi
- unique key ve id strategy

Done when:

- bir implementer migration yazarken yeni karar vermek zorunda kalmaz

Verify:

- `matches` icin provider bagimsiz minimum alan seti acikca yazilmis olmali

---

## KG-PKT-03 - Onboarding Preferences Source Model

Amaç:

- onboarding secimlerini auth metadata disinda kalici source modele tasimak

Scope:

- `user_follow_entities` modelini tasarla
- takim ve lig tercihlerinin nasil yazilacagini belirle
- onboarding akisindan KG event uretimi icin source model kur
- notification preference iliskisini sadece gerekiyorsa ayir

Scope disi:

- UI degisikligi
- onboarding ekranlarini implement etmek

Girdiler:

- onboarding ekranlari
- `SupabaseService.completeOnboarding`
- favorites ve notification preference akislari

Teslimat:

- source tablo tasarimi
- write flow
- read flow
- future KG event kaynaklari

Done when:

- onboarding secimlerinin graph-friendly ve sorgulanabilir persistence modeli net

Verify:

- sadece user metadata'ya dayanilmadigi acikca yazilmis olmali

---

## KG-PKT-04 - KG Event Taxonomy And Payload Schema

Amaç:

- day-1 KG event sozlesmesini dondurmak

Scope:

- minimum event seti icin standard payload shape tanimla
- actor, entity, timestamp, source, correlation id, metadata alanlarini standartlastir
- event naming convention belirle

Scope disi:

- outbox tablo implementasyonu
- event emission kodu

Day-1 event seti:

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

Teslimat:

- event contract spec
- ornek payload'lar
- zorunlu ve opsiyonel alan listesi

Done when:

- her event icin implementer ayni shape ile outbox kaydi uretebilir

Verify:

- event adlari snake_case ve payload alanlari tutarli olmali

---

## KG-PKT-05 - KG Event Outbox Schema

Amaç:

- append-only outbox tasarimini implementasyona hazir hale getirmek

Scope:

- `kg_event_outbox` tablo tasarimi
- unique event id ve idempotency alanlari
- aggregate id, entity uid, event type, payload, emitted at, processing state alanlari
- gerekli index ve constraint'leri tanimla
- retention ve archival notlarini yaz

Scope disi:

- worker yazmak
- event emission kodu eklemek

Girdiler:

- KG-PKT-04 event contract'i

Teslimat:

- outbox schema spec
- index strategy
- lifecycle notlari

Done when:

- DBA veya implementer migration'i belirsizlik olmadan yazabilir

Verify:

- duplicate event replay senaryosu sema seviyesinde dusunulmus olmali

---

## KG-PKT-06 - Event Emission Mapping

Amaç:

- hangi user action'in nerede KG event'i uretecegini netlestirmek

Scope:

- favorites
- match detail open
- chat send
- bet place
- insight vote
- onboarding selection
- badge unlock

Her action icin sunlari yaz:

- kaynak dosya
- emit noktasi
- event adi
- kullanilacak entity uid tipi
- correlation/source bilgisi

Scope disi:

- event emission implementasyonu

Teslimat:

- source-to-event mapping dokumani

Done when:

- her event icin tek ownership noktasi belirli

Verify:

- ayni action icin birden fazla emission noktasi kalmamis olmali

---

## KG-PKT-07 - Neo4j Label And Relation Contract

Amaç:

- day-1 graph label ve relation setini dondurmak

Scope:

- node label seti
- relation seti
- her node/edge icin zorunlu property seti
- unique constraint ve index ihtiyaclari

Node seti:

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

Relation seti:

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

Scope disi:

- worker implementation
- Cypher script yazimi

Teslimat:

- Neo4j model contract markdown

Done when:

- projection worker hangi label/relation'i ne zaman yazacagini belirsiz kalmadan bilebilir

Verify:

- tum node ve edge'ler icin `uid`, `source_system`, `valid_from`, `valid_to`, `metadata` mantigi acikca yer almali

---

## KG-PKT-08 - Entity Registry Contract

Amaç:

- source entity ile canonical entity arasindaki esleme katmanini tanimlamak

Scope:

- `kg_entity_registry` tasarimi
- source table/entity -> canonical uid map mantigi
- provider alias ve provider id strategy
- unresolved entity durumu

Scope disi:

- alias resolution algoritmasi
- full entity resolution implementation

Girdiler:

- KG-PKT-02 canonical domain
- KG-PKT-07 graph contract

Teslimat:

- entity registry spec
- mapping kurallari
- unresolved/ambiguous case handling

Done when:

- implementer projection sirasinda canonical uid nasil bulunacak sorusunu tekrar sormaz

Verify:

- ayni entity'nin farkli provider kayitlari nasil baglanacak acik olmali

---

## KG-PKT-09 - KG Operability Metrics Contract

Amaç:

- KG altyapisinin operasyonel olarak izlenebilmesi icin minimum metrik setini tanimlamak

Scope:

- projection lag
- worker throughput
- dead-letter count
- replay success rate
- fallback usage rate
- query p95

Her metrik icin sunlari yaz:

- tanim
- olcum kaynagi
- birim
- hedef veya threshold
- alert ihtiyaci

Scope disi:

- dashboard implementasyonu
- alerting implementasyonu

Teslimat:

- KG metrics spec

Done when:

- operasyonda "KG saglikli mi" sorusu olculebilir hale gelir

Verify:

- projection lag ve fallback usage icin threshold belirtilmis olmali

---

## Agent'a Verilecek Onerilen Prompt Kalibi

Her packet'i bir agent'a verirken asagidaki kisa kalibi kullan:

```text
Bu gorevde sadece su packet kapsaminda calis:
[PACKET_ID - PACKET_TITLE]

Ana referanslar:
- docs/knowledge-graph-foundation-plan.md
- docs/knowledge-graph-epics-and-issues.md
- docs/knowledge-graph-agent-task-packets.md

Kurallar:
- Source of truth Postgres/Supabase olarak kalacak.
- Knowledge graph projection katmani olacak.
- K-Coin authoritative veri graph'a tasinmayacak.
- Scope disina cikma.
- Gerekirse bulgu not et ama cozmeye kalkma.

Beklenen cikti:
- packet'teki teslimat
- acik varsayimlar
- acceptance kriterlerine gore durum
```

## Not

Eger coklu agent calisacaksa en guvenli sira:

1. KG-PKT-01
2. KG-PKT-02 ve KG-PKT-03
3. KG-PKT-04, KG-PKT-05, KG-PKT-06
4. KG-PKT-07, KG-PKT-08
5. KG-PKT-09

Bu belge issue takip araci yerine dogrudan AI delegation icin optimize edilmistir.
