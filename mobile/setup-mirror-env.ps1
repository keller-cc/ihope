# 国内 Flutter / Pub / 引擎下载镜像（用户级，永久生效）
# 用法：PowerShell -ExecutionPolicy Bypass -File .\setup-mirror-env.ps1
# 执行后请关闭并重新打开终端

$vars = @{
    FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
    PUB_HOSTED_URL           = 'https://pub.flutter-io.cn'
}

foreach ($name in $vars.Keys) {
    [System.Environment]::SetEnvironmentVariable($name, $vars[$name], 'User')
    Write-Host "Set $name = $($vars[$name])"
}

Write-Host ""
Write-Host 'Done. Close this terminal and open a new one, then: flutter run -d android'
Write-Host 'Or use: .\run-android.ps1 (sets mirror for current session only)'
