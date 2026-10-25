<#
.SYNOPSIS
  One-time: writes floci/nginx.conf, exports and trusts the .NET dev certificate so the Floci HTTPS proxy (port 4567) works.
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

# nginx config for the TLS proxy. If a previous `docker compose up` ran without it, Docker auto-created
# a directory with this name, which breaks the bind mount: replace it (only when empty).
$conf = Join-Path $PSScriptRoot 'nginx.conf'
if (Test-Path $conf -PathType Container) {
    if (Get-ChildItem $conf -Force) { throw "$conf is a non-empty directory; remove it manually" }
    Remove-Item $conf -Force
}
$nginx = @'
server {
    listen 4567 ssl;
    server_name localhost;

    ssl_certificate     /certs/localhost.pem;
    ssl_certificate_key /certs/localhost.key;

    # S3 uploads and SES payloads can be large
    client_max_body_size 0;

    location / {
        proxy_pass http://floci:4566;
        proxy_http_version 1.1;
        # Keep the public HTTPS origin so Floci builds correct OIDC/JWKS/queue URLs
        proxy_set_header Host localhost:4567;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host localhost:4567;
        proxy_request_buffering off;
        proxy_buffering off;
    }
}
'@
# .NET call instead of Set-Content: Windows PowerShell 5.1 has no utf8NoBOM (a BOM would break nginx), and this keeps LF endings.
[System.IO.File]::WriteAllText($conf, ($nginx -replace "`r`n", "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))

Write-Host 'ok  floci/certs/localhost.pem + localhost.key + nginx.conf (git-ignored certs). Now: docker compose up -d'
