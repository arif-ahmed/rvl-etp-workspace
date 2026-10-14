# ETP local dev with .NET Aspire

Runs the whole `rvl-gobcb-backend` stack with one command. The AppHost lives here, **outside** the
backend repo, so `rvl-gobcb-backend` is never modified.

## What it starts

| Resource | Details |
|---|---|
| 11 services | Admin 5101, Booking 5102, Event 5103, Platform 5104, PushNotification 5105, Scheduler 5106, TicketChecker 5107, Ticketing 5108, UserAuth 5109, UserIssue 5110, Utility 5111 (health: `/health`) |
| Postgres | one `etp` database (+ pgAdmin), password `etp-local-pg`, volume `etp-postgres-data` |
| Redis | no password, no TLS (+ RedisInsight), volume `etp-redis-data` |
| DynamoDB Local | port 8000 (Ticketing hard-codes it) |

Config is injected as env vars (`ConnectionStrings__*`, `Services__*`, `Cache__Redis__*`,
`DistributedLock__Redis__*`). Everything else (AWS, Cognito, SQS, S3, SES, DgePay) still comes from each
service's own `dotnet user-secrets`.

## Prerequisites

- .NET SDK 10 (AppHost) and .NET SDK 8 (services)
- Docker Desktop running
- The backend submodule checked out: `git submodule update --init`
- User secrets already set for the services (same as before Aspire)

## Run

From the workspace root (`rvl-etp-workspace`):

```powershell
dotnet run --project aspire/Etp.AppHost
```

Or open `aspire/Etp.AppHost` in your IDE and run it (profile `http`).

1. The console prints a dashboard URL with a login token (the dashboard port is dynamic); open it.
2. The first start takes a minute or two: Docker pulls images and all 11 services build.
3. Wait until services show **Running** (green) in the dashboard. Console, structured logs and
   traces are per resource there.

Check from a shell: `curl http://localhost:5103/health` (Event), and so on for 5101-5111.

## Stop

Press `Ctrl+C` in the terminal (or the stop button in the dashboard). Avoid force-killing the process:
it can leave Docker containers behind.

## Troubleshooting

- **Services stuck in "Waiting"** - Postgres/Redis aren't healthy yet. Check their logs in the dashboard.
- **Postgres `password authentication failed`** - the volume was created with another password. Reset:
  `docker volume rm etp-postgres-data` (data is lost), then run again.
- **Service state "Finished"** - it crashed on startup. Open its console logs in the dashboard
  (a Redis connection error means Redis isn't reachable; a missing-config error means user secrets).
- **Port already in use** - another process uses 5101-5111, 8000, or the Redis/Postgres host ports.
- **Reset everything**: stop the AppHost, then `docker volume rm etp-postgres-data etp-redis-data`.

## Changing things

All wiring is in `Etp.AppHost/AppHost.cs`: add a service to the `defs` list, change ports, or add
resources. Redis is passwordless/non-TLS on purpose because `ETP.Core` `CacheConfig` only forwards `host:port`.
