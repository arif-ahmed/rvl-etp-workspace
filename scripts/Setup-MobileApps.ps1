<#
.SYNOPSIS
  Prepares (and optionally runs) local copies of the Flutter apps (user app, ticket checker) for Android. Safe to re-run.

.DESCRIPTION
  The rvl-gobcb-user-app / rvl-gobcb-checker-app submodules are never touched. This script:
  1. Checks prerequisites (fvm, node, Android SDK, keytool) and installs the Flutter version each app pins (via FVM).
  2. Copies each app to mobile-local/<app> (git-ignored; keystores, local.properties and build caches are kept between runs).
  3. Writes env/.env.<flavor> in the COPY, pointing at the local gateway (scripts/mobile-gateway.js, default :5200).
     Cognito pool/client IDs are read from a running Floci; if Floci is down, placeholders are written.
  4. Generates debug/release keystores and their passwords into android/local.properties of the COPY (the Gradle build needs them).
  5. User app only: writes a dummy android/app/google-services.json in the COPY (the build applies the Google-services plugin;
     the real file is not in the repo).
  6. Runs 'flutter pub get'. With -Run it also starts the gateway, sets up adb reverse and runs the app on a device.

  Not solved here (see docs/mobile-local.md, "Known gaps"): signing in against Floci (Amplify Flutter has no endpoint override),
  the 'identity' API (sign-up/OTP), real Firebase, and the checker's VDS_CERTIFICATE.
  NOT TESTED yet: written from reading the code. Expect to fix small things on the first run.
#>
param(
    [ValidateSet('user', 'checker', 'both')][string]$App = 'both',
    [ValidateSet('dev', 'test', 'staging', 'prod')][string]$Flavor = 'dev',
    [int]$GatewayPort = 5200,
    [switch]$Run,            # start gateway + adb reverse + flutter run (needs -App user or checker, not both)
    [string]$Device          # adb device id for flutter run (default: the only connected device)
)
$ErrorActionPreference = 'Stop'

$root  = Split-Path $PSScriptRoot -Parent
$out   = Join-Path $root 'mobile-local'
$floci = 'http://localhost:4566'
$apps  = @{
    user    = @{ Src = 'rvl-gobcb-user-app';    Pool = 'etp-user';          Name = 'user-app' }
    checker = @{ Src = 'rvl-gobcb-checker-app'; Pool = 'etp-ticketchecker'; Name = 'checker-app' }
}
$selected = if ($App -eq 'both') { 'user', 'checker' } else { , $App }
if ($Run -and $selected.Count -ne 1) { throw '-Run needs a single app: -App user or -App checker' }

function Write-Text($path, $text) { [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false)) }
function Random-Password { -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ }) }

# ---- 1. Prerequisites -------------------------------------------------------------------------------------------------
foreach ($tool in 'fvm', 'node', 'git') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool not found on PATH. See docs/mobile-local.md section 2." }
}

$sdk = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) |
    Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sdk) { throw 'Android SDK not found. Install Android Studio and its SDK (docs/mobile-local.md section 2).' }
$env:ANDROID_HOME = $sdk
$env:Path = "$sdk\platform-tools;$sdk\cmdline-tools\latest\bin;$env:Path"

# Android Studio ships a JDK (jbr); use it for Gradle and keytool unless JAVA_HOME is already set.
$jbr = 'C:\Program Files\Android\Android Studio\jbr'
if (-not $env:JAVA_HOME -and (Test-Path $jbr)) { $env:JAVA_HOME = $jbr }
if ($env:JAVA_HOME) { $env:Path = "$env:JAVA_HOME\bin;$env:Path" }
if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) { throw 'keytool not found. Install Android Studio or set JAVA_HOME.' }
Write-Host "ok  Android SDK $sdk"

# Floci Cognito IDs (optional)
function Get-CognitoIds($poolName) {
    $ids = @{ PoolId = 'us-east-1_LOCALPLACEHOLDER'; ClientId = 'LOCALPLACEHOLDER'; Real = $false }
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { Write-Warning 'aws CLI not found; Cognito IDs are placeholders.'; return $ids }
    $env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_REGION = 'us-east-1'; $env:AWS_PAGER = ''
    try {
        $pool = & aws --endpoint-url $floci cognito-idp list-user-pools --max-results 60 --query "UserPools[?Name=='$poolName'].Id | [0]" --output text 2>$null
        if ($LASTEXITCODE -or -not $pool -or $pool -eq 'None') { throw 'pool missing' }
        $client = & aws --endpoint-url $floci cognito-idp list-user-pool-clients --user-pool-id $pool --query "UserPoolClients[?ClientName=='etp-local'].ClientId | [0]" --output text
        if ($LASTEXITCODE -or -not $client -or $client -eq 'None') { throw 'client missing' }
        return @{ PoolId = $pool; ClientId = $client; Real = $true }
    }
    catch { Write-Warning "Floci/$poolName not available ($_). Cognito IDs are placeholders. Run scripts/Seed-EtpCognitoUsers.ps1 and re-run this script."; return $ids }
}

New-Item -ItemType Directory -Force $out | Out-Null

foreach ($key in $selected) {
    $cfg = $apps[$key]
    $src = Join-Path $root $cfg.Src
    $dst = Join-Path $out $cfg.Name
    Write-Host "`n=== $($cfg.Name) ==="
    if (-not (Test-Path (Join-Path $src 'pubspec.yaml'))) { throw "Submodule not checked out: $src (run: git submodule update --init $($cfg.Src))" }

    # ---- 2. Copy ------------------------------------------------------------------------------------------------------
    New-Item -ItemType Directory -Force $dst | Out-Null
    robocopy $src $dst /E /XD .git .dart_tool build .gradle .idea /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
    Write-Host "ok  copied $($cfg.Src) -> $dst"

    # Flutter version the app pins (pubspec: environment.flutter)
    $pub = Get-Content (Join-Path $dst 'pubspec.yaml') -Raw
    if ($pub -notmatch '(?m)^\s*flutter:\s*"?(\d+\.\d+\.\d+)"?\s*$') { throw "No pinned Flutter version in $($cfg.Src)/pubspec.yaml" }
    $flutterVer = $Matches[1]
    if (-not (Test-Path (Join-Path $dst '.fvmrc'))) { Write-Text (Join-Path $dst '.fvmrc') "{`n  `"flutter`": `"$flutterVer`"`n}`n" }

    # ---- 3. Env file --------------------------------------------------------------------------------------------------
    $cog = Get-CognitoIds $cfg.Pool
    $amplify = [ordered]@{
        UserAgent = 'aws-amplify-cli/2.0'; Version = '1.0'
        auth = @{ plugins = @{ awsCognitoAuthPlugin = [ordered]@{
            UserAgent = 'aws-amplify/cli'; Version = '0.1.0'
            IdentityManager = @{ Default = @{} }
            CognitoUserPool = @{ Default = [ordered]@{ PoolId = $cog.PoolId; AppClientId = $cog.ClientId; Region = 'us-east-1' } }
            Auth = @{ Default = @{ authenticationFlowType = 'USER_PASSWORD_AUTH' } }
        } } }
    } | ConvertTo-Json -Depth 10 -Compress
    $gw = "http://localhost:$GatewayPort/"      # localhost works on emulator AND phone because of 'adb reverse' (see -Run)

    if ($key -eq 'user') {
        $envText = @"
# GENERATED by scripts/Setup-MobileApps.ps1 - do not edit, re-run the script.
API_BASE_URL='$gw'
AUTH_API_BASE_URL='${gw}identity/'
AUTH_API_TOKEN='local'
AMPLIFY_CONFIG='$amplify'
TERMS_AND_CONDITIONS_URL='https://example.com/terms'
PRIVACY_AND_POLICY_URL='https://example.com/privacy'
PAYMENT_SUCCESS_URL='https://example.com/payment-success'
ICC_ANTI_DISCRIMINATION_POLICY_URL='https://example.com/anti-discrimination'
ICC_ANTI_RACISM_POLICY_URL='https://example.com/anti-racism'
CONTACT_EMAIL='local@etp.local'
CHAT_COMMUNICATION_HUB='${gw}userissue/'
FIREBASE_ANDROID_API_KEY='local-dummy'
FIREBASE_ANDROID_APP_ID='1:000000000000:android:0000000000000000'
FIREBASE_ANDROID_MESSAGING_SENDER_ID='000000000000'
FIREBASE_ANDROID_PROJECT_ID='etp-local'
FIREBASE_ANDROID_STORAGE_BUCKET='etp-local.appspot.com'
FIREBASE_IOS_API_KEY='local-dummy'
FIREBASE_IOS_APP_ID='1:000000000000:ios:0000000000000000'
FIREBASE_IOS_MESSAGING_SENDER_ID='000000000000'
FIREBASE_IOS_PROJECT_ID='etp-local'
FIREBASE_IOS_STORAGE_BUCKET='etp-local.appspot.com'
FIREBASE_IOS_BUNDLE_ID='com.ticketbangla.gobcbticket'
"@
    }
    else {
        $envText = @"
# GENERATED by scripts/Setup-MobileApps.ps1 - do not edit, re-run the script.
API_BASE_URL='$gw'
AUTH_API_BASE_URL='${gw}identity/'
AMPLIFY_CONFIG='$amplify'
# Public certificate used to verify ticket QR signatures. Not in any repo: ask bs23, or export it from the Ticketing service signing key.
VDS_CERTIFICATE='REPLACE_ME'
"@
    }
    New-Item -ItemType Directory -Force (Join-Path $dst 'env') | Out-Null
    $envFile = Join-Path $dst "env\.env.$Flavor"
    Write-Text $envFile $envText
    Write-Host "ok  $envFile (Cognito: $(if ($cog.Real) { "$($cog.PoolId) / $($cog.ClientId)" } else { 'placeholders' }))"
    if ($key -eq 'checker') { Write-Warning 'VDS_CERTIFICATE is a placeholder: the checker app starts but cannot verify real tickets.' }

    # ---- 4. Keystores + passwords ---------------------------------------------------------------------------------------
    $android  = Join-Path $dst 'android'
    $ksDir    = Join-Path $android 'keystore'
    $propFile = Join-Path $android 'local.properties'
    New-Item -ItemType Directory -Force $ksDir | Out-Null
    if (-not (Test-Path $propFile)) { Write-Text $propFile '' }
    $props = Get-Content $propFile -Raw
    $added = ''
    foreach ($env_ in 'dev', 'test', 'staging', 'prod') {
        foreach ($type in 'Debug', 'Release') {
            $alias = "flavor_$env_$type"
            $jks   = Join-Path $ksDir "$alias.jks"
            if ($props -match [regex]::Escape("$alias.storePassword=")) { if (Test-Path $jks) { continue } }
            $pw = Random-Password
            Remove-Item $jks -ErrorAction SilentlyContinue
            & keytool -genkeypair -keystore $jks -alias $alias -keyalg RSA -keysize 2048 -validity 10000 `
                -storepass $pw -keypass $pw -dname 'CN=ETP Local, O=Local, C=BD' 2>&1 | Out-Null
            if ($LASTEXITCODE) { throw "keytool failed for $alias" }
            # drop any stale lines for this alias, then add the new ones
            $props = ($props -split "\r?\n" | Where-Object { $_ -notmatch ("^" + [regex]::Escape($alias) + "\.") }) -join "`n"
            $added += "$alias.storePassword=$pw`n$alias.keyPassword=$pw`n"
        }
    }
    if ($added) { Write-Text $propFile (($props.TrimEnd() + "`n" + $added).TrimStart()); Write-Host 'ok  keystores generated, passwords in android/local.properties' }
    else { Write-Host 'ok  keystores already present' }

    # ---- 5. Dummy google-services.json (only for apps that apply the plugin) -----------------------------------------------
    if ((Get-Content (Join-Path $android 'app\build.gradle') -Raw) -match 'com\.google\.gms\.google-services') {
        $appId = if ($pub -match '(?m)^name:\s*gobcbticket') { 'com.ticketbangla.gobcbticket' } else { 'com.mahfuznow.ticket_checker' }
        $clients = foreach ($suffix in '', '.dev', '.test', '.staging') {
            foreach ($bt in '', '.debug') {
                @{
                    client_info = @{ mobilesdk_app_id = '1:000000000000:android:0000000000000000'; android_client_info = @{ package_name = "$appId$suffix$bt" } }
                    api_key = @(@{ current_key = 'local-dummy' })
                    services = @{ appinvite_service = @{ other_platform_oauth_client = @() } }
                }
            }
        }
        $gs = @{ project_info = @{ project_number = '000000000000'; project_id = 'etp-local'; storage_bucket = 'etp-local.appspot.com' }; client = @($clients); configuration_version = '1' }
        Write-Text (Join-Path $android 'app\google-services.json') ($gs | ConvertTo-Json -Depth 10)
        Write-Host 'ok  dummy android/app/google-services.json (no real Firebase locally)'
    }

    # ---- 6. Flutter SDK + dependencies ----------------------------------------------------------------------------------------
    Push-Location $dst
    try {
        Write-Host "fvm install $flutterVer (first time downloads ~1 GB)..."
        fvm install
        if ($LASTEXITCODE) { throw 'fvm install failed' }
        fvm flutter pub get
        if ($LASTEXITCODE) { throw 'flutter pub get failed' }
        Write-Host "ok  dependencies resolved for $($cfg.Name)"
    }
    finally { Pop-Location }
}

# ---- Run ------------------------------------------------------------------------------------------------------------------------
$dst = Join-Path $out $apps[$selected[0]].Name
if (-not $Run) {
    Write-Host "`nReady. Run an app with:  pwsh ./scripts/Setup-MobileApps.ps1 -App user -Run   (needs the backend + a device, see docs/mobile-local.md)"
    return
}

$devices = (& adb devices) | Select-String '\tdevice$' | ForEach-Object { ($_ -split "\t")[0] }
if (-not $devices) { throw 'No Android device found. Plug in a phone (USB debugging on) or start an emulator, then check: adb devices' }
if (-not $Device) {
    if (@($devices).Count -gt 1) { throw "Several devices ($($devices -join ', ')). Pass -Device <id>." }
    $Device = @($devices)[0]
}

# Gateway: start once, keep running after this script ends
$listening = Get-NetTCPConnection -LocalPort $GatewayPort -State Listen -ErrorAction SilentlyContinue
if (-not $listening) {
    Start-Process node -ArgumentList "`"$PSScriptRoot\mobile-gateway.js`" $GatewayPort" -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $out 'gateway.log') -RedirectStandardError (Join-Path $out 'gateway.err.log')
    Write-Host "ok  gateway started on :$GatewayPort (log: mobile-local/gateway.log)"
}
else { Write-Host "ok  gateway already listening on :$GatewayPort" }

& adb -s $Device reverse "tcp:$GatewayPort" "tcp:$GatewayPort" | Out-Null
Write-Host "ok  adb reverse tcp:$GatewayPort ($Device): the app's localhost:$GatewayPort reaches this PC"

Push-Location $dst
try { fvm flutter run -d $Device --flavor "flavor_$Flavor" -t "lib/main/main_flavor_$Flavor.dart" }
finally { Pop-Location }
