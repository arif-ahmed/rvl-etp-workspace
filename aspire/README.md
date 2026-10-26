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
| `floci-ui` | `etp-floci-ui`, `http://localhost:4500` | Floci web console |
| `seed-floci`, `seed-cognito` | host processes (`pwsh`) | Run `scripts/Seed-EtpFloci.ps1` and `scripts/Seed-EtpCognitoUsers.ps1` on every start (idempotent) |
| 11 services | Admin 5101, Booking 5102, Event 5103, Platform 5104, PushNotification 5105, Scheduler 5106, TicketChecker 5107, Ticketing 5108, UserAuth 5109, UserIssue 5110, Utility 5111 | health: `/health`. Start only after infra is healthy and both seeds finished |

Postgres, Redis and Floci containers are **persistent**: they keep running after you stop the AppHost, so the next
start is fast and data is kept. Container names and host ports are fixed because the user secrets, seed scripts and
docs depend on them.

Config is injected as env vars (`ConnectionStrings__*`, `Services__*`, `Cache__Redis__*`,
`DistributedLock__Redis__*`, `AWS_ENDPOINT_URL`, `Notification__Endpoint`). Everything else (AWS keys, Cognito IDs,
SQS, S3, SES, DgePay) still comes from each service's own `dotnet user-secrets`.

## Prerequisites

- .NET SDK 10 (AppHost) and .NET SDK 8 (services)
- Docker Desktop running
- PowerShell 7 (`pwsh`) and the AWS CLI on the PATH (the seed steps use them)
- The backend submodule checked out: `git submodule update --init`
- Once per machine: `pwsh ./scripts/Setup-EtpHttps.ps1` (HTTPS certificate for the Floci proxy; the AppHost refuses to
  start without `certs/localhost.pem` and `certs/localhost.key`)
- User secrets already set for the services (`scripts/Set-EtpSecrets.ps1`)

## Run

From the workspace root (`rvl-etp-workspace`):

```powershell
dotnet run --project aspire/Etp.AppHost
```

Or open `aspire/Etp.AppHost` in your IDE and run it (profile `http`).

1. The console prints a dashboard URL with a login token; open it (`http://localhost:15888`).
2. The first start takes a few minutes: Docker pulls images, all services build once, Floci is seeded.
3. Wait until services show **Running** (green) in the dashboard.

Check from a shell: `curl http://localhost:5103/health` (Event), and so on for 5101-5111.

Switches (environment variables or `--ETP_SKIP=...` style arguments):

| Variable | Effect |
|---|---|
| `ETP_SKIP=Event,Booking` | Do not launch those services; run them from your IDE on the same port |
| `ETP_NO_BUILD=true` | Skip the one-time solution build (you just built in the IDE) |
| `ETP_SKIP_SEED=true` | Skip the Floci seed steps (already seeded; faster restart) |
| `ETP_INFRA_ONLY=true` | Infra + Floci seeding only, no build, no services. Use it on first setup, before `Set-EtpSecrets.ps1` |

## Stop

`Ctrl+C` in the terminal (or the stop button in the dashboard) stops the services and the AppHost. Postgres, Redis and
Floci containers stay up on purpose. To stop them as well:

```powershell
docker stop etp-postgres etp-redis etp-floci etp-floci-tls etp-floci-ui etp-dynamodb
```

## Migrating from the old docker-compose setup

Infra used to come from a root `docker-compose.yml`. Run `docker compose down` once (without `-v`) from a checkout
that still has the file, then start the AppHost: it reuses the same container names, ports and volumes, so existing
data carries over.

## Troubleshooting

- **Services stuck in "Waiting"** - a dependency is not healthy or a seed has not finished/failed. Open `postgres`,
  `redis`, `dynamodb`, `floci`, `floci-tls`, `seed-floci`, `seed-cognito` in the dashboard and read their logs.
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
