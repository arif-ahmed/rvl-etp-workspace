# ETP local dev — quickstart

Fake AWS (Floci) so no real AWS is needed. Two things run the whole show:

| Script | Creates |
|---|---|
| `seed.ps1` | S3 bucket, 4 SQS queues, SES identity |
| `seed-users.ps1` | All 4 Cognito pools + clients + test users, then prints PoolId/ClientId |

## 1. Start Floci
```powershell
cd floci
docker compose up -d          # console: http://localhost:4500
```

## 2. Seed
```powershell
./seed.ps1
./seed-users.ps1              # copy PoolId/ClientId from the output
```

## 3. Test users
Password `Passw0rd!23`, username = phone:

| Pool | Phone | Role |
|---|---|---|
| Admin | `+8801700000001`–`...005` | admin, event_manager, ticket_manager, ticket_operator, customer_support |
| User | `+8801700000011` | user |
| TicketChecker | `+8801700000021` | ticket-checker |
| Agent | `+8801700000031` | agent |

## 4. Point services at Floci (per service project folder)
```powershell
dotnet user-secrets set "AWS:Region" "ap-southeast-1"
dotnet user-secrets set "AWS:AccessKey" "test"
dotnet user-secrets set "AWS:SecretAccessKey" "test"
dotnet user-secrets set "AWS:Bucket:Name" "etp-local"
dotnet user-secrets set "AWS:Bucket:BaseUrl" "http://localhost:4566"
# per pool (Admin / User / TicketChecker / Agent), values from step 2:
dotnet user-secrets set "AWS:CognitoPool:Admin:PoolId"    "<pool id>"
dotnet user-secrets set "AWS:CognitoPool:Admin:ClientId"  "<client id>"
dotnet user-secrets set "AWS:CognitoPool:Admin:Authority" "http://localhost:4566/<pool id>"
dotnet user-secrets set "AWS:CognitoPool:Admin:Metadata"  "http://localhost:4566/<pool id>/.well-known/openid-configuration"
```
Before starting services: `$env:AWS_ENDPOINT_URL = "http://localhost:4566"`.

## 5. Run the backend
```powershell
cd ..\aspire
dotnet run --project Etp.AppHost      # Admin on http://localhost:5101
```

## 6. Postman
Import `postman/etp-local-floci.postman_environment.json` + `etp-cognito-auth.postman_collection.json`,
select the `ETP Local - Floci` environment, run folders **00 → 01 → 02 → 03 → 04** in order.
Folder 00 auto-fills the Admin pool ids; folder 04 calls the real Admin service (`:5101`).

## Fix it fast
| Symptom | Fix |
|---|---|
| Every request 401 | Secret PoolId/ClientId are stale → re-set from step 2 output |
| Missing role/program claims | Pool predates the schema → reset below, re-seed |
| Connection refused :4566 | `docker compose up -d` |
| Queue/S3 missing | Re-run `./seed.ps1` |

## Reset (fresh state)
```powershell
docker compose down -v
docker compose up -d
./seed.ps1
./seed-users.ps1          # then update step 4 secrets (ids change) + Postman env
```
