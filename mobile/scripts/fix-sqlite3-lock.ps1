# 解除 sqlite3 hook 构建锁（TimeoutException on .dart_tool\hooks_runner\shared\sqlite3\.lock）
# 用法：先 Ctrl+C 停掉所有 flutter run，再执行：
#   cd D:\IHope\mobile
#   .\scripts\fix-sqlite3-lock.ps1
# 然后只开一个终端：flutter run --flavor domestic -d <设备ID>

$ErrorActionPreference = "Stop"
$MobileDir = Split-Path $PSScriptRoot -Parent
Set-Location $MobileDir

Write-Host "Stopping Gradle daemon..."
$gradlew = Join-Path $MobileDir "android\gradlew.bat"
if (Test-Path $gradlew) {
    & $gradlew --stop 2>$null
}

$hooks = Join-Path $MobileDir ".dart_tool\hooks_runner"
if (Test-Path $hooks) {
    Write-Host "Removing $hooks ..."
    Remove-Item -Recurse -Force $hooks -ErrorAction SilentlyContinue
    if (Test-Path $hooks) {
        Write-Warning "hooks_runner 仍被占用。请关闭所有 flutter run / Android Studio Run，任务管理器结束多余 dart.exe 后重试。"
        exit 1
    }
}

Write-Host "flutter clean + pub get ..."
& flutter clean
& flutter pub get
Write-Host "Done. 请只对一个设备执行 flutter run（勿同时编模拟器+真机）。"
