pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    // pluginManagement 先于 apply(from=...) 求值，仓库须内联配置（CI 禁用阿里云镜像）
    repositories {
        val useCnMirror =
            System.getenv("CI") != "true" &&
                System.getenv("GITHUB_ACTIONS") != "true" &&
                run {
                    val local = java.util.Properties()
                    file("local.properties").takeIf { it.isFile }?.inputStream()?.use {
                        local.load(it)
                    }
                    when (local.getProperty("useCnMavenMirror")?.lowercase()) {
                        "false", "0" -> false
                        "true", "1" -> true
                        else -> {
                            val gradle = java.util.Properties()
                            file("gradle.properties").takeIf { it.isFile }?.inputStream()?.use {
                                gradle.load(it)
                            }
                            gradle.getProperty("useCnMavenMirror", "false") != "false"
                        }
                    }
                }
        if (useCnMirror) {
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/public") }
            maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
