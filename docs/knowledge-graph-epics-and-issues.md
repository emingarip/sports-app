# Knowledge Graph Epics And Issues

Bu belge, `docs/knowledge-graph-foundation-plan.md` icindeki mimari planin uygulanabilir epic ve issue yapisina bolunmus halidir.

Amac, KG altyapisini bir kerede degil; bagimliliklari net, test edilebilir ve sira bazli is paketleri halinde ilerletmektir.

AI agent delegation icin optimize edilmis gorev paketleri ayri olarak `docs/knowledge-graph-agent-task-packets.md` icinde tutulur.

Kullanim sekli:

- `Epic`: buyuk teslimat alani
- `Issue`: bir muhendis veya agent tarafindan alinip bitirilebilecek somut gorev
- `Priority`: is sirasi
- `Depends on`: bagimlilik
- `Done when`: kabul/done kriteri

## Epic KG-01 - Schema Reconciliation And Canonical Domain

Amaç:

- mevcut Supabase schema drift'ini kapatmak
- KG icin canonical spor veri modelini dondurmak
- graph tarafina gitmeden once source of truth katmanini saglamlastirmak

Priority:

- P0

Depends on:

- yok

Done when:

- kodun kullandigi tablo ve alan adlari migration'larla uyumlu
- canonical entity alanlari karara baglanmis
- onboarding/favorites gibi temel source alanlari kalici persistence'a sahip

### Issues

#### KG-01-01 - Source schema envanteri ve drift raporu cikar

- Kodda kullanilan tum tablo/alan/RPC isimlerini migration gercegi ile eslestir
- Farkli isimlendirmeleri tek listede topla
- Ozellikle `users`, `matches`, `match_insights`, `user_insight_votes`, `predictions`, `user_bets`, `user_favorite_matches`, `k_coin_*` alanlarini incele

Done when:

- drift listesi net ve action item seviyesinde cikmis

#### KG-01-02 - Canonical sports domain semasini tanimla

- `teams`, `team_aliases`, `leagues`, `seasons`, `players`, `matches` icin canonical kolon setini belirle
- `provider`, `provider_id`, `canonical_id`, `entity_uid` mantigini dondur
- Match tarafinda provider bagimsiz zorunlu alanlari netlestir

Done when:

- canonical tablo ve kolon listesi implementasyon seviyesinde sabitlenmis

#### KG-01-03 - Missing source tablolar icin migration planini cikar

- Kodda kullanilip migration'da gorunmeyen tablolari tespit et
- `user_favorite_matches`, `k_coin_transactions`, `k_coin_packages`, `k_coin_reward_rules` gibi alanlari dogrula
- Her eksik parca icin migration ihtiyacini netlestir

Done when:

- eksik migration backlog'u ayri issue'lara donusturulmus

#### KG-01-04 - Onboarding tercihlerini kalici source tabloya tasarla

- Sadece auth metadata kullanimi yerine `user_follow_entities` source modelini tanimla
- takim, lig ve gerekirse bildirim tercihlerinin nasil yazilacagini belirle

Done when:

- onboarding secimleri graph'a uygun source sekilde tutulabiliyor

#### KG-01-05 - K-Coin ve KG sinirini belgele

- hangi coin verisinin graph'a girecegini, hangisinin kesinlikle relational kalacagini yaz
- badge, reward, spend, purchase event'lerinin graph tarafina nasil yansiyacagini belirle

Done when:

- K-Coin tarafinda graph authoritative veri kaynagi olmayacak sekilde kurallar net

## Epic KG-02 - Event Contract And Outbox Foundation

Amac:

- KG'nin beslenecegi standart event sozlesmelerini tanimlamak
- tum projection akisini outbox uzerinden deterministic hale getirmek

Priority:

- P0

Depends on:

- KG-01

Done when:

- minimum event seti sabit
- outbox semasi ve retry mantigi net
- bir event ikinci kez islendiginde duplicate projection uretmiyor

### Issues

#### KG-02-01 - Event taxonomy ve payload semasini tanimla

- day-1 event adlarini dondur
- minimum payload alanlarini belirle
- actor, entity, timestamp, source, correlation id ve metadata alanlarini standartlastir

Day-1 minimum event seti:

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

Done when:

- her event icin zorunlu payload shape'i cikmis

#### KG-02-02 - `kg_event_outbox` semasini tasarla

- append-only event tablosunu tanimla
- unique event id, aggregate id, entity uid, event type, payload, emitted at, processing status alanlarini ekle
- idempotency icin gerekli index ve constraint'leri tanimla

Done when:

- outbox tablosu ve index stratejisi implementasyona hazir

#### KG-02-03 - Failure ve replay altyapisini tasarla

- `kg_failed_events`
- `kg_projection_checkpoint`
- retry count
- last error
- dead-letter akislarini netlestir

Done when:

- projection failure ve replay senaryolari kapatilmis

#### KG-02-04 - Source aksiyonlar icin event emission noktalarini haritala

- favorites provider
- match detail open
- chat send
- bet place
- insight vote
- onboarding akisi
- badge unlock

Done when:

- her user action icin event'in nerede emit edilecegi belirli

#### KG-02-05 - Outbox idempotency test plani yaz

- duplicate event replay
- partial batch failure
- worker restart
- checkpoint resume

Done when:

- event pipeline icin otomasyon test matrisi cikmis

## Epic KG-03 - Graph Storage And Projection Worker

Amac:

- Neo4j tarafinda canonical node/edge projection katmanini kurmak
- source event'leri graph yapisina deterministic sekilde yansitmak

Priority:

- P0

Depends on:

- KG-01
- KG-02

Done when:

- Neo4j schema, constraint ve index'ler acik
- worker projection yapiyor
- replay duplicate node/edge uretmiyor

### Issues

#### KG-03-01 - Neo4j label ve relation modelini sabitle

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

Done when:

- label ve relation seti dondurulmus

#### KG-03-02 - `kg_entity_registry` modelini kur

- source entity ile canonical entity arasindaki baglantiyi tut
- provider alias ve provider id map'lerini merkezilestir

Done when:

- ayni entity birden cok provider'dan geldiginde tek canonical uid'e baglanabiliyor

#### KG-03-03 - `kg-sync-worker` servis tasarimini uygula

- batch polling veya queue tabanli tuketim
- event parse
- canonical resolve
- Neo4j write
- checkpoint update

Done when:

- worker event alip projection yazabiliyor

#### KG-03-04 - Historical backfill akisini kur

- mevcut `matches`, `user_bets`, `chat_messages`, `notifications`, `badges`, `devices` ve diger source tablolar uzerinden ilk graph kurulumunu destekle
- backfill ile realtime projection mantigi ayni canonical kurallari kullanmali

Done when:

- sifirdan graph rebuild edilebiliyor

#### KG-03-05 - Projection parity ve replay testlerini yaz

- ayni historical dataset iki kez replay edilince ayni graph state cikmali
- duplicate node/edge olmamali

Done when:

- deterministic projection dogrulanmis

## Epic KG-04 - Personalization And Notification Graph

Amac:

- KG'nin ilk production degerini feed ve bildirim relevance tarafinda acmak

Priority:

- P1

Depends on:

- KG-01
- KG-02
- KG-03

Done when:

- personalized match ranking graph destekli calisiyor
- notification candidate secimi graph destekli calisiyor
- graph kapaliyken fallback mekanizmasi aktif

### Issues

#### KG-04-01 - `kg_user_affinity_snapshot` modelini tanimla

- graph'tan turetilmis ama Postgres'te query edilebilir affinity snapshot katmanini kur
- team, league, match ve gerekiyorsa player affinity alanlarini belirle

Done when:

- graph fallback'i icin okunabilir snapshot var

#### KG-04-02 - Personalized feed scoring fonksiyonunu tasarla

Skor mantigi sabit:

- `%35` explicit follows
- `%25` recent behavior
- `%15` league affinity
- `%10` related-team expansion
- `%10` live-state boost
- `%5` editorial priority

Done when:

- formulu kullanan backend arayuzu net

#### KG-04-03 - `kg-get-personalized-matches` arayuzunu tanimla

- input ve output shape'ini dondur
- mevcut match feed ile entegre olacak kadar netlestir

Done when:

- istemciyi kirpmeden yeni skor siralamasi alinabiliyor

#### KG-04-04 - Notification relevance motorunu tasarla

Girdi sinyalleri:

- event severity
- user affinity
- freshness
- opt-in state

Kurallar:

- ayni topic icin 30 dakika duplicate suppression
- graph down ise simplified affinity fallback

Done when:

- notification candidate secim kurallari net

#### KG-04-05 - Personalization kalite metriklerini ekle

- clickthrough
- open rate
- favorite conversion
- prediction conversion
- notification open rate

Done when:

- personalization sonrasi etkiler olculebilir

## Epic KG-05 - AI Context And Insight Integration

Amac:

- AI insight ve gelecekteki soru-cevap akislarini graph-backed context ile beslemek

Priority:

- P1

Depends on:

- KG-03
- KG-04

Done when:

- AI context backend arayuzu production-ready
- insight generation graph baglami kullaniyor
- explainability korunuyor

### Issues

#### KG-05-01 - `kg-build-ai-context` contract'ini tanimla

- match context
- team and league relations
- rivalry
- recent form
- prediction behavior
- vote distribution
- chat activity
- optional user affinity

Done when:

- AI katmanina gidecek sabit response shape'i cikmis

#### KG-05-02 - Insight source mapping ve provenance modelini ekle

- AI'ya verilen her relation veya fact icin source metadata koru
- hangi bilgi graph'tan, hangi bilgi source tablodan geliyor net olsun

Done when:

- explainability kaybolmadan AI context uretilebiliyor

#### KG-05-03 - `generate-insights` akisini KG context'e tasarla

- bugunku ham tablo okuma veya mock mantigini kaldiracak yeni akis tasarla
- prompt input ve fallback davranisini belirle

Done when:

- insight generation graph tabanli baglamla calisabiliyor

#### KG-05-04 - AI fallback stratejisini yaz

- graph gecici ulasilamazsa hangi minimal context kullanilacak
- hic veri yoksa nasil degrade olunacak

Done when:

- AI akisi graph olmadan da kontrollu sekilde calisiyor

#### KG-05-05 - AI context test paketini ekle

- empty graph
- partial graph
- stale relation
- conflicting provider aliases

Done when:

- AI context edge case'leri regression seviyesinde kapsanmis

## Epic KG-06 - Entity Resolution, Alias And Canonical Identity

Amac:

- provider bagimsiz entity esleme ve canonical kimlik katmanini production seviyesine getirmek

Priority:

- P2

Depends on:

- KG-01
- KG-03

Done when:

- ayni takim/mac/oyuncu farkli kaynaklardan geldiginde tek canonical entity uzerine oturuyor

### Issues

#### KG-06-01 - Team ve league alias modelini kur

- `team_aliases`
- `league_aliases` gerekirse
- provider source mapping

Done when:

- ayni takim farkli isimlerle duplicate node olusturmuyor

#### KG-06-02 - Match canonicalization kurallarini yaz

- provider id
- date window
- home/away canonical team eslesmesi
- league/season baglami

Done when:

- ayni mac farkli feed'lerde tek canonical uid'e baglanabiliyor

#### KG-06-03 - Player canonicalization fazini tasarla

- player verisi provider'da hazir oldugunda alinacak yol
- name collision ve transfer durumlarini planla

Done when:

- player-level expansion icin karar eksigi kalmamis

#### KG-06-04 - Alias resolution kalite metriklerini ekle

- false merge
- false split
- unresolved alias rate

Done when:

- canonicalization kalitesi izlenebilir durumda

## Epic KG-07 - Risk, Device And Abuse Graph

Amac:

- device, account ve davranissal iliskilerden fraud ve abuse sinyalleri uretmek

Priority:

- P2

Depends on:

- KG-03
- KG-06

Done when:

- graph uzerinden risk adjacency analizi yapilabiliyor
- ama balance/ledger authority relational tarafta kaliyor

### Issues

#### KG-07-01 - Device relation modelini kur

- `Device` node
- `USES_DEVICE` edge
- token/device id/source platform baglari

Done when:

- user-device iliskileri graph'ta izlenebilir

#### KG-07-02 - Wallet ve bet davranisindan derived risk event'lerini tanimla

- duplicate account pattern
- coordinated betting
- suspicious reward claim timing

Done when:

- risk graph icin minimum event seti cikmis

#### KG-07-03 - Risk score hesap mantigini tanimla

- sadece advisory olacak
- authoritative action engine olmayacak

Done when:

- risk graph guvenlik yardimci katmani olarak konumlanmis

#### KG-07-04 - Abuse investigation query setini ekle

- common device
- common entity cluster
- synchronized betting pattern

Done when:

- operasyon ekibi veya admin araci icin sorgular hazir

## Epic KG-08 - Operability, Monitoring And Rollout

Amac:

- KG altyapisini izlenebilir, geri alinabilir ve operasyonel olarak guvenli hale getirmek

Priority:

- P0

Depends on:

- KG-02
- KG-03

Done when:

- projection lag, worker sagligi ve fallback oranlari izlenebiliyor
- rollout kontrollu ve geri alinabilir

### Issues

#### KG-08-01 - Operasyon metriklerini tanimla

- projection lag
- worker throughput
- dead-letter count
- replay success rate
- fallback usage rate
- query p95

Done when:

- minimum dashboard metrikleri cikmis

#### KG-08-02 - Alerting kurallarini yaz

- lag threshold
- repeated worker failure
- dead-letter spike
- Neo4j connectivity failure

Done when:

- KG kritik hatalari otomatik gorulur hale gelmis

#### KG-08-03 - Rollout strategy belgesini yaz

- dev
- staging
- shadow mode
- partial production
- full production

Done when:

- KG once read-only shadow mode ile denenebilir durumda

#### KG-08-04 - Rollback ve rebuild prosedurunu yaz

- worker stop
- checkpoint reset
- projection rebuild
- fallback zorlamasi

Done when:

- graph bozuldugunda operasyonel geri donus yolu net

## Onerilen Uygulama Sirasi

Asagidaki sira sabit tavsiye edilir:

1. KG-01 Schema Reconciliation And Canonical Domain
2. KG-02 Event Contract And Outbox Foundation
3. KG-03 Graph Storage And Projection Worker
4. KG-08 Operability, Monitoring And Rollout
5. KG-04 Personalization And Notification Graph
6. KG-05 AI Context And Insight Integration
7. KG-06 Entity Resolution, Alias And Canonical Identity
8. KG-07 Risk, Device And Abuse Graph

## Ilk Sprint Icinde Acilabilecek Minimum Issue Seti

Eger hemen baslanacaksa ilk sprint icin minimum set:

- KG-01-01
- KG-01-02
- KG-01-04
- KG-02-01
- KG-02-02
- KG-02-04
- KG-03-01
- KG-03-02
- KG-08-01

Bu set tamamlanmadan projection worker veya AI integration tarafina gecilmemelidir.
