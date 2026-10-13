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
// Les plugins compilés contre une API Android trop ancienne (file_picker :
// 34) échouent face à androidx récents, qui exigent 36. On aligne tous les
// modules sur 36 — compileSdk seulement : ni targetSdk ni minSdk ne bougent.
// (Par réflexion : la classe de l'extension Android n'est pas visible d'ici.)
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        if (project.name == "app") return@afterEvaluate
        runCatching {
            android.javaClass.getMethod("setCompileSdk", Integer::class.javaObjectType).invoke(android, 36)
        }.recoverCatching {
            android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType).invoke(android, 36)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
