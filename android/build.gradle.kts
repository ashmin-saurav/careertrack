buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // 🟢 BEST CHOICE: Required for reliable Android 15 / 16 KB alignment
        classpath("com.android.tools.build:gradle:8.7.3")

        // Match with modern Kotlin for the best performance
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.24")

        // Standard Firebase bridge
        classpath("com.google.gms:google-services:4.4.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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