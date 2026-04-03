import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun resolveKeystoreValue(propertyName: String, envName: String): String {
    return (keystoreProperties.getProperty(propertyName)
        ?: providers.gradleProperty(envName).orNull
        ?: System.getenv(envName)
        ?: "").trim()
}

val releaseStoreFile = resolveKeystoreValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStorePassword = resolveKeystoreValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = resolveKeystoreValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = resolveKeystoreValue("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseAdMobAppId = (providers.gradleProperty("ADMOB_ANDROID_APP_ID").orNull
    ?: System.getenv("ADMOB_ANDROID_APP_ID")
    ?: "").trim()

android {
    namespace = "com.boskale.sportsapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.boskale.sportsapp"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["admobApplicationId"] = ""
    }

    signingConfigs {
        create("release") {
            if (releaseStoreFile.isNotEmpty() &&
                releaseStorePassword.isNotEmpty() &&
                releaseKeyAlias.isNotEmpty() &&
                releaseKeyPassword.isNotEmpty()
            ) {
                storeFile = rootProject.file(releaseStoreFile)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        getByName("debug") {
            manifestPlaceholders["admobApplicationId"] = "ca-app-pub-3940256099942544~3347511713"
        }
        release {
            manifestPlaceholders["admobApplicationId"] = releaseAdMobAppId

            if (releaseStoreFile.isNotEmpty() &&
                releaseStorePassword.isNotEmpty() &&
                releaseKeyAlias.isNotEmpty() &&
                releaseKeyPassword.isNotEmpty()
            ) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}
