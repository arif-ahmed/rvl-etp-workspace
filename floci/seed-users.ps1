# Creates the Admin Cognito pool (custom attributes defined at creation), an app client, and one user per
# staff role. Roles match rvl-gobcb-backend ETP.Core.Constant.AppConstant.Role; the backend uses the phone
# number as the Cognito username and reads custom:role / custom:program_ids.
#
# Usage:  ./seed-users.ps1            (prints PoolId / ClientId for user-secrets)

$ErrorActionPreference = 'Stop'

$env:AWS_ENDPOINT_URL      = 'http://localhost:4566'
$env:AWS_REGION            = 'ap-southeast-1'
$env:AWS_ACCESS_KEY_ID     = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_PAGER             = ''

$poolName = 'etp-admin'
$password = 'Passw0rd!23'

$users = @(
    @{ Phone = '+8801700000001'; Name = 'Local Admin';         Email = 'admin@etp.local';    Role = 'admin';            Programs = $null }
    @{ Phone = '+8801700000002'; Name = 'Event Manager';       Email = 'eventmgr@etp.local'; Role = 'event_manager';    Programs = '1,2' }
    @{ Phone = '+8801700000003'; Name = 'Ticket Manager';      Email = 'ticketmgr@etp.local'; Role = 'ticket_manager';  Programs = '1,2' }
    @{ Phone = '+8801700000004'; Name = 'BCB Ticket Operator'; Email = 'operator@etp.local'; Role = 'ticket_operator'; Programs = '1' }
    @{ Phone = '+8801700000005'; Name = 'Customer Support';    Email = 'support@etp.local';  Role = 'customer_support'; Programs = $null }
)

$poolId = aws cognito-idp list-user-pools --max-results 60 --query "UserPools[?Name=='$poolName'].Id | [0]" --output text
if (-not $poolId -or $poolId -eq 'None') {
    $poolId = aws cognito-idp create-user-pool --pool-name $poolName `
        --schema Name=role,AttributeDataType=String,Mutable=true Name=program_ids,AttributeDataType=String,Mutable=true `
        --query UserPool.Id --output text
    Write-Host "Created pool $poolId"
} else {
    Write-Host "Using existing pool $poolId"
}

$clientId = aws cognito-idp list-user-pool-clients --user-pool-id $poolId --query "UserPoolClients[?ClientName=='etp-local'].ClientId | [0]" --output text
if (-not $clientId -or $clientId -eq 'None') {
    $clientId = aws cognito-idp create-user-pool-client --user-pool-id $poolId --client-name etp-local `
        --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_ADMIN_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH `
        --query UserPoolClient.ClientId --output text
}

foreach ($u in $users) {
    $exists = aws cognito-idp list-users --user-pool-id $poolId --filter "username = `"$($u.Phone)`"" --query 'length(Users)' --output text
    if ($exists -ne '0') { Write-Host "Skip (exists): $($u.Phone)"; continue }

    $attrs = @(
        "Name=phone_number,Value=$($u.Phone)", "Name=name,Value=$($u.Name)", "Name=email,Value=$($u.Email)",
        "Name=custom:role,Value=$($u.Role)", 'Name=email_verified,Value=true', 'Name=phone_number_verified,Value=true'
    )
    if ($u.Programs) { $attrs += "Name=custom:program_ids,Value='$($u.Programs)'" }   # quotes stop the CLI splitting on the comma

    aws cognito-idp admin-create-user --user-pool-id $poolId --username $u.Phone --message-action SUPPRESS --user-attributes @attrs | Out-Null
    aws cognito-idp admin-set-user-password --user-pool-id $poolId --username $u.Phone --password $password --permanent
    Write-Host "Created $($u.Phone) ($($u.Role))"
}

Write-Host "`n--- user-secrets (Admin pool) ---"
Write-Host "AWS:CognitoPool:Admin:PoolId    = $poolId"
Write-Host "AWS:CognitoPool:Admin:ClientId  = $clientId"
Write-Host "AWS:CognitoPool:Admin:Authority = http://localhost:4566/$poolId"
Write-Host "AWS:CognitoPool:Admin:Metadata  = http://localhost:4566/$poolId/.well-known/openid-configuration"
Write-Host "Users: password '$password', usernames are the phone numbers above"
