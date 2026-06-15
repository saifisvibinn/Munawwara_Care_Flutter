# Shared Android build helpers for Munawwara Care PowerShell scripts.
# Dot-source from build_and_export.ps1 / deploy_devices.ps1:
#   . (Join-Path $PSScriptRoot "build_android_helpers.ps1")

function Assert-EnvFile {
    param([string]$FlutterDir)
    $envFile = Join-Path $FlutterDir ".env"
    if (-not (Test-Path $envFile)) {
        throw @"
.env not found at: $envFile
Copy .env.example to .env and set API_BASE_URL, AGORA_APP_ID, etc.
See docs/env-and-release-builds.md
"@
    }
    return $envFile
}

function Get-GradleDartDefinesFromEnv {
    param([string]$EnvFilePath)
    $defines = [System.Collections.Generic.List[string]]::new()
    foreach ($raw in Get-Content $EnvFilePath) {
        $line = $raw.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { continue }
        $key = $Matches[1]
        $val = $Matches[2].Trim()
        if ($val.Length -ge 2 -and $val.StartsWith('"') -and $val.EndsWith('"')) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        $pair = "${key}=${val}"
        $encoded = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes($pair)
        )
        [void]$defines.Add($encoded)
    }
    if ($defines.Count -eq 0) {
        throw "No KEY=VALUE entries found in $EnvFilePath"
    }
    return ($defines -join ',')
}

function Invoke-AndroidApkBuild {
    param(
        [string]$FlutterDir,
        [ValidateSet('debug', 'release')]
        [string]$BuildMode = 'debug',
        [string]$TargetPlatform = $null
    )
    $envFile = Assert-EnvFile -FlutterDir $FlutterDir
    $dartDefineFile = '--dart-define-from-file=.env'

    $flutterArgs = @('build', 'apk', "--$BuildMode", $dartDefineFile, '--no-pub')
    if ($TargetPlatform) {
        $flutterArgs += @('--target-platform', $TargetPlatform)
    }

    Push-Location $FlutterDir
    try {
        & flutter @flutterArgs
        if ($LASTEXITCODE -eq 0) { return }

        Write-Host '    [!]  flutter build failed - retrying via Gradle (Windows mlkit workaround)' `
            -ForegroundColor Yellow

        $gradleTask = if ($BuildMode -eq 'release') {
            'assembleRelease'
        } else {
            ':google_mlkit_commons:bundleLibCompileToJarDebug', 'assembleDebug'
        }
        $dartDefines = Get-GradleDartDefinesFromEnv -EnvFilePath $envFile
        $gradlew = Join-Path $FlutterDir 'android\gradlew.bat'
        if (-not (Test-Path $gradlew)) {
            throw 'gradlew.bat not found'
        }

        & $gradlew -p (Join-Path $FlutterDir 'android') @gradleTask `
            "-Pdart-defines=$dartDefines"
        if ($LASTEXITCODE -ne 0) {
            throw "Gradle $gradleTask failed (exit $LASTEXITCODE)"
        }
    } finally {
        Pop-Location
    }
}

function Get-AndroidSigningSha1 {
    param(
        [string]$FlutterDir,
        [ValidateSet('debug', 'release')]
        [string]$Variant = 'debug'
    )
    $gradlew = Join-Path $FlutterDir 'android\gradlew.bat'
    if (-not (Test-Path $gradlew)) { return $null }

    $report = & $gradlew -p (Join-Path $FlutterDir 'android') `
        :app:signingReport 2>&1 | Out-String
    $pattern = if ($Variant -eq 'release') {
        '(?ms)Variant:\s*release\s+Config:.*?SHA1:\s*([0-9A-Fa-f:]+)'
    } else {
        '(?ms)Variant:\s*debug\s+Config:\s*debug\s+Store:.*?SHA1:\s*([0-9A-Fa-f:]+)'
    }
    $m = [regex]::Match($report, $pattern)
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
}

function Install-ApkToDevices {
    param(
        [string[]]$DeviceIds,
        [string]$ApkPath,
        [string]$AppId = 'com.munawwaracare.android',
        [switch]$FreshInstall
    )
    $perms = @(
        'android.permission.RECORD_AUDIO',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.READ_PHONE_STATE',
        'android.permission.USE_FULL_SCREEN_INTENT'
    )
    foreach ($device in $DeviceIds) {
        Write-Host ""
        Write-Host "[>] $device Deploying..." -ForegroundColor Cyan
        if ($FreshInstall) {
            adb -s $device uninstall $AppId 2>&1 | Out-Null
            Write-Host '    [OK] Fresh install (uninstalled old)' -ForegroundColor Green
        }
        adb -s $device install -r -d $ApkPath
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    [X]  $device Install failed" -ForegroundColor Red
            continue
        }
        Write-Host "    [OK] $device Installed" -ForegroundColor Green
        foreach ($perm in $perms) {
            adb -s $device shell pm grant $AppId $perm 2>&1 | Out-Null
        }
        adb -s $device shell am start -n "$AppId/.MainActivity" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            adb -s $device shell monkey -p $AppId `
                -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
        }
        Write-Host "    [OK] $device Launched" -ForegroundColor Green
    }
}
