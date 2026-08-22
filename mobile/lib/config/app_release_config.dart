/// App 安装包分发（服务器直链 + GitHub Releases）。
class AppReleaseConfig {
  AppReleaseConfig._();

  static const defaultGithubReleasesUrl =
      'https://github.com/keller-cc/ihope/releases';

  static const defaultGithubRepo = 'keller-cc/ihope';

  static const domesticApkAssetName = 'app-domestic-release.apk';

  static String githubReleasesUrl = defaultGithubReleasesUrl;

  static String githubApiLatestUrl(String repo) =>
      'https://api.github.com/repos/$repo/releases/latest';
}
