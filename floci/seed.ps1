# Seeds Floci (local AWS emulator) with the non-Cognito resources the ETP backend expects:
# S3 bucket, SQS queues, SES sender identity. Idempotent; prints the values to put into
# each service's `dotnet user-secrets`.
# Cognito pools/clients/users come from ./seed-users.ps1 (the custom attribute schema must be
# defined at pool creation, so that script owns Cognito end to end).
#
# Usage:  docker compose up -d ; ./seed.ps1 ; ./seed-users.ps1

$ErrorActionPreference = 'Stop'

$env:AWS_ENDPOINT_URL      = 'http://localhost:4566'
$env:AWS_REGION            = 'ap-southeast-1'
$env:AWS_ACCESS_KEY_ID     = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'

$bucket = 'etp-local'
$queues = @('OrderSuccess', 'EventCapacity', 'FirebaseNotification', 'TicketProcessing', 'VatChallanProcessing', 'TicketSigning')   # AWS:Queue:* (names, not URLs: the code calls GetQueueUrl)

# S3
# Any region other than us-east-1 requires a LocationConstraint matching the region; already existing is fine
aws s3api create-bucket --bucket $bucket --create-bucket-configuration "LocationConstraint=$env:AWS_REGION" 2>$null | Out-Null
aws s3api head-bucket --bucket $bucket 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not create the S3 bucket '$bucket' in Floci ($env:AWS_ENDPOINT_URL, region $env:AWS_REGION)" }
Write-Host "S3 bucket: $bucket"

# SQS
foreach ($q in $queues) {
    aws sqs create-queue --queue-name $q | Out-Null
    Write-Host "SQS queue: $q"
}

# SES (sender identity used by Admin / Ticketing email)
aws ses verify-email-identity --email-address noreply@etp.local | Out-Null
Write-Host 'SES identity: noreply@etp.local'

# Cognito is seeded by ./seed-users.ps1 (pools, app clients, users with the custom attribute schema).

Write-Host "`n--- user-secrets values (set per service) ---"
Write-Host "AWS:Region                = $env:AWS_REGION"
Write-Host "AWS:AccessKey             = test"
Write-Host "AWS:SecretAccessKey       = test"
Write-Host "AWS:Bucket:Name           = $bucket"
Write-Host "AWS:Bucket:BaseUrl        = http://localhost:4566   (code sets S3 ServiceURL from this)"
foreach ($q in $queues) { Write-Host ("AWS:Queue:{0,-20} = {0}" -f $q) }
Write-Host 'Cognito (Admin/User/TicketChecker/Agent pools + users): run ./seed-users.ps1'
