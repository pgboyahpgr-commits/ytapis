plugins {
    kotlin("jvm") version "1.9.24"
}

group = "ytapis"
version = "2.0.0"
description = "Search YouTube and get video metadata — no API key required"

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.json:json:20240303")
    testImplementation(kotlin("test"))
}

kotlin {
    jvmToolchain(17)
}

tasks.test {
    useJUnitPlatform()
}
