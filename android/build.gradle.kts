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

// Flutter's assembleDebug can compile google_mlkit_translation before commons
// is on the classpath (Windows parallel builds). Force jar + explicit dep.
subprojects {
    if (name == "google_mlkit_translation") {
        afterEvaluate {
            dependencies {
                add("implementation", project(":google_mlkit_commons"))
            }
            tasks.matching { it.name.endsWith("JavaWithJavac") }.configureEach {
                dependsOn(":google_mlkit_commons:bundleLibCompileToJarDebug")
            }
        }
    }
}

subprojects {
    tasks.withType<JavaCompile>().configureEach {
        options.compilerArgs.add("-Xlint:-options")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
