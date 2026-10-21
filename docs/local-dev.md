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
 (docker compose)    (docker compose)    + DynamoDB Local :8000 (Ticketing only)
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

Run everything from the workspace root (`rvl-etp-workspace`) in PowerShell 7 unless stated. The order matters.
**The whole sequence at a glance** (each step below explains and checks one part):

```powershell
git clone --recurse-submodules https://github.com/Relief-Validation/rvl-etp-workspace.git ; cd rvl-etp-workspace   # Step 1
docker compose up -d                                                                                               # Step 2
cd floci ; ./setup-https.ps1 ; docker compose up -d ; ./seed.ps1 ; ./seed-users.ps1 ; cd ..                       # Step 3
./scripts/Set-EtpSecrets.ps1                                                                                       # Step 4
dotnet run --project aspire/Etp.AppHost                                                                            # Step 5 (keep this terminal open)
./scripts/Test-EtpLocal.ps1                                                                                        # Step 6 (in a second terminal)
```

### Step 1. Get the code

```powershell
git clone --recurse-submodules https://github.com/Relief-Validation/rvl-etp-workspace.git
cd rvl-etp-workspace
git config submodule.recurse true
```

The workspace pins five product repos at known-good commits. If you cloned without `--recurse-submodules`, run `git submodule update --init`.
Check: `rvl-gobcb-backend/Services` should contain 11 folders.

### Step 2. Start PostgreSQL, Redis and DynamoDB

From the workspace root:

```powershell
docker compose up -d
docker compose ps          # etp-postgres and etp-redis should say "healthy" after ~10 seconds
```

This starts three containers from `docker-compose.yml`, all reachable only from your own PC:

| Container | Address | Credentials | Data |
|---|---|---|---|
| `etp-postgres` | `localhost:5432`, database `etp_local` | user `etp`, password `etp_local_pw` | volume, kept |
| `etp-redis` | `localhost:6379` | none | volume, kept |
| `etp-dynamodb` (Ticketing only) | `http://localhost:8000` | none | in-memory, nothing to seed |

The database is empty the first time: that is correct, the services create their own tables.
If a port is taken (a native Postgres or Redis on your PC), stop that program: `Get-NetTCPConnection -LocalPort 5432 -State Listen`.

### Step 3. Start Floci (fake AWS) and seed it

Floci stands in for AWS so you need no real AWS keys. Its web console is http://localhost:4500. Three details are deliberate:

- **HTTPS for login.** The backend only accepts HTTPS Cognito metadata, so a small proxy container (`etp-floci-tls`, `https://localhost:4567`) fronts Floci for
  the Cognito URLs. It needs a certificate, which `setup-https.ps1` creates, so **run it before the first `docker compose up -d`** in `floci/`.
  AWS calls (S3, SQS, the CLI) still go to `http://localhost:4566`.
- **Region `us-east-1`.** The AWS SDK signs requests to a custom endpoint for `us-east-1`, so everything must be created there. The scripts already do.
- **Seed once.** Seeding creates the bucket, queues and Cognito pools. Do not delete the Floci volume afterwards unless you want to start over.

```powershell
cd floci
./setup-https.ps1                   # one-time: trust + export the .NET dev certificate (accept the Windows prompt)
docker compose up -d
docker compose ps                   # etp-floci must say "healthy" (about 10 seconds); wait and repeat if it says "starting"
./seed.ps1                          # S3 bucket etp-local, SQS queues, SES identity
./seed-users.ps1                    # Cognito: 4 pools (Admin, User, TicketChecker, Agent), app clients, test users
cd ..
```

`seed-users.ps1` ends by printing a block of `AWS:CognitoPool:<Pool>:PoolId / ClientId / Authority / Metadata` lines for all four pools.
You do not copy them: the next step reads them for you. Both scripts are safe to re-run: existing pools, clients, users, bucket and queues are reused,
so nothing is duplicated.

**If you lose the output** (closed the terminal, shut down the PC): you do not need to save it. Run `./seed-users.ps1` again in `floci/` and it prints
the same block, or list the IDs directly:

```powershell
aws --endpoint-url http://localhost:4566 cognito-idp list-user-pools --max-results 60
aws --endpoint-url http://localhost:4566 cognito-idp list-user-pool-clients --user-pool-id <PoolId>
```

Test accounts for the Admin pool (password for all: `Passw0rd!23`, username = phone number; the other pools get one user each):

| Phone | Role |
|---|---|
| +8801700000001 | admin |
| +8801700000002 | event_manager |
| +8801700000003 | ticket_manager |
| +8801700000004 | ticket_operator |
| +8801700000005 | customer_support |

Check: `aws --endpoint-url http://localhost:4566 s3 ls` lists `etp-local`. If the CLI complains about credentials or region, set them for this terminal:
`$env:AWS_ACCESS_KEY_ID="test"; $env:AWS_SECRET_ACCESS_KEY="test"; $env:AWS_REGION="us-east-1"`. This setup was tested with Floci 2.3.0 (pinned in `floci/docker-compose.yml`).

### Step 4. Configure the services (user secrets)

.NET *user secrets* are the standard way to keep config out of git: values are stored per project under
`%APPDATA%\Microsoft\UserSecrets\`. Each of the 11 services needs the same settings, so one script writes them to all of them:

```powershell
./scripts/Set-EtpSecrets.ps1
```

You edit no file. The script:

1. starts from `scripts/user-secrets.example.json` (Floci URL, `test`/`test` keys, queue names, database and Redis addresses, service URLs; the
   payment, TSP and OneID entries are dummies because those features cannot work locally anyway);
2. asks the running Floci for the Cognito `PoolId` and `ClientId` of the Admin, User, TicketChecker and Agent pools and fills in
   `PoolId`, `ClientId`, `Authority` and `Metadata` itself, so there is nothing to copy from the seed output;
3. stops with a clear message if Floci is not running, a pool is missing (run `./seed-users.ps1`), or any `REPLACE_WITH_*` placeholder is left,
   so a half-configured setup cannot be applied;
4. writes the result to every service with `dotnet user-secrets`.

Expected: four `cognito <Pool> pool ... client ...` lines, then one `ok  ETP.<Name>.Service.csproj` line per service. Check one:
`dotnet user-secrets list --project rvl-gobcb-backend/Services/Admin/ETP.Admin.Service`. `./scripts/Set-EtpSecrets.ps1 -DryRun` prints the final JSON without applying it.

**Re-run it** after every `./seed-users.ps1` on a fresh Floci (the IDs change), then restart the AppHost.

*Optional personal overrides:* if you have a real key (for example a real payment sandbox), put only that key in `scripts/user-secrets.json`
(git-ignored, same structure as the example). It is merged on top; values still containing `REPLACE_WITH` are ignored. Never put real keys in any file in a repo.

### Step 5. Start the backend

```powershell
dotnet run --project aspire/Etp.AppHost
```

1. The first run downloads the Aspire packages and builds the 11 services: a few minutes. Keep this terminal open; `Ctrl+C` stops everything.
2. The console prints `Login to the dashboard at http://localhost:15888/login?t=...`. Open that link.
3. In the **Resources** tab each service goes *Starting* -> *Running*. Admin applies the database migrations first; the others follow.
   Wait until all 11 are *Running* (about a minute after the build) before Step 6.
4. If a service shows **Finished** or **Failed to start**, it crashed. Click it and read its console log ([Troubleshooting](#9-troubleshooting)).

### Step 6. Verify

Open a **second** terminal in the workspace root:

```powershell
./scripts/Test-EtpLocal.ps1
```

It checks the five containers, the 11 `/health` endpoints, a Cognito login against Floci, and that a protected Admin endpoint answers
**401 without a token and 200 with one**. Every line should say `PASS`; a `FAIL` line says what to do. If the health lines fail right after Step 5,
the services are still starting: wait and run it again.

Extra checks if you like: `curl http://localhost:5103/event/api/v1/landing-page-image/public` returns `[]`; and in DBeaver/pgAdmin
(`localhost:5432`, db `etp_local`, user `etp`, password `etp_local_pw`) `select count(*) from etp."__EFMigrationsHistory";` returns **129** once all services have started once.
Swagger UIs: `http://localhost:5101/admin/swagger`, `http://localhost:5103/event/swagger` (pattern `/<service name>/swagger`).

Some log noise is expected locally and does not stop the services: Scheduler may log Firebase warnings (no Firebase locally), Ticketing may log
`CryptographicException` because the ticket-signing certificate is not available, and background workers may log `Could NOT acquire lock ... Skipping this cycle`.
To silence Ticketing, skip it (see [Daily routine](#4-daily-routine)).

You are now ready to build, run and debug.

---

## 4. Daily routine

**Morning**

```powershell
git pull
git submodule update --init                # only needed if the pinned submodule commits changed
docker compose up -d                       # PostgreSQL, Redis, DynamoDB (does nothing if already running)
(cd floci; docker compose up -d)           # fake AWS; pools, queues and users persist, so do not re-seed
dotnet run --project aspire/Etp.AppHost    # all services + dashboard
```

Start the Docker parts before the AppHost. Once the services are *Running*, `./scripts/Test-EtpLocal.ps1` confirms that everything works (about 20 seconds). New database migrations that other people added are applied automatically at service startup.

**After a PC shutdown or reboot** there is nothing to redo: your Cognito IDs are saved in the services' user secrets,
and Floci keeps its data in the `etp-floci-data` volume (Docker Desktop usually restarts the container by itself). Just run the two commands above.
If you get 401 everywhere, check that Floci still has its pools: `aws --endpoint-url http://localhost:4566 cognito-idp list-user-pools --max-results 60`.
An empty list (or `aws sqs list-queues` showing nothing) means Floci lost its data: re-run `./seed.ps1` and `./seed-users.ps1` in `floci/`,
run `./scripts/Set-EtpSecrets.ps1` (it picks up the new IDs by itself), restart the AppHost.
(Persistence across restarts has not been verified for Cognito on every Floci version; this check is the safety net.)

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
aws --endpoint-url http://localhost:4566 cognito-idp initiate-auth --region us-east-1 `
  --auth-flow USER_PASSWORD_AUTH --client-id <ADMIN_CLIENT_ID> `
  --auth-parameters USERNAME=+8801700000001,PASSWORD=Passw0rd!23
```

Copy the `AccessToken` value into Swagger's **Authorize** button (token only, no `Bearer`). Admin endpoints scoped to a program also need the header `X-Program-Id: <id>`.
There is also a ready Postman collection in `postman/` ([README section 10](../README.md#10-postman-cognito-and-auth-tests)).

**Look at the database.**

```powershell
docker exec -it etp-postgres psql -U etp -d etp_local     # then:  \dt etp.*   and   select ... ;
```

or (easier) connect DBeaver to `localhost:5432`, database `etp_local`, user `etp`, password `etp_local_pw`.
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

**Reset data (clean database and AWS, keep images)**

```powershell
docker compose down -v                 # deletes the PostgreSQL and Redis volumes
docker compose up -d
(cd floci; docker compose down -v; docker compose up -d; ./seed.ps1; ./seed-users.ps1)
# Floci pool IDs change on re-seed: run ./scripts/Set-EtpSecrets.ps1 again, then restart the AppHost
```

**Full cleanup (data and images)**

```powershell
docker compose down --volumes --rmi all --remove-orphans
(cd floci; docker compose down --volumes --rmi all --remove-orphans)

Get-ChildItem rvl-gobcb-backend/Services -Recurse -Filter '*.Service.csproj' |
  Where-Object { Select-String $_.FullName -Pattern '<UserSecretsId>' -Quiet } |
  ForEach-Object { dotnet user-secrets clear --project $_.FullName }
Remove-Item scripts\user-secrets.json -ErrorAction SilentlyContinue   # only exists if you made personal overrides

docker ps -a --filter "name=etp"                  # leftovers check: should list nothing
docker volume ls --filter "name=etp"
```

`docker rmi` refuses to remove an image that a container still uses, which protects other projects that share `postgres` or `redis`.
Finally, `dotnet clean rvl-gobcb-backend/RVL-ETP.BackEnd.sln` removes build output, and `git submodule foreach "git status --porcelain"` must print nothing.
To start again, go back to [Part 3](#3-first-time-setup).

---

## 9. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `docker version` shows no Server / containers fail to start | Docker Desktop is not running. Start it and wait for the whale icon to be steady |
| `port is already allocated` (5432, 6379, 4566, 8000) | Another program owns the port: `Get-NetTCPConnection -LocalPort 5432 -State Listen`. Stop it (a native Postgres/Redis, LocalStack) |
| Every request fails with `The MetadataAddress or Authority must use HTTPS` | The Cognito URLs in your secrets are `http://`. Run `./setup-https.ps1`, `docker compose up -d` in `floci/`, then `./scripts/Set-EtpSecrets.ps1` and restart the AppHost |
| Valid token still gets **401** `The signature key was not found`, or **403**, or logs `User pool ... does not exist` | Floci was seeded in a different region. The AWS SDK signs requests to a custom endpoint for `us-east-1`, so Floci must hold everything in `us-east-1` (the seed scripts do this). If your pool IDs start with `ap-southeast-1_`, they are from an older setup: re-run `./seed.ps1` and `./seed-users.ps1` in `floci/`, then `./scripts/Set-EtpSecrets.ps1`, and restart the AppHost |
| `etp-floci-tls` keeps restarting, or https://localhost:4567 does not answer | The certificate files are missing. Run `cd floci; ./setup-https.ps1`, then `docker compose up -d` again |
| Service **Finished** right after start | It crashed; read its console log. *Redis/Postgres connection* error: infra is down, run `docker compose up -d` (`docker compose ps` to check) and restart the AppHost. *`[see User Secrets]`/FormatException*: secrets not applied, re-run `Set-EtpSecrets.ps1`. `UserIssue` NullReference on `Application:ServiceName`: re-run the script |
| `password authentication failed for user "etp"` | The Postgres volume was created with another password. `docker compose down -v` and start again |
| `relation "etp.xxx" does not exist` | Admin has not finished its migrations yet; wait, or check Admin's log |
| 401 on every call | Token expired, or the Cognito IDs in your secrets no longer match Floci (they change when Floci's data is recreated). Re-run `./scripts/Set-EtpSecrets.ps1` (it reads the current IDs from Floci), restart |
| AWS errors such as `UnrecognizedClientException` or calls reaching real AWS | Floci is not running; Aspire sets `AWS_ENDPOINT_URL` for the services it starts, but a service you launch yourself needs it too (6.2) |
| S3 `NoSuchBucket` | Bucket missing: `aws --endpoint-url http://localhost:4566 s3 ls`; re-seed if empty |
| Ticketing log spam `CryptographicException` | Missing TSP certificate. Skip it with `ETP_SKIP=Ticketing` unless you work on tickets |
| Build error "file is locked" | A service is still running. Stop the AppHost |
| Breakpoint hollow / "not bound" | Wrong process, or stale build. Rebuild and re-attach |
| `dotnet ef` fails with `System.Runtime, Version=10.0.0.0` | Install the 8.x tool: `dotnet tool install --global dotnet-ef --version 8.0.11` |

Still stuck: Aspire dashboard > the failing service > console logs usually names the cause. Then ask the team with that log line.
