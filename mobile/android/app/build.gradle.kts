plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "uz.baxshiai.baxshi_ai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "uz.baxshiai.app"
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
    }

    buildFeatures { resValues = true }
    flavorDimensions += "audience"
    productFlavors {
        create("user") {
            dimension = "audience"
            resValue("string", "app_name", "Baxshi AI")
        }
        create("admin") {
            dimension = "audience"
            applicationId = "uz.baxshiai.admin"
            resValue("string", "app_name", "Baxshi AI Admin")
        }
    }
    signingConfigs {
        create("production") {
            val keyPath = System.getenv("ANDROID_KEYSTORE_PATH")
            if (keyPath != null) {
                storeFile = file(keyPath)
                storePassword = System.getenv("ANDROID_STORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("production")
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

// Never silently publish a release with a development signing key.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release") } && System.getenv("ANDROID_KEYSTORE_PATH") == null) {
        throw GradleException("Release signing secrets are required. Use --debug for test APKs.")
    }
}
