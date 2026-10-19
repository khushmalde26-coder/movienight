// Plain Kotlin, no Android: the library logic (what each video is, titles, rows, watch history),
// shared by the phone, tablet and TV apps and tested on any machine.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

// Java 17 bytecode, which Android's build tools accept; any JDK 17 or newer builds it.
java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
}
