<#
.SYNOPSIS
    Builds and deploys Munawwara Care to every connected Android device.
.DESCRIPTION
    Requires .env in the Flutter project root. Keys are baked in via
    --dart-define-from-file=.env (see docs/env-and-release-builds.md).
    Builds once, then installs the same APK on all devices (avoids parallel
    flutter run races on Windows).
.PARAMETER Clean
    Run flutter clean before building.
.PARAMETER Release
    Build a release APK (implies Clean).
.PARAMETER FreshInstall
    Uninstall the app on each device before installing (clears app data).
.EXAMPLE
    .\deploy_devices.ps1
    .\deploy_devices.ps1 -Clean
    .\deploy_devices.ps1 -Release
#>
param(
    [switch]$Clean,
    [switch]$Release,
    [switch]$FreshInstall
)

. (Join-Path $PSScriptRoot "build_android_helpers.ps1")

$APP_ID      = "com.munawwaracare.android"
$FLUTTER_DIR = $PSScriptRoot
$BUILD_MODE  = if ($Release) { "release" } else { "debug" }

if ($Release) { $Clean = $true }

Set-Location $FLUTTER_DIR

function Step  { param($m) Write-Host "`n[>] $m" -ForegroundColor Cyan }
function Good  { param($m) Write-Host ('    [OK] ' + $m) -ForegroundColor Green }
function Warn  { param($m) Write-Host ('    [!]  ' + $m) -ForegroundColor Yellow }
function Fail  { param($m) Write-Host ('    [X]  ' + $m) -ForegroundColor Red; exit 1 }

# 1. Tool checks
Step "Checking tools"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { Fail "flutter not found in PATH" }
if (-not (Get-Command adb     -ErrorAction SilentlyContinue)) { Fail "adb not found in PATH" }
Good "flutter + adb found"

try {
    $envFile = Assert-EnvFile -FlutterDir $FLUTTER_DIR
    Good ".env found: $envFile"
} catch {
    Fail $_.Exception.Message
}

# 2. Detect devices
Step "Detecting connected devices"
$adbOut      = adb devices 2>&1
$deviceLines = $adbOut | Select-String -Pattern "^\S+\s+device$"
if ($deviceLines.Count -eq 0) {
    Fail "No devices found. Enable USB Debugging and accept the RSA prompt on each phone."
}
$deviceIds = @($deviceLines | ForEach-Object { ($_ -split "\s+")[0] })
Good "Found $($deviceIds.Count) device(s): $($deviceIds -join ', ')"

# 3. Clean
if ($Clean) {
    Step "Killing Gradle daemons (releases file locks)"
    $gradlew = Join-Path $FLUTTER_DIR "android\gradlew.bat"
    if (Test-Path $gradlew) {
        & $gradlew --stop 2>&1 | Out-Null
    }
    Get-Process -Name "java" -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -like "*gradle*" -or $_.MainWindowTitle -eq ""
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    Good "Gradle daemons stopped"

    Step "Removing Gradle build cache"
    $gradleBuild = Join-Path $FLUTTER_DIR "build"
    if (Test-Path $gradleBuild) {
        Remove-Item -Recurse -Force $gradleBuild -ErrorAction SilentlyContinue
    }
    $androidBuild = Join-Path $FLUTTER_DIR "android\.gradle"
    if (Test-Path $androidBuild) {
        Remove-Item -Recurse -Force $androidBuild -ErrorAction SilentlyContinue
    }
    Good "Build caches cleared"

    Step "Running flutter clean"
    flutter clean 2>&1 | Out-Null
    Good "Clean done"
}

# 4. pub get
Step "flutter pub get"
flutter pub get
if ($LASTEXITCODE -ne 0) { Fail "pub get failed" }
Good "Dependencies up to date"

# 5. Build APK (single build — install to all devices)
Step "Building $BUILD_MODE APK with --dart-define-from-file=.env"
try {
    Invoke-AndroidApkBuild -FlutterDir $FLUTTER_DIR -BuildMode $BUILD_MODE
} catch {
    Fail $_.Exception.Message
}

$APK_PATH = Join-Path $FLUTTER_DIR "build\app\outputs\flutter-apk\app-$BUILD_MODE.apk"
if (-not (Test-Path $APK_PATH)) { Fail "APK not found at: $APK_PATH" }
Good "APK ready: $APK_PATH"

# 6. Deploy to each device
Install-ApkToDevices -DeviceIds $deviceIds -ApkPath $APK_PATH `
    -AppId $APP_ID -FreshInstall:$FreshInstall

$debugSha = Get-AndroidSigningSha1 -FlutterDir $FLUTTER_DIR -Variant debug
if ($debugSha) {
    Write-Host "`nDebug SHA-1 (Firebase FCM for local APKs): $debugSha" -ForegroundColor Yellow
}

Write-Host "`n[DONE] Deployed $BUILD_MODE to $($deviceIds.Count) device(s).`n" `
    -ForegroundColor Green
