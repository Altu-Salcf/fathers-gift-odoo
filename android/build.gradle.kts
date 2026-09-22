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
    val fixNamespace = Action<Project> {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                val getNamespace = android.javaClass.getMethod("getNamespace")
                val currentNamespace = getNamespace.invoke(android) as? String
                if (currentNamespace.isNullOrEmpty()) {
                    var pkgName: String? = null
                    val manifestFile = file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val manifestText = manifestFile.readText()
                        val match = Regex("""package\s*=\s*"([^"]+)"""").find(manifestText)
                        pkgName = match?.groupValues?.get(1)
                    }
                    val finalNamespace = pkgName ?: "com.plugin.${name.replace("-", "_").replace(".", "_")}"
                    val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespace.invoke(android, finalNamespace)
                }
            } catch (_: Exception) {
            }
        }
    }
    if (state.executed) {
        fixNamespace.execute(this)
    } else {
        afterEvaluate(fixNamespace)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
