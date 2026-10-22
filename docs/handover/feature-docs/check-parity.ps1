# Compares the bn/ tree against en/ and lists files present in one but not the other, so the
# translation mirror can be completed and kept in step.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Rel($root) {
    Get-ChildItem -Path $root -Recurse -Filter *.md |
        ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') }
}

$en = Rel (Join-Path $here "en")
$bn = Rel (Join-Path $here "bn")

$missingInBn = $en | Where-Object { $bn -notcontains $_ }
$extraInBn   = $bn | Where-Object { $en -notcontains $_ }

Write-Host ("en/: {0} files   bn/: {1} files" -f $en.Count, $bn.Count)
Write-Host ""
if ($missingInBn) {
    Write-Host ("MISSING in bn/ ({0}):" -f $missingInBn.Count) -ForegroundColor Yellow
    $missingInBn | Sort-Object | ForEach-Object { Write-Host "  $_" }
} else { Write-Host "bn/ has every en/ file." -ForegroundColor Green }
if ($extraInBn) {
    Write-Host ""
    Write-Host ("EXTRA in bn/ ({0}):" -f $extraInBn.Count) -ForegroundColor Yellow
    $extraInBn | Sort-Object | ForEach-Object { Write-Host "  $_" }
}