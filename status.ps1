# Workspace submodule status at a glance.
# Usage: ./status.ps1  (from the workspace root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "== git submodule status ==" -ForegroundColor Cyan
git submodule status
Write-Host ""

foreach ($path in (git config --file .gitmodules --get-regexp '^submodule\..*\.path$' |
        ForEach-Object { ($_ -split ' ')[1] })) {
    $url = git config --file .gitmodules --get "submodule.$path.url"
    Write-Host "== $($url.Split('/')[-1] -replace '\.git$', '') ==" -ForegroundColor Cyan

    Push-Location $path
    try {
        $dirty = git status --porcelain
        if ($dirty) {
            Write-Host " WORKING TREE DIRTY:" -ForegroundColor Yellow
            $dirty | ForEach-Object { Write-Host "   $_" -ForegroundColor Yellow }
        }

        $pins = git log -1 --oneline
        Write-Host " Pinned: $pins"

        # Pinned commit vs branch tip on remote 'main'
        $remoteMain = git rev-parse origin/main 2>$null
        if ($LASTEXITCODE -eq 0) {
            $local = git rev-parse HEAD
            if ($local -ne $remoteMain) {
                $behind = git rev-list --count "$local..$remoteMain"
                if ($behind -gt 0) {
                    Write-Host " FROM PIN: $behind commit(s) behind remote 'main'" -ForegroundColor Yellow
                }
            } else {
                Write-Host " Pin == remote 'main'" -ForegroundColor Green
            }
        }
    } finally {
        Pop-Location
    }
    Write-Host ""
}
