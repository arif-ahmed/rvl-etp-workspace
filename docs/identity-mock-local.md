# Identity / Serverless API mock: prepare the environment and test

The identity (auth) API and the serverless API are Lambda services whose source we do not have (see
[architecture/external-systems.md](architecture/external-systems.md) §3). `mock-identity/` stands in for them locally so registration,
OTP, forgot-password, profile and the backend's user-name lookup can be exercised. Companion to [local-dev.md](local-dev.md),
[user-portal-local.md](user-portal-local.md) and [mobile-local.md](mobile-local.md).

> **Status: the contract is inferred from the client code, not from the real service.** A pass here proves the clients and backend
> behave against our assumptions, not against production. Nothing in a submodule is changed.

## 1. What the mock replaces

| Real endpoint (Lambda) | Called by | Mock behaviour |
|---|---|---|
| `POST /user/register-cached`, `/otp/send-otp`, `/otp/verify-otp`, `/user/register` | User portal, user app | Sign-up wizard; `register` creates the user in the Floci `etp-user` pool |
| `GET/PUT /user/my-profile`, `DELETE /user/delete-my-profile`, `POST /user/register-sso` | User portal, user app | Profile built from Floci Cognito + saved fields |
| `POST /otp/password-reset-request`, `/otp/password-reset` | User portal, user app | Resets the Floci password |
| `GET /user/allowed-app-version` | User app, checker app | Static versions |
| `GET /user/get-bulk-users` | Backend (Booking, Admin, Ticketing, UserIssue) | Looks users up by Cognito `sub` in Floci |
| `POST /admin/login-2fa-send-otp`, `/verify-otp` | Admin portal | Admin script keeps its own stub; the mock serves the same routes |

OTP is always **`123456`**. Email OTPs also go through Floci SES (`noreply@etp.local`); SMS OTPs are only logged.
`GET http://localhost:5120/__dev/outbox` lists the last 50 OTPs sent.

## 2. Prerequisites

- Everything in [local-dev.md](local-dev.md) done: Docker, PostgreSQL/Redis/DynamoDB containers, Floci up, `scripts/Seed-EtpFloci.ps1` and
  `scripts/Seed-EtpCognitoUsers.ps1` run (the mock needs the `etp-user` pool).
- Node.js 18+ (the mock has no npm dependencies).
- Portal testing: Node 20+, AWS CLI, `git submodule update --init rvl-gobcb-user-portal`.

## 3. Prepare

From the workspace root.

```powershell
# 1. Infra and Floci (no-op if already running)
docker compose up -d
pwsh ./scripts/Seed-EtpFloci.ps1          # SES sender noreply@etp.local must exist for email OTPs
pwsh ./scripts/Seed-EtpCognitoUsers.ps1

# 2. Point the backend at the mock (Serverless:BaseUrl = http://localhost:5120/) and restart the services
pwsh ./scripts/Set-EtpSecrets.ps1
dotnet run --project aspire/Etp.AppHost          # keep open

# 3. Start the mock (new terminal, keep open)
node mock-identity/server.js                      # :5120, prints each OTP it issues

# 4. Check it
curl http://localhost:5120/__dev/health           # {"status":"ok","floci":"http://localhost:4566"}
```

Optional settings (environment variables, set before `node`): `MOCK_OTP`, `MOCK_OTP_TTL_MS` (default 5 min),
`MOCK_PENDING_TTL_MS` (abandoned sign-ups dropped, default 30 min), `MOCK_USER_POOL_NAME` (default `etp-user`) or `MOCK_USER_POOL_ID`, `AWS_ENDPOINT_URL`, `MOCK_IDENTITY_PORT`.

Reset: stop the mock, delete `mock-identity/data.json` (pending sign-ups and profiles). Users already created live in Floci Cognito;
they disappear when Floci data is reset (see local-dev.md, Teardown) and re-seeding.

### Client wiring

| Client | Prepare |
|---|---|
| Backend | Done in step 2 (`Serverless:BaseUrl`). Confirm: `dotnet user-secrets list` in a service shows `http://localhost:5120/`. |
| User portal | `pwsh ./scripts/Setup-UserPortal.ps1 -Start` (the generated proxy sends `/p/identity` to :5120). Re-run it to pick up changes. |
| User app / checker app | `pwsh ./scripts/Setup-MobileApps.ps1`; the gateway forwards `identity/` to :5120. Run `node scripts/mobile-gateway.js` if the script does not start it. |
| Admin portal | No change; `pwsh ./scripts/Setup-AdminPortal.ps1 -Start`. |

Mobile sign-in is still blocked by Amplify Flutter having no Cognito endpoint override ([mobile-local.md](mobile-local.md)). Mobile can
only test the identity calls (register, OTP, reset) until that is solved.

## 4. Smoke test (API level, no UI)

```powershell
$h = @{ 'Content-Type' = 'application/json' }
$b = 'http://localhost:5120'
$r = Invoke-RestMethod "$b/user/register-cached" -Method Post -Headers $h -Body '{"name":"Test User","email":"test@etp.local","phone":"01712345678","dob":"1990-01-01","address":"Dhaka"}'
$id = $r.data.user_id
Invoke-RestMethod "$b/otp/send-otp"   -Method Post -Headers $h -Body '{"type":"sms","destination":"01712345678"}'
Invoke-RestMethod "$b/otp/verify-otp" -Method Post -Headers $h -Body '{"type":"sms","destination":"01712345678","otp":"123456"}'
Invoke-RestMethod "$b/user/register"  -Method Post -Headers $h -Body "{`"user_id`":`"$id`",`"password`":`"Passw0rd!23`"}"
```

Then sign in against Floci with phone `+8801712345678` / `Passw0rd!23` (portal login or `aws cognito-idp initiate-auth` with the
`User` pool client id from `Seed-EtpCognitoUsers.ps1`).

## 5. Test cases

| # | Scenario | Steps | Expected |
|---|---|---|---|
| 1 | New user registration | Portal sign-up with a new phone and email; enter OTP `123456`; set password | User created; can sign in; profile page loads |
| 2 | Wrong OTP | Enter `000000` | `invalid_otp` message |
| 3 | Expired OTP | Start mock with `MOCK_OTP_TTL_MS=1000`, wait, verify | `otp_has_expired` |
| 4 | Existing phone | Register `01700000011` (seeded) | `user_already_exists` |
| 5 | Email OTP | Send OTP with `type: email` | 200; entry in `/__dev/outbox` with `delivered: "ses"` (or `"logged"` if SES send failed) |
| 6 | Forgot password | Request reset for `01712345678`, OTP `123456`, new password; sign in with it | Old password rejected, new works |
| 7 | Reset unknown phone | Request reset for `01999999999` | `phone_number_not_found` |
| 8 | Profile update | Signed-in user saves address, DOB, NID | `GET my-profile` returns them; `isProfileCompleted` true |
| 9 | Delete account | Delete my profile | User removed from Floci; sign-in fails |
| 10 | Backend enrichment | Place an order as the new user, then open it in the admin portal or run ticket generation | User name/phone/email filled (no `serverless.invalid` errors in Booking/Admin logs) |
| 11 | Admin 2FA | Admin login, phone `1700000001`, OTP `123456` | Unchanged from [admin-portal-local.md](admin-portal-local.md) |
| 12 | Mock down | Stop the mock, open the portal profile | Clear error (502 / `mock_identity_unreachable` via the gateway), not a crash |

## 6. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Cognito pool 'etp-user' not found` (500 on register) | Floci not seeded: run `scripts/Seed-EtpCognitoUsers.ps1`. |
| Every call returns 500 `internal_server_error` | Floci down; the mock logs the cause in its terminal. |
| Email OTP shows `delivered: "logged"` | Floci SES send failed or sender unverified: re-run `scripts/Seed-EtpFloci.ps1`. The OTP is still `123456`, so tests proceed. |
| Backend still logs `serverless.invalid` | Secrets not re-applied or services not restarted: re-run `Set-EtpSecrets.ps1`, restart AppHost. |
| Portal gets 404/ECONNREFUSED on `/p/identity` | Mock not running, or portal started before the script change: re-run `Setup-UserPortal.ps1`. |
| `user_already_exists` for a phone you deleted | Cognito user still in Floci; delete it with `aws cognito-idp admin-delete-user` (endpoint `http://localhost:4566`). |
| Lambda mode | `mock-identity/lambda.js` and the Floci Lambda steps are in [mock-identity/README.md](../mock-identity/README.md); not verified, optional. |

## 7. Before finishing

`git submodule foreach 'git status --porcelain'` must print nothing.
