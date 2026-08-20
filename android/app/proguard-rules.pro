# R8 kurallari.
#
# minifyEnabled/shrinkResources acilmadan once hicbir kural yoktu; simdi
# aciliyor. Asagidaki paketler ya JNI ya da reflection kullaniyor, yani R8
# onlari "kullanilmiyor" sanip atabilir ve arizasi ancak release APK'da,
# calisma aninda ortaya cikar.

# --- Flutter motoru ---
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# --- Play Core: Flutter'in deferred component API'si referans veriyor ama
#     bagimlilik projede yok; uyariyi susturmazsak R8 hata veriyor. ---
-dontwarn com.google.android.play.core.**

# --- LiveKit / WebRTC: yerel katman Java siniflarini isimle cagiriyor ---
-keep class org.webrtc.** { *; }
-keep class io.livekit.** { *; }
-dontwarn org.webrtc.**

# --- Firebase / Crashlytics: stack trace'lerin okunabilir kalmasi icin ---
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# --- RevenueCat (purchases_flutter): model siniflari JSON'dan reflection ile
#     kuruluyor ---
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# --- Google Mobile Ads ---
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.**

# --- Rive: yerel kutuphane JNI ile baglaniyor ---
-keep class app.rive.runtime.** { *; }
-dontwarn app.rive.runtime.**

# --- Glance / home_widget app widget saglayicisi manifest'ten isimle
#     cozuluyor ---
-keep class com.boskale.sportsapp.SportsAppWidgetProvider { *; }
-keep class androidx.glance.** { *; }

# --- Kotlin coroutines ic siniflari ---
-dontwarn kotlinx.coroutines.**

# Generic imzalari koru: Gson/Moshi tarzi reflection tabanli parser'lar
# TypeToken'i bunlarsiz cozemez.
-keepattributes Signature,InnerClasses,EnclosingMethod
