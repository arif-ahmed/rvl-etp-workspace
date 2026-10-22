# Verifies that every relative markdown link in the feature-docs tree resolves.
# Usage: pwsh -File check-links.ps1 -Root en
param([string]$Root = "en")

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootPath = Join-Path $here $Root
if (-not (Test-Path $rootPath)) { Write-Host "MISSING ROOT: $rootPath"; exit 1 }

$files = Get-ChildItem -Path $rootPath -Recurse -Filter *.md
$broken = @()
$checked = 0

foreach ($f in $files) {
    $text = Get-Content $f.FullName -Raw
    $dir = $f.DirectoryName
    foreach ($m in [regex]::Matches($text, '\]\(([^)]+\.md)(#[^)]*)?\)')) {
        $target = $m.Groups[1].Value
        if ($target -match '^(https?|mailto):') { continue }
        $checked++
        $full = Join-Path $dir $target
        if (-not (Test-Path $full)) {
            $rel = $f.FullName.Substring($here.Length + 1)
            $broken += [pscustomobject]@{ File = $rel; Link = $target }
        }
    }
}

Write-Host "Tree: $Root  ($($files.Count) md files, $checked relative links checked)"
if ($broken.Count -eq 0) {
    Write-Host "RESULT: all links resolve." -ForegroundColor Green
} else {
    Write-Host "RESULT: $($broken.Count) broken link(s):" -ForegroundColor Red
    $broken | Sort-Object File | ForEach-Object { Write-Host ("  {0}  ->  {1}" -f $_.File, $_.Link) }
}