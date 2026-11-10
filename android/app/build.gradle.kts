import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Only use the release keystore when every required field is present.
// Otherwise (e.g. CI without secrets) fall back to debug signing so builds
// never break.
val hasReleaseSigning = keystorePropertiesFile.exists() &&
    listOf("storePassword", "keyPassword", "keyAlias", "storeFile").all {
        (keystoreProperties[it] as? String)?.isNotBlank() == true
    }

// Opt-in: sign the *debug* build type with the release keystore (for
// upgrade-compatible test builds). Enable with
//   -PsignDebugWithRelease=true
// or env ORG_GRADLE_PROJECT_signDebugWithRelease=true
// Never distribute such (debuggable) builds to end users.
val signDebugWithRelease =
    (project.findProperty("signDebugWithRelease") as String?)?.toBoolean() ?: false

// Debug builds get an applicationId suffix by default so a debug build can
// coexist with the release build on the same device (they upgrade independently).
//   default            -> ".debug"
//   -PdebugAppIdSuffix=true        -> ".debug"
//   -PdebugAppIdSuffix=beta        -> ".beta"
//   -PdebugAppIdSuffix=false|none  -> no suffix (same id as release)
// or env ORG_GRADLE_PROJECT_debugAppIdSuffix=...
val debugAppIdSuffixRaw =
    (project.findProperty("debugAppIdSuffix") as String?)?.trim()
val debugAppIdSuffix: String? = when {
    debugAppIdSuffixRaw == null -> ".debug"
    debugAppIdSuffixRaw.isEmpty() -> null
    debugAppIdSuffixRaw.equals("false", true) -> null
    debugAppIdSuffixRaw.equals("none", true) -> null
    debugAppIdSuffixRaw.equals("true", true) -> ".debug"
    debugAppIdSuffixRaw.startsWith(".") -> debugAppIdSuffixRaw
    else -> ".$debugAppIdSuffixRaw"
}

android {
    namespace = "com.medhistorygen.medhistory_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.xinggue.docmasterPei"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    packaging {
        jniLibs {
            excludes += setOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            if (debugAppIdSuffix != null) {
                applicationIdSuffix = debugAppIdSuffix
            }
            signingConfig = if (signDebugWithRelease && hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
