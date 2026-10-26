<#
.SYNOPSIS
  Builds the local user secrets and applies them to every backend service (dotnet user-secrets). Safe to re-run.

.DESCRIPTION
  1. Starts from scripts/user-secrets.example.json (Floci URLs, test keys, queue names, DB/Redis, service URLs).
  2. Asks the running Floci for the Cognito PoolId/ClientId of the Admin, User, TicketChecker and Agent pools
     (created by scripts/Seed-EtpCognitoUsers.ps1) and fills in PoolId, ClientId, Authority and Metadata. Nothing to copy by hand.
  3. Optionally merges scripts/user-secrets.json (git-ignored) on top, for personal overrides such as a real key.
  4. Refuses to apply if a Cognito value is still a placeholder, then writes the result to every service.

  Run it after scripts/Seed-EtpCognitoUsers.ps1, and again whenever Floci is re-seeded.
#>
param([switch]$DryRun)   # -DryRun prints the final JSON and applies nothing
$ErrorActionPreference = 'Stop'
$root     = Split-Path $PSScriptRoot -Parent
$example  = Join-Path $PSScriptRoot 'user-secrets.example.json'
$override = Join-Path $PSScriptRoot 'user-secrets.json'
$endpoint = 'http://localhost:4566'    # AWS API (CLI/SDK)
$oidc     = 'https://localhost:4567'   # Cognito issuer/JWKS: the backend only accepts HTTPS metadata (floci-tls proxy)

# ConvertFrom-Json -AsHashtable only exists in PowerShell 7; this works in Windows PowerShell 5.1 too.
function ConvertTo-Hash($o) {
    if ($o -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hash $p.Value }
        return $h
    }
    return $o
}
function Read-JsonHash($path) { ConvertTo-Hash (Get-Content $path -Raw | ConvertFrom-Json) }

function Merge-Hash($base, $over) {
    foreach ($k in $over.Keys) {
        if ($base.Contains($k) -and $base[$k] -is [System.Collections.IDictionary] -and $over[$k] -is [System.Collections.IDictionary]) { Merge-Hash $base[$k] $over[$k] }
        elseif ($over[$k] -is [string] -and $over[$k] -match 'REPLACE_WITH') { }   # untouched placeholder: keep the auto-filled value
        else { $base[$k] = $over[$k] }
    }
}
function Find-Placeholders($node, $path) {
    if ($node -is [System.Collections.IDictionary]) { foreach ($k in $node.Keys) { Find-Placeholders $node[$k] "${path}${k}:" } }
    elseif ($node -is [string] -and $node -match 'REPLACE_WITH') { $path.TrimEnd(':') }
}

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'AWS CLI not found. Install it (winget install Amazon.AWSCLI) and open a new terminal.' }
$env:AWS_ENDPOINT_URL = $endpoint; $env:AWS_REGION = 'us-east-1'
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_PAGER = ''

$cfg = Read-JsonHash $example

# ---- Cognito values from the running Floci ----
$reachable = $true
try { $null = aws cognito-idp list-user-pools --max-results 1 2>&1; if ($LASTEXITCODE -ne 0) { $reachable = $false } } catch { $reachable = $false }
if (-not $reachable) { throw "Cannot reach Floci at $endpoint. Start it: docker compose up -d" }

foreach ($pool in 'Admin','User','TicketChecker','Agent') {
    $name = "etp-$($pool.ToLower())"
    $id = aws cognito-idp list-user-pools --max-results 60 --query "UserPools[?Name=='$name'].Id | [0]" --output text
    if (-not $id -or $id -eq 'None') { throw "Cognito pool '$name' not found in Floci. Run: pwsh ./scripts/Seed-EtpCognitoUsers.ps1" }
    $client = aws cognito-idp list-user-pool-clients --user-pool-id $id --query "UserPoolClients[?ClientName=='etp-local'].ClientId | [0]" --output text
    if (-not $client -or $client -eq 'None') { throw "App client 'etp-local' not found in pool '$name'. Run: pwsh ./scripts/Seed-EtpCognitoUsers.ps1" }
    $cfg.AWS.CognitoPool[$pool] = [ordered]@{
        PoolId    = $id
        ClientId  = $client
        Authority = "$oidc/$id"
        Metadata  = "$oidc/$id/.well-known/openid-configuration"
    }
    Write-Host ("cognito {0,-13} pool {1}  client {2}" -f $pool, $id, $client)
}

# ---- the HTTPS metadata must be reachable and must name the same issuer the tokens carry ----
$adminId = $cfg.AWS.CognitoPool.Admin.PoolId
try { $doc = Invoke-RestMethod "$oidc/$adminId/.well-known/openid-configuration" -TimeoutSec 10 }
catch { throw "Cannot read $oidc (HTTPS proxy for Floci): $($_.Exception.Message)`nFix: pwsh ./scripts/Setup-EtpHttps.ps1; docker compose up -d" }
if ($doc.issuer -ne "$oidc/$adminId") { throw "Floci reports issuer '$($doc.issuer)', expected '$oidc/$adminId'.`nFix: docker compose up -d to recreate Floci with the HTTPS base URL." }

# ---- personal overrides (optional) ----
if (Test-Path $override) {
    Merge-Hash $cfg (Read-JsonHash $override)
    Write-Host 'merged scripts/user-secrets.json'
}

$left = @(Find-Placeholders $cfg '')
if ($left.Count) { throw "Placeholders left, fix them in scripts/user-secrets.json: $($left -join ', ')" }

$json = $cfg | ConvertTo-Json -Depth 10
if ($DryRun) { $json; return }

$projects = Get-ChildItem (Join-Path $root 'rvl-gobcb-backend/Services') -Recurse -Filter '*.Service.csproj' |
    Where-Object { Select-String -Path $_.FullName -Pattern '<UserSecretsId>' -Quiet }
foreach ($p in $projects) {
    $json | dotnet user-secrets set --project $p.FullName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "user-secrets failed: $($p.Name)" }
    Write-Host "ok  $($p.Name)"
}
Write-Host "Done. Restart the AppHost to pick up the new values."
