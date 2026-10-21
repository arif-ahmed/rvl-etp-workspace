<#
.SYNOPSIS
  One-time: exports and trusts the .NET dev certificate so the Floci HTTPS proxy (port 4567) works.
  Run before the first `docker compose up -d` in floci/. Safe to re-run. A trust prompt may appear on Windows: accept it.
#>
$ErrorActionPreference = 'Stop'
$dir = Join-Path $PSScriptRoot 'certs'
New-Item -ItemType Directory -Force $dir | Out-Null
dotnet dev-certs https --trust
if ($LASTEXITCODE -ne 0) { throw 'dotnet dev-certs --trust failed' }
dotnet dev-certs https --export-path (Join-Path $dir 'localhost.pem') --format Pem --no-password
if ($LASTEXITCODE -ne 0) { throw 'dotnet dev-certs export failed' }
if (-not ((Test-Path "$dir/localhost.pem") -and (Test-Path "$dir/localhost.key"))) { throw 'certificate files were not created' }
Write-Host 'ok  floci/certs/localhost.pem + localhost.key (git-ignored). Now: docker compose up -d'
