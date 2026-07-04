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
    // Pin the NDK for every module (including plugin subprojects that read
    // flutter.ndkVersion themselves), since the version Flutter recommends
    // isn't fully installed in this environment.
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.ndkVersion = "27.0.12077973"
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
