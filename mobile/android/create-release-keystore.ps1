# 生成 release 签名（仅需一次）。将生成的 jks 与 key.properties 用于本地与 CI，保证 OTA 签名一致。
# 生成后：复制 key.properties.example -> key.properties 并填入密码；GitHub Secrets 见 mobile/README.md

$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $keytool) {
    Write-Error "keytool not found. Install JDK and add keytool to PATH."
    exit 1
}

$jks = Join-Path $PSScriptRoot "app\ihope-release.jks"
if (Test-Path $jks) {
    Write-Host "Keystore already exists: $jks"
    exit 0
}

$keytool @(
    "-genkeypair", "-v",
    "-keystore", $jks,
    "-storetype", "JKS",
    "-keyalg", "RSA",
    "-keysize", "2048",
    "-validity", "10000",
    "-alias", "ihope",
    "-storepass", "CHANGE_ME",
    "-keypass", "CHANGE_ME",
    "-dname", "CN=CLPRINCE, OU=IHope, O=CLPRINCE, L=HK, ST=HK, C=CN"
)

Write-Host "Created $jks"
Write-Host "Copy key.properties.example to key.properties and set passwords."
Write-Host "Add ANDROID_KEYSTORE_BASE64 + passwords to GitHub Secrets for CI."
