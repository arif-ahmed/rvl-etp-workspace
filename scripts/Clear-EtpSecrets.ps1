<#
.SYNOPSIS
  Removes the user secrets that Set-EtpSecrets.ps1 wrote, from every backend service, and the optional
  scripts/user-secrets.json override file. Used in the full cleanup (docs/local-dev.md, Teardown).
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$projects = Get-ChildItem (Join-Path $root 'rvl-gobcb-backend/Services') -Recurse -Filter '*.Service.csproj' |
    Where-Object { Select-String -Path $_.FullName -Pattern '<UserSecretsId>' -Quiet }
foreach ($p in $projects) {
    dotnet user-secrets clear --project $p.FullName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "user-secrets clear failed: $($p.Name)" }
    Write-Host "cleared  $($p.Name)"
}
$override = Join-Path $PSScriptRoot 'user-secrets.json'
if (Test-Path $override) { Remove-Item $override; Write-Host 'removed  scripts/user-secrets.json' }
