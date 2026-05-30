<#
.SYNOPSIS
    Automates the process of cleaning (optional), building a release/debug APK/AAB (optional),
    copying them to the Desktop, and optionally deploying to connected devices.
.EXAMPLE
    .\build_and_export.ps1
#>

# Colors & Logging Helpers
function Step  { param($m) Write-Host "`n[>] $m" -ForegroundColor Cyan }
function Good  { param($m) Write-Host "    [OK] $m" -ForegroundColor Green }
function Warn  { param($m) Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Fail  { param($m) Write-Host "    [X]  $m" -ForegroundColor Red; exit 1 }

$ROOT_DIR = $PSScriptRoot

# 1. Locate Flutter Directory
if (Test-Path (Join-Path $ROOT_DIR "Munawwara_Care_Flutter")) {
    $FLUTTER_DIR = Join-Path $ROOT_DIR "Munawwara_Care_Flutter"
} elseif ((Test-Path (Join-Path $ROOT_DIR "pubspec.yaml")) -and (Test-Path (Join-Path $ROOT_DIR "android"))) {
    $FLUTTER_DIR = $ROOT_DIR
} else {
    Fail "Could not find Flutter project directory. Please run this script from the workspace root or the Munawwara_Care_Flutter directory."
}

# 1.5 Interactive Configuration (Optimized for 8GB RAM performance)
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
    # Option 1 (Default): Release APK - arm64 only
    $buildApk = $true
    $buildAab = $false
    $targetPlatform = "android-arm64"
}

$cleanChoice = Read-Host "Do you want to perform a clean build? (y/N) (Default: N - recommended for fast build)"
if ($cleanChoice -eq "y" -or $cleanChoice -eq "yes") {
    $cleanBuild = $true
} else {
    $cleanBuild = $false
}
Write-Host "================================================================" -ForegroundColor Cyan

# 2. Tool checks
Step "Checking tools..."
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Fail "flutter not found in PATH. Please install Flutter and add it to your environment variables."
}
Good "Flutter found"

# 3. Clean (Optional)
if ($cleanBuild) {
    Step "Cleaning previous build files and caches..."
    $gradlew = Join-Path $FLUTTER_DIR "android\gradlew.bat"
    if (Test-Path $gradlew) {
        Step "Stopping Gradle daemons to release file locks..."
        & $gradlew -p (Join-Path $FLUTTER_DIR "android") --stop 2>&1 | Out-Null
        Good "Gradle daemons stopped"
    }

    # Kill any java processes holding lint-cache locks to prevent building errors
    Get-Process -Name "java" -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -like "*gradle*" -or $_.MainWindowTitle -eq ""
    } | Stop-Process -Force -ErrorAction SilentlyContinue

    # Remove build directory manually for a fresh start
    $buildDir = Join-Path $FLUTTER_DIR "build"
    if (Test-Path $buildDir) {
        Remove-Item -Recurse -Force $buildDir -ErrorAction SilentlyContinue
    }
    $androidGradleDir = Join-Path $FLUTTER_DIR "android\.gradle"
    if (Test-Path $androidGradleDir) {
        Remove-Item -Recurse -Force $androidGradleDir -ErrorAction SilentlyContinue
    }

    # Run flutter clean
    Set-Location $FLUTTER_DIR
    flutter clean
    Good "Clean complete"
} else {
    Step "Skipping clean (reusing caches to save CPU & RAM)..."
    Set-Location $FLUTTER_DIR
}

# 4. Fetch Dependencies
Step "Fetching dependencies..."
flutter pub get
if ($LASTEXITCODE -ne 0) { Fail "flutter pub get failed" }
Good "Dependencies synced successfully"

# 4b. Warn if .env uses a LAN backend
$envFile = Join-Path $FLUTTER_DIR ".env"
if (Test-Path $envFile) {
    $apiLine = Get-Content $envFile | Where-Object {
        $_ -match '^\s*API_BASE_URL\s*=' -and $_ -notmatch '^\s*#'
    } | Select-Object -First 1
    if ($apiLine -match '192\.168\.|10\.0\.2\.2|localhost|127\.0\.0\.1|http://10\.') {
        Warn "API_BASE_URL in .env looks like LAN/dev - release builds will NOT work on mobile data."
        Warn "Use production HTTPS before Play upload. See docs/voice-calls-networking.md"
    }
}
$pubspecPath = Join-Path $FLUTTER_DIR "pubspec.yaml"
if (Test-Path $pubspecPath) {
    $verLine = Get-Content $pubspecPath | Where-Object { $_ -match '^\s*version:\s*' } | Select-Object -First 1
    if ($verLine) {
        Good "Building app version: $($verLine.Trim())"
    }
}

# 5. Build AAB (App Bundle)
$AAB_SOURCE = $null
if ($buildAab) {
    Step "Building release App Bundle (AAB)..."
    flutter build appbundle --release
    if ($LASTEXITCODE -ne 0) { Fail "Flutter AAB build failed" }
    $AAB_SOURCE = Join-Path $FLUTTER_DIR "build\app\outputs\bundle\release\app-release.aab"
    if (-not (Test-Path $AAB_SOURCE)) { Fail "AAB not found at: $AAB_SOURCE" }
    Good "App Bundle built successfully"
}

# 6. Build APK
$APK_SOURCE = $null
if ($buildApk) {
    Step "Building $buildMode APK..."
    if ($targetPlatform) {
        flutter build apk --$buildMode --target-platform $targetPlatform
    } else {
        flutter build apk --$buildMode
    }
    if ($LASTEXITCODE -ne 0) { Fail "Flutter APK build failed" }
    $APK_SOURCE = Join-Path $FLUTTER_DIR "build\app\outputs\flutter-apk\app-$buildMode.apk"
    if (-not (Test-Path $APK_SOURCE)) { Fail "APK not found at: $APK_SOURCE" }
    Good "APK built successfully"
}

# 7. Export to Desktop
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
    if (Test-Path $AAB_DEST) {
        Good "Copied AAB to Desktop: $AAB_DEST"
    } else {
        Fail "Failed to copy AAB to Desktop"
    }
}

if ($buildApk -and (Test-Path $APK_SOURCE)) {
    Copy-Item -Path $APK_SOURCE -Destination $APK_DEST -Force
    if (Test-Path $APK_DEST) {
        Good "Copied APK to Desktop: $APK_DEST"
    } else {
        Fail "Failed to copy APK to Desktop"
    }
}

# 7.5 Optional Deployment to Connected Devices
if ($buildApk -and (Get-Command adb -ErrorAction SilentlyContinue)) {
    $adbOut = adb devices 2>&1
    $deviceLines = $adbOut | Select-String -Pattern "^\S+\s+device$"
    if ($deviceLines.Count -gt 0) {
        $deviceIds = @($deviceLines | ForEach-Object { ($_ -split "\s+")[0] })
        Write-Host ""
        $deployChoice = Read-Host "Found $($deviceIds.Count) connected device(s). Do you want to deploy and launch the APK? (y/N)"
        if ($deployChoice -eq "y" -or $deployChoice -eq "yes") {
            $APP_ID = "com.munawwaracare.android"
            foreach ($device in $deviceIds) {
                Step "[$device] Uninstalling old version..."
                adb -s $device uninstall $APP_ID 2>&1 | Out-Null
                
                Step "[$device] Installing APK..."
                adb -s $device install -r -d $APK_DEST
                if ($LASTEXITCODE -eq 0) {
                    Good "[$device] Install successful"
                    
                    Step "[$device] Granting permissions..."
                    $perms = @(
                        "android.permission.RECORD_AUDIO",
                        "android.permission.POST_NOTIFICATIONS",
                        "android.permission.READ_PHONE_STATE",
                        "android.permission.USE_FULL_SCREEN_INTENT"
                    )
                    foreach ($perm in $perms) {
                        adb -s $device shell pm grant $APP_ID $perm 2>&1 | Out-Null
                    }
                    
                    Step "[$device] Launching app..."
                    adb -s $device shell monkey -p $APP_ID -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
                    Good "[$device] App launched"
                } else {
                    Warn "[$device] Install failed"
                }
            }
        }
    }
}

# 8. SHA-1 Fingerprint & File Hash Extraction
Step "Extracting SHA-1 keys and file hashes..."

$apkFileHash = ""
$aabFileHash = ""
if ($buildApk -and (Test-Path $APK_DEST)) {
    $apkFileHash = (Get-FileHash -Path $APK_DEST -Algorithm SHA1).Hash.ToLower()
}
if ($buildAab -and (Test-Path $AAB_DEST)) {
    $aabFileHash = (Get-FileHash -Path $AAB_DEST -Algorithm SHA1).Hash.ToLower()
}

# Extract Keystore details from key.properties
$keyPropsPath = Join-Path $FLUTTER_DIR "android\key.properties"
$storeFile = "upload-keystore.jks"
$storePassword = ""
$keyAlias = "upload"

if (Test-Path $keyPropsPath) {
    $properties = @{}
    Get-Content $keyPropsPath | Where-Object { $_ -match '=' -and $_ -notmatch '^\s*#' } | ForEach-Object {
        $parts = $_ -split '=', 2
        $properties[$parts[0].Trim()] = $parts[1].Trim()
    }
    if ($properties.ContainsKey("storeFile")) { $storeFile = $properties["storeFile"] }
    if ($properties.ContainsKey("storePassword")) { $storePassword = $properties["storePassword"] }
    if ($properties.ContainsKey("keyAlias")) { $keyAlias = $properties["keyAlias"] }
}

$keystorePath = Join-Path $FLUTTER_DIR "android\app\$storeFile"
if (-not (Test-Path $keystorePath)) {
    $keystorePath = Join-Path $FLUTTER_DIR "android\app\upload-keystore.jks"
}

$sha1Fingerprint = $null

if (Test-Path $keystorePath) {
    function Find-KeyTool {
        $kt = Get-Command keytool -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
        if ($kt) { return $kt }
        if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\keytool.exe")) {
            return "$env:JAVA_HOME\bin\keytool.exe"
        }
        $commonPaths = @(
            "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe",
            "C:\Program Files\Android\Android Studio\jre\bin\keytool.exe",
            "C:\Program Files\Android\Android Studio 1\jbr\bin\keytool.exe",
            "C:\Program Files\Android\Android Studio 1\jre\bin\keytool.exe",
            "$env:LOCALAPPDATA\Android\Android Studio\jbr\bin\keytool.exe",
            "$env:LOCALAPPDATA\Android\Android Studio\jre\bin\keytool.exe"
        )
        foreach ($p in $commonPaths) {
            if (Test-Path $p) { return $p }
        }
        if (Test-Path "C:\Program Files\Java") {
            $javaKt = Get-ChildItem "C:\Program Files\Java" -Filter "keytool.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
            if ($javaKt) {
                if ($javaKt -is [array]) { return $javaKt[0] }
                return $javaKt
            }
        }
        return $null
    }

    $keytool = Find-KeyTool
    if ($keytool -and $storePassword) {
        $ktOutput = & $keytool -list -v -keystore $keystorePath -alias $keyAlias -storepass $storePassword 2>&1
        $sha1Line = $ktOutput | Select-String -Pattern 'SHA1:\s+([0-9A-Fa-f:]+)'
        if ($sha1Line) {
            $sha1Fingerprint = ($sha1Line -split "SHA1:")[1].Trim()
        }
    }

    if (-not $sha1Fingerprint -and (Test-Path $gradlew)) {
        Step "Direct keytool extraction failed. Attempting Gradle signingReport..."
        $gradleReport = & $gradlew -p (Join-Path $FLUTTER_DIR "android") signingReport 2>&1 | Out-String
        $gradleShaMatches = [regex]::Matches(
            $gradleReport,
            '(?ms)Variant:\s*release.*?SHA1:\s*([0-9A-Fa-f:]+)'
        )
        if ($gradleShaMatches.Count -gt 0) {
            $sha1Fingerprint = $gradleShaMatches[0].Groups[1].Value.Trim()
        } else {
            $aliasPattern = '(?ms)Alias:\s*' + [regex]::Escape($keyAlias) +
                '.*?SHA1:\s*([0-9A-Fa-f:]+)'
            $gradleShaMatches = [regex]::Matches($gradleReport, $aliasPattern)
            if ($gradleShaMatches.Count -gt 0) {
                $sha1Fingerprint = $gradleShaMatches[0].Groups[1].Value.Trim()
            }
        }
    }
}

# 9. Final Summary
Write-Host "`n================================================================" -ForegroundColor Green
Write-Host " BUILD AND EXPORT SUMMARY" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host "Artifacts copied to your Desktop:"
if ($buildAab -and (Test-Path $AAB_DEST)) { Write-Host "  * Munawwara-Care.aab" -ForegroundColor White }
if ($buildApk -and (Test-Path $APK_DEST)) { Write-Host "  * $(Split-Path $APK_DEST -Leaf)" -ForegroundColor White }
Write-Host ""

if ($sha1Fingerprint) {
    Write-Host "SIGNING CERTIFICATE SHA-1 FINGERPRINT" -ForegroundColor Green
    Write-Host "  (Used for Firebase, Google Play Console, Google Sign-In, etc.)"
    Write-Host "  SHA-1: $sha1Fingerprint" -ForegroundColor Yellow
    Write-Host ""
} else {
    Warn "Could not extract signing key SHA-1. Ensure Java is installed and key.properties contains correct passwords."
}

Write-Host "FILE HASHES (SHA-1)" -ForegroundColor Green
Write-Host "  (Used for checking file integrity / download verification)"
if ($buildApk -and (Test-Path $APK_DEST)) { Write-Host "  $(Split-Path $APK_DEST -Leaf): $apkFileHash" -ForegroundColor Yellow }
if ($buildAab -and (Test-Path $AAB_DEST)) { Write-Host "  Munawwara-Care.aab: $aabFileHash" -ForegroundColor Yellow }
Write-Host "================================================================" -ForegroundColor Green
