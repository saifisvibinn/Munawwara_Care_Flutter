<#
.SYNOPSIS
    Builds and deploys Munawwara Care to every connected Android device.
.PARAMETER Clean
    Run flutter clean before building.
.PARAMETER Release
    Build a release APK (implies Clean).
.EXAMPLE
    .\deploy_devices.ps1
    .\deploy_devices.ps1 -Clean
    .\deploy_devices.ps1 -Release
#>
param(
    [switch]$Clean,
    [switch]$Release
)

$APP_ID      = "com.munawwaracare.android"
$FLUTTER_DIR = $PSScriptRoot
$BUILD_MODE  = if ($Release) { "release" } else { "debug" }

# Release always implies clean
if ($Release) { $Clean = $true }

Set-Location $FLUTTER_DIR

function Step  { param($m) Write-Host "`n[>] $m" -ForegroundColor Cyan }
function Good  { param($m) Write-Host "    [OK] $m" -ForegroundColor Green }
function Warn  { param($m) Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Fail  { param($m) Write-Host "    [X]  $m" -ForegroundColor Red; exit 1 }

# 1. Tool checks
Step "Checking tools"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { Fail "flutter not found in PATH" }
if (-not (Get-Command adb     -ErrorAction SilentlyContinue)) { Fail "adb not found in PATH" }
Good "flutter + adb found"

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
    # Also kill any java processes holding lint-cache locks
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

# 5. Build APK
Step "Building $BUILD_MODE APK"
flutter build apk "--$BUILD_MODE" --no-pub
if ($LASTEXITCODE -ne 0) { Fail "flutter build apk failed" }

$APK_PATH = Join-Path $FLUTTER_DIR "build\app\outputs\flutter-apk\app-$BUILD_MODE.apk"
if (-not (Test-Path $APK_PATH)) { Fail "APK not found at: $APK_PATH" }
Good "APK ready: $APK_PATH"

# 6. Deploy to each device
foreach ($device in $deviceIds) {

    Step "[$device] Uninstalling old version"
    adb -s $device uninstall $APP_ID 2>&1 | Out-Null
    Good "[$device] Old version removed (if any)"

    Step "[$device] Installing APK"
    adb -s $device install -r -d $APK_PATH
    if ($LASTEXITCODE -ne 0) {
        Warn "[$device] Install failed - skipping this device"
        continue
    }
    Good "[$device] Install successful"

    Step "[$device] Granting runtime permissions"
    $perms = @(
        "android.permission.RECORD_AUDIO",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.READ_PHONE_STATE",
        "android.permission.USE_FULL_SCREEN_INTENT"
    )
    foreach ($perm in $perms) {
        adb -s $device shell pm grant $APP_ID $perm 2>&1 | Out-Null
    }
    Good "[$device] Permissions granted"

    Step "[$device] Launching app"
    adb -s $device shell am start -n "$APP_ID/$APP_ID.MainActivity" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        adb -s $device shell monkey -p $APP_ID -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
    }
    Good "[$device] App launched"
}

Write-Host "`n[DONE] Deployed $BUILD_MODE to $($deviceIds.Count) device(s).`n" -ForegroundColor Green
