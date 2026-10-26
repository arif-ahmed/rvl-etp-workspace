# User portal: local setup, run, debug

How to run the Angular user (customer) portal (`rvl-gobcb-user-portal/ETP-Web`, Angular 19) on your PC against the local backend and Floci
(fake AWS). Companion to [local-dev.md](local-dev.md) (backend) and [admin-portal-local.md](admin-portal-local.md) (same pattern, admin side).

> **The submodule is never edited.** The script builds a throw-away copy in `portal-local/user-portal/` (git-ignored) and puts all
> local config there. Delete that folder at any time; the script recreates it.

## Contents

1. [Why a copy, and what is different in it](#1-why-a-copy-and-what-is-different-in-it)
2. [Prerequisites](#2-prerequisites)
3. [Setup and run](#3-setup-and-run)
4. [After a Cognito reset](#4-after-a-cognito-reset)
5. [Log in and what works](#5-log-in-and-what-works)
6. [Debug](#6-debug)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Why a copy, and what is different in it

| Problem in the submodule | What the copy does about it |
|---|---|
| There is **no** `src/environments/` folder; CI writes `environment.ts` from AWS SSM (`/rvl/<env>/user-portal/environment.ts`) | Script creates `environment.ts` and `environment.prod.ts` with the current Floci pool/client IDs and local paths |
| Amplify talks to real `cognito-idp.<region>.amazonaws.com` (no endpoint setting) | Script adds `endpoint` to `awsConfig.ts` in the copy, pointing at the dev-server proxy |
| Floci sends no CORS headers; its HTTPS proxy uses a self-signed certificate | Browser only talks to `localhost:4201`; the dev server proxies to Floci and to the backend services |
| The portal expects **one gateway host** for all APIs (`/booking`, `/event`, `/ticketing`, `/admin`, `/userissue` under one base) | All `services.*` hosts are `/p`; the proxy splits by path to the five local services |
| Hosted-UI SSO code hardcodes `https://<domain>` and Floci has no hosted UI | Script patches `cognito.service.ts` in the copy to plain `<domain>`; the proxy hosts a fake OneID at `/p/oneid` (section 5) |
| The portal signs in with SRP; `scripts/Seed-EtpCognitoUsers.ps1` only enables password auth on the app client | Script enables `ALLOW_USER_SRP_AUTH` on the Floci client |

All other Angular source is an unmodified copy.

```
browser :4201 ── ng serve (portal-local/user-portal)
                   ├─ /p/cognito     -> Floci        :4566
                   ├─ /p/event       -> Event        :5103
                   ├─ /p/booking     -> Booking      :5102
                   ├─ /p/ticketing   -> Ticketing    :5108
                   ├─ /p/admin       -> Admin        :5101   (general notices, discounts)
                   ├─ /p/userissue   -> UserIssue    :5110   (incl. websocket chat hub)
                   ├─ /p/oneid       -> fake OneID (authorize/token/logout, section 5)
                   └─ /p/identity    -> stub for user/my-profile, 503 for the rest
```

## 2. Prerequisites

Backend setup from [local-dev.md](local-dev.md) done and running (Floci seeded with `scripts/Seed-EtpCognitoUsers.ps1`, AppHost started), plus:

- Node.js 20+ (tested with 24) and npm
- AWS CLI on PATH
- The submodule checked out: `git submodule update --init rvl-gobcb-user-portal`
- Optional but recommended: `pwsh ./scripts/Seed-EtpData.ps1`, otherwise the home page and My Tickets are empty

## 3. Setup and run

From the workspace root:

```bash
# prepare only (copy, config, npm install)
pwsh ./scripts/Setup-UserPortal.ps1

# prepare and start the dev server (keeps running; Ctrl+C to stop)
pwsh ./scripts/Setup-UserPortal.ps1 -Start
```

Open <http://localhost:4201> (port 4201 so it can run next to the admin portal on 4200; change with `-Port`).

**Fresh clone:** `portal-local/` does not exist after a clone, by design. It is generated and git-ignored. Just run the script; it creates
the folder. Initialise the submodule first (`git submodule update --init`). The first run takes a few minutes (`npm install`); later runs take seconds.
The script is safe to re-run at any time, even while the dev server is running (it live-reloads).

## 4. After a Cognito reset

Pool and client IDs change whenever Floci's data is recreated. Nothing is edited by hand:

```bash
docker rm -f etp-floci etp-floci-tls etp-floci-ui   # Floci only; Postgres and Redis keep their data
docker volume rm etp-floci-data
# restart the AppHost: it re-creates Floci and re-runs the seed scripts (so the two seed lines below are only needed if you skipped that)
pwsh ./scripts/Seed-EtpFloci.ps1
pwsh ./scripts/Seed-EtpCognitoUsers.ps1          # new Cognito pools, clients, users
pwsh ./scripts/Set-EtpSecrets.ps1    # backend picks up the new IDs; restart the AppHost
pwsh ./scripts/Setup-UserPortal.ps1 -Start
```

The script reads the IDs live from Floci. Clear the browser's site data for `localhost:4201` afterwards: tokens from the old pool are rejected.
If you also reset Postgres, re-run `pwsh ./scripts/Seed-EtpData.ps1`; it looks up the new Cognito `sub` values for the order owners.

## 5. Log in and what works

Open <http://localhost:4201/en/auth/login>.

| Field | Enter |
|---|---|
| Phone Number | `1700000011` (10 digits, the form adds `+880`) |
| Password | `Passw0rd!23` |

Press **Next**. You land on the home page with **My Tickets** and **Logout** in the menu. This is the only seeded customer
(User pool, role `user`); `Seed-EtpData.ps1` attaches its sample orders to this user.

| Works locally | Does not work locally |
|---|---|
| Home page, programs, event lists (real seeded data) | **Register / sign-up, OTP, forgot password**: they call the "identity" API (`/user/register-cached`, `/otp/*`), which has no source in any repo. The proxy answers 503 |
| Password login through Cognito (Floci), logout | **Real OneID**: needs OneID's registered client and a Cognito hosted-UI domain with OneID as identity provider; those exist only in the deployed AWS account. Floci has no hosted UI |
| **Login with OneID Wallet (fake)**, see below | Payment return, biometric capture (Innovatrics SDK), Google Analytics |
| My Tickets (orders from the Booking service) | |
| Profile: `GET /user/my-profile` is a **local stub** built from the token (name "Local User", role `user`) | |
| Event details, ticket booking screens (backend permitting) | |

### Login with OneID (fake)

`/en/auth/login?sso_init=oneid` does nothing when opened directly: it only acts inside the popup (window named `OneID Login`) that the
**Login with OneID Wallet** button opens. Click the button instead. The dev-server proxy (`proxy.conf.js`) plays OneID:

```
button -> popup /en/auth/login?sso_init=oneid   (portal creates the PKCE verifier)
       -> /p/oneid/oauth2/authorize             fake: auto-approves, redirects back with a one-time code
       -> popup /en/auth/login?code=...         portal exchanges the code
       -> /p/oneid/oauth2/token                 fake: checks the PKCE challenge, returns REAL Floci tokens for 1700000011
       -> popup closes, main page reads the tokens, loads the profile (stub), you are signed in
```

There is no username/password screen: the fake always signs in as the seeded customer `1700000011`. The tokens are genuine Floci tokens, so
the backend accepts them. To test a different user, change `SSO_USER` in the generated `proxy.conf.js` (and the script's template).
The script also patches the copy's `cognito.service.ts` because the portal hardcodes `https://` on the Cognito domain.
Allow popups for `localhost:4201` in your browser, or the portal shows "Popup was blocked".

## 6. Debug

- **Browser DevTools (F12).** `ng serve` uses the development build with source maps: Sources tab -> `src/app/...` for breakpoints in the
  TypeScript. **Network** (filter `p/`) shows every API call and status; **Console** shows errors. The `NG0505 hydration` warning and
  404s for seed images are harmless.
- **Where the code is.** Login form: `src/app/modules/featured/auth/components/user-login/user-login.component.ts`. Cognito and token
  handling: `src/app/modules/shared/services/cognito.service.ts`. Which requests get a bearer token:
  `src/app/modules/core/interceptors/token.interceptor.ts`. Identity/profile state: `src/app/modules/core/modules/identity/store/`.
  API base URLs: `src/environments/environment.ts` (generated).
- **Backend side of a failing call.** The proxy forwards unchanged, so the same request appears in the service log in the Aspire
  dashboard (<http://localhost:15888>). 401 = token problem, 404 = wrong path.
- **VS Code.** Open `portal-local/user-portal` as a folder, run the script with `-Start`, attach with a Chrome launch config
  (`"type": "chrome", "request": "launch", "url": "http://localhost:4201", "webRoot": "${workspaceFolder}"`).
- **Editing portal code to try a fix.** Edit the **copy** (it hot-reloads). The next script run overwrites it from the submodule, so port
  real fixes to the portal's own repository via a PR.

## 7. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Login: `USER_SRP_AUTH flow not enabled for this client` | Floci client was re-seeded. Re-run `Setup-UserPortal.ps1` (it re-enables SRP) |
| Login: "Incorrect username or password" | Wrong user, or Floci was reset. Re-run the script; use `1700000011` (the Admin-pool users `…01` to `…05` are not in this pool) |
| SSO: "Popup was blocked" | Allow popups for localhost:4201 |
| SSO: "Authentication failed" | Floci rejected the seeded user (pool reset?). Re-run the script; check `1700000011` exists in the User pool |
| Login: "User does not exist" | `Seed-EtpCognitoUsers.ps1` not run for the User pool |
| Script: `Cannot reach Floci` | Start the AppHost (`dotnet run --project aspire/Etp.AppHost`) |
| Script: `Pool 'etp-user' not found` / `Client 'etp-local' not found` | `pwsh ./scripts/Seed-EtpCognitoUsers.ps1` |
| Home page lists are empty | No data. `pwsh ./scripts/Seed-EtpData.ps1` (backend must be running) |
| My Tickets empty or 401 | Backend holds old Cognito IDs: `pwsh ./scripts/Set-EtpSecrets.ps1`, restart AppHost; or orders were seeded for another Cognito `sub` (re-run `Seed-EtpData.ps1 -Reset`) |
| 502 / `ECONNREFUSED` in the dev-server window | A backend service is not running (see the Aspire dashboard) |
| Port 4201 in use | Another `ng serve` is running. Stop it, or pass `-Port` |
| `npm install` errors | Delete `portal-local/user-portal/node_modules` and re-run |
| Starting fresh | Delete `portal-local/` and run the script |
