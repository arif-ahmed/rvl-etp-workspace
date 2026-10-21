# Seeds Cognito for local dev against Floci (fake AWS): all four user pools the backend expects
# (Admin, User, TicketChecker, Agent), each with the custom attributes the backend reads
# (custom:role, custom:program_ids), one app client per pool ('etp-local'), and one user per role.
# Roles match rvl-gobcb-backend ETP.Core.Constant.AppConstant.Role; the backend uses the phone
# number as the Cognito username and reads custom:role / custom:program_ids (see
# CognitoUserAttributesMiddleware).
#
# The custom attribute schema must be defined at pool creation (real Cognito rule), so this script
# is the single owner of Cognito; seed.ps1 only covers S3/SQS/SES.
# Idempotent: reuses pools/clients, skips users that already exist.
#
# Usage:  ./seed-users.ps1            (prints PoolId / ClientId per pool for user-secrets)

$ErrorActionPreference = 'Stop'

$env:AWS_ENDPOINT_URL      = 'http://localhost:4566'
$env:AWS_REGION            = 'us-east-1'
$env:AWS_ACCESS_KEY_ID     = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_PAGER             = ''

$password   = 'Passw0rd!23'
$clientName = 'etp-local'

$pools = [ordered]@{
    Admin = @(
        @{ Phone = '+8801700000001'; Name = 'Local Admin';         Email = 'admin@etp.local';    Role = 'admin';            Programs = $null }
        @{ Phone = '+8801700000002'; Name = 'Event Manager';       Email = 'eventmgr@etp.local'; Role = 'event_manager';    Programs = '1,2' }
        @{ Phone = '+8801700000003'; Name = 'Ticket Manager';      Email = 'ticketmgr@etp.local'; Role = 'ticket_manager';  Programs = '1,2' }
        @{ Phone = '+8801700000004'; Name = 'BCB Ticket Operator'; Email = 'operator@etp.local'; Role = 'ticket_operator'; Programs = '1' }
        @{ Phone = '+8801700000005'; Name = 'Customer Support';    Email = 'support@etp.local';  Role = 'customer_support'; Programs = $null }
    )
    User = @(
        @{ Phone = '+8801700000011'; Name = 'Local User';           Email = 'user@etp.local';     Role = 'user';             Programs = '1,2' }
    )
    TicketChecker = @(
        @{ Phone = '+8801700000021'; Name = 'Local Ticket Checker'; Email = 'checker@etp.local';  Role = 'ticket-checker';   Programs = $null }
    )
    Agent = @(
        @{ Phone = '+8801700000031'; Name = 'Local Agent';          Email = 'agent@etp.local';    Role = 'agent';            Programs = $null }
    )
}

$poolSecrets = [ordered]@{}
foreach ($p in $pools.Keys) {
    $poolName = "etp-$($p.ToLower())"

    $poolId = aws cognito-idp list-user-pools --max-results 60 --query "UserPools[?Name=='$poolName'].Id | [0]" --output text
    if (-not $poolId -or $poolId -eq 'None') {
        $poolId = aws cognito-idp create-user-pool --pool-name $poolName `
            --schema Name=role,AttributeDataType=String,Mutable=true Name=program_ids,AttributeDataType=String,Mutable=true `
            --query UserPool.Id --output text
        Write-Host "Created pool $poolName ($poolId)"
    }
    else {
        $schemaNames = aws cognito-idp describe-user-pool --user-pool-id $poolId --query 'UserPool.SchemaAttributes[].Name' --output text
        if ($schemaNames -notmatch 'custom:role' -or $schemaNames -notmatch 'custom:program_ids') {
            Write-Warning "Pool $poolName ($poolId) predates the custom attribute schema. Logins work, but custom:role / custom:program_ids claims will be missing. Fix: docker compose down -v ; docker compose up -d ; ./seed.ps1 ; ./seed-users.ps1"
        }
        Write-Host "Using existing pool $poolName ($poolId)"
    }

    $clientId = aws cognito-idp list-user-pool-clients --user-pool-id $poolId --query "UserPoolClients[?ClientName=='$clientName'].ClientId | [0]" --output text
    if (-not $clientId -or $clientId -eq 'None') {
        $clientId = aws cognito-idp create-user-pool-client --user-pool-id $poolId --client-name $clientName `
            --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_ADMIN_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH `
            --query UserPoolClient.ClientId --output text
    }

    foreach ($u in $pools[$p]) {
        $exists = aws cognito-idp list-users --user-pool-id $poolId --filter "username = `"$($u.Phone)`"" --query 'length(Users)' --output text
        if ($exists -ne '0') { Write-Host "  Skip (exists): $($u.Phone) ($($u.Role))"; continue }

        $attrs = @(
            "Name=phone_number,Value=$($u.Phone)", "Name=name,Value=$($u.Name)", "Name=email,Value=$($u.Email)",
            "Name=custom:role,Value=$($u.Role)", 'Name=email_verified,Value=true', 'Name=phone_number_verified,Value=true'
        )
        if ($u.Programs) { $attrs += "Name=custom:program_ids,Value='$($u.Programs)'" }   # quotes stop the CLI splitting on the comma

        aws cognito-idp admin-create-user --user-pool-id $poolId --username $u.Phone --message-action SUPPRESS --user-attributes @attrs | Out-Null
        aws cognito-idp admin-set-user-password --user-pool-id $poolId --username $u.Phone --password $password --permanent
        Write-Host "  Created $($u.Phone) ($($u.Role))"
    }

    $poolSecrets[$p] = @{ PoolId = $poolId; ClientId = $clientId }
}

Write-Host "`n--- user-secrets values (set per service) ---"
Write-Host "AWS:Region                = $($env:AWS_REGION)"
Write-Host "AWS:AccessKey             = test"
Write-Host "AWS:SecretAccessKey       = test"
Write-Host "AWS:Bucket:Name           = etp-local"
Write-Host "AWS:Bucket:BaseUrl        = http://localhost:4566"
foreach ($p in $poolSecrets.Keys) {
    $s = $poolSecrets[$p]
    Write-Host "AWS:CognitoPool:$p:PoolId   = $($s.PoolId)"
    Write-Host "AWS:CognitoPool:$p:ClientId = $($s.ClientId)"
    Write-Host "AWS:CognitoPool:$p:Authority = https://localhost:4567/$($s.PoolId)"
    Write-Host "AWS:CognitoPool:$p:Metadata  = https://localhost:4567/$($s.PoolId)/.well-known/openid-configuration"
}

Write-Host "`nUsers (username = phone, password '$password'):"
foreach ($p in $poolSecrets.Keys) {
    Write-Host ("  {0}: {1}" -f $p, (($pools[$p] | ForEach-Object { "$($_.Phone) = $($_.Role)" }) -join ', '))
}
