# Testing services locally (admin token + authorized endpoint)

How to get an admin token from the local Floci Cognito and call an authorized Admin endpoint, with Postman, the Postman CLI, curl, or Swagger.
Last verified against the local stack on 2026-10-26 (results in [Verified status](#verified-status)).

## Prerequisites

- Stack is up (Aspire AppHost, Docker infra, Floci) and seeded: `scripts/Seed-EtpFloci.ps1`, `scripts/Seed-EtpCognitoUsers.ps1` ([README sections 5 and 7](../README.md)).
- Seeded admin user: username `+8801700000001`, password `Passw0rd!23`, role `admin`. Other roles: see [README section 10](../README.md#10-postman-cognito-and-auth-tests).
- Import `postman/etp-cognito-auth.postman_collection.json` and `postman/etp-local-floci.postman_environment.json`; select **ETP Local - Floci**.

## URLs that are easy to get wrong

| What | URL | Note |
|---|---|---|
| Floci Cognito API | `http://localhost:4566/` | login (`InitiateAuth`) and admin calls |
| Token issuer (`iss`) and JWKS | `https://localhost:4567/<poolId>` | the TLS proxy URL, **not** 4566; the backend validates against this |
| Admin API | `http://localhost:5101/admin/api/v1/...` | the service has a **`/admin` path base**; without it every route is 404 |
| Admin health | `http://localhost:5101/health` | health is at the root, **not** under `/admin` |
| Admin Swagger | `http://localhost:5101/admin/swagger` | |

The environment variables `admin_base_url` (with `/admin`), `admin_host_url` (health), and `floci_oidc_url` (issuer) encode this.

## 1. Get an admin token

### Postman

Run folder **00 - Setup & discovery** (resolves pool and client ids), then **01 - Login per role / Login as admin**.
The token is stored in `access_token_admin` (and `id_token_admin`, `refresh_token_admin`).

### Postman CLI

```powershell
postman collection run postman/etp-cognito-auth.postman_collection.json `
  -e postman/etp-local-floci.postman_environment.json `
  -i "00 - Setup & discovery" -i "Login as admin"
```

### curl (no Postman)

The client id is the `etp-local` app client of the `etp-admin` pool; list it with `ListUserPoolClients` (folder 00) or read `AWS:CognitoPool:Admin:ClientId` from the Admin user secrets.

```bash
curl -s -X POST http://localhost:4566/ \
  -H 'Content-Type: application/x-amz-json-1.1' \
  -H 'X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth' \
  -d '{"AuthFlow":"USER_PASSWORD_AUTH","ClientId":"<ADMIN_CLIENT_ID>","AuthParameters":{"USERNAME":"+8801700000001","PASSWORD":"Passw0rd!23"}}'
```

Use `AuthenticationResult.AccessToken` (not the ID token; the backend rejects ID tokens with 401).

A good token has `token_use=access`, `iss=https://localhost:4567/<poolId>`, `client_id=<admin client>`, and `scope=aws.cognito.signin.user.admin`.

## 2. Call an authorized endpoint

```bash
curl -i http://localhost:5101/admin/api/v1/admin-users -H "Authorization: Bearer <ACCESS_TOKEN>"
```

Postman: folder **04 - Backend JWT validation / Valid admin access token**, or folder **05** for the per-role allow/deny matrix.
In Swagger, press **Authorize** and paste the token only (no `Bearer ` prefix).

Reading the status code:

| Status | Meaning |
|---|---|
| 200 | token accepted and role allowed |
| 401 | token rejected (missing, malformed, wrong signature, ID token, wrong issuer or client id) |
| 403 | token **accepted**, but the `admin` role claim is missing; see [Known issue](#known-issue-403-for-every-valid-token) |
| 404 | wrong URL, usually the missing `/admin` path base |

Admin program-scoped endpoints also need the header `X-Program-Id: <id>`.

## 3. Run the whole suite

```powershell
postman collection run postman/etp-cognito-auth.postman_collection.json -e postman/etp-local-floci.postman_environment.json
```

Folder 07 needs `service_api_key` (secret; the value of `Authentication:ServiceApiKey` in the Admin user secrets) and fails without it, for example `--env-var service_api_key=<value>`. Folders 06 and 08 create/delete a throwaway user and revoke the sessions of one login, so run them last and only locally.
`postman collection run -i <folder or request name>` runs a subset; repeat `-i` to combine.

## Before you test: Floci must be seeded in us-east-1

Floci holds everything (Cognito pools, queues, bucket) in **`us-east-1`**, and the services use the same region. If you set Floci up earlier in `ap-southeast-1`, re-seed once:

```powershell
docker compose up -d                           # also starts the :4569 notification stub
./scripts/Seed-EtpFloci.ps1
./scripts/Seed-EtpCognitoUsers.ps1
./scripts/Set-EtpSecrets.ps1                   # new pool ids into every service's user secrets
# stop the AppHost (Ctrl+C), then:
dotnet run --project aspire/Etp.AppHost
```

Pools created earlier in `ap-southeast-1` are separate and harmless; `docker compose down -v` removes them if you want a clean Floci.

| Port | Container | Purpose |
|---|---|---|
| 4566 | etp-floci | Floci AWS API: services, AWS CLI, Postman, seed scripts |
| 4567 | etp-floci-tls | HTTPS front; token issuer and JWKS |
| 4569 | etp-floci-tls | stand-in for the external SMS gateway (`Notification:Endpoint` is a placeholder), always answers 200, sends nothing |

## Verified status

Run on 2026-10-26 against Floci 2.3.0 seeded in `us-east-1` and an Admin instance started with the secrets from `Set-EtpSecrets.ps1` (service key from the Admin user secrets): 76 requests, 150 assertions, **150 passed, 0 failed**, exit code 0.

| Folder | Result |
|---|---|
| 00 Discovery, 01 Login (5 roles), 02 negative auth, 03 token lifecycle | pass |
| 04 Backend JWT validation (bad tokens 401, valid admin token 200) | pass |
| 05 Role matrix, 4 endpoints x 5 roles | pass |
| 06 Admin user lifecycle (create, login, change role, disable, enable, reset, delete) | pass |
| 07 Service token | pass with `service_api_key` set |
| 08 Session revocation | pass |

With Floci in `ap-southeast-1` the same run gave 120/150: every valid token got 403, which cascaded into folders 04, 05 and 06. Swagger failed the same way, because it sends the same token to the same middleware.

## Why the region is us-east-1 (and not the production ap-southeast-1)

**Symptom it avoids:** every `[Authorize(Roles = ...)]` Admin endpoint returned 403 for every role, including `admin`.

**Cause:** the role is not in the JWT. `CognitoUserAttributesMiddleware` adds it by calling Cognito `AdminGetUser` and mapping `custom:role` to a role claim; its errors are swallowed (logged only), so the request continues with no role.
In the Admin log:

```text
ERR Error enriching user claims with Cognito attributes
Amazon.CognitoIdentityProvider.Model.ResourceNotFoundException: User pool ap-southeast-1_<id> does not exist.
```

The pool did exist. Floci scopes pools by the **region in the request signature**. With AWSSDK.CognitoIdentityProvider 3.7.403.34, setting `AWS_ENDPOINT_URL` (which Aspire does) makes the SDK sign with **us-east-1** regardless of the region the code passes (reproduced in a standalone console app; `AWS_REGION` / `AWS_DEFAULT_REGION` do not change it). A pool in `ap-southeast-1` is therefore never found.

**Local fix (in place):** create everything in Floci in `us-east-1`, so the signing region and the pools agree. Nothing else is needed: no proxy, no backend change. The hard-coded `RegionEndpoint.APSoutheast1` in the backend's generic AWS options is harmless locally, for the same reason (the signing region is us-east-1 once an endpoint is set).

**Proper fix (backend repo, optional):** build the Cognito client with an explicit config so the signing region is kept, for example
`new AmazonCognitoIdentityProviderConfig { RegionEndpoint = ..., ServiceURL = <AWS endpoint>, AuthenticationRegion = region }`, in the `Admin`, `Booking` and `UserIssue` `DependencyConfig.cs`. Raise it as a PR against `rvl-gobcb-backend`; do not patch the submodule here. Real AWS is not affected. With that fix the local region could be `ap-southeast-1` again.

**How to see the service log:** `aspire logs admin --apphost aspire/Etp.AppHost/Etp.AppHost.csproj` and search for `Error enriching`.

**Note on the user cache:** the middleware caches `AdminGetUser` per user in Redis (shared by all instances). A good lookup is cached, so results can look correct on an instance you have not restarted. Restart before concluding anything.

## Testing a service you run from Visual Studio

A service started by the VS debugger (for example Admin on `http://localhost:5099`) returns **403 for every role-protected endpoint** even with a valid token, unless it has `AWS_ENDPOINT_URL=http://localhost:4566`: the AppHost sets it, Visual Studio does not, so the role lookup goes to real AWS (`The security token included in the request is invalid` in the log). Close all VS windows and start it with:

```powershell
./scripts/Start-VisualStudio.ps1
```

Stop the AppHost's copy of the same service first (or start the AppHost with `ETP_SKIP=Admin`), run the service in VS, and use a fresh Floci token against its port (5099 for Admin from VS). Details: [local-dev.md section 6.2](local-dev.md#62-debug-a-service-from-its-first-line).

## Known limitation: creating users sends an SMS

Admin "create user" and "set password" call an external notification gateway to SMS the password. In the user secrets `Notification:Endpoint` is the placeholder `https://notification.invalid/`, which fails with `No such host is known. (notification.invalid:443)` (HTTP 400 after ~14 s, although the Cognito user was already created).
The AppHost now sets `Notification__Endpoint=http://localhost:4569/` (the nginx stub). The generated password is therefore not delivered anywhere; folder 06 sets a known password itself.

## Other notes

- The collection's issuer checks compare against `https://localhost:4567/<poolId>` (`floci_oidc_url`); before 2026-10-26 they expected port 4566 and failed.
- On Node 24, `localhost` can fail with "Invalid IP address: undefined" in newman; use `--env-var floci_url=http://127.0.0.1:4566`.
- Service ports 5101-5111; only the Admin service is covered by this collection.
