# 生成 release 签名（仅需一次）。将生成的 jks 与 key.properties 用于本地与 CI，保证 OTA 签名一致。
# 用法：先改下面 $StorePass，再运行 .\create-release-keystore.ps1

param(
    [string]$StorePass = "CHANGE_ME",
    [string]$KeyAlias = "ihope"
)

$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $keytool) {
    Write-Error "keytool not found. Install JDK 21 and add keytool to PATH."
    exit 1
}

if ($StorePass -eq "CHANGE_ME") {
    Write-Error "请编辑脚本，将 `$StorePass 改成你自己的密码后再运行。"
    exit 1
}

$jks = Join-Path $PSScriptRoot "app\ihope-release.jks"
if (Test-Path $jks) {
    Write-Host "Keystore already exists: $jks"
    exit 0
}

$jksDir = Split-Path $jks -Parent
if (-not (Test-Path $jksDir)) {
    New-Item -ItemType Directory -Path $jksDir -Force | Out-Null
}

$keytoolArgs = @(
    "-genkeypair", "-v",
    "-keystore", $jks,
    "-storetype", "JKS",
    "-keyalg", "RSA",
    "-keysize", "2048",
    "-validity", "10000",
    "-alias", $KeyAlias,
    "-storepass", $StorePass,
    "-keypass", $StorePass,
    "-dname", "CN=CLPRINCE, OU=IHope, O=CLPRINCE, L=HK, ST=HK, C=CN"
)

& $keytool.Source @keytoolArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "keytool failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "Created $jks"
Write-Host "Copy key.properties.example to key.properties and set:"
Write-Host "  storePassword=$StorePass"
Write-Host "  keyPassword=$StorePass"
Write-Host "  keyAlias=$KeyAlias"
Write-Host "Add ANDROID_KEYSTORE_BASE64 + passwords to GitHub Secrets for CI."
