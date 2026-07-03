import java.util.Base64

plugins {

    id("com.android.application")

    id("dev.flutter.flutter-gradle-plugin")

}

fun parseDartDefines(): Map<String, String> {
    val encoded = project.findProperty("dart-defines") as String? ?: return emptyMap()
    if (encoded.isEmpty()) return emptyMap()
    return encoded.split(",")
        .mapNotNull { entry ->
            try {
                val decoded = String(Base64.getDecoder().decode(entry.trim()), Charsets.UTF_8)
                val eq = decoded.indexOf('=')
                if (eq <= 0) null
                else decoded.substring(0, eq) to decoded.substring(eq + 1)
            } catch (_: IllegalArgumentException) {
                null
            }
        }
        .toMap()
}

val dartDefines = parseDartDefines()
val apiBaseFromDefine = dartDefines["API_BASE"] ?: ""
// Release + http API（如局域网联调包）允许明文；https 或未传 API_BASE 则禁止
val allowCleartextTraffic = apiBaseFromDefine.startsWith("http://")



if (file("google-services.json").exists()) {

    apply(plugin = "com.google.gms.google-services")

}



android {

    namespace = "com.clprince.ihope"

    compileSdk = 36

    ndkVersion = flutter.ndkVersion



    compileOptions {

        sourceCompatibility = JavaVersion.VERSION_21

        targetCompatibility = JavaVersion.VERSION_21

        isCoreLibraryDesugaringEnabled = true

    }



    defaultConfig {

        applicationId = "com.clprince.ihope"

        minSdk = flutter.minSdkVersion

        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode

        versionName = flutter.versionName
        resValue("string", "app_name", "IHope")
        manifestPlaceholders["usesCleartextTraffic"] = allowCleartextTraffic.toString()

        ndk {

            abiFilters += listOf("arm64-v8a", "x86_64")

        }

    }



    flavorDimensions += "market"

    productFlavors {

        create("domestic") {

            dimension = "market"

            applicationIdSuffix = ".cn"

            resValue("string", "app_name", "IHope")

            val jpushKey = (project.findProperty("JPUSH_APPKEY") as String?) ?: ""

            manifestPlaceholders["JPUSH_APPKEY"] = jpushKey

            manifestPlaceholders["JPUSH_CHANNEL"] = "clprince-ihope-domestic"

        }

        create("global") {

            dimension = "market"

            resValue("string", "app_name", "IHope")

        }

    }



    buildTypes {

        release {

            signingConfig = signingConfigs.getByName("debug")

        }

    }

}



kotlin {

    compilerOptions {

        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21

    }

}



flutter {

    source = "../.."

}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}


