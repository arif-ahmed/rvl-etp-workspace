<#
.SYNOPSIS
  One-time: trusts the .NET dev certificate and exports it to certs/ so the Floci HTTPS proxy (port 4567) works.
  Run before the first AppHost start. Safe to re-run. A trust prompt may appear on Windows: accept it.
  The proxy config is floci/nginx.conf; only the certificate is machine-specific (git-ignored).
#>
$ErrorActionPreference = 'Stop'
$dir = Join-Path $PSScriptRoot '../certs'
New-Item -ItemType Directory -Force $dir | Out-Null
dotnet dev-certs https --trust
if ($LASTEXITCODE -ne 0) { throw 'dotnet dev-certs --trust failed' }
dotnet dev-certs https --export-path (Join-Path $dir 'localhost.pem') --format Pem --no-password
if ($LASTEXITCODE -ne 0) { throw 'dotnet dev-certs export failed' }
if (-not ((Test-Path "$dir/localhost.pem") -and (Test-Path "$dir/localhost.key"))) { throw 'certificate files were not created' }

Write-Host 'ok  certs/localhost.pem + localhost.key (git-ignored). Now: dotnet run --project aspire/Etp.AppHost'
