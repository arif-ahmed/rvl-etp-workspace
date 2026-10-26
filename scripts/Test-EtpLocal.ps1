<#
.SYNOPSIS
  Checks that the local environment works end to end. Run it with the AppHost started.
  Checks: PostgreSQL/Redis/Floci containers, the 11 service /health endpoints, a Cognito login against Floci,
  and that a protected Admin endpoint answers 401 without a token and 200 with one.
#>
$ErrorActionPreference = 'Continue'
$script:fail = 0
function Check($name, [bool]$ok, $detail = '') {
    if ($ok) { Write-Host ("PASS  {0}" -f $name) -ForegroundColor Green }
    else { Write-Host ("FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
}
function Get-Status($url, $headers = @{}) {
    try { return [int](Invoke-WebRequest $url -Headers $headers -UseBasicParsing -TimeoutSec 20).StatusCode }
    catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode } else { return 0 } }
}

# containers
$running = @(docker ps --format '{{.Names}}' 2>$null)
foreach ($c in 'etp-postgres','etp-redis','etp-dynamodb','etp-floci','etp-floci-tls') {
    Check "container $c" ($running -contains $c) 'not running: docker compose up -d (workspace root)'
}

# services
$ports = [ordered]@{ Admin=5101; Booking=5102; Event=5103; Platform=5104; PushNotification=5105; Scheduler=5106; TicketChecker=5107; Ticketing=5108; UserAuth=5109; UserIssue=5110; Utility=5111 }
foreach ($n in $ports.Keys) {
    $s = Get-Status "http://localhost:$($ports[$n])/health"
    Check "health $n ($($ports[$n]))" ($s -eq 200) "HTTP $s. Open the service's console log in the Aspire dashboard"
}

# login + protected call
$env:AWS_ENDPOINT_URL = 'http://localhost:4566'; $env:AWS_REGION = 'ap-southeast-1'
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_PAGER = ''
$pool = aws cognito-idp list-user-pools --max-results 60 --query "UserPools[?Name=='etp-admin'].Id | [0]" --output text 2>$null
$client = if ($pool -and $pool -ne 'None') { aws cognito-idp list-user-pool-clients --user-pool-id $pool --query "UserPoolClients[?ClientName=='etp-local'].ClientId | [0]" --output text 2>$null }
Check 'Floci has the etp-admin pool and client' ($pool -and $pool -ne 'None' -and $client -and $client -ne 'None') 'run pwsh ./scripts/Seed-EtpCognitoUsers.ps1, then ./scripts/Set-EtpSecrets.ps1'
if ($pool -and $pool -ne 'None' -and $client -and $client -ne 'None') {
    $token = aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id $client --auth-parameters 'USERNAME=+8801700000001,PASSWORD=Passw0rd!23' --query AuthenticationResult.AccessToken --output text 2>$null
    Check 'Cognito login (admin test user)' ($token -and $token -ne 'None') 'Seed-EtpCognitoUsers.ps1 not run?'
    $url = 'http://localhost:5101/admin/api/v1/events'
    $noTok = Get-Status $url
    Check 'protected endpoint without token -> 401' ($noTok -eq 401) "HTTP $noTok"
    if ($token -and $token -ne 'None') {
        $withTok = Get-Status $url @{ Authorization = "Bearer $token"; 'X-Program-Id' = '1' }
        Check 'protected endpoint with token -> 200' ($withTok -eq 200) "HTTP $withTok. 401: re-run ./scripts/Set-EtpSecrets.ps1 and restart the AppHost. 403: Floci seeded in the wrong region (must be ap-southeast-1)"
    }
}
if ($script:fail) { Write-Host "`n$($script:fail) check(s) failed. See docs/local-dev.md, Troubleshooting." -ForegroundColor Red; exit 1 }
Write-Host "`nAll checks passed. The environment is ready." -ForegroundColor Green
