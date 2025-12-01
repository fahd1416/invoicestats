// Configuration of the build environment for the entire project
// تهيئة بيئة البناء للمشروع بأكمله.

// ** كتلة buildscript: هنا نعرّف خدمات Google (Firebase) لـ Gradle **
buildscript {
    // تعريف إصدار Kotlin داخل نطاق buildscript (الصيغة الصحيحة لـ KTS)
    val kotlin_version = "1.8.20"

    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        // أدوات بناء Android الأساسية
        classpath("com.android.tools.build:gradle:8.1.1") 
        // استخدام المتغير المعرّف
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version")
        
        // ⬅️ إضافة خدمة Google Services (Firebase)
        classpath("com.google.gms:google-services:4.4.1") 
    }
}


allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}