import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials are kept locally in android/key.properties.
// Never commit key.properties or the .jks file to the repository.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.example.helloworld"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Keep this ID unchanged so future releases can update the same Android app.
        applicationId = "com.example.helloworld"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                val storePath = keystoreProperties.getProperty("storeFile")
                    ?: throw GradleException("Missing storeFile in android/key.properties")
                storeFile = file(storePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                    ?: throw GradleException("Missing storePassword in android/key.properties")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                    ?: throw GradleException("Missing keyAlias in android/key.properties")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: throw GradleException("Missing keyPassword in android/key.properties")
            }
        }
    }

    buildTypes {
        release {
            // Do not fall back to the debug key for a release build.
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
