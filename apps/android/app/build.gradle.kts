plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("app.cash.paparazzi")
}

android {
    namespace = "io.bitrise.sample.counter"
    compileSdk = 34

    defaultConfig {
        applicationId = "io.bitrise.sample.counter"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // Sample only: sign release with the debug key so Appium/BrowserStack can install it.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    testOptions {
        unitTests.isIncludeAndroidResources = true
        // Turn off animations on the emulator for stable UI tests.
        animationsDisabled = true
    }
}

// BitrisePaparazzi.kt needs real JDK classes (ImageIO, BufferedImage) to save
// per-test-case diff images; Kotlin JVM test compilation excludes the JDK by
// default, so re-enable it for unit test compile tasks only. Also point each
// Test task's snapshot output at build/bitrise-snapshots/<task-name> and
// expose the task name as a system property, both read by
// BitriseSnapshotHandler to build the attachment's file name convention.
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
    if ("UnitTest" in name) compilerOptions.noJdk.set(false)
}

tasks.withType<Test>().configureEach {
    val snapshots = layout.buildDirectory.dir("bitrise-snapshots/$name")
    systemProperty("bitrise.test.task", name)
    outputs.dir(snapshots)
    doFirst { snapshots.get().asFile.deleteRecursively() }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    // Local unit tests (JVM)
    testImplementation("junit:junit:4.13.2")

    // Instrumented UI tests (emulator/device)
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
}
