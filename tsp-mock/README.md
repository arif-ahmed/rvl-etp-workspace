# tsp-mock — local TSP gateway stand-in

Stands in for the government TSP/VDS gateway (`TSP:AuthUrl` / `TSP:SignUrl`) that the Ticketing service calls to
sign ticket PDFs and embed the VDS QR. With it running, the real `TicketSigning` worker pipeline runs end-to-end
locally: blank PDF → sign → signed upload to S3 → ticket `Generated` → order `Generated` → download.

Plain node, no dependencies:

```bash
node tsp-mock/server.js          # listens on :5130
```

It is the "signing" twin of `mock-identity/` (OneID/identity). Real PAdES signatures and VDS QR validity are still
UAT-only: the mock **echoes the submitted PDF back** as the signed result — nothing in the local aftermath parses
the signature or QR (only the checker app does, and it cannot run against Floci).

## Contract

| Call | Mock response |
|---|---|
| `GET {TSP:AuthUrl}` (mTLS + no bearer) | `{ code: 200, data: { token: "mock-tsp-token" } }` — `TspAuthProvider` caches it in Redis `tsp_token` for 1 min |
| `POST {TSP:SignUrl}` (bearer + mTLS, body = `TicketSigningPayload`) | `{ code: 200, data: { signedData: ["<base64 pdf>", …] } }` — one echo per submitted document |

Routes are matched on the path suffix (`/auth`, `/sign`) with any prefix, and the configured URLs must end in `/`
(the clients request the empty relative path on their BaseAddress).

## One-time setup

1. Client certificate: `pwsh ./scripts/New-TspMockCert.ps1` — generates a self-signed
   `tsp-mock/certs/tspgw_client.pfx` (empty password) and copies it into the Ticketing build output
   (`…/ETP.Ticketing.Service/bin/Debug/net8.0/Cert/`). The service loads this file unconditionally at first TSP
   client use; without it you get `CryptographicException` loops. `bin/` is gitignored, so the submodule stays clean.
2. User secrets (Ticketing service):
   ```bash
   dotnet user-secrets set "TSP:AuthUrl" "http://localhost:5130/auth/"   --project rvl-gobcb-backend/Services/Ticketing/ETP.Ticketing.Service
   dotnet user-secrets set "TSP:SignUrl" "http://localhost:5130/sign/"   --project rvl-gobcb-backend/Services/Ticketing/ETP.Ticketing.Service
   dotnet user-secrets set "TSP:UserId" "tsp-mock-user"                  --project rvl-gobcb-backend/Services/Ticketing/ETP.Ticketing.Service
   dotnet user-secrets set "TSP:DigitalIdentityId" "tsp-mock-identity"   --project rvl-gobcb-backend/Services/Ticketing/ETP.Ticketing.Service
   ```
   (The repo default `https://tsp.invalid/…` values in secrets can stay — the four keys above override them.)

## Test flow (signing aftermath)

See the "TSP (ticket signing) mock" section of `docs/local-dev.md`.
