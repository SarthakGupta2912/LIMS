plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Compile the user's reference library directly, without modifying its sources.
val reference = file("../../../Meshrabiya-main/lib-meshrabiya")
require(reference.isDirectory) { "Meshrabiya-main must be beside invoice_management_system" }

android {
    namespace = "com.ustadmobile.httpoverbluetooth"
    compileSdk = 36
    defaultConfig { minSdk = 26 }
    sourceSets.getByName("main") {
        java.srcDir(reference.resolve("src/main/java"))
        manifest.srcFile(reference.resolve("src/main/AndroidManifest.xml"))
        res.srcDir(reference.resolve("src/main/res"))
    }
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

dependencies {
    implementation("androidx.core:core-ktx:1.10.1")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.athaydes.rawhttp:rawhttp-core:2.5.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.5.1")
    implementation("androidx.datastore:datastore-preferences:1.1.7")
    implementation("org.bouncycastle:bcprov-jdk18on:1.75")
    implementation("org.bouncycastle:bcpkix-jdk18on:1.75")
    implementation("com.github.seancfoley:ipaddress:5.4.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
