plugins {

    id("com.android.application")

    id("dev.flutter.flutter-gradle-plugin")

}



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

    }



    defaultConfig {

        applicationId = "com.clprince.ihope"

        minSdk = flutter.minSdkVersion

        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode

        versionName = flutter.versionName
        resValue("string", "app_name", "IHope")

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


