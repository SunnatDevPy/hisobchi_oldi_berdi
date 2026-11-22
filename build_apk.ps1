param(
    [switch]$Deploy = $false
)

$ErrorActionPreference = "Stop"

Write-Host "=== 1. Flutter & Android SDK muhiti sozlanmoqda ===" -ForegroundColor Cyan
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.21.102-hotspot"
$env:ANDROID_HOME = "C:\dev\android-sdk"
$env:ANDROID_SDK_ROOT = "C:\dev\android-sdk"
$env:Path = "C:\dev\flutter\bin;$env:JAVA_HOME\bin;C:\dev\android-sdk\platform-tools;$env:Path"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location "$RootDir\mobile"

try {
    Write-Host "=== 2. Kod tahlili (flutter analyze) ===" -ForegroundColor Cyan
    flutter analyze

    Write-Host "=== 3. Release APK yig'ilmoqda (ARM + ARM64) ===" -ForegroundColor Cyan
    flutter build apk --release --target-platform android-arm,android-arm64

    $BuiltApk = "$RootDir\mobile\build\app\outputs\flutter-apk\app-release.apk"
    $DistDir = "$RootDir\dist"
    $DistApk = "$DistDir\hisobchi.apk"

    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
    Copy-Item -Force $BuiltApk $DistApk

    $SizeMb = [math]::Round((Get-Item $DistApk).Length / 1MB, 2)
    Write-Host "✅ APK muvaffaqiyatli yig'ildi: $DistApk ($SizeMb MB)" -ForegroundColor Green

    if ($Deploy) {
        Write-Host "=== 4. Serverga (46.8.194.206) yuklanmoqda ===" -ForegroundColor Cyan
        scp $DistApk ubuntu@46.8.194.206:/home/ubuntu/hisobchi_oldi_berdi/data/hisobchi.apk
        Write-Host "🚀 Serverdagi APK yangilandi! (Telegram bot /apk va https://hisobchi.okaposai.uz/download/hisobchi.apk)" -ForegroundColor Green
    }
}
finally {
    Pop-Location
}
