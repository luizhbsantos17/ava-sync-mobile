import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Assinatura: se existir android/key.properties (ou variaveis ANDROID_STOREFILE etc. no CI),
// usa o keystore fixo; senao, a chave de debug (bom para testar).
val kp = Properties()
val kpArq = rootProject.file("key.properties")
if (kpArq.exists()) kp.load(kpArq.inputStream())
fun prop(n: String): String? = (kp.getProperty(n) ?: System.getenv("ANDROID_" + n.uppercase()))?.takeIf { it.isNotBlank() }
val temChave = prop("storeFile") != null

// Push do Social (Firebase Cloud Messaging). Os valores vêm de variáveis FCM_* (secrets do
// GitHub no CI) ou de android/key.properties (fcm.api_key etc.). Sem eles o app funciona
// igual, só sem push: as notificações do Social chegam pelo segundo plano (~15 min).
fun fcm(n: String): String = (System.getenv("FCM_$n") ?: kp.getProperty("fcm." + n.lowercase()) ?: "").trim()


android {
    buildFeatures {
        resValues = true
    }
    namespace = "io.github.avasync.ava_sync_mobile"
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.avasync.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        resValue("string", "fcm_api_key", fcm("API_KEY"))
        resValue("string", "fcm_project_id", fcm("PROJECT_ID"))
        resValue("string", "fcm_sender_id", fcm("SENDER_ID"))
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("production") {
            dimension = "distribution"
            manifestPlaceholders["appLabel"] = "AVA Sync"
            resValue("string", "fcm_app_id", fcm("APP_ID"))
        }
        create("beta") {
            dimension = "distribution"
            applicationIdSuffix = ".beta"
            versionNameSuffix = "-beta"
            manifestPlaceholders["appLabel"] = "AVA Sync Teste"
            resValue("string", "fcm_app_id", fcm("APP_ID_BETA"))
        }
    }

    if (temChave) {
        signingConfigs {
            create("release") {
                storeFile = file(prop("storeFile")!!)
                storePassword = prop("storePassword")
                keyAlias = prop("keyAlias")
                keyPassword = prop("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = if (temChave) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // só o receptor de push; a notificação é montada pelo Dart (lib/social/push.dart)
    implementation("com.google.firebase:firebase-messaging:24.1.0")
}
