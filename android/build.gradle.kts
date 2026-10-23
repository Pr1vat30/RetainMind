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

// flutter_pcm_sound 3.3.3 hard-codes compileSdk 33, but its AndroidX
// dependencies require API 34+. Raise only that plugin module's compile SDK.
subprojects {
    if (name == "flutter_pcm_sound") {
        afterEvaluate {
            val androidExtension = extensions.findByName("android")
            val setCompileSdk = androidExtension?.javaClass?.methods?.firstOrNull {
                it.name == "setCompileSdk" &&
                    it.parameterTypes.contentEquals(arrayOf(Integer::class.java))
            }
            requireNotNull(setCompileSdk) {
                "Could not configure flutter_pcm_sound compileSdk"
            }.invoke(androidExtension, 34)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
