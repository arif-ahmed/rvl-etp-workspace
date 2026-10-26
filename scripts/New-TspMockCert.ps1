<#
.SYNOPSIS
  Creates the self-signed TSP client certificate (tspgw_client.pfx) for the tsp-mock local setup and copies it
  into the Ticketing service build output. Safe to re-run.

.DESCRIPTION
  The Ticketing service loads `Cert/tspgw_client.pfx` from its output folder at the first TSP client use
  (no password: `new X509Certificate2(certPath)`), and without it the Ticketing worker throws CryptographicException
  in a loop. Locally nothing validates that certificate — the mock gateway (tsp-mock, port 5130) ignores client
  certificates — so a self-signed placeholder with an empty password is enough.

  The pfx lands in tsp-mock/certs/ (workspace, git-ignored? no — kept out of git via .gitignore if added) and is
  copied to rvl-gobcb-backend/Services/Ticketing/ETP.Ticketing.Service/bin/Debug/net8.0/Cert/.
  bin/ is git-ignored, so the submodule's `git status` stays clean.

  Re-run after every clean/rebuild of the Ticketing service (the output folder is wiped).

.NOTES
  Requires openssl on PATH (Git Bash ships it).
#>
param(
    # Path of the Ticketing service whose build output receives the certificate.
    [string]$TicketingProject = (Join-Path $PSScriptRoot '..\rvl-gobcb-backend\Services\Ticketing\ETP.Ticketing.Service')
)
$ErrorActionPreference = 'Stop'

$certDir   = Join-Path $PSScriptRoot '..\tsp-mock\certs'
$pfxPath   = Join-Path $certDir 'tspgw_client.pfx'
$keyPath   = Join-Path $certDir 'tspgw_client.key'
$crtPath   = Join-Path $certDir 'tspgw_client.crt'
$outCertDir = Join-Path $TicketingProject 'bin\Debug\net8.0\Cert'

New-Item -ItemType Directory -Force -Path $certDir | Out-Null

if (-not (Test-Path $pfxPath)) {
    openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes `
        -keyout $keyPath -out $crtPath `
        -subj '/CN=tsp-mock.local/O=ETP Local/OU=tsp-mock' `
        -addext 'subjectAltName=DNS:tsp-mock.local,DNS:localhost' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "openssl failed (exit $LASTEXITCODE)" }
    # Empty password (-passout pass:) — the service constructs X509Certificate2 without one.
    openssl pkcs12 -export -passout pass: `
        -inkey $keyPath -in $crtPath -out $pfxPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "openssl pkcs12 export failed (exit $LASTEXITCODE)" }
    Remove-Item $keyPath, $crtPath
    Write-Host "Created $pfxPath"
}
else {
    Write-Host "Reusing existing $pfxPath"
}

if (-not (Test-Path (Join-Path $TicketingProject 'ETP.Ticketing.Service.csproj'))) {
    throw "Ticketing project not found at $TicketingProject"
}
New-Item -ItemType Directory -Force -Path $outCertDir | Out-Null
Copy-Item $pfxPath (Join-Path $outCertDir 'tspgw_client.pfx') -Force
Write-Host "Copied to $outCertDir\tspgw_client.pfx"
Write-Host 'Note: re-run this script after a clean/rebuild of the Ticketing service.'
