# mock-identity

Local stand-in for the two Lambda APIs whose source we do not have (see `docs/architecture/external-systems.md` §3):
the **Auth/Identity API** (`auth.api.gobcbticket.com.bd`: register, OTP, profile, password reset) and the **Serverless API**
(`user/get-bulk-users`, `admin/login-2fa-*`). The contract is **inferred from the callers** (user portal
`identity-api.service.ts`, user app `auth_api_service_impl.dart`, backend `ServerlessClient.cs`) and is unconfirmed
against the real service. No dependencies, Node 18+. Users are created in Floci Cognito (pool `etp-user`), so
sign-in afterwards uses real Floci tokens.

```powershell
# Floci must be up and seeded (scripts/Seed-EtpCognitoUsers.ps1)
node mock-identity/server.js            # :5120
```

| Consumer | Pointed at the mock by |
|---|---|
| User portal | `scripts/Setup-UserPortal.ps1` (`/p/identity` proxy -> :5120) |
| User app | `scripts/mobile-gateway.js` (`/identity/...` -> :5120) |
| Backend (`get-bulk-users`) | `Serverless:BaseUrl = http://localhost:5120/` (`scripts/user-secrets.example.json`, re-run `Set-EtpSecrets.ps1`) |
| Admin portal 2FA | keeps its own stub (OTP `123456`); the mock serves the same endpoints too |

- **OTP** is always `123456` (`MOCK_OTP` to change); expires after 5 min, but `123456` is also accepted when none was sent.
- **Email OTPs** are sent through Floci SES (`noreply@etp.local`, best effort); SMS OTPs are only logged. `GET /__dev/outbox` lists the last 50.
- Phone numbers are normalised to `+8801...` (Cognito username in the seed data).
- State (pending sign-ups, profiles) persists in `mock-identity/data.json` (gitignored).

## As a Floci Lambda (optional)
`lambda.js` exports `handler` for API Gateway proxy events (v1/v2). Requires Floci with the Docker socket mounted
(the AppHost has it off on purpose: no Docker socket is mounted into Floci) and Floci Lambda function-URL / API Gateway support, **not yet verified**:

```powershell
Compress-Archive mock-identity\handler.js, mock-identity\lambda.js -DestinationPath mock-identity\fn.zip -Force
aws --endpoint-url http://localhost:4566 lambda create-function --function-name etp-mock-identity --runtime nodejs20.x `
  --handler lambda.handler --zip-file fileb://mock-identity/fn.zip --role arn:aws:iam::000000000000:role/x `
  --environment "Variables={AWS_ENDPOINT_URL=http://host.docker.internal:4566}"
aws --endpoint-url http://localhost:4566 lambda create-function-url-config --function-name etp-mock-identity --auth-type NONE
```
