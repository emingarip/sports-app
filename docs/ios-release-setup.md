# iOS yayın kurulumu

iOS tarafı bugüne kadar hiç derlenmedi. Bu depoda yapılabilecek her şey
yapıldı; kalan üç madde **macOS + Xcode gerektiriyor** ve buradan yapılamaz.

Son güncelleme: 2026-08-20

## Bu depoda tamamlananlar

| Konu | Durum |
| --- | --- |
| `Podfile` | ✅ Eklendi, `platform :ios, '16.1'` |
| Deployment target | ✅ `project.pbxproj` içinde 3 yerde 13.0 → 16.1 |
| App Group entitlements | ✅ `Runner.entitlements` + `SportsAppWidgetExtension.entitlements` |
| ATT açıklaması | ✅ `NSUserTrackingUsageDescription` |
| SKAdNetwork | ✅ Google'ın kimliği (`cstr6suwn9.skadnetwork`) |
| AdMob app id | ✅ `Release.xcconfig` boştu, test kimliği yazıldı |
| Uygulama ikonu | ✅ `flutter_launcher_icons` ile üretildi |

**Deployment target neden 16.1?** `live_activities` paketi Live Activities
API'sini kullanıyor, o da iOS 16.1+. 13.0 kaldığı sürece widget extension
hedefi derlenmez. Bu, iOS 13-16.0 cihazlarını kapsam dışı bırakır — kabul
edilebilir değilse `live_activities` ve `home_widget` kaldırılıp hedef
düşürülmeli.

## macOS'ta yapılacaklar

### 1. Widget extension hedefini Xcode projesine ekle (zorunlu)

`ios/SportsAppWidgetExtension/` altındaki üç Swift dosyası diskte duruyor ama
**`project.pbxproj` içinde hiçbir hedef kaydı yok** — doğrulandı:
`grep -c SportsAppWidgetExtension ios/Runner.xcodeproj/project.pbxproj` → `0`.
Yani Live Activities ve ana ekran widget'ı iOS'ta hiç derlenmiyor.

Bu adım elle pbxproj düzenlemesiyle yapılmadı: hedef + build phase + embed
adımı eklemek uzun ve doğrulanamaz bir düzenleme, bozuk bir proje dosyası
riski gerçek. Xcode'da:

1. File > New > Target > **Widget Extension**, adı `SportsAppWidgetExtension`.
   "Include Live Activity" işaretli, "Include Configuration Intent" işaretsiz.
2. Xcode'un ürettiği şablon dosyalarını sil, `ios/SportsAppWidgetExtension/`
   altındaki üç dosyayı hedefe ekle.
3. Hedefin Signing & Capabilities sekmesinde **App Groups** ekle ve
   `group.com.boskale.sportsapp` seç. Runner hedefinde de aynısını yap.
4. Hedefin "Code Signing Entitlements" alanını
   `SportsAppWidgetExtension/SportsAppWidgetExtension.entitlements` yap.
5. Runner hedefinin Build Settings > Code Signing Entitlements alanını
   `Runner/Runner.entitlements` yap.

### 2. Firebase yapılandırması

`ios/Runner/GoogleService-Info.plist` yok. `Firebase.initializeApp()`
`main.dart` içindeki try/catch'e takılıyor: uygulama açılıyor ama Crashlytics
ve push bildirimleri sessizce ölü.

Firebase konsolundan `com.boskale.sportsapp` bundle id'si için iOS
uygulaması ekle, plist'i indir, `ios/Runner/` altına koy ve **Runner
hedefine ekle** (sadece klasöre kopyalamak yetmez).

### 3. İmzalama

`DEVELOPMENT_TEAM` ayarlı değil, `CODE_SIGN_STYLE = Automatic`. Xcode'da
takımı seç; Apple Developer portalında App ID için App Groups ve Push
Notifications yetkilerini aç.

## Doğrulama

```bash
flutter build ipa --release --dart-define-from-file=.env
```

Ardından cihazda elle kontrol:

- Maçlar sekmesi doluyor mu (`AI_SPORT_AGENT_BASE_URL` regresyonunun tek
  güvenilir testi)
- Ana ekrana widget eklenebiliyor ve veri gösteriyor mu (App Group çalışıyor mu)
- İlk açılışta ATT dialogu çıkıyor mu
