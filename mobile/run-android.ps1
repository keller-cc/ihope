# 当前终端启用国内镜像并运行 Android（无需永久改系统环境变量）
# 用法：.\run-android.ps1
#       .\run-android.ps1 -Device emulator-5554

param(
    [string]$Device = 'android'
)

$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'

Write-Host "FLUTTER_STORAGE_BASE_URL = $env:FLUTTER_STORAGE_BASE_URL"
Write-Host "PUB_HOSTED_URL = $env:PUB_HOSTED_URL"
Write-Host ""

flutter run -d $Device @args
