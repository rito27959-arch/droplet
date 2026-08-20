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

// `receive_sharing_intent` ne déclare pas son propre compileOptions Java et
// retombe sur le défaut 1.8, alors que sa compilation Kotlin résout déjà
// vers 17 (JDK du projet) — Gradle refuse ce décalage ("Inconsistent JVM
// Target Compatibility"). Correctif ciblé sur CE seul module : un
// `subprojects { ... }` généralisé à tous les plugins tiers casse le
// classpath Android (bootclasspath) d'autres modules (ex. file_picker),
// visiblement parce que poser sourceCompatibility/targetCompatibility en
// dehors du DSL `android.compileOptions` d'AGP perd l'injection
// android.jar propre à AGP pour ces tâches.
gradle.projectsEvaluated {
    project(":receive_sharing_intent").tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
