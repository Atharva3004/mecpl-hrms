import java.util.Properties
import java.io.FileInputStream

// 🔐 Load keystore properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("org.jetbrains.kotlin.android")
    // Reads google-services.json so Firebase SDKs can find the project config.
    id("com.google.gms.google-services")
}


android {
    // ✅ REAL & FINAL PACKAGE NAME
    namespace = "com.mecpl.hrms"

    compileSdk = 36
    // ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications — backports java.time and
        // other Java 8+ APIs to older Android versions.
        isCoreLibraryDesugaringEnabled = true
    }

    // Kotlin 2.3+ compiler options
    kotlin {
        jvmToolchain(17)
    }

    defaultConfig {
        applicationId = "com.mecpl.hrms"
        minSdk = flutter.minSdkVersion
        
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 🔥 VERY IMPORTANT — MUST BE INSIDE android {}
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // ✅ RELEASE SIGNING
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("release")

            // 🔥 DISABLE SYMBOL STRIPPING (CRITICAL FIX)
            ndk {
                debugSymbolLevel = "NONE"
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
