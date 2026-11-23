import java.io.FileInputStream
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

fun signingConfigValue(propertyKey: String, envKey: String): String? {
    val fromProp = keystoreProperties.getProperty(propertyKey)?.trim()
    if (!fromProp.isNullOrEmpty()) return fromProp
    val fromEnv = System.getenv(envKey)?.trim()
    return if (!fromEnv.isNullOrEmpty()) fromEnv else null
}

val releaseStoreFilePath = signingConfigValue("storeFile", "DISPLAYMAC_KEYSTORE_PATH")
val releaseStorePassword = signingConfigValue("storePassword", "DISPLAYMAC_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingConfigValue("keyAlias", "DISPLAYMAC_KEY_ALIAS")
val releaseKeyPassword = signingConfigValue("keyPassword", "DISPLAYMAC_KEY_PASSWORD")
val hasReleaseSigning = !releaseStoreFilePath.isNullOrEmpty() &&
    !releaseStorePassword.isNullOrEmpty() &&
    !releaseKeyAlias.isNullOrEmpty() &&
    !releaseKeyPassword.isNullOrEmpty()

android {
    namespace = "com.displaymac.client"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.displaymac.remote"
        minSdk = 26
        targetSdk = 34
        versionCode = 3
        versionName = "1.0.2"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("universal") {
            storeFile = rootProject.file("displaymac-debug.jks")
            storePassword = "android"
            keyAlias = "displaymac"
            keyPassword = "android"
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
            enableV4Signing = false
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("universal")
        }
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("universal")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    lint {
        abortOnError = true
        warningsAsErrors = false
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.kotlinx.coroutines.android)

    testImplementation(libs.junit)
}
