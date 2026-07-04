import org.gradle.api.Project
import org.gradle.api.artifacts.dsl.RepositoryHandler
import org.gradle.api.initialization.Settings
import java.util.Properties

/** GitHub Actions / CI 不使用阿里云镜像（海外 runner 易 502）。 */
fun cnMavenMirrorEnabled(rootDir: java.io.File): Boolean {
    if (System.getenv("CI") == "true" || System.getenv("GITHUB_ACTIONS") == "true") {
        return false
    }
    val local = Properties()
    rootDir.resolve("local.properties").takeIf { it.isFile }?.inputStream()?.use {
        local.load(it)
    }
    when (local.getProperty("useCnMavenMirror")?.lowercase()) {
        "false", "0" -> return false
        "true", "1" -> return true
    }
    val gradle = Properties()
    rootDir.resolve("gradle.properties").takeIf { it.isFile }?.inputStream()?.use {
        gradle.load(it)
    }
    return gradle.getProperty("useCnMavenMirror", "true") != "false"
}

fun cnMavenMirrorEnabled(settings: Settings): Boolean =
    cnMavenMirrorEnabled(settings.rootDir)

fun cnMavenMirrorEnabled(project: Project): Boolean =
    cnMavenMirrorEnabled(project.rootProject.projectDir)

fun RepositoryHandler.configureIhopeRepositories(
    useCnMirror: Boolean,
    includeGradlePluginMirror: Boolean = false,
) {
    if (useCnMirror) {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        if (includeGradlePluginMirror) {
            maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        }
    }
    google()
    mavenCentral()
}

fun RepositoryHandler.configureIhopePluginRepositories(useCnMirror: Boolean) {
    configureIhopeRepositories(useCnMirror, includeGradlePluginMirror = true)
    gradlePluginPortal()
}
