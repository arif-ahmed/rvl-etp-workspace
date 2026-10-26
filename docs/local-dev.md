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
  (S3 files, SQS queues, Cognito login). Locally these run in Docker containers from one compose file; you do not install them on Windows. AWS is played by **Floci**, an emulator: it never talks to the real AWS account.
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
                                      + HTTPS proxy :4567 (Cognito URLs), console :4500
 DynamoDB Local :8000 (Ticketing only)

 All of these containers come from the one docker-compose.yml in the workspace root.
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
| Docker Desktop 4.26+ (Compose 2.23.1+) | runs PostgreSQL, Redis, Floci, DynamoDB Local; the Floci proxy config is inline in `docker-compose.yml` | `winget install Docker.DockerDesktop`, then enable the **WSL 2** engine and start it |
| PowerShell 7 | the seed scripts | `winget install Microsoft.PowerShell` |
| AWS CLI v2 | inspect Floci (buckets, queues) | `winget install Amazon.AWSCLI` |
| An IDE | build and debug | Visual Studio 2022 17.8+ **or** VS Code with *C# Dev Kit* **or** JetBrains Rider |
| Optional | | Postman or Bruno (API calls), DBeaver (browse the DB) |

Open a **new** PowerShell 7 window (`pwsh`) and check:

```bash
# expect a line starting 8.0 and a line starting 10.0
dotnet --list-sdks
# 7.x
pwsh --version
# must show both "Client" and "Server"; if Server is missing, Docker Desktop is not running
docker version
aws --version
```

Give Docker Desktop at least 8 GB of RAM (Settings > Resources, or `%UserProfile%\.wslconfig`): 11 services plus containers are hungry.

---

## 3. First-time setup

Run everything from the workspace root (`rvl-etp-workspace`). **Every command works unchanged in both Git Bash and PowerShell 7**: PowerShell scripts are
started as `pwsh ./scripts/<name>.ps1` (bash cannot run a `.ps1` directly). Where a command differs by shell, both forms are shown. The order matters.
**The whole sequence at a glance** (each step below explains and checks one part):

```bash
# Step 1: download the workspace and its 5 product repos
git clone --recurse-submodules https://github.com/Relief-Validation/rvl-etp-workspace.git
# enter it; everything below runs from this folder
cd rvl-etp-workspace
# Step 2: trust + export the .NET dev certificate (needed by Floci's HTTPS proxy)
pwsh ./scripts/Setup-EtpHttps.ps1
# start PostgreSQL, Redis, DynamoDB Local and Floci (fake AWS) with its HTTPS proxy and web console
docker compose up -d
# Step 3: create the S3 bucket, SQS queues and SES identity in Floci
pwsh ./scripts/Seed-EtpFloci.ps1
# create the 4 Cognito pools, app clients and test users
pwsh ./scripts/Seed-EtpCognitoUsers.ps1
# Step 4: write config + Cognito IDs into every service's user secrets
pwsh ./scripts/Set-EtpSecrets.ps1
# Step 5: build and start all 11 services + dashboard (keep this terminal open)
dotnet run --project aspire/Etp.AppHost
# Step 6: in a SECOND terminal, check containers, health, login, protected call
pwsh ./scripts/Test-EtpLocal.ps1
# Step 7 (optional): load BCB cricket test data (series, BPL, grounds, orders, tickets)
pwsh ./scripts/Seed-EtpData.ps1
```

### Step 1. Get the code

```bash
# download the workspace and all 5 submodules
git clone --recurse-submodules https://github.com/Relief-Validation/rvl-etp-workspace.git
# enter the workspace
cd rvl-etp-workspace
# make git pull/checkout also move the submodules to their pinned commits
git config submodule.recurse true
```

The workspace pins five product repos at known-good commits. If you cloned without `--recurse-submodules`, run `git submodule update --init`.
Check: `rvl-gobcb-backend/Services` should contain 11 folders.

### Step 2. Start the containers (PostgreSQL, Redis, DynamoDB, Floci)

Everything the services need outside your code runs from the single `docker-compose.yml` in the workspace root:

```bash
# one-time, BEFORE the first compose up: trust + export the .NET dev certificate for Floci's HTTPS proxy (accept the Windows prompt)
pwsh ./scripts/Setup-EtpHttps.ps1
# download images (first time) and start all six containers in the background
docker compose up -d
# list them; etp-postgres, etp-redis and etp-floci should say "healthy" after ~10 seconds
docker compose ps
```

The certificate goes to `floci/certs/` (git-ignored, per machine). The proxy's nginx config is inline in `docker-compose.yml`, so there is no other file to create.
If you run `docker compose up -d` first, it stops with `bind source path does not exist: .../floci/certs`: run the script, then repeat. The six containers:

| Container | Address | Credentials | Data |
|---|---|---|---|
| `etp-postgres` | `localhost:5432`, database `etp_local` | user `etp`, password `etp_local_pw` | volume, kept |
| `etp-redis` | `localhost:6379` | none | volume, kept |
| `etp-dynamodb` (Ticketing only) | `http://localhost:8000` | none | in-memory, nothing to seed |
| `etp-floci` (fake AWS) | `http://localhost:4566` | `test` / `test` | volume `etp-floci-data`, kept |
| `etp-floci-tls` (HTTPS proxy for Cognito URLs) | `https://localhost:4567` | none | none |
| `etp-floci-ui` (web console) | `http://localhost:4500` | none | none |

The database is empty the first time: that is correct, the services create their own tables.
If a port is taken (a native Postgres or Redis on your PC), stop that program. Find the owner with `pwsh -c "Get-NetTCPConnection -LocalPort 5432 -State Listen"`.

### Step 3. Seed Floci (fake AWS)

Floci stands in for AWS so you need no real AWS keys. It is an emulator: it cannot reach the real AWS resources. Its web console is http://localhost:4500. Three details are deliberate:

- **HTTPS for login.** The backend only accepts HTTPS Cognito metadata, so a small proxy container (`etp-floci-tls`, `https://localhost:4567`) fronts Floci for
  the Cognito URLs, using the certificate from Step 2. AWS calls (S3, SQS, the CLI) still go to `http://localhost:4566`.
- **Region `ap-southeast-1` (Singapore).** Everything in Floci must be created in this one region, to match the real AWS deployment. The seed scripts, the CLI and the services must all use it.
- **Seed once.** Seeding creates the bucket, queues and Cognito pools. Do not delete the Floci volume afterwards unless you want to start over.

```bash
# etp-floci must say "healthy" (about 10 seconds); wait and repeat if it says "starting"
docker compose ps
# create S3 bucket etp-local, SQS queues, SES identity
pwsh ./scripts/Seed-EtpFloci.ps1
# create 4 Cognito pools (Admin, User, TicketChecker, Agent), app clients, test users
pwsh ./scripts/Seed-EtpCognitoUsers.ps1
```

`Seed-EtpCognitoUsers.ps1` prints the `PoolId` / `ClientId` of the four pools. You do not need to copy or keep them: the next step reads them from Floci itself.
Both scripts are safe to re-run: existing pools, clients, users, bucket and queues are reused, so nothing is duplicated.
To list the IDs yourself: `aws --endpoint-url http://localhost:4566 cognito-idp list-user-pools --max-results 60` (AWS CLI setup below).

Test accounts for the Admin pool (password for all: `Passw0rd!23`, username = phone number; the other pools get one user each):

| Phone | Role |
|---|---|
| +8801700000001 | admin |
| +8801700000002 | event_manager |
| +8801700000003 | ticket_manager |
| +8801700000004 | ticket_operator |
| +8801700000005 | customer_support |

**AWS CLI for Floci (once per terminal).** The `aws` commands in this manual need dummy credentials and the region. Set them in the shell you use:

```powershell
# PowerShell 7
$env:AWS_ACCESS_KEY_ID = "test"; $env:AWS_SECRET_ACCESS_KEY = "test"; $env:AWS_REGION = "ap-southeast-1"
```

```bash
# Git Bash
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=ap-southeast-1
```

Check: `aws --endpoint-url http://localhost:4566 s3 ls` lists the bucket `etp-local`. This setup was tested with Floci 2.3.0 (pinned in `docker-compose.yml`).

### Step 4. Configure the services (user secrets)

.NET *user secrets* are the standard way to keep config out of git: values are stored per project under
`%APPDATA%\Microsoft\UserSecrets\`. Each of the 11 services needs the same settings, so one script writes them to all of them:

```bash
# read the Cognito IDs from Floci, merge with the example config, write to all 11 services
pwsh ./scripts/Set-EtpSecrets.ps1
```

You edit no file. The script:

1. starts from `scripts/user-secrets.example.json` (Floci URL, `test`/`test` keys, queue names, database and Redis addresses, service URLs; the
   payment, TSP and OneID entries are dummies because those features cannot work locally anyway);
2. asks the running Floci for the Cognito `PoolId` and `ClientId` of the Admin, User, TicketChecker and Agent pools and fills in
   `PoolId`, `ClientId`, `Authority` and `Metadata` itself, so there is nothing to copy from the seed output;
3. stops with a clear message if Floci is not running, a pool is missing (run `pwsh ./scripts/Seed-EtpCognitoUsers.ps1`), or any `REPLACE_WITH_*` placeholder is left,
   so a half-configured setup cannot be applied;
4. writes the result to every service with `dotnet user-secrets`.

Expected: four `cognito <Pool> pool ... client ...` lines, then one `ok  ETP.<Name>.Service.csproj` line for each of the 10 services that read secrets (UserAuth reads none). Check one:
`dotnet user-secrets list --project rvl-gobcb-backend/Services/Admin/ETP.Admin.Service`. `pwsh ./scripts/Set-EtpSecrets.ps1 -DryRun` prints the final JSON without applying it.

**Re-run it** after every `pwsh ./scripts/Seed-EtpCognitoUsers.ps1` on a fresh Floci (the IDs change), then restart the AppHost.

*Optional personal overrides:* if you have a real key (for example a real payment sandbox), put only that key in `scripts/user-secrets.json`
(git-ignored, same structure as the example). It is merged on top; values still containing `REPLACE_WITH` are ignored. Never put real keys in any file in a repo.

### Step 5. Start the backend

The AppHost first builds `rvl-gobcb-backend/RVL-ETP.BackEnd.sln` **once, serially** (the first time takes a few minutes; you will see
`[Etp.AppHost] Building ... once before starting the services`), then starts each service with `dotnet run --no-build`.

Why: a plain `dotnet run` per service builds first, and 11 parallel builds all rewrite the shared `ETP.Core*/obj/**/*.sourcelink.json`
even when nothing changed. A few collide (`Error writing to source link file ... being used by another process`, `CS2012`), so a
*different* set of services died on every start. Do not run `dotnet build` on the solution (or build in your IDE) while the AppHost is
starting. If you already built and want to skip the AppHost's build, pass `-- --ETP_NO_BUILD=true`.

```bash
# build and start the 11 services + dashboard; Ctrl+C stops them
dotnet run --project aspire/Etp.AppHost
```

1. The first run downloads the Aspire packages and builds the 11 services: a few minutes. Keep this terminal open; `Ctrl+C` stops everything.
2. The console prints `Login to the dashboard at http://localhost:15888/login?t=...`. Open that link.
3. In the **Resources** tab each service goes *Starting* -> *Running*. Admin applies the database migrations first; the others follow.
   Wait until all 11 are *Running* (about a minute after the build) before Step 6.
4. If a service shows **Finished** or **Failed to start**, it crashed. Click it and read its console log ([Troubleshooting](#9-troubleshooting)).

### Step 6. Verify

Open a **second** terminal in the workspace root:

```bash
# PASS/FAIL checks: containers, 11 health endpoints, Cognito login, 401 without token / 200 with token
pwsh ./scripts/Test-EtpLocal.ps1
```

It checks the five containers, the 11 `/health` endpoints, a Cognito login against Floci, and that a protected Admin endpoint answers
**401 without a token and 200 with one**. Every line should say `PASS`; a `FAIL` line says what to do. If the health lines fail right after Step 5,
the services are still starting: wait and run it again.

Extra checks if you like: `curl.exe http://localhost:5103/event/api/v1/landing-page-image/public` returns `[]` on an empty database (rows once you have run the [test-data script](#7-everyday-tasks)); and in DBeaver/pgAdmin
(`localhost:5432`, db `etp_local`, user `etp`, password `etp_local_pw`) `select count(*) from etp."__EFMigrationsHistory";` returns **129** once all services have started once.
Swagger UIs are listed in the table below.

**Swagger (API explorer) for every service.** Open the link in a browser while the AppHost is running. Pattern: `http://localhost:<port>/<service-name>/swagger`
(the plain `/swagger` path returns 404). To call a protected endpoint, use the **Authorize** button and paste an access token ([Everyday tasks](#7-everyday-tasks)).

| Service | Port | Swagger UI | OpenAPI JSON |
|---|---|---|---|
| Admin | 5101 | http://localhost:5101/admin/swagger | http://localhost:5101/admin/swagger/v1/swagger.json |
| Booking | 5102 | http://localhost:5102/booking/swagger | http://localhost:5102/booking/swagger/v1/swagger.json |
| Event | 5103 | http://localhost:5103/event/swagger | http://localhost:5103/event/swagger/v1/swagger.json |
| Platform | 5104 | http://localhost:5104/platform/swagger | http://localhost:5104/platform/swagger/v1/swagger.json |
| PushNotification | 5105 | http://localhost:5105/pushnotification/swagger | http://localhost:5105/pushnotification/swagger/v1/swagger.json |
| Scheduler | 5106 | http://localhost:5106/scheduler/swagger | http://localhost:5106/scheduler/swagger/v1/swagger.json |
| TicketChecker | 5107 | http://localhost:5107/ticketchecker/swagger | http://localhost:5107/ticketchecker/swagger/v1/swagger.json |
| Ticketing | 5108 | http://localhost:5108/ticketing/swagger | http://localhost:5108/ticketing/swagger/v1/swagger.json |
| UserAuth | 5109 | none (an empty stub service: only `/health` answers) | none |
| UserIssue | 5110 | http://localhost:5110/userissue/swagger | http://localhost:5110/userissue/swagger/v1/swagger.json |
| Utility | 5111 | http://localhost:5111/utility/swagger | http://localhost:5111/utility/swagger/v1/swagger.json |

All of these were opened and answered with HTTP 200 on a fresh setup. Health check for every service: `http://localhost:<port>/health`.

Some log noise is expected locally and does not stop the services: Scheduler may log Firebase warnings (no Firebase locally), Ticketing may log
`CryptographicException` because the ticket-signing certificate is not available, and background workers may log `Could NOT acquire lock ... Skipping this cycle`.
To silence Ticketing, skip it (see [Daily routine](#4-daily-routine)).

### Step 7. Load test data (optional)

The database has its tables but no rows. With all services *Running* (Step 5), load the BCB cricket sample data from the second terminal:

```bash
# programs, grounds, matches, prices, capacity, orders, tickets, scans, issues (safe to re-run; add -Reset to reload)
pwsh ./scripts/Seed-EtpData.ps1
```

What it contains, how to log in as the owners of the orders, and what it does not cover: [Everyday tasks, Test data](#7-everyday-tasks).
Check: `curl.exe http://localhost:5103/event/api/v1/landing-page-image/public` now returns the landing-page images instead of `[]`.

You are now ready to build, run and debug.

**Portals (optional):** to log in to the Angular portals against this backend, see [admin-portal-local.md](admin-portal-local.md)
(`pwsh ./scripts/Setup-AdminPortal.ps1 -Start`) and [user-portal-local.md](user-portal-local.md) (`pwsh ./scripts/Setup-UserPortal.ps1 -Start`).

---

## 4. Daily routine

**Morning**

```bash
# get the latest workspace changes
git pull
# only needed if the pinned submodule commits changed
git submodule update --init
# PostgreSQL, Redis, DynamoDB and Floci (does nothing if already running; Floci's pools, queues and users persist, so do not re-seed)
docker compose up -d
# start all services + dashboard
dotnet run --project aspire/Etp.AppHost
```

Start the Docker parts before the AppHost. Once the services are *Running*, `pwsh ./scripts/Test-EtpLocal.ps1` confirms that everything works (about 20 seconds). New database migrations that other people added are applied automatically at service startup.

**After a PC shutdown or reboot** there is nothing to redo: your Cognito IDs are saved in the services' user secrets,
and Floci keeps its data in the `etp-floci-data` volume. Just run the commands above.
If you get 401 everywhere, check that Floci still has its pools: `aws --endpoint-url http://localhost:4566 cognito-idp list-user-pools --max-results 60` (AWS CLI setup: Step 3).
An empty list means Floci lost its data (persistence is not guaranteed on every Floci version): follow "After either reset" in [Teardown](#8-teardown-and-cleanup).

**Run fewer services** (saves RAM and noise). Pass the names (comma separated, no spaces) after `--`:

```bash
# start everything except the listed services
dotnet run --project aspire/Etp.AppHost -- --ETP_SKIP=Platform,UserAuth,Utility,Ticketing
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
- Optional: `docker compose stop`. Your data stays.

---

## 5. Build

The services build automatically when Aspire starts them. To build or check for compile errors yourself:

```bash
# compile the whole backend; stop the AppHost first
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
`curl.exe http://localhost:5103/event/api/v1/landing-page-image/public`. Execution should stop on your breakpoint.

Tips:
- Attach to **two services at once** to step through a call from one into the other (for example Booking calling Admin).
- Stop on any thrown exception: Visual Studio `Ctrl+Alt+E` and tick *Common Language Runtime Exceptions*; VS Code, tick *All Exceptions* in the Breakpoints panel.
- Background workers (`Workers/BackgroundServices/*`) start about a minute after boot. Put a breakpoint inside `ExecuteAsync`.
- You cannot hit breakpoints in code that already ran (startup, migrations) with a late attach: use 6.2.

### 6.2 Debug a service from its first line

Tell Aspire not to start that service, then start it yourself from the IDE on the same port. All other services keep calling it at the usual URL,
so breakpoints fire for calls coming from them too. Example for **Event** (port 5103):

```bash
# start everything except Event (your IDE starts it)
dotnet run --project aspire/Etp.AppHost -- --ETP_SKIP=Event
```

| IDE | Steps |
|---|---|
| **VS Code** | *Run and Debug* > **Event (5103)** > F5. Configs for all 11 services are in `.vscode/launch.json`; they build first and set the port, environment and Floci endpoint |
| **Rider** | *Run > Edit Configurations > + > .NET Project*, project `ETP.Event.Service`, untick the launch profile, environment variables `ASPNETCORE_ENVIRONMENT=Development;ASPNETCORE_URLS=http://localhost:5103;AWS_ENDPOINT_URL=http://localhost:4566`, then Debug |
| **Visual Studio** | Run it in a terminal with those variables (commands right below the table), then attach (6.1) |

Run one service from a terminal (Event shown; use its port from the list in 6.2) so Visual Studio can attach:

```powershell
# PowerShell 7: set the variables, then start Event without its launch profile
$env:ASPNETCORE_ENVIRONMENT = "Development"; $env:ASPNETCORE_URLS = "http://localhost:5103"; $env:AWS_ENDPOINT_URL = "http://localhost:4566"
dotnet run --project rvl-gobcb-backend/Services/Event/ETP.Event.Service --no-launch-profile
```

```bash
# Git Bash: same thing in one line
ASPNETCORE_ENVIRONMENT=Development ASPNETCORE_URLS=http://localhost:5103 AWS_ENDPOINT_URL=http://localhost:4566 dotnet run --project rvl-gobcb-backend/Services/Event/ETP.Event.Service --no-launch-profile
```

Why not simply press F5 on the service in Visual Studio? The repo's `launchSettings.json` ports differ from the fixed ports the services expect
(and two services share 5033), and fixing that would mean editing a file inside a submodule. Do not use the *Launch Profiles* editor for the same reason.

This works because the connection strings and service URLs are also in your user secrets (Step 4), so a service started outside Aspire finds Postgres, Redis and its siblings.
Start **Admin** first if the database is empty, because it creates the tables.

### 6.3 F5 on the AppHost

Visual Studio 17.9+ and Rider (with Aspire support) can start `aspire/Etp.AppHost` (profile `http`) under the debugger and attach to the child services.
VS Code has an **Aspire AppHost** config in `launch.json`. This is not verified for every IDE version; if breakpoints show as "not bound", use 6.1.

---

## 7. Everyday tasks

**Call a protected API.** Most endpoints need a Cognito token. Get one from Floci for a seeded user (use the Admin `ClientId` printed by `pwsh ./scripts/Seed-EtpCognitoUsers.ps1`; AWS CLI setup: Step 3):

```bash
# log in as the admin test user; prints the tokens
aws --endpoint-url http://localhost:4566 cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id <ADMIN_CLIENT_ID> --auth-parameters 'USERNAME=+8801700000001,PASSWORD=Passw0rd!23'
```

Copy the `AccessToken` value into Swagger's **Authorize** button (token only, no `Bearer`). Admin endpoints scoped to a program also need the header `X-Program-Id: <id>`.
There is also a ready Postman collection in `postman/` ([README section 10](../README.md#10-postman-cognito-and-auth-tests)).

**Look at the database.**

```bash
# open a SQL prompt in the Postgres container; try:  \dt etp.*   or   select ... ;
docker exec -it etp-postgres psql -U etp -d etp_local
```

or (easier) connect DBeaver to `localhost:5432`, database `etp_local`, user `etp`, password `etp_local_pw`.
**Test data (BCB cricket).** The code has no seeder, so the workspace ships one. After all services were *Running* once (that applies the migrations), run:

```bash
# idempotent; add -Reset to wipe the seed rows and load them again (use it after pulling a new version of the seed)
pwsh ./scripts/Seed-EtpData.ps1
```

It loads a small, linked cricket data set (plain SQL in `scripts/seed/`). Ground names are real; **fixtures, stand layouts and prices are sample data**, not the real BCB schedule or tariff.

| Area | What you get |
|---|---|
| **Programs** (Ids match the Cognito users' `custom:program_ids` = 1,2) | **1 Bangladesh vs India Series** (bilateral; 15% VAT added on top, 2% platform charge, ticket prefix `BDI`) and **2 Bangladesh Premier League** (franchise tournament; prices include VAT, 3% platform charge, prefix `BPL`). Teams: Bangladesh, India; Dhaka Capitals, Chattogram Challengers, Rangpur Riders, Sylhet Strikers |
| **Grounds** | Sher-e-Bangla National Cricket Stadium (Mirpur), Zahur Ahmed Chowdhury Stadium (Chattogram), Sylhet International Cricket Stadium. Each has gallery > block > level (a seated Pavilion with Row A/B, general stands, a Student Enclosure at Mirpur), entry gates and mini gates |
| **Matches** (7) | 1 Test over 5 days (one segment per day = a multi-segment ticket) · 2 **1st ODI at Mirpur, live today** (started an hour ago) · 3 2nd ODI at Chattogram · 4 1st T20I at Sylhet, **unpublished draft** · 5-7 three BPL matches. Each has settings, segments, and price + capacity per level |
| **Promotions** | Discounts: early bird 10% on the Mirpur Pavilion (active), a flat one (expired), BPL launch 15% (upcoming). Promo codes `BCBWELCOME10` (2nd ODI Pavilion), `BPLFLAT100`, `OLDCODE` (expired) |
| **Inventory cases** | Seated rows with sold, locked and free seats; a general stand; **sold-out online** (1st ODI Student Enclosure, all 300 seats handed to a partner reservation); **limited availability** (Sylhet BPL General, 25 of 300 left, below the 10% threshold); a complimentary reservation (B9, B10; one ticket already issued) |
| **Orders** (9, all for the `+8801700000011` user) | Paid x6, Pending (seat locked), Failed (declined), Cancelled. Series orders show VAT on top; BPL orders show VAT included; one order used a promo code, one an early-bird discount. 14 tickets (status Active, Requested, Generated), booked-user records, raffle rows |
| **Match day** | Gates and gate staff for the ticket-checker user, scans for the live ODI (a normal entry, a duplicate scan, a manual entry) |
| **Support and push** | 2 user issues (Open, Resolved) with chat on 1st ODI orders, device tokens, activity logs, landing-page images (hero, sponsors, notice, FAQ, one unpublished) |

Rows that belong to a user carry the real Cognito `sub` of the seeded Floci users (looked up when you run the script), so log in as `+8801700000011` (user),
`+8801700000021` (ticket checker), `+8801700000004` (ticket operator) or `+8801700000001` (admin) to see them. Seed rows use Ids below 100; the identity sequences
are moved past 99, so rows you create later through the APIs never collide and are left alone by `-Reset`. The script also clears the services' Redis cache so new rows show up straight away.

Try it: `curl.exe http://localhost:5103/event/api/v1/landing-page-image/public` returns the published images. In Swagger (Admin, with a token) `GET /admin/api/v1/events` lists the matches.

**What this does not cover**
- **Real payments and ticket PDFs.** DgePay, the TSP certificate and OneID are dummies locally, so you cannot run a genuine book > pay > ticket flow. The seed supplies the *results* (paid orders, tickets, scans) so
  the read, list, report, admin and gate screens can be tested; writes (booking, seat lock, cancel, issue reply, check-in) work on this data but payment callbacks and ticket signing do not.
- **S3 files.** Image, SVG and PDF values are placeholder paths, not objects in Floci.
- **Services with no tables.** Scheduler, Utility, Platform and UserAuth store nothing in Postgres, so there is nothing to seed. The DynamoDB ticket queue is written on demand.
- **Agent sales and OneID.** The Agent pool user exists but no agent-sold tickets are seeded.

After `docker compose down -v` the seed is gone along with the schema; start the AppHost once, then run the script again. If you reset **only Floci**, the database keeps its rows but the Cognito users get new `sub` values, so run `pwsh ./scripts/Seed-EtpData.ps1 -Reset` to relink them.

**Look at fake AWS.**

```bash
# list every file in the local S3 bucket
aws --endpoint-url http://localhost:4566 s3 ls s3://etp-local --recursive
# list the local SQS queues
aws --endpoint-url http://localhost:4566 sqs list-queues
```

**Inspect Redis.** `docker exec etp-redis redis-cli --scan` lists keys; `docker exec etp-redis redis-cli flushall` clears the cache.

**Before you commit.** Add specific files (no `git add -A`), never commit secrets, and check that submodules are untouched:
`git submodule foreach "git status --porcelain"` must print nothing.

---

## 8. Teardown and cleanup

Pick the level you need. Never run `docker system prune -a --volumes`: it deletes the data of every project on your machine.

**Stop only (data kept)**

```bash
# first press Ctrl+C in the AppHost terminal
# stop all containers: PostgreSQL, Redis, DynamoDB, Floci (data stays in volumes)
docker compose stop
```

**Reset data (clean database and AWS, keep images)**

To wipe **everything** (PostgreSQL, Redis and Floci) and start empty:

```bash
# remove all containers AND all data volumes (PostgreSQL, Redis, Floci)
docker compose down -v
# start them again, empty
docker compose up -d
```

To reset **only Floci** (keep the database): this wipes its buckets, queues and Cognito pools, and the IDs change.

```bash
# remove the Floci containers, then its data volume
docker compose rm -sf floci floci-tls floci-ui
docker volume rm etp-floci-data
# start Floci again, empty (PostgreSQL and Redis are untouched)
docker compose up -d
```

**After either reset**, seed Floci again:

```bash
# re-create bucket, queues, SES identity
pwsh ./scripts/Seed-EtpFloci.ps1
# re-create Cognito pools and users (new IDs)
pwsh ./scripts/Seed-EtpCognitoUsers.ps1
# pick up the new Cognito IDs; then restart the AppHost
pwsh ./scripts/Set-EtpSecrets.ps1
# only if you reset Floci but kept the database: relink the test data to the new users (needs the AppHost running)
pwsh ./scripts/Seed-EtpData.ps1 -Reset
```

**Full cleanup (data and images)**

```bash
# remove all containers (infra, Floci, proxy, console), data volumes and images
docker compose down --volumes --rmi all --remove-orphans
# remove the user secrets from all 11 services (+ your optional override file)
pwsh ./scripts/Clear-EtpSecrets.ps1
# remove the exported HTTPS certificate (Setup-EtpHttps.ps1 recreates it)
rm -rf floci/certs
# leftovers check: should list nothing
docker ps -a --filter "name=etp"
# leftovers check: should list nothing
docker volume ls --filter "name=etp"
```

`docker rmi` refuses to remove an image that a container still uses, which protects other projects that share `postgres` or `redis`.
Finally, `dotnet clean rvl-gobcb-backend/RVL-ETP.BackEnd.sln` (removes build output), and `git submodule foreach "git status --porcelain"` must print nothing.
To start again, go back to [Part 3](#3-first-time-setup).

---

## 9. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `docker version` shows no Server / containers fail to start | Docker Desktop is not running. Start it and wait for the whale icon to be steady |
| `port is already allocated` (5432, 6379, 8000, 4566, 4567, 4500) | Another program owns the port: `pwsh -c "Get-NetTCPConnection -LocalPort 5432 -State Listen"` shows which. Stop it (a native Postgres/Redis, LocalStack) |
| Every request fails with `The MetadataAddress or Authority must use HTTPS` | The Cognito URLs in your secrets are `http://`. Run `pwsh ./scripts/Setup-EtpHttps.ps1`, `docker compose up -d`, then `pwsh ./scripts/Set-EtpSecrets.ps1` and restart the AppHost |
| Valid token still gets **401** `The signature key was not found`, or **403**, or logs `User pool ... does not exist` | Usually the pools in Floci do not match your secrets (see "401 on every call" below) or were created in another region: everything must be in `ap-southeast-1`. Reset only Floci and re-seed ([Teardown](#8-teardown-and-cleanup)). If a fresh seed still gives the signature error, check the discovery document through the proxy: `curl.exe -k https://localhost:4567/<PoolId>/.well-known/openid-configuration` must show `"jwks_uri"` first; that rewrite is the `sub_filter` block in the `floci_nginx` config of `docker-compose.yml` (a workaround for mismatched IdentityModel package versions in the backend) |
| `docker compose up -d` fails with `bind source path does not exist: .../floci/certs` | You have not created the HTTPS certificate yet. Run `pwsh ./scripts/Setup-EtpHttps.ps1`, then `docker compose up -d` again |
| `etp-floci-tls` keeps restarting, or https://localhost:4567 does not answer | The certificate files are missing or incomplete. Run `pwsh ./scripts/Setup-EtpHttps.ps1`, then `docker compose up -d` again |
| `docker compose up -d` rejects the `configs:` block (an error mentioning `content`) | Docker Compose is too old for inline configs. Update Docker Desktop (4.26 or newer); check with `docker compose version` (2.23.1+) |
| The "Open Floci UI" button on http://localhost:4566 shows "could not reach the container runtime" | Expected: no Docker socket is mounted on purpose. Open the console at http://localhost:4500 directly |
| Service **Finished** right after start | It crashed; read its console log. *Redis/Postgres connection* error: infra is down, run `docker compose up -d` (`docker compose ps` to check) and restart the AppHost. *`[see User Secrets]`/FormatException*: secrets not applied, re-run `pwsh ./scripts/Set-EtpSecrets.ps1`. `UserIssue` NullReference on `Application:ServiceName`: re-run the script |
| `container name "/etp-floci" is already in use` after pulling | Floci used to have its own compose file and project. Remove the old containers (data in the `etp-floci-data` volume is kept, no re-seed): `docker rm -f etp-floci etp-floci-tls etp-floci-ui`, then `docker compose up -d` |
| `password authentication failed for user "etp"` | The Postgres volume was created with another password. `docker compose down -v` and start again |
| `relation "etp.xxx" does not exist` | Admin has not finished its migrations yet; wait, or check Admin's log |
| Admin crashes at startup with `42P07: relation "__EFMigrationsHistory" already exists` | Concurrent migration race on a fresh database. Restart the AppHost; if it repeats after a reset, run `docker compose down -v && docker compose up -d`, then start the AppHost again |
| Several services **Failed to start** with build errors `CS2012` / `error MSB3026` / `Error writing to source link file` ("file ... is being used by another process") — different services fail on each restart | Parallel-build race: the AppHost now builds once and runs services with `--no-build`, so this means something else is building at the same time (IDE background build, an older AppHost, or `--ETP_NO_BUILD=true` with a stale tree). Stop the AppHost, wait for IDE builds to finish, start it again. Stale processes from earlier failed runs can also hold locks: `Get-Process ETP.* | Stop-Process -Force`. Recurring on every cold rebuild? Exclude the workspace from Defender real-time scanning (admin PowerShell): `Add-MpPreference -ExclusionPath '<workspace root>'` |
| 401 on every call | Token expired, or the Cognito IDs in your secrets no longer match Floci (they change when Floci's data is recreated). Re-run `pwsh ./scripts/Set-EtpSecrets.ps1` (it reads the current IDs from Floci), restart |
| AWS errors such as `UnrecognizedClientException` or calls reaching real AWS | Floci is not running; Aspire sets `AWS_ENDPOINT_URL` for the services it starts, but a service you launch yourself needs it too (6.2) |
| S3 `NoSuchBucket` | Bucket missing: `aws --endpoint-url http://localhost:4566 s3 ls` (AWS CLI setup: Step 3); re-seed if empty |
| Ticketing log spam `CryptographicException` | Missing TSP certificate. Skip it with `-- --ETP_SKIP=Ticketing` (see Daily routine) unless you work on tickets |
| Build error "file is locked" | A service is still running. Stop the AppHost |
| Breakpoint hollow / "not bound" | Wrong process, or stale build. Rebuild and re-attach |
| `dotnet ef` fails with `System.Runtime, Version=10.0.0.0` | Install the 8.x tool: `dotnet tool install --global dotnet-ef --version 8.0.11` |

Still stuck: Aspire dashboard > the failing service > console logs usually names the cause. Then ask the team with that log line.
