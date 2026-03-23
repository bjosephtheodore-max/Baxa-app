import org.gradle.api.tasks.Delete

buildscript {
    val kotlinVersion by extra("2.1.0")

    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Force Kotlin Gradle plugin version for any dependency that requests an older version
configurations.all {
    resolutionStrategy {
        force("org.jetbrains.kotlin:kotlin-gradle-plugin:2.1.0")
    }
}

val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}