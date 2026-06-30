import com.android.build.gradle.BaseExtension
import org.gradle.api.tasks.Exec
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile
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
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
    }
    tasks.withType<Exec>().configureEach {
        environment("PATH", ndkSafePath())
    }
}

// 部分 Flutter 插件仍声明 Java 8，在新 JDK 下会打印「源值 8 已过时」警告
subprojects {
    afterEvaluate {
        extensions.findByType(BaseExtension::class.java)?.apply {
            @Suppress("DEPRECATION")
            compileSdkVersion(36)
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_21
                targetCompatibility = JavaVersion.VERSION_21
            }
        }
    }
    tasks.withType(KotlinJvmCompile::class.java).configureEach {
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
