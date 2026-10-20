# Floci: local AWS emulation for ETP

[Floci](https://floci.io/aws/) is a single-container AWS emulator (port 4566). It stands in for real AWS
S3, SQS, SES and Cognito while developing the `rvl-gobcb-backend` services. It is standalone: it does not
depend on the Aspire AppHost, and you can use it with or without it.

> The compose file and seed script have not been verified against a live Floci yet. Where this guide says
> "confirm", check the Floci docs for your image version.

| Resource | Name(s) |
|---|---|
| S3 bucket | `etp-local` |
| SQS queues | `OrderSuccess`, `EventCapacity`, `FirebaseNotification`, `TicketProcessing` |
| SES identity | `noreply@etp.local` |
| Cognito pools | `Admin`, `User`, `TicketChecker`, `Agent` (each with one app client) |
| Region | `ap-southeast-1` |
| Credentials | any value works; we use `test` / `test` |

DynamoDB is not on Floci. `Ticketing` hard-codes DynamoDB Local at `localhost:8000` (provided by Aspire).

---

## First-time setup (once per machine)

### 1. Prerequisites
- Docker Desktop running
- AWS CLI v2 (`aws --version`)
- PowerShell 7 (`pwsh`)

### 2. Start Floci
```powershell
cd floci
docker compose up -d
docker compose logs -f floci     # wait until it reports ready, then Ctrl+C
```
This starts two containers, both pinned to fixed versions in `docker-compose.yml`:

| Container | URL |
|---|---|
| `etp-floci` (emulator) | http://localhost:4566 |
| `etp-floci-ui` (web console) | http://localhost:4500 |

The console is a normal compose service and talks to Floci at `http://floci:4566` on the compose network.
No Docker socket is mounted. The "Open Floci UI" button on the 4566 dashboard therefore does not work (it
needs the socket to launch its own sidecar); open http://localhost:4500 directly instead.

Quick check: `aws --endpoint-url http://localhost:4566 s3 ls` should return without error
(set `AWS_ACCESS_KEY_ID=test` and `AWS_SECRET_ACCESS_KEY=test` first if the CLI complains about credentials).

### 3. Seed the resources
```powershell
./seed.ps1
```
Copy the printed output. It contains the generated Cognito `PoolId` / `ClientId` values.

### 4. Point the services at Floci
Run in each service project folder (`rvl-gobcb-backend/Services/<Name>/ETP.<Name>.Service`), for the
services that use AWS. Use the values printed by `seed.ps1`:

```powershell
dotnet user-secrets set "AWS:Region" "ap-southeast-1"
dotnet user-secrets set "AWS:AccessKey" "test"
dotnet user-secrets set "AWS:SecretAccessKey" "test"
dotnet user-secrets set "AWS:Bucket:Name" "etp-local"
dotnet user-secrets set "AWS:Bucket:BaseUrl" "http://localhost:4566"   # the code uses this as the S3 ServiceURL
dotnet user-secrets set "AWS:Queue:OrderSuccess" "OrderSuccess"
dotnet user-secrets set "AWS:Queue:EventCapacity" "EventCapacity"
dotnet user-secrets set "AWS:Queue:FirebaseNotification" "FirebaseNotification"
dotnet user-secrets set "AWS:Queue:TicketProcessing" "TicketProcessing"   # Utility only
# repeat for Admin, User, TicketChecker, Agent:
dotnet user-secrets set "AWS:CognitoPool:Admin:PoolId" "<from seed output>"
dotnet user-secrets set "AWS:CognitoPool:Admin:ClientId" "<from seed output>"
dotnet user-secrets set "AWS:CognitoPool:Admin:Authority" "<Floci issuer URL for the pool>"
dotnet user-secrets set "AWS:CognitoPool:Admin:Metadata" "<Floci OIDC/JWKS metadata URL for the pool>"
```

Also make the AWS SDK use Floci for SQS / SES / Cognito (these have no endpoint set in code). Set this in
the shell that starts the services, or add it to each service's `ASPNETCORE` environment:

```powershell
$env:AWS_ENDPOINT_URL = "http://localhost:4566"
```
Confirm your AWSSDK version honours `AWS_ENDPOINT_URL`; if SQS calls still go to real AWS, upgrade the SDK
or add a `ServiceURL` in the client config.

With Aspire, add `.WithEnvironment("AWS_ENDPOINT_URL", "http://localhost:4566")` in the service loop of
`aspire/Etp.AppHost/AppHost.cs`.

### 5. Verify end to end
1. Start the backend (`dotnet run --project aspire/Etp.AppHost`, or run services individually).
2. `curl http://localhost:5103/health` returns healthy.
3. Exercise one upload (S3), one queue message (SQS), and one login (Cognito).

### 6. Known gaps to close
- Cognito custom attributes / groups the backend expects (see `CognitoUserAttributesMiddleware`) are not created by `seed.ps1` yet.
- `Authority` / `Metadata` URLs for Floci Cognito need confirming from the Floci docs.
- Firebase push notifications and the DgePay payment gateway are not AWS, so Floci does not cover them.

---

## Everyday playbook

### Start of day
```powershell
cd floci
docker compose up -d          # no-op if already running
```
- Data persists in the `etp-floci-data` volume, so you normally do **not** re-run `seed.ps1`.
- If the volume has persisted state but `aws sqs list-queues` shows nothing, the data was lost: re-seed (see Reset).
- Then start the backend as usual (`dotnet run --project aspire/Etp.AppHost`). Start Floci first.

### During the day
| Need | Command |
|---|---|
| List buckets | `aws --endpoint-url http://localhost:4566 s3 ls` |
| List objects | `aws --endpoint-url http://localhost:4566 s3 ls s3://etp-local --recursive` |
| List queues | `aws --endpoint-url http://localhost:4566 sqs list-queues` |
| Peek at a queue | `aws --endpoint-url http://localhost:4566 sqs receive-message --queue-url <url>` |
| Purge a queue | `aws --endpoint-url http://localhost:4566 sqs purge-queue --queue-url <url>` |
| Floci logs | `docker compose logs -f floci` |

Tip: set `$env:AWS_ENDPOINT_URL`, `AWS_REGION`, and the `test` credentials in your shell profile for dev
sessions so you can drop `--endpoint-url`.

### End of day
```powershell
docker compose stop           # keeps data
```

### Reset (clean slate)
```powershell
docker compose down -v        # deletes the etp-floci-data volume
docker compose up -d
./seed.ps1
```
Cognito pool and client IDs are regenerated on re-seed, so update the user-secrets again (step 4).

---

## Troubleshooting

- **Connection refused on 4566:** container not running. `docker compose ps`, then `docker compose logs floci`.
- **Console at :4500 not loading:** `docker compose ps` and `docker compose logs floci-ui`. Do not set `PORT` on the `floci-ui` service; it moves the server off 4500.
- **"Open Floci UI" button errors with "could not reach the container runtime":** expected, see step 2. Use http://localhost:4500.
- **Upgrading:** image tags are pinned (`floci/floci`, `floci/floci-ui`). Bump both in `docker-compose.yml` together, then `docker compose pull && docker compose up -d`.
- **Port 4566 in use:** LocalStack or another emulator is running. Stop it, or change the host port in `docker-compose.yml` and every endpoint URL.
- **Services still hit real AWS:** `AWS_ENDPOINT_URL` is not set in the process that starts the service, or the SDK version ignores it.
- **S3 `NoSuchBucket` / DNS errors:** `AWS:Bucket:BaseUrl` must be `http://localhost:4566` and the bucket must exist (`aws s3 ls`).
- **Queue not found:** the code calls `GetQueueUrl` with the queue *name*, so the secret must be the name (not a URL), and the queue must exist.
- **401 from services after re-seed:** Cognito pool/client IDs changed; update user-secrets and restart services.
- **Emulator fidelity:** the advertised service count is not a fidelity guarantee. Treat Cognito token claims and IAM as things to verify, not assume.

---

## Teardown

Run from the `floci/` folder. Pick the level you need.

### 1. Stop only (keeps containers and data)
```powershell
docker compose stop
```

### 2. Remove containers and network (keeps data and images)
```powershell
docker compose down
```

### 3. Full cleanup: containers, network, data volume and images
```powershell
docker compose down --volumes --rmi all --remove-orphans
```
- `--volumes` deletes `etp-floci-data`: **all buckets, queues and Cognito pools are lost.**
- `--rmi all` deletes the pinned `floci/floci` and `floci/floci-ui` images (they are pulled again on the next `up`).
- `--remove-orphans` also removes leftover containers from this project.

### 4. Leftovers check
```powershell
docker ps -a --filter "name=floci"            # should be empty
docker volume ls --filter "name=floci"        # should be empty
docker images --filter "reference=floci/*"    # should be empty
```
If the dashboard's "Open Floci UI" button was ever used with the Docker socket mounted, it leaves a sidecar
that compose does not manage:
```powershell
docker rm -f floci-aws-ui
```

### After a full teardown
Next time start from [First-time setup](#first-time-setup-once-per-machine): `docker compose up -d`,
`./seed.ps1`, and update the user-secrets, since Cognito pool/client IDs are regenerated.
