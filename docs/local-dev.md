# Local development manual

For a .NET developer who has just joined the project, including if you have never worked on a microservices system.
Follow it top to bottom once (**Part 3**), then use **Part 4** every day. Time for the first setup: 45 to 60 minutes, mostly downloads.

> **One rule:** never edit files inside the `rvl-gobcb-*` folders. They are separate repositories (git submodules) owned by the
> product team. Everything local (ports, config, scripts) lives in this workspace repo, in environment variables, or in user secrets.
> Detailed reference for rarer topics: [README](../README.md).

## Contents

1. [How the system fits together](#1-how-the-system-fits-together)
2. [Prerequisites](#2-prerequisites)
3. [First-time setup](#3-first-time-setup)
4. [Daily routine](#4-daily-routine)
5. [Build](#5-build)
6. [Debug](#6-debug)
7. [Everyday tasks](#7-everyday-tasks)
8. [Teardown and cleanup](#8-teardown-and-cleanup)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. How the system fits together

If you come from a single ASP.NET solution, three ideas are new:

- **Many small web APIs instead of one.** The backend (`rvl-gobcb-backend`) is 11 separate ASP.NET Core services. Each is its own
  process with its own port, and they call each other over HTTP. To test a booking you may need Admin, Event, Booking and Ticketing
  all running.
- **Shared infrastructure runs outside your code.** The services need a database (PostgreSQL), a cache and lock store (Redis) and AWS
  (S3 files, SQS queues, Cognito login). Locally these run in Docker containers; you do not install them on Windows.
- **Something has to start all of it.** Starting 11 projects by hand is painful, so we use **.NET Aspire** as a launcher: one command starts
  every service on its fixed port, and a web dashboard shows each service's state, logs and traces. Aspire is a dev tool only, not part of the product.

```
 you / Postman / Angular portals
            |  HTTP
 +----------v-------------------------------------------------+
 |  11 .NET services (started by Aspire)                      |
 |  Admin 5101  Booking 5102  Event 5103  Platform 5104       |
 |  PushNotification 5105  Scheduler 5106  TicketChecker 5107 |
 |  Ticketing 5108  UserAuth 5109  UserIssue 5110  Utility 5111|
 +----+-----------------+--------------------+----------------+
      |                 |                    |
 PostgreSQL :5432   Redis :6379     Floci :4566 (fake AWS: S3, SQS, SES, Cognito)
 (docker compose)   (docker compose)  + DynamoDB Local :8000 (Ticketing only)
```

Facts that explain most "why is this happening" moments:

| Fact | Consequence |
|---|---|
| All services share **one database** (`etp_local`), one schema per area | One Postgres container is enough. Admin owns the core tables |
| **Migrations run automatically** when a service starts | No `dotnet ef database update`. A fresh database fills itself in on first run |
| **No Redis, no service** | If Redis is down, services crash on startup |
| Settings come from **environment variables (set by Aspire) + user secrets** | The `appsettings.json` files contain only `[see User Secrets]` placeholders; real values are not in git |
| Login uses **AWS Cognito** | Locally, Floci plays Cognito. Protected endpoints need a token; `/health` does not |
| Ports are **fixed** (5101 to 5111) | Services find each other by these URLs, so do not change them |

---

## 2. Prerequisites

| Tool | Why | Install (PowerShell) |
|---|---|---|
| Git | clone the repos | `winget install Git.Git` |
| .NET SDK 8 | the services target `net8.0` | `winget install Microsoft.DotNet.SDK.8` |
| .NET SDK 10 | the Aspire launcher targets `net10.0` | `winget install Microsoft.DotNet.SDK.10` |
| Docker Desktop | runs PostgreSQL, Redis, Floci, DynamoDB Local | `winget install Docker.DockerDesktop`, then enable the **WSL 2** engine and start it |
| PowerShell 7 | the seed scripts | `winget install Microsoft.PowerShell` |
| AWS CLI v2 | inspect Floci (buckets, queues) | `winget install Amazon.AWSCLI` |
| An IDE | build and debug | Visual Studio 2022 17.8+ **or** VS Code with *C# Dev Kit* **or** JetBrains Rider |
| Optional | | Postman or Bruno (API calls), DBeaver (browse the DB) |

Open a **new** PowerShell 7 window (`pwsh`) and check:

```powershell
dotnet --list-sdks     # expect a line starting 8.0 and a line starting 10.0
pwsh --version         # 7.x
docker version         # must show both "Client" and "Server"; if Server is missing, Docker Desktop is not running
aws --version
```

Give Docker Desktop at least 8 GB of RAM (Settings > Resources, or `%UserProfile%\.wslconfig`): 11 services plus containers are hungry.

---

## 3. First-time setup

Run everything from the workspace root (`rvl-etp-workspace`) in PowerShell 7 unless stated.

### Step 1. Get the code

```powershell
git clone --recurse-submodules https://github.com/Relief-Validation/rvl-etp-workspace.git
cd rvl-etp-workspace
git config submodule.recurse true
```

The workspace pins five product repos at known-good commits. If you cloned without `--recurse-submodules`, run `git submodule update --init`.
Check: `rvl-gobcb-backend/Services` should contain 11 folders.

### Step 2. Start PostgreSQL and Redis

```powershell
docker compose up -d
docker compose ps
```

Expected: two containers, `etp-postgres` and `etp-redis`, status `healthy` after about 10 seconds.

| | Address | Credentials |
|---|---|---|
| PostgreSQL 16 | `localhost:5432`, database `etp_local` | user `etp`, password `etp_local_pw` |
| Redis 7 | `localhost:6379` | none |

Both listen on `127.0.0.1` only. Data lives in Docker volumes, so it survives restarts. The database is empty: that is correct.
Verify:

```powershell
docker exec etp-postgres psql -U etp -d etp_local -c "select 1;"
docker exec etp-redis redis-cli ping            # PONG
```

If the port is taken (a native Postgres or Redis on your PC), stop that one. The rest of this manual assumes 5432 and 6379.

### Step 3. Start Floci (fake AWS) and seed it

Floci stands in for AWS so you need no real AWS keys. It also has its own web console at http://localhost:4500.

```powershell
cd floci
docker compose up -d
docker compose logs -f floci        # wait until it says it is ready, then press Ctrl+C
./seed.ps1                          # creates bucket etp-local, SQS queues, SES identity, Cognito pools
./seed-users.ps1                    # Admin Cognito pool with custom attributes + 5 staff users
cd ..
```

**Keep the output of both scripts.** They print Cognito `PoolId`, `ClientId` (and for Admin an `Authority` and `Metadata` URL).
You need them in the next step. Run `seed.ps1` only once per fresh Floci volume; running it again creates duplicate pools.
For the **Admin** pool use the values printed by `seed-users.ps1`, not `seed.ps1`.

Test accounts created by `seed-users.ps1` (password for all: `Passw0rd!23`, username = phone number):

| Phone | Role |
|---|---|
| +8801700000001 | admin |
| +8801700000002 | event_manager |
| +8801700000003 | ticket_manager |
| +8801700000004 | ticket_operator |
| +8801700000005 | customer_support |

Check: `aws --endpoint-url http://localhost:4566 s3 ls` lists `etp-local` (if the CLI complains about credentials, set
`$env:AWS_ACCESS_KEY_ID="test"; $env:AWS_SECRET_ACCESS_KEY="test"; $env:AWS_REGION="ap-southeast-1"`).

> The Floci setup and the `Authority`/`Metadata` URL format have not been verified against every Floci version. If login fails
> later, see [README section 7](../README.md#7-floci-local-aws-emulation).

### Step 4. Configure the services (user secrets)

.NET *user secrets* are the standard way to keep config out of git: values are stored per project under
`%APPDATA%\Microsoft\UserSecrets\`. Each of the 11 services needs the same settings, so one script applies a single JSON file to all of them.

```powershell
copy scripts\user-secrets.example.json scripts\user-secrets.json
notepad scripts\user-secrets.json
```

`scripts\user-secrets.json` is git-ignored. In it, replace every `REPLACE_WITH_*` value:

| Section | Replace with |
|---|---|
| `AWS:CognitoPool:Admin` (`PoolId`, `ClientId`, `Authority`, `Metadata`) | the output of `seed-users.ps1` |
| `AWS:CognitoPool:User`, `TicketChecker`, `Agent` | the output of `seed.ps1` (`Authority` = `http://localhost:4566/<PoolId>`, `Metadata` = that plus `/.well-known/openid-configuration`) |
| `PaymentSettings`, `TSP`, `OneIdSettings`, ... | leave the dummy values. They are only needed for payment, ticket-signing and OneID features, which cannot work locally anyway |

Everything else (Floci URL, `test`/`test` keys, queue names, database and Redis addresses, service URLs) is already filled in for this setup.
Then apply it:

```powershell
./scripts/Set-EtpSecrets.ps1
```

Expected: one `ok  ETP.<Name>.Service.csproj` line per service. Check one:
`dotnet user-secrets list --project rvl-gobcb-backend/Services/Admin/ETP.Admin.Service`.
Edit the JSON and re-run the script any time; then restart the services. Never put real keys in any file in a repo.

### Step 5. Start the backend

```powershell
dotnet run --project aspire/Etp.AppHost
```

1. The first run downloads the Aspire packages and builds the 11 services: a few minutes.
2. The console prints `Login to the dashboard at http://localhost:15888/login?t=...`. Open that link.
3. In the **Resources** tab each service goes *Starting* -> *Running*. Admin applies the database migrations first; the others follow.
4. If a service shows **Finished** or **Failed to start**, it crashed. Click it and read its console log ([Troubleshooting](#9-troubleshooting)).

### Step 6. Verify

```powershell
curl http://localhost:5103/health                                   # Event -> Healthy. Try 5101 to 5111
curl http://localhost:5103/event/api/v1/landing-page-image/public   # [] (empty list, no login needed)
docker exec etp-postgres psql -U etp -d etp_local -tAc 'select count(*) from etp."__EFMigrationsHistory";'
```

The last command should print **129** once all services have started once. Swagger UIs: `http://localhost:5101/admin/swagger`,
`http://localhost:5103/event/swagger` (pattern `/<service name>/swagger`).

Two things are **normal** on a fresh setup: the Scheduler logs `Firebase notification: processing failed` every minute (no Firebase locally),
and Ticketing floods its log with `CryptographicException ... cannot find the path` because the ticket-signing certificate is not available locally.
If the noise bothers you, skip Ticketing (see [Daily routine](#4-daily-routine)).

You are now ready to build, run and debug.

---

## 4. Daily routine

**Morning**

```powershell
git pull
git submodule update --init                # only needed if the pinned submodule commits changed
docker compose up -d                       # PostgreSQL + Redis (does nothing if already running)
(cd floci; docker compose up -d)           # fake AWS; its data persists, so do not re-seed
dotnet run --project aspire/Etp.AppHost    # all services + dashboard
```

Start the Docker parts before the AppHost. New database migrations that other people added are applied automatically at service startup.
If `aws sqs list-queues` shows nothing, Floci lost its data: re-run `./seed.ps1` and `./seed-users.ps1` and update the Cognito IDs
in `scripts\user-secrets.json` (Step 4).

**Run fewer services** (saves RAM and noise). Set this *before* starting the AppHost; names are comma separated:

```powershell
$env:ETP_SKIP = "Platform,UserAuth,Utility,Ticketing"
dotnet run --project aspire/Etp.AppHost
```

Always keep Admin. Suggested sets per task:

| Task | Run |
|---|---|
| Admin portal features (events, venues, users) | Admin, Event |
| Booking / order flow | Admin, Event, Booking, Ticketing |
| Tickets / PDF | Admin, Booking, Event, Ticketing |
| Ticket check at the gate | Admin, Ticketing, TicketChecker |
| Notifications / scheduled jobs | Admin, Booking, Ticketing, Scheduler, PushNotification |

**During the day:** use the Aspire dashboard. *Resources* shows state and console logs, *Structured* gives searchable logs across all
services, *Traces* follows one request as it hops between services (very useful for understanding who calls whom).

**Evening**

- `Ctrl+C` in the AppHost terminal (wait for it to exit; do not close the window, that can leave processes behind).
- Optional: `docker compose stop` and `(cd floci; docker compose stop)`. Your data stays.

---

## 5. Build

The services build automatically when Aspire starts them. To build or check for compile errors yourself:

```powershell
dotnet build rvl-gobcb-backend/RVL-ETP.BackEnd.sln
```

or open `rvl-gobcb-backend/RVL-ETP.BackEnd.sln` in your IDE and build the solution. Build output goes to the git-ignored `bin/` and `obj/` folders.
Stop the AppHost before a manual build; running services lock their DLLs and the build fails with "file in use".

Changing code: edit in the submodule's own repo/branch under your usual workflow (the workspace only pins commits). Tests live in the backend repo's test projects:
`dotnet test rvl-gobcb-backend/RVL-ETP.BackEnd.sln`.

---

## 6. Debug

The services are normal `dotnet` processes, so a debugger can attach to any of them while Aspire runs them.

### 6.1 Attach (default, works everywhere)

Start the backend ([Step 5](#step-5-start-the-backend)) and wait until the service is **Running**. Each service is a process called `ETP.<Name>.Service`.

| IDE | Steps |
|---|---|
| **Visual Studio** | Open `rvl-gobcb-backend/RVL-ETP.BackEnd.sln`. *Debug > Attach to Process* (`Ctrl+Alt+P`), select `ETP.Event.Service.exe`, confirm *Attach to: Managed (.NET Core, .NET 5+)*, **Attach**. Repeat or multi-select for more services |
| **VS Code** | Open the **workspace root** folder (not a submodule) with *C# Dev Kit* installed. *Run and Debug* (`Ctrl+Shift+D`) > **Attach to a running ETP service (pick process)** > F5, type the service name in the picker |
| **Rider** | Open the same `.sln`. *Run > Attach to Process...*, choose `ETP.Event.Service` |

Try it now: open `rvl-gobcb-backend/Services/Event/ETP.Event.Service/Api/LandingPageImageController.cs`, put a breakpoint on
`var result = await siteSettingsManager.GetAllPublishedAsync();`, attach to Event, then call
`curl http://localhost:5103/event/api/v1/landing-page-image/public`. Execution should stop on your breakpoint.

Tips:
- Attach to **two services at once** to step through a call from one into the other (for example Booking calling Admin).
- Stop on any thrown exception: Visual Studio `Ctrl+Alt+E` and tick *Common Language Runtime Exceptions*; VS Code, tick *All Exceptions* in the Breakpoints panel.
- Background workers (`Workers/BackgroundServices/*`) start about a minute after boot. Put a breakpoint inside `ExecuteAsync`.
- You cannot hit breakpoints in code that already ran (startup, migrations) with a late attach: use 6.2.

### 6.2 Debug a service from its first line

Tell Aspire not to start that service, then start it yourself from the IDE on the same port. All other services keep calling it at the usual URL,
so breakpoints fire for calls coming from them too. Example for **Event** (port 5103):

```powershell
$env:ETP_SKIP = "Event"
dotnet run --project aspire/Etp.AppHost
```

| IDE | Steps |
|---|---|
| **VS Code** | *Run and Debug* > **Event (5103)** > F5. Configs for all 11 services are in `.vscode/launch.json`; they build first and set the port, environment and Floci endpoint |
| **Rider** | *Run > Edit Configurations > + > .NET Project*, project `ETP.Event.Service`, untick the launch profile, environment variables `ASPNETCORE_ENVIRONMENT=Development;ASPNETCORE_URLS=http://localhost:5103;AWS_ENDPOINT_URL=http://localhost:4566`, then Debug |
| **Visual Studio** | Run it in a terminal with those variables, then attach (6.1): `$env:ASPNETCORE_ENVIRONMENT="Development"; $env:ASPNETCORE_URLS="http://localhost:5103"; $env:AWS_ENDPOINT_URL="http://localhost:4566"; dotnet run --project rvl-gobcb-backend/Services/Event/ETP.Event.Service --no-launch-profile` |

Why not simply press F5 on the service in Visual Studio? The repo's `launchSettings.json` ports differ from the fixed ports the services expect
(and two services share 5033), and fixing that would mean editing a file inside a submodule. Do not use the *Launch Profiles* editor for the same reason.

This works because the connection strings and service URLs are also in your user secrets (Step 4), so a service started outside Aspire finds Postgres, Redis and its siblings.
Start **Admin** first if the database is empty, because it creates the tables.

### 6.3 F5 on the AppHost

Visual Studio 17.9+ and Rider (with Aspire support) can start `aspire/Etp.AppHost` (profile `http`) under the debugger and attach to the child services.
VS Code has an **Aspire AppHost** config in `launch.json`. This is not verified for every IDE version; if breakpoints show as "not bound", use 6.1.

---

## 7. Everyday tasks

**Call a protected API.** Most endpoints need a Cognito token. Get one from Floci for a seeded user (use the Admin `ClientId` from `seed-users.ps1`):

```powershell
aws --endpoint-url http://localhost:4566 cognito-idp initiate-auth --region ap-southeast-1 `
  --auth-flow USER_PASSWORD_AUTH --client-id <ADMIN_CLIENT_ID> `
  --auth-parameters USERNAME=+8801700000001,PASSWORD=Passw0rd!23
```

Copy the `AccessToken` value into Swagger's **Authorize** button (token only, no `Bearer`). Admin endpoints scoped to a program also need the header `X-Program-Id: <id>`.
There is also a ready Postman collection in `postman/` ([README section 10](../README.md#10-postman-cognito-and-auth-tests)).

**Look at the database.**

```powershell
docker exec -it etp-postgres psql -U etp -d etp_local     # then:  \dt etp.*   and   select ... ;
```

or connect DBeaver to `localhost:5432`, database `etp_local`, user `etp`, password `etp_local_pw`.
There is no seed data: create events and venues through the Admin API, or ask the team lead for a sanitized dump.

**Look at fake AWS.**

```powershell
aws --endpoint-url http://localhost:4566 s3 ls s3://etp-local --recursive
aws --endpoint-url http://localhost:4566 sqs list-queues
```

**Inspect Redis.** `docker exec etp-redis redis-cli --scan` lists keys; `docker exec etp-redis redis-cli flushall` clears the cache.

**Before you commit.** Add specific files (no `git add -A`), never commit secrets, and check that submodules are untouched:
`git submodule foreach "git status --porcelain"` must print nothing.

---

## 8. Teardown and cleanup

Pick the level you need. Never run `docker system prune -a --volumes`: it deletes the data of every project on your machine.

**Stop only (data kept)**

```powershell
# Ctrl+C in the AppHost terminal first
docker compose stop
(cd floci; docker compose stop)
```

**Remove containers (data kept)**

```powershell
docker compose down
(cd floci; docker compose down)
```

**Reset data (clean database/AWS, keep images)**

```powershell
docker compose down -v                 # deletes the PostgreSQL and Redis volumes
docker compose up -d
(cd floci; docker compose down -v; docker compose up -d; ./seed.ps1; ./seed-users.ps1)
# Floci pool IDs change on re-seed: update scripts\user-secrets.json, run ./scripts/Set-EtpSecrets.ps1, restart the AppHost
```

**Full cleanup (data and images)**

```powershell
docker compose down --volumes --rmi all --remove-orphans
(cd floci; docker compose down --volumes --rmi all --remove-orphans)
docker rm -f etp-dynamodb 2>$null
docker rmi amazon/dynamodb-local 2>$null          # started by Aspire for Ticketing

Get-ChildItem rvl-gobcb-backend/Services -Recurse -Filter '*.Service.csproj' |
  Where-Object { Select-String $_.FullName -Pattern '<UserSecretsId>' -Quiet } |
  ForEach-Object { dotnet user-secrets clear --project $_.FullName }
Remove-Item scripts\user-secrets.json             # back up real keys first

docker ps -a --filter "name=etp"                  # leftovers check: should list nothing
docker volume ls --filter "name=etp"
```

`--rmi all` removes the `postgres` and `redis` images; if another project of yours uses them, Docker refuses to remove an image that is in use, which is the safety net.
Finally, `dotnet clean rvl-gobcb-backend/RVL-ETP.BackEnd.sln` removes build output, and `git submodule foreach "git status --porcelain"` must print nothing.
To start again, go back to [Part 3](#3-first-time-setup).

---

## 9. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `docker version` shows no Server / compose fails | Docker Desktop is not running. Start it and wait for the whale icon to be steady |
| `port is already allocated` (5432, 6379, 4566, 8000) | Another program owns the port: `Get-NetTCPConnection -LocalPort 5432 -State Listen`. Stop it (a native Postgres/Redis, LocalStack) |
| Service stuck in **Waiting** | Aspire waits for a dependency. Check `docker compose ps` and the dashboard logs |
| Service **Finished** right after start | It crashed; read its console log. *Redis* error: Redis is down. *`[see User Secrets]`/FormatException*: secrets not applied, re-run `Set-EtpSecrets.ps1`. `UserIssue` NullReference on `Application:ServiceName`: re-run the script |
| `password authentication failed for user "etp"` | The Postgres volume was created with another password. `docker compose down -v` and start again |
| `relation "etp.xxx" does not exist` | Admin has not finished its migrations yet; wait, or check Admin's log |
| 401 on every call | Token expired, or the Cognito IDs in your secrets no longer match Floci (they change when you re-seed). Update the file, re-run the script, restart |
| AWS errors such as `UnrecognizedClientException` or calls reaching real AWS | Floci is not running; Aspire sets `AWS_ENDPOINT_URL` for the services it starts, but a service you launch yourself needs it too (6.2) |
| S3 `NoSuchBucket` | Bucket missing: `aws --endpoint-url http://localhost:4566 s3 ls`; re-seed if empty |
| Ticketing log spam `CryptographicException` | Missing TSP certificate. Skip it with `ETP_SKIP=Ticketing` unless you work on tickets |
| Build error "file is locked" | A service is still running. Stop the AppHost |
| Breakpoint hollow / "not bound" | Wrong process, or stale build. Rebuild and re-attach |
| `dotnet ef` fails with `System.Runtime, Version=10.0.0.0` | Install the 8.x tool: `dotnet tool install --global dotnet-ef --version 8.0.11` |

Still stuck: Aspire dashboard > the failing service > console logs usually names the cause. Then ask the team with that log line.
