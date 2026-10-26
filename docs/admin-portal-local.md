# Admin portal: local setup, run, debug

How to run the Angular admin portal (`rvl-gobcb-admin-portal`) on your PC against the local backend and Floci (fake AWS).
Companion to [local-dev.md](local-dev.md), which covers the backend.

> **The submodule is never edited.** The script builds a throw-away copy in `portal-local/admin-portal/` (git-ignored) and puts all
> local config there. Delete that folder at any time; the script recreates it.

## Contents

1. [Why a copy, and what is different in it](#1-why-a-copy-and-what-is-different-in-it)
2. [Prerequisites](#2-prerequisites)
3. [Setup and run](#3-setup-and-run)
4. [After a Cognito reset](#4-after-a-cognito-reset)
5. [Log in](#5-log-in)
6. [Debug](#6-debug)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Why a copy, and what is different in it

The portal cannot run from the submodule as checked out:

| Problem in the submodule | What the copy does about it |
|---|---|
| `src/environments/environment*.ts` are **empty**; CI fills them from AWS SSM at build time | Script writes them with the current Floci pool/client IDs and local paths |
| Amplify talks to real `cognito-idp.<region>.amazonaws.com` (no endpoint setting) | Script adds `endpoint` to `aws-exports.ts` in the copy, pointing at the dev-server proxy |
| Floci sends no CORS headers; its HTTPS proxy uses a self-signed cert the browser rejects | Browser only talks to `localhost:4200`; the dev server proxies `/p/cognito` to Floci and `/p/<service>` to the backend |
| Login starts with a phone **OTP** from a "serverless" API whose source is not in any repo | Proxy answers the two OTP endpoints locally (**OTP is always `123456`**, local only) |
| The portal signs in with SRP; `scripts/Seed-EtpCognitoUsers.ps1` only enables password auth on the app client | Script enables `ALLOW_USER_SRP_AUTH` on the Floci client |

All other Angular source is an unmodified copy.

```
browser :4200 ── ng serve (portal-local/admin-portal)
                   ├─ /p/cognito     -> Floci        :4566
                   ├─ /p/admin       -> Admin        :5101
                   ├─ /p/booking     -> Booking      :5102
                   ├─ /p/ticketing   -> Ticketing    :5108
                   ├─ /p/userissue   -> UserIssue    :5110
                   └─ /p/serverless  -> local OTP stub (no network)
```

## 2. Prerequisites

Backend setup from [local-dev.md](local-dev.md) done and running (Floci seeded with `scripts/Seed-EtpCognitoUsers.ps1`, AppHost started), plus:

- Node.js 20+ (tested with 24) and npm
- AWS CLI on PATH (already needed for local-dev Step 3)
- The submodule checked out: `git submodule update --init rvl-gobcb-admin-portal`

Check Floci and the Admin service first:

```bash
curl.exe http://localhost:5101/health          # Healthy
aws --endpoint-url http://localhost:4566 cognito-idp list-user-pools --max-results 60   # 4 etp-* pools
```

## 3. Setup and run

From the workspace root:

```bash
# prepare only (copy, config, npm install)
pwsh ./scripts/Setup-AdminPortal.ps1

# prepare and start the dev server (keeps running; Ctrl+C to stop)
pwsh ./scripts/Setup-AdminPortal.ps1 -Start
```

**Fresh clone:** `portal-local/` does not exist after a clone, by design. It is generated and git-ignored (never committed). Just run the
script above; it creates the folder. Make sure the submodule is checked out first (`git submodule update --init`).

The first run takes a few minutes (`npm install`). Later runs take seconds: `node_modules` is kept and reinstalled only when
`package.json` changes. Use `-Port 4300` for another port.

Expected output:

```
cognito Admin pool us-east-1_xxxxxxxxx client xxxxxxxxxxxxxxxxxxxxxxxxxx
ok  SRP enabled on app client
ok  copied ... -> portal-local\admin-portal
ok  environment.ts, aws-exports.ts, proxy.conf.js written
Ready. Log in at http://localhost:4200 ...
```

Open <http://localhost:4200>. The script is safe to re-run at any time, even while the dev server is running (it live-reloads).

## 4. After a Cognito reset

Pool and client IDs change whenever Floci's data is recreated. Nothing in the portal is hand-edited, so the recovery is the same
sequence as the backend, plus one command:

```bash
# 1. recreate Floci data (see local-dev.md, Teardown)
docker rm -f etp-floci etp-floci-tls etp-floci-ui   # Floci only; Postgres and Redis keep their data
docker volume rm etp-floci-data
# restart the AppHost: it re-creates Floci and re-runs the seed scripts (so the two seed lines below are only needed if you skipped that)
pwsh ./scripts/Seed-EtpFloci.ps1
pwsh ./scripts/Seed-EtpCognitoUsers.ps1          # new Cognito pools, clients, users

# 2. backend: pick up the new IDs, then restart the AppHost
pwsh ./scripts/Set-EtpSecrets.ps1

# 3. portal: re-read the IDs, re-enable SRP, rewrite config
pwsh ./scripts/Setup-AdminPortal.ps1 -Start
```

The script reads the IDs live from Floci, so there is no value to copy. If you see `Pool 'etp-admin' not found` the seed step
(`Seed-EtpCognitoUsers.ps1`) was skipped. Log out / clear site data in the browser afterwards: tokens from the old pool are rejected.

## 5. Log in

The login screen is a 3-step flow: phone -> OTP -> password.

| Step | Enter |
|---|---|
| Phone | the 10 digits **without** `+880`, e.g. `1700000001` |
| OTP | `123456` (local stub; the six boxes auto-advance) |
| Password | `Passw0rd!23` |

Seeded Admin-pool users (all use the same password), from `scripts/Seed-EtpCognitoUsers.ps1`:

| Phone | Role | Lands on |
|---|---|---|
| `1700000001` | admin | Program management |
| `1700000002` | event_manager (programs 1,2) | Program management |
| `1700000003` | ticket_manager (programs 1,2) | Home |
| `1700000004` | ticket_operator (program 1) | Home |
| `1700000005` | customer_support | Home |

Test data (programs, orders, tickets) comes from `pwsh ./scripts/Seed-EtpData.ps1`; without it the lists are empty.

Smoke test without a browser (token through the proxy, then a protected call):

```bash
curl.exe -s -X POST http://localhost:4200/p/cognito -H "Content-Type: application/x-amz-json-1.1" -H "X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth" -d "{\"AuthFlow\":\"USER_PASSWORD_AUTH\",\"ClientId\":\"<ClientId>\",\"AuthParameters\":{\"USERNAME\":\"+8801700000001\",\"PASSWORD\":\"Passw0rd!23\"}}"
```

## 6. Debug

- **Browser DevTools (F12).** `ng serve` uses the development build with source maps: Sources tab -> `webpack://` / `src/app/...` to set
  breakpoints in the TypeScript. Look at **Network** (filter `p/`) to see each API call and status, **Console** for errors.
- **Where the code is.** Login: `src/app/modules/auth/login/login.component.ts`. Cognito/token handling:
  `src/app/core/services/cognito.service.ts`. Auth header on every call: `src/app/core/interceptors/auth.interceptor.ts`.
  API base URLs: `src/app/core/application-config.service.ts` (all come from `environment.ts`).
- **VS Code.** Open `portal-local/admin-portal` as a folder, run `ng serve` via the script, then attach with a Chrome launch config
  (`"type": "chrome", "request": "launch", "url": "http://localhost:4200", "webRoot": "${workspaceFolder}"`).
- **Backend side of a failing call.** The proxy forwards unchanged, so the same request hits the service log in the Aspire dashboard
  (<http://localhost:15888>). A 401 there means a token problem, a 404 a wrong path.
- **Editing portal code to try a fix.** Edit the **copy** (`portal-local/admin-portal/src/...`), it hot-reloads. The next
  `Setup-AdminPortal.ps1` run overwrites it from the submodule, so port real fixes to the portal's own repository via a PR.
- **Dev-server output.** Warnings about `ng2-pdf-viewer` and "dynamic import cannot be analyzed by Vite" are harmless.

## 7. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| "An unexpected error occurred" / "Something went wrong" on Send OTP | The OTP stub is not in place (old config or wrong server). Re-run the script with `-Start`, hard-refresh |
| Login: `USER_SRP_AUTH flow not enabled for this client` | Floci client was re-seeded. Re-run `Setup-AdminPortal.ps1` (it re-enables SRP) |
| Login: "Incorrect username or password" | Wrong user or Floci reset. Re-run the script and `Seed-EtpCognitoUsers.ps1` if the pool is missing; check the phone has no `+880` typed |
| Login: "The user does not exist" | Admin pool has no such phone. Users `…01` to `…05` only (the User/Agent/Checker users are in other pools) |
| Script: `Cannot reach Floci` | Start the AppHost (`dotnet run --project aspire/Etp.AppHost`) |
| Script: `Pool 'etp-admin' not found` / `Client 'etp-local' not found` | `pwsh ./scripts/Seed-EtpCognitoUsers.ps1` |
| Logged in, every API call 401 | Backend still holds the old Cognito IDs: `pwsh ./scripts/Set-EtpSecrets.ps1`, restart AppHost |
| Logged in, API calls 502 / `ECONNREFUSED` in the dev-server window | A backend service is not running (Admin :5101 etc.). Check the Aspire dashboard |
| Port 4200 already in use | Another `ng serve` is running. Stop it, or use `-Port 4300` |
| Images on the programs page 404 | Seed image URLs point at S3 paths the browser cannot reach locally. Cosmetic |
| `npm install` errors | Delete `portal-local/admin-portal/node_modules` and re-run. The script uses `--legacy-peer-deps`, as the portal's own CI does |
| Starting fresh | Delete `portal-local/` and run the script |

## Limits of this setup

- The OTP is a stub. Real 2FA (SMS through the "serverless" API) is not reproduced; forgot-password and change-password flows that depend
  on Cognito messages are untested here.
- Only the Admin pool and the Admin portal are covered. The user portal (Cognito OAuth/OneID settings) is not set up.
- The `cloudFront` signed-cookie features (media gallery) have no local equivalent.
