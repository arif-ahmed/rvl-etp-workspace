# Starts Visual Studio on the backend solution with the local-Floci environment, so a service you run (F5) from
# VS talks to Floci instead of real AWS. Anything the VS debugger starts inherits these variables.
#
# Why: the AppHost sets AWS_ENDPOINT_URL for the services it launches, but Visual Studio does not. Without it the
# Cognito client sends the fake keys to real AWS, AdminGetUser fails (swallowed), no role claim is added and every
# [Authorize(Roles = ...)] endpoint answers 403. We cannot put it in launchSettings.json (that file is in a submodule).
#
# Usage:  ./scripts/Start-VisualStudio.ps1            (close every open Visual Studio window first)
# Then in VS run the service with its launch profile (Admin: http://localhost:5099). Stop the AppHost's copy of that service first
# (or start the AppHost with ETP_SKIP=Admin), and use a fresh token from Floci.

param(
    [string]$Solution = (Join-Path $PSScriptRoot '..\rvl-gobcb-backend\RVL-ETP.BackEnd.sln')
)

$ErrorActionPreference = 'Stop'

$Solution = (Resolve-Path $Solution).Path

$env:AWS_ENDPOINT_URL       = 'http://localhost:4566'    # Floci; its region is us-east-1, which is what the AWS SDK signs with
$env:Notification__Endpoint = 'http://localhost:4569/'   # nginx stub for the SMS gateway (admin create user / set password)

if (Get-Process devenv -ErrorAction SilentlyContinue) {
    Write-Warning 'Visual Studio is already running. A running instance keeps its old environment, so close all VS windows and run this again.'
}

# devenv is not on PATH outside a Developer prompt: ask vswhere
$devenv = Get-Command devenv.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $devenv) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $devenv = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find 'Common7\IDE\devenv.exe' | Select-Object -First 1
    }
}
if (-not $devenv) { throw 'devenv.exe not found. Run this from "Developer PowerShell for VS" or install Visual Studio.' }

Write-Host "AWS_ENDPOINT_URL       = $env:AWS_ENDPOINT_URL"
Write-Host "Notification__Endpoint = $env:Notification__Endpoint"
Write-Host "Starting $devenv $Solution"
Start-Process -FilePath $devenv -ArgumentList "`"$Solution`""
