<#
.SYNOPSIS
    Automates cleaning (optional), building release/debug APK/AAB with .env
    dart-defines, copying artifacts to Desktop, and optional device deploy.
.DESCRIPTION
    IOS branch: .env is NOT bundled in the APK. All builds use
    --dart-define-from-file=.env so API_BASE_URL and Agora keys are embedded.
    See docs/env-and-release-builds.md
.EXAMPLE
    .\build_and_export.ps1
#>

. (Join-Path $PSScriptRoot "build_android_helpers.ps1")

function Step  { param($m) Write-Host "`n[>] $m" -ForegroundColor Cyan }
function Good  { param($m) Write-Host ('    [OK] ' + $m) -ForegroundColor Green }
function Warn  { param($m) Write-Host ('    [!]  ' + $m) -ForegroundColor Yellow }
function Fail  { param($m) Write-Host ('    [X]  ' + $m) -ForegroundColor Red; exit 1 }

$ROOT_DIR = $PSScriptRoot

if (Test-Path (Join-Path $ROOT_DIR "Munawwara_Care_Flutter")) {
    $FLUTTER_DIR = Join-Path $ROOT_DIR "Munawwara_Care_Flutter"
} elseif ((Test-Path (Join-Path $ROOT_DIR "pubspec.yaml")) -and `
    (Test-Path (Join-Path $ROOT_DIR "android"))) {
    $FLUTTER_DIR = $ROOT_DIR
} else {
    Fail "Could not find Flutter project directory."
}

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "            FLUTTER BUILD OPTIMIZATION MENU (8GB RAM)" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Select build target:" -ForegroundColor White
Write-Host "  [1] Release APK - arm64 only (Small ~90MB, recommended for testing)" -ForegroundColor White
Write-Host "  [2] Release APK - Fat (~297MB, works on all devices)" -ForegroundColor White
Write-Host "  [3] Release AAB only (For Play Store release upload)" -ForegroundColor White
Write-Host "  [4] Both Release APK (Fat) & AAB" -ForegroundColor White
Write-Host "  [5] Debug APK - arm64 only (Fastest build - recommended for quick local testing)" -ForegroundColor White
$choice = Read-Host "Enter option [1-5] (Default: 1)"

$buildMode = "release"
$targetPlatform = $null
if ($choice -eq "2") {
    $buildApk = $true
    $buildAab = $false
} elseif ($choice -eq "3") {
    $buildApk = $false
    $buildAab = $true
} elseif ($choice -eq "4") {
    $buildApk = $true
    $buildAab = $true
} elseif ($choice -eq "5") {
    $buildApk = $true
    $buildAab = $false
    $buildMode = "debug"
    $targetPlatform = "android-arm64"
} else {
    $buildApk = $true
    $buildAab = $false
    $targetPlatform = "android-arm64"
}

$cleanChoice = Read-Host "Do you want to perform a clean build? (y/N) (Default: N)"
$cleanBuild = ($cleanChoice -eq "y" -or $cleanChoice -eq "yes")
Write-Host "================================================================" -ForegroundColor Cyan

Step "Checking tools..."
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Fail "flutter not found in PATH."
}
Good "Flutter found"

try {
    $envFile = Assert-EnvFile -FlutterDir $FLUTTER_DIR
    Good ".env found (dart-define-from-file will be used)"
} catch {
    Fail $_.Exception.Message
}

if ($cleanBuild) {
    Step "Cleaning previous build files and caches..."
    $gradlew = Join-Path $FLUTTER_DIR "android\gradlew.bat"
    if (Test-Path $gradlew) {
        Step "Stopping Gradle daemons..."
        & $gradlew -p (Join-Path $FLUTTER_DIR "android") --stop 2>&1 | Out-Null
        Good "Gradle daemons stopped"
    }
    Get-Process -Name "java" -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -like "*gradle*" -or $_.MainWindowTitle -eq ""
    } | Stop-Process -Force -ErrorAction SilentlyContinue

    $buildDir = Join-Path $FLUTTER_DIR "build"
    if (Test-Path $buildDir) {
        Remove-Item -Recurse -Force $buildDir -ErrorAction SilentlyContinue
    }
    $androidGradleDir = Join-Path $FLUTTER_DIR "android\.gradle"
    if (Test-Path $androidGradleDir) {
        Remove-Item -Recurse -Force $androidGradleDir -ErrorAction SilentlyContinue
    }
    Set-Location $FLUTTER_DIR
    flutter clean
    Good "Clean complete"
} else {
    Step "Skipping clean (reusing caches)..."
    Set-Location $FLUTTER_DIR
}

Step "Fetching dependencies..."
flutter pub get
if ($LASTEXITCODE -ne 0) { Fail "flutter pub get failed" }
Good "Dependencies synced"

$apiLine = Get-Content $envFile | Where-Object {
    $_ -match '^\s*API_BASE_URL\s*=' -and $_ -notmatch '^\s*#'
} | Select-Object -First 1
$lanApiPattern = [regex]'192\.168\.|10\.0\.2\.2|localhost|127\.0\.0\.1|http://10\.'
if ($apiLine -and $lanApiPattern.IsMatch($apiLine)) {
    Warn 'API_BASE_URL in .env looks like LAN/dev - will not work on mobile data.'
    Warn "Use production HTTPS before Play upload. See docs/env-and-release-builds.md"
}

$pubspecPath = Join-Path $FLUTTER_DIR "pubspec.yaml"
if (Test-Path $pubspecPath) {
    $verLine = Get-Content $pubspecPath | Where-Object {
        $_ -match '^\s*version:\s*'
    } | Select-Object -First 1
    if ($verLine) { Good "Building app version: $($verLine.Trim())" }
}

$DART_DEFINE_FILE = "--dart-define-from-file=.env"

$AAB_SOURCE = $null
if ($buildAab) {
    Step "Building release App Bundle (AAB) with .env defines..."
    flutter build appbundle --release $DART_DEFINE_FILE
    if ($LASTEXITCODE -ne 0) { Fail "Flutter AAB build failed" }
    $AAB_SOURCE = Join-Path $FLUTTER_DIR `
        "build\app\outputs\bundle\release\app-release.aab"
    if (-not (Test-Path $AAB_SOURCE)) { Fail "AAB not found at: $AAB_SOURCE" }
    Good "App Bundle built"
}

$APK_SOURCE = $null
if ($buildApk) {
    Step "Building $buildMode APK with .env defines..."
    try {
        Invoke-AndroidApkBuild -FlutterDir $FLUTTER_DIR `
            -BuildMode $buildMode -TargetPlatform $targetPlatform
    } catch {
        Fail $_.Exception.Message
    }
    $APK_SOURCE = Join-Path $FLUTTER_DIR `
        "build\app\outputs\flutter-apk\app-$buildMode.apk"
    if (-not (Test-Path $APK_SOURCE)) { Fail "APK not found at: $APK_SOURCE" }
    Good "APK built"
}

Step "Exporting artifacts to Desktop..."
$DesktopPath = [Environment]::GetFolderPath('Desktop')
if (-not $DesktopPath) {
    $DesktopPath = Join-Path $env:USERPROFILE "Desktop"
}

$AAB_DEST = Join-Path $DesktopPath "Munawwara-Care.aab"
$APK_DEST = if ($buildMode -eq "debug") {
    if ($targetPlatform -eq "android-arm64") {
        Join-Path $DesktopPath "Munawwara-Care-Debug-arm64.apk"
    } else {
        Join-Path $DesktopPath "Munawwara-Care-Debug.apk"
    }
} else {
    if ($targetPlatform -eq "android-arm64") {
        Join-Path $DesktopPath "Munawwara-Care-arm64.apk"
    } else {
        Join-Path $DesktopPath "Munawwara-Care.apk"
    }
}

if ($buildAab -and (Test-Path $AAB_SOURCE)) {
    Copy-Item -Path $AAB_SOURCE -Destination $AAB_DEST -Force
    if (Test-Path $AAB_DEST) { Good "Copied AAB to Desktop: $AAB_DEST" }
    else { Fail "Failed to copy AAB to Desktop" }
}

if ($buildApk -and (Test-Path $APK_SOURCE)) {
    Copy-Item -Path $APK_SOURCE -Destination $APK_DEST -Force
    if (Test-Path $APK_DEST) { Good "Copied APK to Desktop: $APK_DEST" }
    else { Fail "Failed to copy APK to Desktop" }
}

if ($buildApk -and (Get-Command adb -ErrorAction SilentlyContinue)) {
    $adbOut = adb devices 2>&1
    $deviceLines = $adbOut | Select-String -Pattern "^\S+\s+device$"
    if ($deviceLines.Count -gt 0) {
        $deviceIds = @($deviceLines | ForEach-Object { ($_ -split "\s+")[0] })
        Write-Host ""
        $deployChoice = Read-Host `
            "Found $($deviceIds.Count) device(s). Deploy and launch APK? (y/N)"
        if ($deployChoice -eq "y" -or $deployChoice -eq "yes") {
            $freshChoice = Read-Host "Uninstall first (clears app data)? (y/N)"
            $fresh = ($freshChoice -eq "y" -or $freshChoice -eq "yes")
            Install-ApkToDevices -DeviceIds $deviceIds -ApkPath $APK_DEST `
                -FreshInstall:$fresh
        }
    }
}

Step "Extracting signing fingerprints and file hashes..."

$apkFileHash = ""
$aabFileHash = ""
if ($buildApk -and (Test-Path $APK_DEST)) {
    $apkFileHash = (Get-FileHash -Path $APK_DEST -Algorithm SHA1).Hash.ToLower()
}
if ($buildAab -and (Test-Path $AAB_DEST)) {
    $aabFileHash = (Get-FileHash -Path $AAB_DEST -Algorithm SHA1).Hash.ToLower()
}

$debugSha1 = Get-AndroidSigningSha1 -FlutterDir $FLUTTER_DIR -Variant debug
$releaseSha1 = Get-AndroidSigningSha1 -FlutterDir $FLUTTER_DIR -Variant release

$keyPropsPath = Join-Path $FLUTTER_DIR "android\key.properties"
$storeFile = "upload-keystore.jks"
$storePassword = ""
$keyAlias = "upload"
$gradlew = Join-Path $FLUTTER_DIR "android\gradlew.bat"

if (Test-Path $keyPropsPath) {
    $properties = @{}
    Get-Content $keyPropsPath | Where-Object {
        $_ -match '=' -and $_ -notmatch '^\s*#'
    } | ForEach-Object {
        $parts = $_ -split '=', 2
        $properties[$parts[0].Trim()] = $parts[1].Trim()
    }
    if ($properties.ContainsKey("storeFile")) { $storeFile = $properties["storeFile"] }
    if ($properties.ContainsKey("storePassword")) {
        $storePassword = $properties["storePassword"]
    }
    if ($properties.ContainsKey("keyAlias")) { $keyAlias = $properties["keyAlias"] }
}

$keystorePath = Join-Path $FLUTTER_DIR "android\app\$storeFile"
if (-not (Test-Path $keystorePath)) {
    $keystorePath = Join-Path $FLUTTER_DIR "android\app\upload-keystore.jks"
}

$sha1Fingerprint = $releaseSha1

if (-not $sha1Fingerprint -and (Test-Path $keystorePath)) {
    function Find-KeyTool {
        $kt = Get-Command keytool -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Source
        if ($kt) { return $kt }
        if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\keytool.exe")) {
            return "$env:JAVA_HOME\bin\keytool.exe"
        }
        $commonPaths = @(
            "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe",
            "$env:LOCALAPPDATA\Android\Android Studio\jbr\bin\keytool.exe"
        )
        foreach ($p in $commonPaths) {
            if (Test-Path $p) { return $p }
        }
        return $null
    }
    $keytool = Find-KeyTool
    if ($keytool -and $storePassword) {
        $ktOutput = & $keytool -list -v -keystore $keystorePath `
            -alias $keyAlias -storepass $storePassword 2>&1
        $sha1Regex = [regex]'SHA1:\s+([0-9A-Fa-f:]+)'
        $sha1Match = $sha1Regex.Match(($ktOutput | Out-String))
        if ($sha1Match.Success) {
            $sha1Fingerprint = $sha1Match.Groups[1].Value.Trim()
        }
    }
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host " BUILD AND EXPORT SUMMARY" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host "Artifacts on Desktop:"
if ($buildAab -and (Test-Path $AAB_DEST)) {
    Write-Host "  * Munawwara-Care.aab" -ForegroundColor White
}
if ($buildApk -and (Test-Path $APK_DEST)) {
    Write-Host "  * $(Split-Path $APK_DEST -Leaf)" -ForegroundColor White
}
Write-Host ""

Write-Host "FIREBASE SHA-1 FINGERPRINTS" -ForegroundColor Green
if ($debugSha1) {
    Write-Host '  Debug (flutter run / debug APK - add for FCM on dev builds):' `
        -ForegroundColor White
    Write-Host "    $debugSha1" -ForegroundColor Yellow
}
if ($sha1Fingerprint) {
    Write-Host "  Release (Play Store / release APK):" -ForegroundColor White
    Write-Host "    $sha1Fingerprint" -ForegroundColor Yellow
} elseif (-not $debugSha1) {
    Warn "Could not extract SHA-1. Run: cd android; .\gradlew :app:signingReport"
}
Write-Host ""

Write-Host "FILE HASHES (artifact integrity)" -ForegroundColor Green
if ($buildApk -and (Test-Path $APK_DEST)) {
    Write-Host "  $(Split-Path $APK_DEST -Leaf): $apkFileHash" -ForegroundColor Yellow
}
if ($buildAab -and (Test-Path $AAB_DEST)) {
    Write-Host "  Munawwara-Care.aab: $aabFileHash" -ForegroundColor Yellow
}
Write-Host "================================================================" -ForegroundColor Green
