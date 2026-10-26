# rvl-etp-workspace

Orchestrator repo for the ETP (Event Ticketing Platform) system. It pins the 5 product repos as
git submodules and holds all local-development glue (Aspire, Floci, Postman, helper scripts).
This README is the single guide for setting up and running the local environment.

> The submodules are **stable code**. All wiring, ports, emulation and docs live here, so none of
> the 5 repos need to be modified for local development.

> **Quick start:** see [docs/local-dev.md](docs/local-dev.md) (setup, run, debug, teardown on one page). This README is the detailed reference.

## Contents

1. [What you get](#1-what-you-get)
2. [Repository layout](#2-repository-layout)
3. [Prerequisites](#3-prerequisites)
4. [First-time setup](#4-first-time-setup)
5. [Daily workflow](#5-daily-workflow)
6. [Services and ports](#6-services-and-ports)
7. [Floci: local AWS emulation](#7-floci-local-aws-emulation)
8. [Service configuration (user secrets)](#8-service-configuration-user-secrets)
9. [Working with the backend](#9-working-with-the-backend) (debugging, database, protected APIs)
10. [Postman: Cognito and auth tests](#10-postman-cognito-and-auth-tests)
11. [Submodule workflow](#11-submodule-workflow)
12. [Troubleshooting](#12-troubleshooting)
13. [Reset and teardown](#13-reset-and-teardown)
14. [Running without Aspire](#14-running-without-aspire)
15. [Known backend issues](#15-known-backend-issues)

---

## 1. What you get

| Piece | Where | What it does |
|---|---|---|
| Backend, 11 .NET services | `rvl-gobcb-backend` (submodule) | Run with one command through .NET Aspire |
| Postgres, Redis, DynamoDB Local | started by Aspire | Shared `etp` database, cache and locks |
| Local AWS (S3, SQS, SES, Cognito) | `floci/` | Floci emulator, so no real AWS keys are needed |
| API tests | `postman/` | Cognito login and auth collection |

Six rules that save time:

1. **All services share one PostgreSQL database** (`etp`, one schema per bounded context).
2. **Migrations run automatically at service startup.** Admin owns the core tables; Aspire starts everything and the services wait for Postgres.
3. **No Redis, no service.** Redis is used for cache and distributed locks.
4. **Config comes from env vars (set by Aspire) plus user secrets.** The repo's `appsettings.json` only contains `"[see User Secrets]"`.
5. **Login is AWS Cognito.** Protected endpoints need a Cognito token; `/health` and `[AllowAnonymous]` endpoints do not.
6. **Never point a local service at the shared dev DB or dev SQS queues.** Your branch's migrations would run against the shared DB and your local worker would consume the dev environment's messages.

## 2. Repository layout

| Path | Contents |
|---|---|
| `rvl-gobcb-backend/` | backend microservices (11 .NET services), git submodule |
| `rvl-gobcb-admin-portal/` | Angular admin portal, git submodule |
| `rvl-gobcb-user-portal/` | Angular user portal, git submodule |
| `rvl-gobcb-user-app/` | user mobile app, git submodule |
| `rvl-gobcb-checker-app/` | ticket checker mobile app, git submodule |
| `aspire/Etp.AppHost/` | .NET Aspire AppHost that runs the whole backend (all wiring is in `AppHost.cs`) |
| `floci/` | `nginx.conf` for the Floci HTTPS proxy (the containers themselves are defined in the AppHost; seed scripts are in `scripts/`) |
| `postman/` | Postman collection and environment |
| `status.ps1` | shows submodule pins vs. remote `main` |

## 3. Prerequisites

| Tool | Why | Install |
|---|---|---|
| Git | clone | `winget install Git.Git` |
| .NET SDK 10 | builds/runs the AppHost | `winget install Microsoft.DotNet.SDK.10` |
| .NET SDK 8 | builds/runs the services (`net8.0`) | `winget install Microsoft.DotNet.SDK.8` |
| Docker Desktop | Postgres, Redis, DynamoDB Local, Floci | `winget install Docker.DockerDesktop`, enable the WSL 2 engine |
| PowerShell 7 | seed scripts | `winget install Microsoft.PowerShell` |
| AWS CLI v2 | talk to Floci | `winget install Amazon.AWSCLI` |
| IDE | debugging | Visual Studio 2022 17.8+ or VS Code with C# Dev Kit |
| dotnet-ef 8.0.11 (optional) | create migrations | `dotnet tool install --global dotnet-ef --version 8.0.11` |
| Postman or Bruno, DBeaver (optional) | API tests, browse the DB | |

Check in a new terminal:

```powershell
dotnet --list-runtimes   # Microsoft.AspNetCore.App 8.0.x must be listed
pwsh --version           # 7.x
docker version           # the Server section must be present (Docker Desktop running)
```

If an existing global dotnet-ef 9/10 fails with `Could not load ... System.Runtime, Version=10.0.0.0`,
install 8.0.11 side by side: `dotnet tool install dotnet-ef --version 8.0.11 --tool-path "$env:USERPROFILE\.etp-local\tools"`.

## 4. First-time setup

About 30 to 45 minutes, mostly downloads.

### 4.1 Clone with submodules

```powershell
git clone --recurse-submodules https://github.com/Relief-Validation/rvl-etp-workspace.git
cd rvl-etp-workspace
# already cloned without submodules:
git submodule update --init
git config submodule.recurse true     # recommended: pull/checkout move submodules too
```

### 4.2 Start the infrastructure (PostgreSQL, Redis, DynamoDB, Floci)

The AppHost starts the infrastructure containers itself and seeds Floci on every start, so there is no separate
infra step. Once per machine, create the certificate for the Floci HTTPS proxy:

```powershell
pwsh ./scripts/Setup-EtpHttps.ps1          # once: certificate for the HTTPS proxy
$env:ETP_INFRA_ONLY = 'true'; dotnet run --project aspire/Etp.AppHost
# starts infra and seeds Floci (bucket, queues, SES, Cognito pools + users) but no services; Ctrl+C once
# seed-floci and seed-cognito show Finished in the dashboard (the containers keep running)
Remove-Item Env:ETP_INFRA_ONLY
```

(The services need the Cognito IDs from step 4.3 before they can start, hence infra only for now. With Floci up you can also run
`pwsh ./scripts/Seed-EtpFloci.ps1` and `pwsh ./scripts/Seed-EtpCognitoUsers.ps1` by hand; both are idempotent.)

Copy the output of both scripts (also visible in the `seed-*` console logs in the dashboard): they print the Cognito `PoolId` / `ClientId` (and for Admin, `Authority` / `Metadata`) values you need in step 4.3.
`Seed-EtpCognitoUsers.ps1` is what makes login work for the Admin service and the Postman collection ([section 10](#10-postman-cognito-and-auth-tests));
for the Admin pool, use the values it prints rather than the ones from `Seed-EtpFloci.ps1`.
Details in [section 7](#7-floci-local-aws-emulation).

### 4.3 Set the service configuration

Follow [section 8](#8-service-configuration-user-secrets): write your `user-secrets.json` and apply it to the services.
Aspire provides the database, Redis and service URLs; user secrets provide AWS, Cognito and everything else.

### 4.4 Run the backend

```powershell
dotnet run --project aspire/Etp.AppHost
```

1. The console prints a dashboard URL with a login token (the port is dynamic). Open it.
2. The first start takes a minute or two: Docker pulls images and the 11 services build.
3. Wait until every resource shows **Running** (green). Console logs, structured logs and traces are per resource.

You can also open `aspire/Etp.AppHost` in your IDE and run it with the `http` profile.

### 4.5 Verify

```powershell
curl http://localhost:5103/health     # Event; repeat for 5101-5111
docker exec <postgres-container> psql -U postgres -d etp -tAc 'select count(*) from etp."__EFMigrationsHistory";'
```

(Find the container name with `docker ps`; Postgres user is `postgres`, password `etp-local-pg`.)
Once all services are up, the total migration count should be 129 (Admin 81, plus Logging, Booking, Ticketing, PushNotification, UserIssue).

Then try one real call through to the database, no auth needed:

```powershell
curl http://localhost:5103/event/api/v1/landing-page-image/public     # [] on a fresh DB
```

The pieces to exercise end to end: one S3 upload, one SQS message, one Cognito login ([section 7](#7-floci-local-aws-emulation) and [section 10](#10-postman-cognito-and-auth-tests)).

## 5. Daily workflow

**Morning**

```powershell
git pull                              # then: git submodule update --init  (if pins moved)
dotnet run --project aspire/Etp.AppHost
```

Start Floci before the AppHost. Floci data lives in the `etp-floci-data` volume, so you normally do not re-run `Seed-EtpFloci.ps1`.
If `aws sqs list-queues` shows nothing, the data was lost: re-seed.

New migrations pulled from others need no action; the owning service applies them on startup.

**During the day**

| Need | Command |
|---|---|
| List buckets | `aws --endpoint-url http://localhost:4566 s3 ls` |
| List objects | `aws --endpoint-url http://localhost:4566 s3 ls s3://etp-local --recursive` |
| List queues | `aws --endpoint-url http://localhost:4566 sqs list-queues` |
| Peek at a queue | `aws --endpoint-url http://localhost:4566 sqs receive-message --queue-url <url>` |
| Purge a queue | `aws --endpoint-url http://localhost:4566 sqs purge-queue --queue-url <url>` |
| Floci logs | `docker logs -f etp-floci` (or the `floci` resource in the Aspire dashboard) |

Tip: put `AWS_ENDPOINT_URL=http://localhost:4566`, `AWS_REGION=us-east-1` and the `test`/`test` credentials in your
shell profile for dev sessions so you can drop `--endpoint-url`.

**Which services do I need?** The AppHost starts all 11. For lighter runs, comment services out of the `defs` list in `AppHost.cs`
(keep Admin) based on the task:

| Task | Run |
|---|---|
| Admin portal features (events, venues, programs, users) | Admin, Event |
| Booking / order / payment flow | Admin, Event, Booking, Ticketing |
| Ticket generation / PDF | Admin, Booking, Event, Ticketing |
| Ticket check at the gate | Admin, Ticketing, TicketChecker |
| User issues / chat | Admin, UserIssue, Booking, Ticketing |
| Push notifications / scheduled jobs | Admin, Booking, Ticketing, Scheduler, PushNotification |
| Ticket processing / merge | Admin, Booking, Ticketing, Utility |

**End of day**

- Stop the AppHost with `Ctrl+C` (or the stop button in the dashboard). Do not force-kill it; that can leave containers behind.
- The infra containers stay up on purpose (data kept). To stop them too: `docker stop etp-postgres etp-redis etp-dynamodb etp-floci etp-floci-tls etp-floci-ui`.

## 6. Services and ports

Ports are fixed because services call each other through `Services__*` URLs. The `launchSettings.json` ports are not used
(they collide, for example Scheduler and Utility both use 5033).

| Service | Port | Purpose | Calls |
|---|---|---|---|
| Admin | 5101 | events, venues, programs, users; **owns DB migrations** | Booking, Event, Ticketing, UserIssue, PushNotification |
| Booking | 5102 | seat reservation, orders, payment | Admin, Event, Ticketing |
| Event | 5103 | public event and venue info | Admin, Booking |
| Platform | 5104 | near-empty stub | |
| PushNotification | 5105 | device tokens | |
| Scheduler | 5106 | background jobs, notifications | Admin, Booking, Ticketing |
| TicketChecker | 5107 | gate ticket validation | Admin, Ticketing |
| Ticketing | 5108 | ticket generation, PDF, signing | Admin, Booking, Event |
| UserAuth | 5109 | near-empty stub | |
| UserIssue | 5110 | user issues, chat | Booking, Ticketing |
| Utility | 5111 | ticket processing / merge | Admin, Booking, Ticketing |

Health check: `GET /health` on each port. Swagger lives under the service prefix, for example
`http://localhost:5101/admin/swagger`, `http://localhost:5103/event/swagger`
(prefixes: `admin`, `event`, `booking`, `ticketing`, `ticketchecker`, `scheduler`, `utility`, `pushnotification`, `userissue`).
If a launch URL 404s, type `/<prefix>/swagger` yourself.

Infrastructure started by the AppHost:

| Resource | Details |
|---|---|
| Postgres | container `etp-postgres`, database `etp_local`, user `etp`, password `etp_local_pw`, volume `etp-local_etp-pgdata` |
| Redis | container `etp-redis`, no password, no TLS, volume `etp-local_etp-redis-data` |
| DynamoDB Local | port 8000 (Ticketing hard-codes it) |

Redis is passwordless on purpose: `ETP.Core` `CacheConfig` only forwards `host:port` to the DataProtection multiplexer.

## 7. Floci: local AWS emulation

[Floci](https://floci.io/aws/) is a single-container AWS emulator (port 4566). It stands in for real S3, SQS, SES and Cognito.
It is standalone and does not depend on the Aspire AppHost.

> The AppHost wiring and seed script have not been verified against a live Floci yet. Where this README says "confirm",
> check the Floci docs for your image version.

| Resource | Name(s) |
|---|---|
| S3 bucket | `etp-local` |
| SQS queues | `OrderSuccess`, `EventCapacity`, `FirebaseNotification`, `TicketProcessing`; **also needed but not yet created by `Seed-EtpFloci.ps1`:** `VatChallanProcessing`, `TicketSigning` |
| SES identity | `noreply@etp.local` |
| Cognito pools | `Admin`, `User`, `TicketChecker`, `Agent` (each with one app client) |
| Region | `us-east-1` (not the production region on purpose, see [docs/local-dev.md](docs/local-dev.md)) |
| Credentials | any value works; we use `test` / `test` |

DynamoDB is not on Floci; Aspire provides DynamoDB Local on port 8000.

The AppHost also starts the Floci containers, pinned to fixed versions in `aspire/Etp.AppHost/AppHost.cs`:

| Container | URL |
|---|---|
| `etp-floci` (emulator) | http://localhost:4566 |
| `etp-floci-ui` (web console) | http://localhost:4500 |

The console talks to Floci at `http://floci:4566` on the container network and no Docker socket is mounted, so the
"Open Floci UI" button on the 4566 dashboard does not work. Open http://localhost:4500 directly.

Quick check: `aws --endpoint-url http://localhost:4566 s3 ls` (set `AWS_ACCESS_KEY_ID=test` and `AWS_SECRET_ACCESS_KEY=test` first if the CLI complains).

### Pointing the services at Floci

1. Put the Floci values in your user secrets ([section 8](#8-service-configuration-user-secrets), the template already uses them).
2. Make the AWS SDK use Floci for SQS / SES / Cognito (the code sets no endpoint for these). Set this in the shell that starts the AppHost:

   ```powershell
   $env:AWS_ENDPOINT_URL = "http://localhost:4566"
   ```

   Or add `.WithEnvironment("AWS_ENDPOINT_URL", "http://localhost:4566")` in the service loop of `aspire/Etp.AppHost/AppHost.cs`.
   Confirm your AWSSDK version honours `AWS_ENDPOINT_URL`; if SQS calls still go to real AWS, upgrade the SDK or add a `ServiceURL` in the client config.
3. `AWS:Bucket:BaseUrl` is used by the code as the S3 `ServiceURL`, so it must be `http://localhost:4566`.
   Queue secrets must be queue **names**, not URLs (the code calls `GetQueueUrl`).

### Known gaps

- `Seed-EtpFloci.ps1` creates plain pools. Only the Admin pool made by `Seed-EtpCognitoUsers.ps1` has the custom attributes (`custom:role`, `custom:program_ids`) the backend reads; User, TicketChecker and Agent pools have none, and no users.
- Both scripts create a pool named `etp-admin`, and `Seed-EtpCognitoUsers.ps1` reuses the first pool with that name. If it picks the one from `Seed-EtpFloci.ps1` (no custom attributes), the Postman custom-attribute checks fail. Not verified; if you see that, `docker compose down -v` and run `./seed-users.ps1` before `./seed.ps1`.
- `Seed-EtpFloci.ps1` creates new pools on every run (S3 and SQS are idempotent). Run it once per fresh Floci volume.
- The Admin `Authority` / `Metadata` URLs (`http://localhost:4566/<poolId>` and `.../.well-known/openid-configuration`) come from `Seed-EtpCognitoUsers.ps1` and are unconfirmed against the Floci docs. For the other pools the URL pattern is presumably the same, unconfirmed.
- Firebase push notifications and the DgePay payment gateway are not AWS, so Floci does not cover them.
- The advertised service count is not a fidelity guarantee. Verify Cognito token claims and IAM rather than assuming them.

## 8. Service configuration (user secrets)

Aspire injects `ConnectionStrings__*`, `Services__*`, `Cache__Redis__*` and `DistributedLock__Redis__*`.
Everything else (JWT, AWS, Cognito, payment, TSP...) comes from each service's **user secrets**, which live outside the repo
(`%APPDATA%\Microsoft\UserSecrets\<UserSecretsId>\secrets.json`, loaded only in `Development`). In Visual Studio you can also
right-click a project, **Manage User Secrets**.

Keep one personal config file outside every repo, then apply it to all services. Never commit real keys; keep a backup in a password manager.

### 8.1 Create `%USERPROFILE%\.etp-local\user-secrets.json`

The values below target Floci. The `REPLACE_WITH_*` values for Cognito come from `Seed-EtpFloci.ps1` output, and for the Admin pool from
`Seed-EtpCognitoUsers.ps1` output, which also prints the `Authority` and `Metadata` URLs (`http://localhost:4566/<poolId>` and
`http://localhost:4566/<poolId>/.well-known/openid-configuration`; use the same pattern for the other pools). If you use a real dev pool, get the values from the team lead. Dummy values are fine for everything else; health, Swagger and
anonymous APIs work without real keys.

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.etp-local" | Out-Null
notepad "$env:USERPROFILE\.etp-local\user-secrets.json"     # paste the JSON below, save
```

```json
{
  "Authentication": {
    "Jwt": {
      "Key": "local-dev-only-signing-key-change-me-0123456789abcdef",
      "Issuer": "etp-local",
      "Audience": "etp-local-services"
    },
    "ServiceApiKey": "local-dev-service-api-key",
    "TokenIssuer": "http://localhost:5101/admin/api/v1/token",
    "Authority": "etp-local",
    "Audience": "etp-local-services",
    "ClientSecret": "local-dev-only-signing-key-change-me-0123456789abcdef"
  },
  "AWS": {
    "Region": "us-east-1",
    "AccessKey": "test",
    "SecretAccessKey": "test",
    "Bucket": { "Name": "etp-local", "BaseUrl": "http://localhost:4566" },
    "Ticket": {
      "Bucket": { "Name": "etp-local", "BaseUrl": "http://localhost:4566" },
      "TemplateBase": "templates/",
      "BlankBase": "blank/",
      "SignedBase": "signed/",
      "ShareBase": "share/",
      "MergeBase": "merge/",
      "MergeBuffer": "10",
      "MergeSize": "50",
      "ShareExpiryMinutes": "60",
      "EmailSender": "noreply@etp.local"
    },
    "Queue": {
      "OrderSuccess": "OrderSuccess",
      "EventCapacity": "EventCapacity",
      "FirebaseNotification": "FirebaseNotification",
      "TicketProcessing": "TicketProcessing",
      "VatChallanProcessing": "VatChallanProcessing",
      "TicketSigning": "TicketSigning"
    },
    "CognitoPool": {
      "Admin": {
        "PoolId": "REPLACE_WITH_SEED_OUTPUT",
        "ClientId": "REPLACE_WITH_SEED_OUTPUT",
        "Authority": "REPLACE_WITH_FLOCI_ISSUER_URL",
        "Metadata": "REPLACE_WITH_FLOCI_OIDC_METADATA_URL"
      },
      "User": {
        "PoolId": "REPLACE_WITH_SEED_OUTPUT",
        "ClientId": "REPLACE_WITH_SEED_OUTPUT",
        "Authority": "REPLACE_WITH_FLOCI_ISSUER_URL",
        "Metadata": "REPLACE_WITH_FLOCI_OIDC_METADATA_URL"
      },
      "TicketChecker": {
        "PoolId": "REPLACE_WITH_SEED_OUTPUT",
        "ClientId": "REPLACE_WITH_SEED_OUTPUT",
        "Authority": "REPLACE_WITH_FLOCI_ISSUER_URL",
        "Metadata": "REPLACE_WITH_FLOCI_OIDC_METADATA_URL"
      },
      "Agent": {
        "PoolId": "REPLACE_WITH_SEED_OUTPUT",
        "ClientId": "REPLACE_WITH_SEED_OUTPUT",
        "Authority": "REPLACE_WITH_FLOCI_ISSUER_URL",
        "Metadata": "REPLACE_WITH_FLOCI_OIDC_METADATA_URL"
      }
    }
  },
  "PaymentSettings": {
    "DgePay": {
      "MerchantClientId": "REPLACE_ME",
      "MerchantClientSecret": "REPLACE_ME",
      "MerchantApiKey": "REPLACE_ME",
      "BaseUrl": "https://dgepay-sandbox.invalid/",
      "RedirectUrl": "http://localhost:4200/payment/callback"
    }
  },
  "Notification": { "Endpoint": "https://notification.invalid/", "Authorization": "local-dummy" },
  "Serverless": { "BaseUrl": "https://serverless.invalid/", "Authorization": "local-dummy" },
  "TSP": {
    "AuthUrl": "https://tsp.invalid/auth/",
    "SignUrl": "https://tsp.invalid/sign/",
    "UserId": "REPLACE_ME",
    "DigitalIdentityId": "REPLACE_ME"
  },
  "OneIdSettings": {
    "TokenUrl": "https://oneid.invalid/token",
    "DocumentSyncUrl": "https://oneid.invalid/sync",
    "AuthorizationToken": "REPLACE_ME"
  },
  "CloudfrontTicketValidator": { "BucketName": "REPLACE_ME", "ObjectKey": "REPLACE_ME" },
  "Services": { "AppBase": "http://localhost:5120/" }
}
```

### 8.2 Apply it to every service

Run from the workspace root. Safe to re-run after every edit of the JSON, then restart the services.

```powershell
$json = Get-Content "$env:USERPROFILE\.etp-local\user-secrets.json" -Raw
$null = $json | ConvertFrom-Json        # stops here if the JSON is broken
$projects = Get-ChildItem rvl-gobcb-backend/Services -Recurse -Filter '*.Service.csproj' |
    Where-Object { Select-String -Path $_.FullName -Pattern '<UserSecretsId>' -Quiet }
foreach ($p in $projects) {
    $json | dotnet user-secrets set --project $p.FullName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "user-secrets failed: $($p.Name)" }
    Write-Host "ok  $($p.Name)"
}
# UserIssue has no appsettings.json in the repo, so its Application section comes from here
$ui = ($projects | Where-Object Name -eq 'ETP.UserIssue.Service.csproj').FullName
dotnet user-secrets set 'Application:ServiceName' 'userissue' --project $ui | Out-Null
dotnet user-secrets set 'Application:Title' 'RVL ETP ETicketing - User Issue API' --project $ui | Out-Null
dotnet user-secrets set 'Application:Description' 'API for user issue related utilities' --project $ui | Out-Null
```

Check one: `dotnet user-secrets list --project rvl-gobcb-backend/Services/Admin/ETP.Admin.Service`.

Notes:

- `Services:AppBase` is the only `Services:*` key Aspire does not set, so it lives in the JSON.
- The Floci Cognito pool IDs change on every re-seed; update the JSON, re-apply, restart.
- A real dev AWS key or Cognito pool (instead of Floci) goes into the same JSON. Use your **own** SQS queue names
  (for example `etp-dev-<yourname>-order-success`), never the dev environment's queues.

## 9. Working with the backend

### 9.1 Debugging

Aspire runs each service as a normal `dotnet` process, so attach a debugger to it:

- **Visual Studio:** Debug, Attach to Process (`Ctrl+Alt+P`), pick `ETP.<Name>.Service.exe`.
- **VS Code:** `Ctrl+Shift+P`, **Debug: Attach to a .NET 5+ or .NET Core process**, pick `ETP.<Name>.Service`.
- **Exceptions where they happen (VS):** `Ctrl+Alt+E`, tick *Common Language Runtime Exceptions*.
- **Background workers:** put a breakpoint in the `ExecuteAsync` of `Workers/BackgroundServices/*`; most start about a minute after boot.
- **Service-to-service calls:** attach to both services and breakpoints fire in both.

Quick breakpoint check: open `Services/Event/ETP.Event.Service/Api/LandingPageImageController.cs`, break on
`var result = await siteSettingsManager.GetAllPublishedAsync();`, attach to Event, then call
`GET http://localhost:5103/event/api/v1/landing-page-image/public`.

To iterate on one service with Hot Reload while the rest stay in Aspire, disable that resource in the AppHost and run it
yourself with its fixed port, using the env vars from `AppHost.cs`
(`dotnet watch --project rvl-gobcb-backend/Services/Event/ETP.Event.Service run --urls http://localhost:5103`).

### 9.2 Database

- **Browse:** DBeaver/psql (`docker exec -it etp-postgres psql -U etp -d etp_local`). Database `etp_local`, schema `etp`, user `etp`, password `etp_local_pw`
  (host and port: see the Postgres resource in the dashboard).
- **Test data:** there is no seed data in the code; create events and venues through the Admin API, or restore a sanitized
  dev dump from the team lead:

  ```powershell
  docker cp .\etp_dev_sanitized.dump <postgres-container>:/tmp/etp.dump
  docker exec <postgres-container> pg_restore -U postgres -d etp --clean --if-exists --no-owner /tmp/etp.dump
  ```

- **New migration** (Redis must be running, because `dotnet ef` runs the service's `Program.cs`):

  ```powershell
  dotnet ef migrations add <MigrationName> -p rvl-gobcb-backend/Services/Admin/ETP.Admin.Storage -s rvl-gobcb-backend/Services/Admin/ETP.Admin.Service -c AdminDbContext
  ```

  | DbContext | `-p` (migrations project) | `-s` (startup project) |
  |---|---|---|
  | `AdminDbContext` | `Services/Admin/ETP.Admin.Storage` | `Services/Admin/ETP.Admin.Service` |
  | `LoggingDbContext` | `Core/ETP.Core.EntityFramework` | `Services/Admin/ETP.Admin.Service` |
  | `BookingDbContext` | `Services/Booking/ETP.Booking.Storage` | `Services/Booking/ETP.Booking.Service` |
  | `TicketingDbContext` | `Services/Ticketing/ETP.Ticketing.Storage` | `Services/Ticketing/ETP.Ticketing.Service` |
  | `PushNotificationDbContext` | `Services/PushNotification/ETP.PushNotification.Storage` | `Services/PushNotification/ETP.PushNotification.Service` |
  | `UserIssueDbContext` | `Services/UserIssue/ETP.UserIssue.Storage` | `Services/UserIssue/ETP.UserIssue.Service` |

  `database update` is not needed; services apply migrations on startup. Admin has two contexts, so `-c` is mandatory there.
  Work in the upstream backend repo and bump the pin afterwards ([section 11](#11-submodule-workflow)).

### 9.3 Calling protected APIs

Most endpoints are `[Authorize]`. With Floci, get a token from the seeded pool (the Postman collection does this for you,
[section 10](#10-postman-cognito-and-auth-tests)). With a real dev pool:

```powershell
aws cognito-idp initiate-auth --region us-east-1 --auth-flow USER_PASSWORD_AUTH --client-id <CLIENT_ID> --auth-parameters USERNAME=<user>,PASSWORD=<password>
```

Take the `AccessToken` and paste it (token only) into Swagger's **Authorize** button. Step-by-step token and endpoint testing, with known issues, is in [docs/testing-services.md](docs/testing-services.md). Admin program-scoped endpoints also need the
header `X-Program-Id: <id>`. For service-to-service JWTs:
`GET http://localhost:5101/admin/api/v1/token` with header `ServiceApiKey: local-dev-service-api-key`.

### 9.4 Errors that are normal locally

| Where | Log | Cause |
|---|---|---|
| Booking, Scheduler, Utility, TicketChecker | AWS / SQS / `UnrecognizedClientException` | Floci not running, `AWS_ENDPOINT_URL` not set, or dummy keys |
| Scheduler | `Firebase notification: processing failed` (every minute) | no Firebase config; ignore |
| Ticketing | `CryptographicException: The system cannot find the path specified`, continuously and fast | TSP certificate `tspgw_client.pfx` missing, and the worker has no retry delay. Stop Ticketing if you are not working on it; otherwise get the cert from the team lead and place it at `Services/Ticketing/ETP.Ticketing.Service/bin/Debug/net8.0/Cert/tspgw_client.pfx` (`bin/` is git-ignored) |
| all | `Failed to determine the https port for redirect` | http-only profile; ignore |

### 9.5 Before you commit

- Never edit files inside a submodule from this workspace for local convenience; change ports/config through the AppHost, env vars or user secrets.
- Add specific files, avoid `git add -A`.
- Real keys never go into any file in a repo.
- Before pushing: `git log --oneline origin/<branch>..HEAD`.

## 10. Postman: Cognito and auth tests

Files in `postman/`:

| File | Purpose |
|---|---|
| `etp-cognito-auth.postman_collection.json` | Collection v2.1, 75 requests with test scripts |
| `etp-local-floci.postman_environment.json` | Environment for Floci (`:4566`, issuer `:4567`) and the Admin service (`:5101/admin`) |

### Run

1. Floci is up and `scripts/Seed-EtpCognitoUsers.ps1` has been run. It creates the `etp-admin` pool (with `custom:role` and `custom:program_ids`), the `etp-local` client and 5 staff users, all with password `Passw0rd!23` and the phone number as username:

   | Phone | Role | Programs |
   |---|---|---|
   | +8801700000001 | admin | none |
   | +8801700000002 | event_manager | 1,2 |
   | +8801700000003 | ticket_manager | 1,2 |
   | +8801700000004 | ticket_operator | 1 |
   | +8801700000005 | customer_support | none |

   Re-running it is safe; existing users are skipped.
2. The Admin service is running with the `AWS:CognitoPool:Admin:*` values printed by `Seed-EtpCognitoUsers.ps1` in its user secrets.
3. Import both files into Postman, select the **ETP Local - Floci** environment, and run the collection in order.
   Folder 00 resolves `admin_pool_id`, `admin_client_id` and `admin_authority` itself; folder 01 stores the per-role tokens that later folders use.
4. Optional: set `service_api_key` (secret) to enable folder 07.

CLI: `newman run postman/etp-cognito-auth.postman_collection.json -e postman/etp-local-floci.postman_environment.json`.
On Node 24, `localhost` can fail with "Invalid IP address: undefined"; add
`--env-var floci_url=http://127.0.0.1:4566 --env-var admin_base_url=http://127.0.0.1:5101`.

### Folders

| # | Covers |
|---|---|
| 00 | Pool/client discovery, custom attributes, OIDC issuer equals Authority, JWKS, service health |
| 01 | Login for the 5 seeded roles; token claims (`iss`, `client_id`, `scope`, `custom:role`) |
| 02 | Wrong password, unknown user/client, bad auth flow, garbage token |
| 03 | GetUser, AdminGetUser (by phone and by `sub`), refresh |
| 04 | Backend JWT validation: no/malformed/forged/tampered/ID token, query-string token |
| 05 | Role matrix: 4 Admin endpoints x 5 roles |
| 06 | Create / login / change role / disable / enable / reset / delete a throwaway user (`tmp_phone`) |
| 07 | Service-token endpoint (non-Cognito HMAC scheme) |
| 08 | GlobalSignOut and refresh revocation (run last) |

### Caveats

- Run on 2026-10-26 against Floci seeded in `us-east-1`: 150 of 150 assertions pass. Details, ports and the region rationale are in [docs/testing-services.md](docs/testing-services.md).
  between the backend's Cognito client and Floci, so folders 04 (valid token), 05 and 06 fail; details and fix in [docs/testing-services.md](docs/testing-services.md).
- Only the Admin pool is covered. The User, TicketChecker and Agent pools (`Seed-EtpFloci.ps1`) have no seeded users or tests yet.
- Folder 06 `set-forget-password` documents an unauthenticated password-set endpoint (`[AllowAnonymous]`, no OTP check in
  `AdminUserManager.ForgetSetPasswordAsync`); see the request description.

## 11. Submodule workflow

Each submodule is **pinned to a commit**, not auto-synced to `main`. `branch = main` in `.gitmodules` only matters when deliberately refreshing a pin.

- After cloning/fetching: `git submodule update --init` (restores the pinned commits).
- Check pins vs. remote `main`: `./status.ps1` (or `git submodule foreach 'git log -1 --oneline'`).
- **Deliberately** advance a pin (for example after an upstream fix):

  ```powershell
  git submodule update --remote rvl-gobcb-backend   # one repo only
  git commit -m "Bump rvl-gobcb-backend"            # commit the pin immediately
  ```

Rules of thumb:

- Never commit inside a submodule directory from this workspace; work in the upstream repos (or their forks) and bump the pin here afterwards.
- A `git status` in this repo should normally be clean. A modified submodule line (`rvl-gobcb-*`) means a pin moved: commit it or discard it, never leave it hanging.

## 12. Troubleshooting

| Problem | Cause / fix |
|---|---|
| Services stuck in "Waiting" | Postgres/Redis not healthy yet; check their logs in the Aspire dashboard |
| Postgres `password authentication failed` | Volume was created with another password. `docker rm -f etp-postgres; docker volume rm etp-local_etp-pgdata` (data lost), run again |
| Service state "Finished" | It crashed on startup; read its console log in the dashboard. Redis error: Redis unreachable. Missing-config error: user secrets |
| Port already in use | Another process uses 5101-5111, 8000, 4566, or the Redis/Postgres host ports. `Get-NetTCPConnection -LocalPort <port> -State Listen` shows the owner |
| `FormatException` / `Distributed lock...` at startup | User secrets not applied (config still `[see User Secrets]`); re-run [8.2](#82-apply-it-to-every-service) |
| `NullReferenceException` in Program.cs for `Application:ServiceName` (UserIssue) | UserIssue's Application section missing; re-run 8.2 |
| `relation "etp.xxx" does not exist` | Admin migrations did not run yet; wait for Admin or check its log |
| Connection refused on 4566 | Floci not running: check the `floci` resource in the Aspire dashboard, or `docker logs etp-floci` |
| Floci console at :4500 not loading | `docker logs etp-floci-ui`. Do not set `PORT` on the `floci-ui` resource; it moves the server off 4500 |
| "Open Floci UI" button: "could not reach the container runtime" | Expected (no Docker socket). Use http://localhost:4500 |
| Port 4566 in use | LocalStack or another emulator is running. Stop it, or change the host port in `AppHost.cs` and every endpoint URL |
| Services still hit real AWS | `AWS_ENDPOINT_URL` not set in the process that starts the AppHost, or the SDK ignores it |
| S3 `NoSuchBucket` / DNS errors | `AWS:Bucket:BaseUrl` must be `http://localhost:4566` and the bucket must exist (`aws s3 ls`) |
| Queue not found | The secret must be the queue *name* (not a URL) and the queue must exist |
| 401 everywhere | Cognito IDs are dummy, belong to another pool, the token expired, or you re-seeded: update the JSON, re-apply, restart |
| `UriFormatException` in some client | A URL in config is still a placeholder; use a valid URL ending in `/` |
| `dotnet ef` fails with `System.Runtime, Version=10.0.0.0` | dotnet-ef 10 installed; use 8.0.11 ([section 3](#3-prerequisites)) |
| `docker run`: container name already in use | It already exists; `docker start <name>` |
| Floci upgrade | Image tags are pinned (`floci/floci`, `floci/floci-ui`). Bump both in `AppHost.cs`, then `docker rm -f etp-floci etp-floci-ui` and restart the AppHost (it pulls the new tags) |

## 13. Reset and teardown

| Goal | Command | What is lost |
|---|---|---|
| Stop backend | `Ctrl+C` in the AppHost terminal | nothing |
| Stop Floci (and the other containers) | `docker stop etp-postgres etp-redis etp-dynamodb etp-floci etp-floci-tls etp-floci-ui` | nothing |
| Remove containers | `docker rm -f etp-postgres etp-redis etp-dynamodb etp-floci etp-floci-tls etp-floci-ui` | nothing (volumes kept) |
| Reset Floci data only | `docker rm -f etp-floci etp-floci-tls etp-floci-ui; docker volume rm etp-floci-data`, then restart the AppHost (it re-seeds) | all buckets, queues, Cognito pools; IDs regenerate, so update user secrets |
| Reset backend data | stop the AppHost, `docker rm -f etp-postgres etp-redis; docker volume rm etp-local_etp-pgdata etp-local_etp-redis-data` | all DB and Redis data |
| Clear user secrets | `Get-ChildItem rvl-gobcb-backend/Services -Recurse -Filter *.Service.csproj \| ? { Select-String -Path $_.FullName -Pattern '<UserSecretsId>' -Quiet } \| % { dotnet user-secrets clear --project $_.FullName }` | all service secrets |
| Remove personal files | `Remove-Item -Recurse $env:USERPROFILE\.etp-local` | your `user-secrets.json`; back up real keys first |
| Build output | `dotnet clean` in the backend | bin/obj (back up the TSP cert if you placed one) |

**Full Floci cleanup** (containers, data volume and images):

```powershell
docker rm -f etp-floci etp-floci-tls etp-floci-ui; docker volume rm etp-floci-data; docker rmi floci/floci:2.3.0 floci/floci-ui:0.7.0
docker ps -a --filter "name=floci"            # leftovers check, should be empty
docker volume ls --filter "name=floci"        # should be empty
docker images --filter "reference=floci/*"    # should be empty
docker rm -f floci-aws-ui                     # only if the dashboard's "Open Floci UI" ever created a sidecar
```

After a full teardown, start again from [4.2](#42-start-the-infrastructure-postgresql-redis-dynamodb-floci).

Do not run `docker system prune -a --volumes`; it deletes the containers, images and volumes of **every** project on the machine.

## 14. Running without Aspire

Only if you cannot use Aspire (for example you want Visual Studio multi-project F5 with breakpoints from the first line).

1. Start Postgres and Redis yourself on non-default ports, to avoid clashing with other projects:

   ```powershell
   docker run -d --name etp-postgres --restart unless-stopped -e POSTGRES_DB=etp_local -e POSTGRES_USER=etp -e POSTGRES_PASSWORD=etp_local_pw -p 5433:5432 -v etp-pgdata:/var/lib/postgresql/data postgres:16.4-alpine
   docker run -d --name etp-redis --restart unless-stopped -p 6380:6379 -v etp-redisdata:/data redis:7.4-alpine
   ```

2. Add the keys Aspire would normally inject to your `user-secrets.json`, then re-apply ([8.2](#82-apply-it-to-every-service)):

   ```json
   {
     "ConnectionStrings": {
       "Admin": "Host=localhost;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true"
     },
     "Services": {
       "Admin": "http://localhost:5101/", "Booking": "http://localhost:5102/", "Event": "http://localhost:5103/",
       "Platform": "http://localhost:5104/", "PushNotification": "http://localhost:5105/", "Scheduler": "http://localhost:5106/",
       "TicketChecker": "http://localhost:5107/", "Ticketing": "http://localhost:5108/", "UserAuth": "http://localhost:5109/",
       "UserIssue": "http://localhost:5110/", "Utility": "http://localhost:5111/", "AppBase": "http://localhost:5120/"
     },
     "Cache": { "Redis": { "ConnectionString": "localhost:6380", "InstanceName": "etp-local:", "DefaultDatabase": "0" } },
     "DistributedLock": { "Redis": { "EndPoint": "localhost", "Port": "6380", "Database": "0", "AccessKey": "" } }
   }
   ```

   Repeat the `ConnectionStrings` entry for each key: `Admin, Booking, Event, Platform, Scheduler, TicketChecker, Ticketing, UserAuth, UserIssue, PushNotification`.
3. Run **Admin first** (it creates the core tables), then the others, each on its fixed port:

   ```powershell
   dotnet run --project rvl-gobcb-backend/Services/Admin/ETP.Admin.Service --launch-profile http --urls http://localhost:5101
   ```

   In Visual Studio use *Multiple startup projects* with the **http** profile (never IIS Express or https), Admin at the top, and override the
   URL per project (Scheduler and Utility both default to 5033 and cannot start together).

## 15. Known backend issues

Found while setting this up; worth separate tickets in the backend repo:

1. **Cognito client region (403 on every valid token locally):** with `AWS_ENDPOINT_URL` set, AWSSDK 3.7.403 signs Cognito calls with `us-east-1` whatever region the code passes, and Floci looks pools up by the signing region. Locally this is avoided by creating everything in Floci in `us-east-1`; the real fix is an explicit `AuthenticationRegion` in the backend (`DependencyConfig.cs` of Admin, Booking, UserIssue). Details in [docs/testing-services.md](docs/testing-services.md).
2. **Ticketing `TicketGenerationService`:** no delay after `catch`, so an exception makes the loop spin and write hundreds of error logs per second (production risk too).
3. **`launchSettings.json`:** Utility and Scheduler both use `http` 5033; PushNotification and Ticketing both use `https` 7007; the launch URLs of Utility, Platform and PushNotification point at the wrong Swagger path.
4. **Backend README is outdated:** it says SQL Server (it is PostgreSQL), `dotnet ef database update` lacks `-c`, and the Docker Compose section does not work locally.
5. **Config:** UserIssue has no `appsettings.json` in the repo, and the `DistributedLock:Redis:Database` key is missing everywhere although the code needs it.
6. **Security:** the TSP HttpClient sets `ServerCertificateCustomValidationCallback = (...) => true`; Swagger is open in every environment; some regions are hard-coded.
7. `UserAuth` and `Platform` are near-empty stubs, and 4 `*.Client` projects are not in the solution.
8. Full configuration for the real environments lives in AWS SSM Parameter Store (`/rvl/<env>/<service>-service-appsettings`). If you copy values from there, take only Cognito/S3 style values, never connection strings, Redis or `AWS:Queue:*` (rule 6 in [section 1](#1-what-you-get)).
