plugins {
    id("com.android.application")
    id("kotlin-android")
    // ⬅️ تطبيق الـ plugin لخدمات Google (Firebase)
    id("com.google.gms.google-services") 
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // ⬅️ يجب أن يتطابق namespace مع applicationId
    namespace = "com.wethaaq.invoicestats" 
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
        // ⬅️ هذا يجب أن يتطابق مع اسم الحزمة في google-services.json
        applicationId = "com.wethaaq.invoicestats" 
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// ** اعتماديات Firebase الفعلية **
dependencies {
    // يفضل استخدام Firebase BOM لتوحيد إصدارات جميع حزم Firebase
    implementation(platform("com.google.firebase:firebase-bom:32.7.0")) 
    
    // حزم Firebase الأساسية
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")
    // يمكنك إضافة اعتماديات أخرى هنا لاحقاً مثل firestore
}