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
subprojects {
    plugins.withId("com.android.library") {
        if (project.name == "file_picker") {
            pluginManager.apply("com.android.built-in-kotlin")
        } else if (project.name == "share_plus") {
            // share_plus 13 detects AGP 9 and does not apply the legacy plugin,
            // while this project temporarily keeps built-in Kotlin disabled for
            // flutter_tts compatibility. Apply KGP explicitly until flutter_tts
            // can join the full built-in Kotlin migration.
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
