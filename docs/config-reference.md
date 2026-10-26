# Configuration reference: every repo, every key, dev values (local + manual mode)

One-page reference for what configuration **each of the 5 product repos + the local glue** needs, what
every value is used for, and the concrete dev values that get the whole platform up for testing and
debugging. Companion docs: [local-dev.md](local-dev.md) (backend + Floci), [admin-portal-local.md](admin-portal-local.md),
[user-portal-local.md](user-portal-local.md), [mobile-local.md](mobile-local.md).

Ground rules:

- **Never write config inside a submodule** (`rvl-gobcb-*`). The repos ship placeholders; real values live
  in per-service **user secrets** (backend) or are **generated** into throw-away copies (`portal-local/`,
  `mobile-local/`, git-ignored) by the setup scripts.
- The one-shot helpers: `scripts/Set-EtpSecrets.ps1` (backend), `scripts/Setup-AdminPortal.ps1` /
  `Setup-UserPortal.ps1` / `Setup-MobileApps.ps1` (clients). This doc records *what they set and why*,
  so you can do it by hand or diff a failing setup.
- Shared dev AWS values come from SSM (`/rvl/<env>/...`); see §7.

Contents:

1. [Backend (11 services) — user secrets](#1-backend)
2. [Admin portal (Angular, port 4200)](#2-admin-portal-angular-port-4200)
3. [User portal (Angular, port 4201)](#3-user-portal-angular-port-4201)
4. [User app (Flutter, Android)](#4-user-app-flutter-android)
5. [Checker app (Flutter, Android)](#5-checker-app-flutter-android)
6. [Mobile gateway (port 5200)](#6-mobile-gateway-port-5200)
7. [Shared dev environment (real AWS)](#7-shared-dev-environment-real-aws)
8. [End-to-end verification](#8-end-to-end-verification)
9. [Semantic index: what each kind of value is used for](#9-semantic-index-what-each-kind-of-value-is-used-for)

---

## 1. Backend

### 1.1 Where config physically lives

| Layer | File / location | Loaded when |
|---|---|---|
| Repo placeholders | `Services/<Area>/ETP.<Area>.Service/appsettings.json` (`"[see User Secrets]"`) — never edit | always |
| **User secrets** (the real values) | `%APPDATA%\Microsoft\UserSecrets\<UserSecretsId>\secrets.json` per service | only with `ASPNETCORE_ENVIRONMENT=Development` |
| Env vars | set in the shell/IDE that starts services; highest precedence | always |

Per-service secrets folders (`<UserSecretsId>` from each `.Service.csproj`):

| Service | Secrets folder | Port |
|---|---|---|
| Admin | `20cf7ee0-a8dd-45a9-bf39-87bccd6cb4e9` | 5101 |
| Booking | `eb6360e6-ee4a-4276-8d4f-5851af3cee8c` | 5102 |
| Event | `802e4ee0-24bb-44fe-a64d-d5430d7c4763` | 5103 |
| Platform | `c494b7b3-ae67-4882-9afd-e25da2f13013` | 5104 |
| PushNotification | `c494b7b3-ae67-4882-9afd-e25da2f13014` | 5105 |
| Scheduler | `20f0d4dd-d20e-4f1d-9b30-83cb207fb1d1` | 5106 |
| TicketChecker | `625d7fb3-16b3-45a2-abae-90bb8d9a34e4` | 5107 |
| Ticketing | `c80b7bdb-eecb-4681-a7ae-43f6c7162c5c` | 5108 |
| UserIssue | `b7778227-4e3f-464a-8924-13f38286dc03` | 5110 |
| Utility | `54562abf-ff9a-4c77-a32e-eeea3780ae27` | 5111 |
| UserAuth | *(no UserSecretsId — near-empty stub)* | 5109 |

### 1.2 The master JSON (apply to every service)

Start from `scripts/user-secrets.example.json`, copy to `%USERPROFILE%\.etp-local\user-secrets.json`,
edit, then push to each service (equivalent of what the Aspire AppHost injects + per-service secrets):

```powershell
$projects = Get-ChildItem rvl-gobcb-backend/Services -Recurse -Filter '*.Service.csproj' |
    Where-Object { Select-String -Path $_.FullName -Pattern '<UserSecretsId>' -Quiet }
foreach ($p in $projects) {
    Get-Content "$env:USERPROFILE\.etp-local\user-secrets.json" -Raw |
        dotnet user-secrets set --project $p.FullName
}
# UserIssue has no appsettings.json -> its Application section must be set explicitly
$ui = 'rvl-gobcb-backend/Services/UserIssue/ETP.UserIssue.Service'
dotnet user-secrets set 'Application:ServiceName'  'userissue' --project $ui
dotnet user-secrets set 'Application:Title'        'RVL ETP ETicketing - User Issue API' --project $ui
dotnet user-secrets set 'Application:Description'  'API for user issue related utilities' --project $ui
```

Key groups and purpose:

| Key | Dev value | Used for |
|---|---|---|
| `ConnectionStrings:<Service>` ×10 | `Host=localhost;Port=5432;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true` | Npgsql per EF DbContext; one shared DB. **Ticketing reads the `Booking` key, not `Ticketing`** |
| `Services:<Name>` ×11 + `AppBase` | `http://localhost:5101/` … `5111/`; AppBase `http://localhost:4200/` | cross-service `HttpClient` base addresses; AppBase = portal URL for generated links |
| `Cache:Redis:ConnectionString / InstanceName / DefaultDatabase` | `localhost:6379` / `etp-local:` / `0` | distributed cache + DataProtection; Redis is contacted eagerly at startup |
| `DistributedLock:Redis:EndPoint / Port / Database / AccessKey` | `localhost` / `6379` / `0` / `""` | RedLock for background jobs (`Database` is missing from repo appsettings — must come from secrets) |
| `Application:ServiceName / Title / Description` | shipped in each repo's appsettings (except **UserIssue**) | controller route prefix `/<name>/api/...`, Swagger titles |
| `AWS:Region / AccessKey / SecretAccessKey` | `us-east-1` / `test` / `test` | SQS, MassTransit SQS bus, S3, SES, Cognito, DynamoDB clients |
| `AWS:Bucket:Name / :BaseUrl` | `etp-local` / `http://localhost:4566` | generic S3 media bucket + its ServiceURL (BaseUrl must be the Floci endpoint, not a CDN) |
| `AWS:Ticket:Bucket:{Name,BaseUrl}` | `etp-local` / `http://localhost:4566` | ticket-assets bucket; **Booking reads it although Booking's appsettings has no `AWS:Ticket` node** |
| `AWS:Ticket:TemplateBase / BlankBase / SignedBase / ShareBase / MergeBase` | `templates/`, `blank/`, `signed/`, `share/`, `merge/` | S3 key prefixes of the ticket PDF pipeline |
| `AWS:Ticket:MergeBuffer / MergeSize` | `10` / `50` | PDF merge batching (pages per buffer / per chunk) |
| `AWS:Ticket:ShareExpiryMinutes` | `60` | presigned ticket-share link TTL |
| `AWS:Ticket:EmailSender` | `noreply@etp.local` | SES sender for ticket emails |
| `AWS:Queue:*` (6 names) | `OrderSuccess`, `EventCapacity`, `FirebaseNotification`, `TicketProcessing`, `VatChallanProcessing`, `TicketSigning` | SQS queue **names** (code calls `GetQueueUrl` — names, never URLs) |
| `AWS:CognitoPool:<Admin/User/TicketChecker/Agent>:{PoolId,ClientId,Authority,Metadata}` | Floci `Seed-EtpFloci.ps1` / `Seed-EtpCognitoUsers.ps1` output | per-audience JwtBearer schemes: expected issuer (Authority), token audience (ClientId), OIDC discovery (Metadata); PoolId maps Cognito users to app roles (Admin middleware) |
| `Authentication:Jwt:{Key,Issuer,Audience}` | long random string / `etp-local` / `etp-local-services` | service-to-service JWTs signed by Admin's `/admin/api/v1/token` |
| `Authentication:ServiceApiKey` | `local-dev-service-api-key` | HMAC header guarding Admin's token endpoint |
| `Notification:{Endpoint,Authorization}` | dummy URL ending `/`, header value | external notification service (Admin, Booking, Scheduler) |
| `Serverless:{BaseUrl,Authorization}` | dummy URL ending `/`, header value | serverless 2FA-OTP app (Admin, Booking, Ticketing, UserIssue) |
| `PaymentSettings:DgePay:{MerchantClientId,MerchantClientSecret,MerchantApiKey,BaseUrl,RedirectUrl}` | placeholders; `https://dgepay-sandbox.invalid/`; redirect to the user app | DgePay payment gateway (Booking) |
| `PaymentSettings:SSLCommerz:*`, `PaymentSettings:NBROpenApi:*` | placeholders | second payment gateway + VAT invoicing (Booking) |
| `TSP:{AuthUrl,SignUrl,UserId,DigitalIdentityId}` | placeholders (URLs must end `/`) | PDF e-sign gateway (Ticketing) |
| `OneIdSettings:{TokenUrl,DocumentSyncUrl,AuthorizationToken}` | placeholders | government OneID citizen/NID document sync (Ticketing) |
| `CloudfrontTicketValidator:{BucketName,ObjectKey}` | placeholders | ticket-validator object read from S3 (Ticketing) |

### 1.3 Per-service needs and run order (manual mode)

| Start order | Service | Port | Boot-crash if missing | Also consumes |
|---|---|---|---|---|
| 1 | **Admin** (owns all DB migrations) | 5101 | CS `Admin`, `Services:Event/PushNotification/Booking/Ticketing/UserIssue`, Redis, Lock, `AWS:Ticket:Bucket:Name`, `Notification:Endpoint`, `Serverless:BaseUrl` | all 4 Cognito pools, `Authentication:Jwt:*`, `ServiceApiKey` |
| 2+ | Booking | 5102 | CS `Booking`, `Services:Event/Ticketing/AppBase`, Redis, `AWS:Ticket:Bucket:Name`, `Notification`, `Serverless` | Queues `OrderSuccess/EventCapacity/VatChallanProcessing/TicketSigning`; `PaymentSettings:DgePay` |
| 2+ | Event | 5103 | CS `Event`, `Services:Booking`, Redis | Queue `FirebaseNotification` |
| 2+ | Platform | 5104 | CS `Platform`, Redis | stub (integration code commented out) |
| 2+ | PushNotification | 5105 | CS `PushNotification`, Redis | Queue `FirebaseNotification` |
| 2+ | Scheduler | 5106 | CS `Scheduler`, `Services:Booking/Admin/Ticketing`, Redis (incl. `Database`), Lock | Queues `OrderSuccess/EventCapacity/FirebaseNotification`; `FirebasePushNotificationConfig:*` (else logs "processing failed" every minute — ignorable) |
| 2+ | TicketChecker | 5107 | CS `TicketChecker`, `Services:Ticketing`, Redis, Lock | Cognito `TicketChecker` + Admin pools |
| 2+ | Ticketing | 5108 | CS **`Booking`** (not `:Ticketing`), `Services:Event/Booking/AppBase`, `Serverless:BaseUrl` | Cognito pools; `TSP:*`, `OneIdSettings:*`, `CloudfrontTicketValidator:*`, `AWS:Ticket:*` incl. `MergeSize`; Queues `TicketSigning/TicketProcessing`; TSP cert `bin/Debug/net8.0/Cert/tspgw_client.pfx` optional (else an error-loop — stop the service if unused) |
| 2+ | UserAuth | 5109 | — | stub |
| 2+ | UserIssue | 5110 | `Application:*` (the 3 keys above), CS `UserIssue`, `Services:Booking/Ticketing` | Cognito pools, `Serverless:*`; hosts the chat hub |
| 2+ | Utility | 5111 | CS `Utility`, `Services:Admin/Booking/Ticketing`, Redis, Lock | `AWS:Ticket:*` full set; Queues `OrderSuccess/EventCapacity/TicketProcessing` |

Run each one (never the `launchSettings.json` ports — Scheduler and Utility collide at 5033):

```powershell
$env:AWS_ENDPOINT_URL = "http://localhost:4566"   # redirects SDK SQS/SES/Cognito calls to Floci; NO secrets-file equivalent
$env:ASPNETCORE_ENVIRONMENT = "Development"        # REQUIRED with --no-launch-profile, otherwise user secrets do not load
dotnet run --project rvl-gobcb-backend/Services/Admin/ETP.Admin.Service --no-launch-profile --urls http://localhost:5101
```

Repeat per service/port (Booking→5102, Event→5103, Platform→5104, PushNotification→5105,
Scheduler→5106, TicketChecker→5107, Ticketing→5108, UserAuth→5109, UserIssue→5110, Utility→5111).

---

## 2. Admin portal (Angular, port 4200)

The submodule ships **empty** `src/environments/environment.ts` files (CI fills them from SSM at build
time). Locally, `scripts/Setup-AdminPortal.ps1` copies the repo to `portal-local/admin-portal`
(git-ignored) and **generates** the config there:

File `portal-local/admin-portal/src/environments/environment.ts` (+ identical `environment.prod.ts`):

```ts
export const environment = {
  production: false,
  aws: { region: 'us-east-1', userPoolId: '<etp-admin pool id>', userPoolWebClientId: '<etp-local client id>' },
  services: {
    admin: '/p/admin', booking: '/p/booking', ticketing: '/p/ticketing',
    userissue: '/p/userissue', userissuehub: '/p/userissue',
  },
  serverless: { baseUrl: '/p/serverless', authorization: 'local' },
  cloudFront: { cloudFrontUrl: 'http://localhost:4200', mainDomain: 'localhost' },
};
```

`<etp-admin pool id>` / `<etp-local client id>` = the Cognito IDs printed by `scripts/Seed-EtpCognitoUsers.ps1`
(change at every Floci re-seed — re-run the setup script afterwards).

| Key | Purpose |
|---|---|
| `aws.region / userPoolId / userPoolWebClientId` | Admin staff login via Amplify/Cognito (`etp-admin` pool, `etp-local` client); roles come from the `custom:role` attribute |
| `services.admin / booking / ticketing` | API base prefixes; `proxy.conf.js` maps `/p/admin → :5101`, `/p/booking → :5102`, `/p/ticketing → :5108` |
| `services.userissue / userissuehub` | issues list + SignalR chat hub; proxy `/p/userissue → :5110` with WebSocket enabled |
| `serverless.{baseUrl,authorization}` | login 2FA OTP flow; the proxy runs an in-process **stub** — any phone works, OTP is always `123456` |
| `cloudFront.cloudFrontUrl / mainDomain` | media/image URL prefix; `mainDomain` = cookie domain cleared on logout |

Generated patches (in the copy only): `aws-exports.ts` gets an extra
`endpoint: 'http://localhost:4200/p/cognito'` so Amplify reaches Floci through the dev-server proxy.

Manual run after generating:

```powershell
pwsh ./scripts/Setup-AdminPortal.ps1          # generate (idempotent; re-run after Floci re-seed)
cd portal-local/admin-portal
npx ng serve --proxy-config proxy.conf.js --port 4200
```

Login: phone `1700000001` (10 digits, no country code), OTP `123456`, password `Passw0rd!23`.

---

## 3. User portal (Angular, port 4201)

Same pattern: `scripts/Setup-UserPortal.ps1` → `portal-local/user-portal`. The repo has **no**
`src/environments/` folder at all (code imports it through a path alias), so the build fails until the
copy is generated. Generated file `portal-local/user-portal/src/environments/environment.ts`:

```ts
export const environment = {
  production: false,
  aws: {
    region: 'us-east-1',
    userPoolId: '<etp-user pool id>',
    userPoolWebClientId: '<etp-local client id>',
    oauth: {
      domain: 'http://localhost:4201/p/oneid',
      scope: ['openid', 'email', 'phone', 'profile'],
      redirectSignIn:  'http://localhost:4201/en/auth/login',
      redirectSignOut: 'http://localhost:4201/en/',
      responseType: 'code',
    },
    oneIdRegisterUrl: '',
    oneIdLogoutUrl: '',
  },
  services: {
    bookings: '/p', events: '/p', tickets: '/p',
    userissue: '/p', userissuehub: '/p',
    identity: '/p/identity',
  },
  headerkey: 'local',
  googleAnalyticsId: '',
  homePageSettings: { homeTotalEvents: 6, fourImage: 4, eventContentImage: '' },
};
```

| Key | Purpose |
|---|---|
| `aws.userPool*` | customer Cognito pool (`etp-user`) + app client for sign-in |
| `aws.oauth.*` | hosted-UI-style PKCE (`responseType: 'code'`) sign-in. The proxy serves a **fake OneID** at `/p/oneid`: `/oauth2/authorize` auto-approves, `/oauth2/token` calls Floci `InitiateAuth` as the seeded customer, `/logout` redirects |
| `aws.oneIdRegisterUrl / oneIdLogoutUrl` | external OneID SSO links — empty locally |
| `services.bookings/events/tickets/userissue` | `/p` + proxy fan-out by path → `:5102 / :5103 / :5108 / :5110` (chat hub ws) |
| `services.identity` | profile/register/OTP API → `/p/identity`. **No identity service exists locally**: only `GET /user/my-profile` (derived from your JWT); everything else returns 503 |
| `headerkey` | value used as the `Authorization: <headerkey>` header on identity API calls — a static gateway key in prod |
| `googleAnalyticsId` | Google Analytics tracker id, empty locally |
| `homePageSettings` | home-page tile counts (`homeTotalEvents`, `fourImage`) and image prefix |

Generated patches (copy only): endpoint override in `awsConfig.ts` (`…/p/cognito`), and
`cognito.service.ts`'s hardcoded `https://${domain}` rewritten to plain `http:` (faux OneID is http-only).

Manual run:

```powershell
pwsh ./scripts/Setup-UserPortal.ps1
cd portal-local/user-portal
npx ng serve --proxy-config proxy.conf.js --port 4201
```

Login: `/en/auth/login`, phone `1700000011`, password `Passw0rd!23` (only seeded local customer).

---

## 4. User app (Flutter, Android)

`scripts/Setup-MobileApps.ps1` copies the repo to `mobile-local/user-app` and writes
`env/.env.dev` (the app **throws at startup** if any required key is missing):

```ini
API_BASE_URL='http://localhost:5200/'
AUTH_API_BASE_URL='http://localhost:5200/identity/'
AUTH_API_TOKEN='local'
AMPLIFY_CONFIG=<one JSON string, see below>
TERMS_AND_CONDITIONS_URL='https://example.com/terms'
PRIVACY_AND_POLICY_URL='https://example.com/privacy'
PAYMENT_SUCCESS_URL='https://example.com/payment-success'
ICC_ANTI_DISCRIMINATION_POLICY_URL='https://example.com/anti-discrimination'
ICC_ANTI_RACISM_POLICY_URL='https://example.com/anti-racism'
CONTACT_EMAIL='local@etp.local'
CHAT_COMMUNICATION_HUB='http://localhost:5200/userissue/'
FIREBASE_ANDROID_API_KEY='local-dummy'
FIREBASE_ANDROID_APP_ID='1:000000000000:android:0000000000000000'
FIREBASE_ANDROID_MESSAGING_SENDER_ID='000000000000'
FIREBASE_ANDROID_PROJECT_ID='etp-local'
FIREBASE_ANDROID_STORAGE_BUCKET='etp-local.appspot.com'
FIREBASE_IOS_API_KEY='local-dummy'
FIREBASE_IOS_APP_ID='1:000000000000:ios:0000000000000000'
FIREBASE_IOS_MESSAGING_SENDER_ID='000000000000'
FIREBASE_IOS_PROJECT_ID='etp-local'
FIREBASE_IOS_STORAGE_BUCKET='etp-local.appspot.com'
FIREBASE_IOS_BUNDLE_ID='com.ticketbangla.gobcbticket'
```

`AMPLIFY_CONFIG` is a single-line JSON string generated by the setup script:

```json
{"UserAgent":"aws-amplify-cli/2.0","Version":"1.0","auth":{"plugins":{"awsCognitoAuthPlugin":
{"UserAgent":"aws-amplify/cli","Version":"0.1.0","IdentityManager":{"Default":{}},
"CognitoUserPool":{"Default":{"PoolId":"<etp-user pool id>","AppClientId":"<etp-local client id>",
"Region":"us-east-1"}},"Auth":{"Default":{"authenticationFlowType":"USER_PASSWORD_AUTH"}}}}}}
```

| Key | Purpose |
|---|---|
| `API_BASE_URL` | main API client (sends `Bearer <Cognito access token>`) — base for `event/api/v1/...`, `booking/api/v1/...`, `ticketing/api/v1/...`, `userissue/api/v1/...`, `admin/api/v1/...`. Points at the **mobile gateway** (§6). Trailing `/` matters: clients join paths relatively (`$baseUrl/$endpoint`) |
| `AUTH_API_BASE_URL` / `AUTH_API_TOKEN` | auth/profile client base (`user/my-profile`, `user/delete-my-profile`) + static `Authorization` header value. Identitity has no local backend → 503 |
| `AMPLIFY_CONFIG` | Amplify Cognito init; must be from the **same** Floci seed as the backend's `AWS:CognitoPool:User` values, or issued JWTs won't validate on the backend. Known gap: Amplify Flutter has no endpoint override, so sign-in still targets real `cognito-idp.<region>.amazonaws.com` — the apps start but cannot log in against Floci (see mobile-local.md gap 1) |
| policy URLs ×4 | login/sign-up webviews (terms, privacy, ICC anti-discrimination, ICC anti-racism) |
| `PAYMENT_SUCCESS_URL` | webview redirect target after a payment flow |
| `CONTACT_EMAIL` | "to" address of the contact screen |
| `CHAT_COMMUNICATION_HUB` | chat hub base; the app appends `/userissue/chathub` |
| `FIREBASE_*` (Android+iOS) | Firebase options bundling (FCM push, analytics) — dummy values, `google-services.json` also stays dummy locally |

Run (needs backend + Floci running; see mobile-local.md for the toolchain):

```powershell
pwsh ./scripts/Setup-MobileApps.ps1 -App user          # generate copy + env + keystores
cd mobile-local/user-app
adb reverse tcp:5200 tcp:5200                          # phone's localhost -> this PC (already done with -Run)
fvm flutter run --flavor flavor_dev -t lib/main/main_flavor_dev.dart
```

---

## 5. Checker app (Flutter, Android)

Same mechanism → `mobile-local/checker-app/env/.env.dev`; only three required keys:

```ini
API_BASE_URL='http://localhost:5200/'
AUTH_API_BASE_URL='http://localhost:5200/identity/'
AMPLIFY_CONFIG=<same JSON shape, but CognitoUserPool = etp-ticketchecker pool>
VDS_CERTIFICATE='REPLACE_ME'
```

| Key | Purpose |
|---|---|
| `API_BASE_URL` | calls `ticketchecker/api/v1/tickets/sync-tickets`, event lists, app-version check — Bearer token from the TicketChecker pool |
| `AUTH_API_BASE_URL` | auth client base (identity API, 503 locally) |
| `AMPLIFY_CONFIG` | Amplify init against the **`etp-ticketchecker`** pool (same Floci-restore caveat and no-endpoint-override gap as the user app) |
| `VDS_CERTIFICATE` | PEM public certificate passed to native (Kotlin) code to verify **VDS-signed ticket QR codes**; placeholder locally, real value from bs23 |

Run: `pwsh ./scripts/Setup-MobileApps.ps1 -App checker -Run`, or `fvm flutter run --flavor flavor_dev
-t lib/main/main_flavor_dev.dart` inside `mobile-local/checker-app` after `adb reverse`.

---

## 6. Mobile gateway (port 5200)

`scripts/mobile-gateway.js` — plain Node, no dependencies. Both apps send every call to one host and the
gateway fans out per path (mirrors how the deployed system has a single ingress):

| Path prefix | Upstream |
|---|---|
| `/admin` | :5101 |
| `/booking` | :5102 |
| `/event` | :5103 |
| `/pushnotification` | :5105 |
| `/scheduler` | :5106 |
| `/ticketchecker` | :5107 |
| `/ticketing` | :5108 |
| `/userissue` | :5110 |
| `/utility` | :5111 |
| `/identity` | 503 (no backend exists) |

`adb reverse tcp:5200 tcp:5200` makes `localhost:5200` on a phone resolve to this PC (repeat after
replugging; `-Run` does it). No `adb reverse`: emulator → `10.0.2.2`, physical phone → the PC's LAN IP.
Health check: `http://localhost:5200/health`.

---

## 7. Shared dev environment (real AWS)

Everything above is the fully-local setup (Floci emulator). If you point at the team's shared **dev**
environment instead: the Cognito/S3-style values go into exactly the same places (backend user secrets,
portal `environment.ts`, mobile `.env`), sourced from AWS SSM Parameter Store
(`/rvl/<env>/...-appsettings`, see `docs/rvl-handover-AWS-access-summary.md`). Rules:

- Take **only** Cognito/S3-style values from there — never connection strings, Redis, or anything the
  code gets locally via the local infra.
- With shared dev SQS, set **your own** queue names (`etp-dev-<yourname>-order-success`) — never the
  environment's real queues. The code consumes them: your local workers would steal dev messages.
- Cognito pool IDs must be consistent: the portals/apps' Amplify config and the backend's
  `AWS:CognitoPool:*` must belong to the *same* pools, or token validation fails everywhere.

---

## 8. End-to-end verification

| Check | Expectation |
|---|---|
| `curl http://localhost:5101/health` … 5111 | 200 `Healthy` on every backend service |
| `curl http://localhost:5103/event/api/v1/landing-page-image/public` | `[]` on a fresh DB (anonymous, real DB read) |
| `docker exec etp-postgres psql -U etp -d etp_local -tAc 'select count(*) from etp."__EFMigrationsHistory";'` | 129 migrations once Admin has run |
| Backend secrets | `dotnet user-secrets list --project rvl-gobcb-backend/Services/Admin/ETP.Admin.Service` shows every section |
| Floci | `aws --endpoint-url http://localhost:4566 s3 ls` shows `etp-local`; SQS list shows the 6 queues |
| Admin portal | login at `http://localhost:4200` with phone `1700000001` / OTP `123456` |
| User portal | login at `http://localhost:4201/en/auth/login` with `1700000011` / `Passw0rd!23` |
| Apps | startup log prints `API_BASE_URL: http://localhost:5200/`; `http://localhost:5200/health` JSON in the device browser |
| Test data | `pwsh ./scripts/Seed-EtpData.ps1` (events/venues), then book in the user app |

Frequent failure → cause map is in `README.md` §12 and each companion doc's troubleshooting table.
The classic config-only ones: services crash on `FormatException`/NRE at boot = master JSON not applied
(re-run §1.2); 401 everywhere = Cognito IDs stale after a Floci re-seed (update master JSON **and**
re-run the client setup scripts so all sides use the same pool IDs); services still hitting real AWS =
`AWS_ENDPOINT_URL` not set in the launching shell.

---

## 9. Semantic index: what each kind of value is used for

| Kind of value | Who sets it | Consumed where |
|---|---|---|
| **DB connection strings** | backend user secrets (+ AppHost) | each service's EF DbContext; migrations on startup |
| **Service base URLs** (`Services:*`) | backend user secrets | cross-service TypedClients; single ingress fan-out across all clients |
| **Cognito pool/client IDs** | Floci seed output → backend secrets + portal `environment.ts` + app `AMPLIFY_CONFIG` | login (Amplify), JWT issuance and validation, role mapping |
| **Issuer/audience/metadata** | same pools | JwtBearer validation per audience scheme |
| **Service-to-service JWT key + API key** | backend user secrets | Admin token endpoint, protected internal APIs, Postman folder 07 |
| **AWS credentials + region** | user secrets (`test/test` locally) | SQS, S3, SES, Cognito, DynamoDB SDK clients |
| **Queue names** | user secrets (+ Floci seed) | MassTransit/SQS producers and background consumers |
| **S3 buckets and key prefixes** | user secrets | media manager, ticket PDF pipeline, shares |
| **Payment/TSP/OneID endpoint credentials** | user secrets (placeholders locally) | Booking order payment, Ticketing PDF e-sign, OneID sync |
| **Route prefixes** (`Application:ServiceName`) | repo appsettings (UserIssue set manually) | controller route prefix, Swagger docs |
| **Portal runtime config** (`environment.ts`) | generated per local copy (SSM in CI) | Amplify init, API base paths, OAuth redirects, analytics, home-page setting |
| **App env files** (`.env.<flavor>`) | generated per local copy (SSM in CI) | API base URLs, Amplify config, hub URL, policy/payment webviews, Firebase options |
| **Local-only plumbing** | workspace scripts | dev-server proxies (`/p/*`), fake OneID, OTP stub, mobile gateway, `adb reverse` |
