# Shorebird ile Versiyonlama Stratejisi

Bu proje, uygulama mağazalarına (App Store / Google Play) onaya göndermeden anında (OTA - Over-The-Air) güncelleme yapabilmek için **Shorebird** kullanmaktadır. Geliştirme süreçlerinde alınan her aksiyon için yama (patch) mi yoksa sürüm (release) güncellemesi mi yapılacağı çok net bir kurala tabidir:

## 1. Ufak Düzeltmeler ve UI Değişiklikleri (PATCH)
* Sadece Dart kodunda yapılan hataların düzeltilmesi (bugfix) veya arayüz (UI/UX) değişikliklerinde veya state (provider vb.) değişikliklerinde kullanılır.
* **KURAL:** `pubspec.yaml` dosyası içindeki `version:` anahtarı altındaki sürüm adı ve derleme (build) numarası (`version: 1.0.0+1`) **KENDISINDEN ONCEKI MARKET SURUMUYLE AYNI KALMALI, DEĞİŞTİRİLMEMELİDİR.**
* **AKSİYON:** Kod tamamlandığında Market'e yeni binary yüklenmez. Terminalden `shorebird patch android` komutu verilerek canlıdaki kullanıcılara anında kod yollanır.

## 2. Büyük Özellikler, Paket Yüklemeleri ve Native Değişimler (RELEASE)
* Projeye yeni bir pub paketi dâhil edildiğinde (özellikle kamera, lokasyon gibi native izin / kod çağıran eklentiler), `AndroidManifest.xml` veya `Info.plist` dosyalarında oynama yapıldığında, ya da Flutter Core Engine güncellendiğinde kullanılır.
* **KURAL:** `pubspec.yaml` dosyası içindeki `version:` anahtarındaki MAJOR.MINOR.PATCH numarası anlama göre güncellenmeli ve derleme numarası (build number), mağazada yüklü olan (Örn: `+1`) en son sürümden bir fazlası yapılmak **ZORUNDADIR** (`version: 1.1.0+2` vb).
* **AKSİYON:** Terminalden `shorebird release android` komutu verilerek uygulamanın `.aab` (Android App Bundle) veya `.ipa` dosyası alınır. Bu dosya daha sonra Google Play Console (veya Apple App Store Connect) ortamlarına derleme (release) olarak eklenerek standart uzun onay sürecinden geçirilir.
