# Verifies that every [UNCONFIRMED: Q-nn] marker in the tree is defined in 99-open-queries.md,
# that every Q-nn defined there is actually referenced somewhere, and reports the totals.
param([string]$Root = "en")

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootPath = Join-Path $here $Root
$regPath = Join-Path $rootPath "99-open-queries.md"

if (-not (Test-Path $regPath)) { Write-Host "MISSING registry: $regPath"; exit 1 }

# --- defined: Q-nn appearing as a leading table cell / heading in the registry
$regText = Get-Content $regPath -Raw
$defined = [regex]::Matches($regText, '(?m)^\s*\|?\s*\**Q-(\d{2})\**\s*\|') |
          ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

# --- referenced: every Q-nn mentioned in any file of the tree
$files = Get-ChildItem -Path $rootPath -Recurse -Filter *.md
$referenced = @{}
foreach ($f in $files) {
    $t = Get-Content $f.FullName -Raw
    foreach ($m in [regex]::Matches($t, 'Q-(\d{2})')) {
        $id = $m.Groups[1].Value
        if (-not $referenced.ContainsKey($id)) { $referenced[$id] = @() }
        $referenced[$id] += $f.Name
    }
}
$refIds = $referenced.Keys | Sort-Object -Unique

$undefined = $refIds | Where-Object { $defined -notcontains $_ }
$unreferenced = $defined | Where-Object { $refIds -notcontains $_ }

# numeric range report
$all = ($refIds + $defined) | Sort-Object -Unique
$nums = $all | ForEach-Object { [int]$_ }
$max = ($nums | Measure-Object -Maximum).Maximum
$gap = 1..$max | ForEach-Object { '{0:D2}' -f $_ } | Where-Object { $refIds -notcontains $_ -and $defined -notcontains $_ }

Write-Host "Tree: $Root"
$maxStr = $max.ToString('00')
Write-Host ("  registry defines : {0} query ids (Q-01..Q-{1})" -f $defined.Count, $maxStr)
Write-Host "  referenced in tree: $($refIds.Count) distinct Q-nn"
Write-Host ""
if ($gap) { Write-Host "Unused ids (documented as unused is fine): $($gap -join ', ')" -ForegroundColor Yellow }
if ($undefined) {
    Write-Host "UNDEFINED references (must be fixed): $($undefined -join ', ')" -ForegroundColor Red
} else { Write-Host "Every referenced Q-nn is defined. OK" -ForegroundColor Green }
if ($unreferenced) {
    Write-Host "Defined but never referenced from a feature file: $($unreferenced -join ', ')" -ForegroundColor Yellow
}
if (-not $gap -and -not $undefined -and -not $unreferenced) { Write-Host "RESULT: clean." -ForegroundColor Green }