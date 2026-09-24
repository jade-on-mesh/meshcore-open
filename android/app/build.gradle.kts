import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.meshcore.meshcore_open"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.meshcore.meshcore_open.otp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Codec2 native build removed - no longer needed
        // externalNativeBuild {
        //     cmake {
        //         arguments += listOf("-DANDROID_STL=c++_shared")
        //     }
        // }
        // arm64-v8a only, deliberately.
        //
        //  * ONNX Runtime (flutter_onnxruntime, used by the AEIC-SE image codec)
        //    ships a per-ABI .so. arm64-v8a alone costs ~18 MB of APK; a
        //    universal APK carrying armeabi-v7a and x86_64 as well costs ~56 MB.
        //  * llamadart only declares android-arm64 and android-x64 backends in
        //    pubspec.yaml's `hooks.user_defines`, so an armeabi-v7a build already
        //    has no translation backend at all.
        //  * The image codec needs ~2.7 GiB peak resident, which no 32-bit
        //    address space can provide regardless of ABI.
        //
        // Consequence: this APK will not install on 32-bit-only ARM devices or on
        // x86_64 emulators. For emulator work, temporarily add "x86_64" here.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
        // Without key.properties (the normal case for this OTP dev build),
        // the release build type used to fall back to the implicit "debug"
        // signing config, which points at ~/.android/debug.keystore. That
        // file doesn't exist on a fresh GitHub Actions runner, so the
        // Android Gradle Plugin auto-generates a brand new one - with a
        // brand new random key - on EVERY CI run. Two builds from two
        // different runs therefore always have different signatures, and
        // sideloading a newer build over an older one fails with "App not
        // installed as package conflicts with existing package" even though
        // applicationId never changed. otp-debug.keystore is a fixed,
        // checked-in keystore (fine for a personal-sideload debug key, same
        // trust model as the default debug key it replaces) so every build -
        // CI or local - signs identically and can always upgrade in place.
        create("otpDebug") {
            storeFile = file("otp-debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("otpDebug")
            }
            // ONNX Runtime resolves its Java classes from native code by name.
            // Without these rules R8 renames them and the process SIGABRTs with
            // "java_class == null" the instant the codec runs a model.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Codec2 native build removed - no longer needed
    // externalNativeBuild {
    //     cmake {
    //         path = file("src/main/cpp/CMakeLists.txt")
    //     }
    // }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
