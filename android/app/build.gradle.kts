// android/app/build.gradle.kts

val flutterVersionCode: String = "7"
val flutterVersionName: String = "1.2025.0"

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.gearup.app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    buildFeatures {
        buildConfig = true // Force la génération de la classe BuildConfig
    }

    defaultConfig {
        applicationId = "com.gearup.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
    }

    signingConfigs {
        create("release") {
            storeFile = file("/home/yannick/Documents/gearup/dev/gearup_android/my-upload-key.keystore")
            storePassword = "Gearup200125"
            keyAlias = "my-upload-key"
            keyPassword = "Gearup200125"
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

flutter { source = "../.." }

// Make sure any transitive inclusion of core-common is excluded globally
configurations {
    all {
        // keep analytics libs out if you want
        exclude(group = "com.google.android.gms", module = "play-services-measurement")

        // Prevent duplicate Play Core classes by excluding core-common wherever it appears transitively
        exclude(group = "com.google.android.play", module = "core-common")
    }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.3.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-appcheck-playintegrity")
    implementation("com.google.firebase:firebase-storage")
    implementation("com.google.firebase:firebase-appcheck-debug")
    implementation("com.google.firebase:firebase-appcheck")

    implementation("com.google.android.gms:play-services-ads:23.0.0")
    implementation("com.google.android.gms:play-services-measurement:23.0.0")
    implementation("com.google.android.gms:play-services-measurement-base:23.0.0")
    implementation("com.google.android.gms:play-services-measurement-impl:23.0.0")
    implementation("com.google.android.gms:play-services-measurement-api:23.0.0")
    implementation("com.google.android.gms:play-services-measurement-sdk-api:23.0.0")
    
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.9.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.browser:browser:1.8.0")
    implementation("androidx.webkit:webkit:1.14.0")
    implementation("androidx.window:window:1.2.0")
    implementation("androidx.activity:activity-ktx:1.8.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")

    // --- Play Core (only core) ---
    // Keep core but explicitly exclude core-common in case any transitive dependency drags it in
    implementation("com.google.android.play:core:1.10.3") {
        exclude(group = "com.google.android.play", module = "core-common")
    }
}

apply(plugin = "com.google.gms.google-services")
