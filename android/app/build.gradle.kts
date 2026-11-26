import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Kunci tanda tangan rilis permanen. android/key.properties berisi password.
// storeFile dicari relatif terhadap modul android/app dulu (konvensi Flutter &
// CI tim: storeFile=release.jks -> android/app/release.jks), lalu relatif
// terhadap android/ (mis. storeFile=keystore/release.jks dari skrip versi
// awal). Semua di-ignore git. Lihat scripts/create-release-keystore.ps1.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val releaseKeystoreFile: File? = keystoreProperties.getProperty("storeFile")
    ?.let { path -> listOf(file(path), rootProject.file(path)).firstOrNull { it.exists() } }
val hasReleaseKeystore = releaseKeystoreFile != null
if (keystoreProperties.getProperty("storeFile") != null && !hasReleaseKeystore) {
    logger.warn("key.properties ada tapi keystore tidak ditemukan; release memakai debug key.")
}

android {
    namespace = "com.motorqu.solid"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // ID permanen aplikasi. JANGAN diganti setelah rilis: Android menganggap
        // ID berbeda sebagai aplikasi lain sehingga auto-update akan putus.
        applicationId = "com.motorqu.solid"
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

        // Skema redirect OIDC sengaja tidak ikut diganti: harus sama dengan
        // redirect_uris di client-profile.jsonld yang sudah di-hosting.
        manifestPlaceholders.putAll(mapOf(
            "appAuthRedirectScheme" to "com.example.motorqusolid",
            "oidcRedirectScheme" to "com.example.motorqusolid"
        ))
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Pakai keystore permanen bila android/key.properties tersedia.
            // Tanpa itu, jatuh ke debug key agar `flutter run --release` lokal
            // tetap jalan. CI menolak build tanpa keystore (lihat build.yaml).
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
}
