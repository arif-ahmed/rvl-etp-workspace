# Verifies that every Postman request name cited in the feature-docs tree actually exists in the
# referenced collection under postman/services/*.json. Extracts the request names the docs claim
# (patterns like: "POST /api/v1/landing-page-image") and checks them against the real names.
param([string]$Root = "en")

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootPath = Join-Path $here $Root
$wsRoot = Resolve-Path (Join-Path $here "..\..\..")
$pmDir = Join-Path $wsRoot "postman\services"

if (-not (Test-Path $pmDir)) { Write-Host "MISSING postman dir: $pmDir"; exit 1 }

# --- build the index of real request names, per collection
$real = @{}
Get-ChildItem $pmDir -Filter *.json | ForEach-Object {
    $key = $_.BaseName
    $real[$key] = New-Object System.Collections.Generic.List[string]
    $json = Get-Content $_.FullName -Raw | ConvertFrom-Json
    # folders are item[]; a request has a "request" property, a folder has nested "item"
    foreach ($folder in $json.item) {
        if ($null -ne $folder.request) { $real[$key].Add($folder.name); continue }
        foreach ($req in $folder.item) {
            if ($null -ne $req.request) { $real[$key].Add($req.name) }
        }
    }
}
$allNames = @()
foreach ($k in $real.Keys) { $allNames += $real[$k] }
Write-Host ("Indexed {0} requests across {1} collections." -f $allNames.Count, $real.Count)
Write-Host ""

# --- extract cited names from the docs: quoted strings that look like "METHOD /path"
$files = Get-ChildItem -Path $rootPath -Recurse -Filter *.md
$cited = @{}
foreach ($f in $files) {
    $t = Get-Content $f.FullName -Raw
    foreach ($m in [regex]::Matches($t, '"((?:GET|POST|PUT|DELETE|PATCH)\s+/[^"]+)"')) {
        $name = $m.Groups[1].Value
        # a real Postman request name is "VERB /path"; prose such as
        # "GET / PUT (HTTP + token)" or "POST /user-issue<br/>..." is not one
        if ($name -notmatch '^(GET|POST|PUT|DELETE|PATCH) /[a-zA-Z{]') { continue }
        if (-not $cited.ContainsKey($name)) { $cited[$name] = @() }
        $cited[$name] += $f.Name
    }
}

Write-Host ("Docs cite {0} distinct Postman request names." -f $cited.Count)
Write-Host ""

$missing = @()
foreach ($name in ($cited.Keys | Sort-Object)) {
    if ($allNames -notcontains $name) { $missing += [pscustomobject]@{ Name = $name; Cited = ($cited[$name] | Select-Object -Unique) -join ', ' } }
}

if ($missing.Count -eq 0) {
    Write-Host "RESULT: every cited Postman request name exists." -ForegroundColor Green
} else {
    Write-Host ("RESULT: {0} cited name(s) not found in any collection:" -f $missing.Count) -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host ("  MISSING: {0}   (cited in {1})" -f $_.Name, $_.Cited) }
}