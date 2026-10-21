# Applies scripts/user-secrets.json to every backend service (dotnet user-secrets). Safe to re-run.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$file = Join-Path $PSScriptRoot 'user-secrets.json'
if (-not (Test-Path $file)) { throw "Copy scripts/user-secrets.example.json to scripts/user-secrets.json and edit it first." }
$json = Get-Content $file -Raw
$null = $json | ConvertFrom-Json   # fails here if the JSON is broken
$projects = Get-ChildItem (Join-Path $root 'rvl-gobcb-backend/Services') -Recurse -Filter '*.Service.csproj' |
    Where-Object { Select-String -Path $_.FullName -Pattern '<UserSecretsId>' -Quiet }
foreach ($p in $projects) {
    $json | dotnet user-secrets set --project $p.FullName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "user-secrets failed: $($p.Name)" }
    Write-Host "ok  $($p.Name)"
}
