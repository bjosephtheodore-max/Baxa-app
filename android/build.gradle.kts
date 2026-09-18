import org.gradle.api.tasks.Delete
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

buildscript {
    val kotlinVersion by extra("2.3.20")

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
        force("org.jetbrains.kotlin:kotlin-gradle-plugin:2.3.20")
    }
}

val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    project.evaluationDependsOn(":app")

    // screen_protector fixe sa cible Java à 17 dans son propre build.gradle
    // mais ne fixe jamais sa cible Kotlin, qui retombe alors sur le JDK
    // utilisé par Gradle sur la machine (21 ici) — Gradle refuse cet écart
    // entre javac et kotlinc au sein d'un même module. On aligne donc sa
    // cible Kotlin sur 17 explicitement, pour CE plugin précis seulement :
    // ne pas généraliser à tous les sous-projets — d'autres plugins (ex.
    // geocoding_android) déclarent 11 et casseraient si on leur imposait 17.
    if (project.name == "screen_protector") {
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_17)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}