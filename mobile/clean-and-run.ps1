# 清理 Flutter / Gradle / Kotlin 缓存后重新运行（修复 incremental cache 损坏）
# 用法：.\clean-and-run.ps1

param(
    [string]$Device = 'android'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'

Write-Host 'Stopping Gradle daemons...'
Push-Location android
try {
    if (Test-Path '.\gradlew.bat') {
        & .\gradlew.bat --stop 2>$null
    }
} finally {
    Pop-Location
}

Write-Host 'Removing build caches...'
foreach ($dir in @('build', '.dart_tool')) {
    if (Test-Path $dir) {
        Remove-Item -Recurse -Force $dir
    }
}

Write-Host 'flutter clean...'
flutter clean

Write-Host 'flutter pub get...'
flutter pub get

Write-Host 'flutter run...'
flutter run -d $Device @args
