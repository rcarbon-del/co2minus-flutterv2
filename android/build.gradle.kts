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

// 1. FIRST: Register the afterEvaluate hook for all subprojects
// Fix for "Namespace not specified" in older plugins
subprojects {
    afterEvaluate {
        if (hasProperty("android")) {
            val android = extensions.getByName("android")
            try {
                val getNamespace = android.javaClass.getMethod("getNamespace")
                val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                if (getNamespace.invoke(android) == null) {
                    setNamespace.invoke(android, "com.abvlnt.co2minus.${project.name.replace("-", "_")}")
                }
            } catch (e: Exception) {
                // Handle cases where the extension isn't what we expect
            }
        }
    }
}

// 2. SECOND: Force the evaluation (the hook above will now fire safely for :app)
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}