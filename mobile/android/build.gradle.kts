import org.gradle.api.tasks.Exec
import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile

/** GitHub Actions / CI 不使用阿里云镜像（海外 runner 易 502）。 */
fun cnMavenMirrorEnabled(): Boolean {
    if (System.getenv("CI") == "true" || System.getenv("GITHUB_ACTIONS") == "true") {
        return false
    }
    val local = java.util.Properties()
    rootProject.file("local.properties").takeIf { it.isFile }?.inputStream()?.use {
        local.load(it)
    }
    when (local.getProperty("useCnMavenMirror")?.lowercase()) {
        "false", "0" -> return false
        "true", "1" -> return true
    }
    val gradle = java.util.Properties()
    rootProject.file("gradle.properties").takeIf { it.isFile }?.inputStream()?.use {
        gradle.load(it)
    }
    return gradle.getProperty("useCnMavenMirror", "false") != "false"
}

// MSYS2/Mingw 在 PATH 里会让 CMake 误用主机 GCC，导致 NDK 编译失败
fun ndkSafePath(): String =
    (System.getenv("PATH") ?: "")
        .split(';')
        .filter { segment ->
            val s = segment.lowercase().replace('/', '\\')
            s.isNotBlank() &&
                !s.contains("msys64") &&
                !s.contains("mingw") &&
                !s.contains("cygwin") &&
                !s.endsWith("\\git\\usr\\bin")
        }
        .joinToString(";")

allprojects {
    repositories {
        if (cnMavenMirrorEnabled()) {
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/public") }
        }
        google()
        mavenCentral()
    }
    tasks.withType<Exec>().configureEach {
        environment("PATH", ndkSafePath())
    }
}

// 部分 Flutter 插件仍声明 Java 8；统一 JVM 21（勿用 options.release，AGP 会报错）
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_21.toString()
        targetCompatibility = JavaVersion.VERSION_21.toString()
    }
    tasks.withType<KotlinJvmCompile>().configureEach {
        compilerOptions.jvmTarget.set(JvmTarget.JVM_21)
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
