// ---------------------------------------------------------------------------
// Eklenti uyumluluğu: bazı eklentiler (ör. porcupine_flutter 4.0.0) kendi
// build.gradle dosyalarında compileSdkVersion 31 sabitliyor. AGP 9 döneminde
// bağımlı oldukları androidx paketleri en az 34 istediği için derleme duruyor.
// Burada tüm alt projelerin compileSdk değerini uygulamanınkiyle eşitliyoruz.
// (Yansıma kullanılıyor: AGP 8 ve 9'da DSL sınıf adları değişebiliyor.)
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        val compileSdk = 36
        val applied =
            runCatching {
                androidExt.javaClass
                    .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    .invoke(androidExt, compileSdk)
                true
            }.getOrElse {
                runCatching {
                    androidExt.javaClass
                        .getMethod("setCompileSdkVersion", Integer::class.java)
                        .invoke(androidExt, compileSdk)
                    true
                }.getOrDefault(false)
            }
        if (!applied) {
            logger.info("[compileSdk uyumu] ${project.name} için otomatik ayar yapılamadı")
        }
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

// Android lint ("lintVital*") AGP 9 + eklenti kombinasyonunda çökebiliyor
// (ör. image_picker_android:lintVitalAnalyzeRelease / CommentDetector).
// APK üretimi için gerekli olmadığından bu görevleri kapatıyoruz.
subprojects {
    tasks.configureEach {
        if (name.startsWith("lintVital") || name == "lint" || name == "lintDebug") {
            enabled = false
        }
    }
}
