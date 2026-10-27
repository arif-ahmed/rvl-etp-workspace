# ETP local dev with .NET Aspire

Runs the whole `rvl-gobcb-backend` stack **and its infrastructure** with one command. The AppHost lives here,
**outside** the backend repo, so `rvl-gobcb-backend` is never modified (services are launched by csproj path and
configured with env vars only).

## What it starts

| Resource | Container / port | Notes |
|---|---|---|
| `postgres` | `etp-postgres`, `localhost:5432` | PostgreSQL 16, db `etp_local`, user `etp`, password `etp_local_pw`, volume `etp-local_etp-pgdata` |
| `redis` | `etp-redis`, `localhost:6379` | Redis 7, no password, no TLS, volume `etp-local_etp-redis-data` |
| `dynamodb` | `etp-dynamodb`, `localhost:8000` | DynamoDB Local, in-memory (Ticketing hard-codes it) |
| `floci` | `etp-floci`, `http://localhost:4566` | Fake AWS (S3, SQS, SES, Cognito), persistent volume `etp-floci-data` |
| `floci-tls` | `etp-floci-tls`, `https://localhost:4567`, `http://localhost:4569` | nginx: HTTPS front for Cognito URLs + notification stub. Config: `floci/nginx.conf` |
| `floci-ui` | `etp-floci-ui`, `http://localhost:4500` | Floci web console. `floci-tls` and `floci-ui` are nested under `floci` in the dashboard (display only) |
| 11 services | Admin 5101, Booking 5102, Event 5103, Platform 5104, PushNotification 5105, Scheduler 5106, TicketChecker 5107, Ticketing 5108, UserAuth 5109, UserIssue 5110, Utility 5111 | health: `/health`. Start only after infra is healthy; the ten others also wait for Admin (see Start order) |

Floci seeding is **not** part of the AppHost. Floci is persistent and the seed scripts are idempotent, so seeding is a
one-time setup step (see First-time setup).

## Start order

```
postgres, redis, dynamodb, floci -> floci-tls
      -> admin          (applies the shared DB migrations before it listens; /health is green only afterwards)
      -> the other 10 services
```

About eight services run `Database.Migrate()` at startup against the same database and the same
`etp.__EFMigrationsHistory` table. The backend is on EF Core 8, which has no migration lock, so starting them all at once
on a fresh database can fail with `42P07` or `relation "etp.xxx" does not exist`. Making the other services wait for
Admin avoids that. If you run Admin from your IDE (`ETP_SKIP=Admin`), the AppHost waits for `http://localhost:5101/health` instead.

Postgres, Redis and Floci containers are **persistent**: they keep running after you stop the AppHost, so the next
start is fast and data is kept. Container names and host ports are fixed because the user secrets, seed scripts and
docs depend on them.

Config is injected as env vars (`ConnectionStrings__*`, `Services__*`, `Cache__Redis__*`,
`DistributedLock__Redis__*`, `AWS_ENDPOINT_URL`, `Notification__Endpoint`). Everything else (AWS keys, Cognito IDs,
SQS, S3, SES, DgePay) still comes from each service's own `dotnet user-secrets`.

## Prerequisites

- .NET SDK 10 (AppHost) and .NET SDK 8 (services)
- Docker Desktop running
- PowerShell 7 (`pwsh`) and the AWS CLI on the PATH (the one-time Floci seed scripts use them)
- The backend submodule checked out: `git submodule update --init`
- Once per machine: `pwsh ./scripts/Setup-EtpHttps.ps1` (HTTPS certificate for the Floci proxy; the AppHost refuses to
  start without `certs/localhost.pem` and `certs/localhost.key`)
- User secrets already set for the services (`scripts/Set-EtpSecrets.ps1`)

## First-time setup (once per machine, and again after a Floci data reset)

```powershell
$env:ETP_INFRA_ONLY = "true"; dotnet run --project aspire/Etp.AppHost   # infra only; leave it running
pwsh ./scripts/Seed-EtpFloci.ps1
pwsh ./scripts/Seed-EtpCognitoUsers.ps1
pwsh ./scripts/Set-EtpSecrets.ps1
```

Then stop the infra-only run (`Ctrl+C`; the containers keep running) and use the normal run below.

## Run

From the workspace root (`rvl-etp-workspace`):

```powershell
dotnet run --project aspire/Etp.AppHost
```

Or open `aspire/Etp.AppHost` in your IDE and run it (profile `http`).

1. The console prints a dashboard URL with a login token; open it (`http://localhost:15888`).
2. The first start takes a few minutes: Docker pulls images and all services build once.
3. Wait until services show **Running** (green) in the dashboard.

Check from a shell: `curl http://localhost:5103/health` (Event), and so on for 5101-5111.

Switches (environment variables or `--ETP_SKIP=...` style arguments):

| Variable | Effect |
|---|---|
| `ETP_SKIP=Event,Booking` | Do not launch those services; run them from your IDE on the same port |
| `ETP_NO_BUILD=true` | Skip the one-time solution build (you just built in the IDE) |
| `ETP_INFRA_ONLY=true` | Infra only, no build, no services. Use it on first setup, to seed Floci before `Set-EtpSecrets.ps1` |

## Stop

`Ctrl+C` in the terminal (or the stop button in the dashboard) stops the services and the AppHost. Postgres, Redis and
Floci containers stay up on purpose. To stop them as well:

```powershell
docker stop etp-postgres etp-redis etp-floci etp-floci-tls etp-floci-ui etp-dynamodb
```

## Using docker compose instead

The root `docker-compose.yml` starts the same infrastructure (no services, no seeding). Use one or the other, never
both: container names, ports and volumes are identical, so data carries over when you switch. Steps:
[docs/local-dev.md](../docs/local-dev.md#choosing-aspire-or-docker-compose).

## Troubleshooting

- **Services stuck in "Waiting"** - a dependency is not healthy. Open `postgres`, `redis`, `dynamodb`, `floci`,
  `floci-tls` and `admin` in the dashboard and read their logs. Everything except Admin waits for Admin's migrations.
- **401 on every call right after a Floci reset** - Floci was not re-seeded. Run the First-time setup steps again.
- **AppHost exits with "HTTPS certificate missing"** - run `pwsh ./scripts/Setup-EtpHttps.ps1`.
- **Port already in use / name conflict** - the old compose stack or a native Postgres/Redis is running. Remove
  leftovers with `docker rm -f etp-postgres etp-redis etp-dynamodb etp-floci etp-floci-tls etp-floci-ui`
  (volumes are kept).
- **Postgres `password authentication failed`** - the volume was created with another password. Reset:
  `docker rm -f etp-postgres; docker volume rm etp-local_etp-pgdata` (data is lost), then run again.
- **Service state "Finished"** - it crashed on startup. Open its console logs in the dashboard
  (a Redis connection error means Redis isn't reachable; a missing-config error means user secrets).
- **Reset everything**: stop the AppHost, then
  `docker rm -f etp-postgres etp-redis etp-floci etp-floci-tls etp-floci-ui etp-dynamodb` and
  `docker volume rm etp-local_etp-pgdata etp-local_etp-redis-data etp-floci-data`.

## Changing things

All wiring is in `Etp.AppHost/AppHost.cs`: add a service to the `defs` list, change ports, image tags or resources.
Redis is a plain container (not `AddRedis`) because it must be passwordless/non-TLS: `ETP.Core` `CacheConfig` only
forwards `host:port`. The Redis and DynamoDB health probes use `127.0.0.1` on purpose (`localhost` tries `::1` first
and stalls, because Docker publishes on IPv4 loopback only).
