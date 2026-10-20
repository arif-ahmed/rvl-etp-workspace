# Seeds Floci with the AWS resources the ETP backend expects, then prints the values to put into
# each service's `dotnet user-secrets`. Idempotent for S3/SQS; Cognito pools are created each run
# (reset with: docker compose down -v).
#
# Usage:  docker compose up -d ; ./seed.ps1

$ErrorActionPreference = 'Stop'

$env:AWS_ENDPOINT_URL      = 'http://localhost:4566'
$env:AWS_REGION            = 'ap-southeast-1'
$env:AWS_ACCESS_KEY_ID     = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'

$bucket = 'etp-local'
$queues = @('OrderSuccess', 'EventCapacity', 'FirebaseNotification', 'TicketProcessing')   # AWS:Queue:* (names, not URLs: the code calls GetQueueUrl)
$pools  = @('Admin', 'User', 'TicketChecker', 'Agent')                                       # AWS:CognitoPool:*

# S3
aws s3api create-bucket --bucket $bucket --create-bucket-configuration LocationConstraint=$env:AWS_REGION 2>$null | Out-Null
Write-Host "S3 bucket: $bucket"

# SQS
foreach ($q in $queues) {
    aws sqs create-queue --queue-name $q | Out-Null
    Write-Host "SQS queue: $q"
}

# SES (sender identity used by Admin / Ticketing email)
aws ses verify-email-identity --email-address noreply@etp.local | Out-Null
Write-Host 'SES identity: noreply@etp.local'

# Cognito: one pool + app client per role
$secrets = [ordered]@{}
foreach ($p in $pools) {
    $poolId = aws cognito-idp create-user-pool --pool-name "etp-$($p.ToLower())" --query 'UserPool.Id' --output text
    $clientId = aws cognito-idp create-user-pool-client --user-pool-id $poolId --client-name "etp-$($p.ToLower())-client" `
        --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH ALLOW_ADMIN_USER_PASSWORD_AUTH `
        --query 'UserPoolClient.ClientId' --output text
    $secrets[$p] = @{ PoolId = $poolId; ClientId = $clientId }
}

Write-Host "`n--- user-secrets values (set per service) ---"
Write-Host "AWS:Region                = $env:AWS_REGION"
Write-Host "AWS:AccessKey             = test"
Write-Host "AWS:SecretAccessKey       = test"
Write-Host "AWS:Bucket:Name           = $bucket"
Write-Host "AWS:Bucket:BaseUrl        = http://localhost:4566   (code sets S3 ServiceURL from this)"
foreach ($q in $queues) { Write-Host ("AWS:Queue:{0,-20} = {0}" -f $q) }
foreach ($p in $pools) {
    $s = $secrets[$p]
    Write-Host "AWS:CognitoPool:$p:PoolId   = $($s.PoolId)"
    Write-Host "AWS:CognitoPool:$p:ClientId = $($s.ClientId)"
    Write-Host "AWS:CognitoPool:$p:Authority/Metadata = check Floci docs for the issuer/JWKS URL of this pool"
}
