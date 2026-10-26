# ETP E2E tests (Playwright)

End-to-end tests for the ETP platform. **Nothing here modifies a submodule** —
the tests run against the local stack that `docs/local-dev.md` sets up
(Aspire AppHost, Floci fake AWS, `mock-identity`, `tsp-mock`, and the
`portal-local/` dev-server copies of the portals).

## Prerequisites

1. Backend + infra per `docs/local-dev.md`:
   - `dotnet run --project aspire/Etp.AppHost` (infra, Floci seeding, 11 services)
   - `node mock-identity/server.js` (:5120) and `node tsp-mock/server.js` (:5130)
2. User portal dev server: `pwsh ./scripts/Setup-UserPortal.ps1 -Start` (:4201)
3. Seed data (events, orders): `pwsh ./scripts/Seed-EtpData.ps1`
4. Node.js 20+, then in this folder:

   ```bash
   npm install
   npx playwright install chromium
   ```

A `globalSetup` health-check pings the portal, the Event/Booking services and
both mocks before any test runs and tells you exactly which start command is
missing if something is down.

## Running

```bash
npm run test:user            # user portal suite (phase 1)
npm run test:admin           # admin portal suite (phase 2, needs E2E_RUN_ADMIN=1 + admin portal on :4200)
npm test                     # everything enabled
npm run test:headed          # watch the browser
```

### Run a specific feature

Every test is tagged with its feature. Pick by tag or by folder:

```bash
npx playwright test --grep @booking        # all booking tests
npx playwright test --grep @auth           # all auth tests (login/register/oneid/reset)
npx playwright test tests/user/booking     # by folder
```

Tags: `@auth` `@register` `@oneid` `@reset` `@events` `@tickets` `@booking`
`@profile` (+ `@negative` variants). Phase 2 adds `@admin-*` and
`@ticket-lifecycle` for cross-portal flows.

### Reports and screenshots

Every run writes `playwright-report/index.html` (open with `npm run report`):

- failures get an automatic screenshot and, on retry, a full trace
  (step-through DOM snapshots);
- default screenshots are failures-only — set `E2E_SCREENSHOT=on` to capture
  every test;
- `test-results/` and `playwright-report/` are git-ignored.

## Configuration

Copy `.env.example` to `.env` (or export the variables) to change URLs,
credentials, OTP, or the screenshot mode. Defaults match the documented local
stack: user portal :4201, Event :5103, Booking :5102, mock-identity :5120,
tsp-mock :5130, seeded customer `1700000011` / `Passw0rd!23`.

## How it works

- **Auth.** The `user-setup` project logs in once through the real UI (Cognito
  SRP via Floci) and saves `playwright/.auth/user.json`; every other test
  reuses that storageState (Amplify keeps its tokens in localStorage, which
  storageState preserves). Register/forgot-password tests run logged-out.
  The admin project does the same with 2FA (OTP via mock-identity).
- **Booking.** The flagship `@booking` test registers a brand-new user through
  the mock-identity API (unique phone per run — no seed-data collisions),
  books a seat through the UI, then completes payment with the Booking
  service's own `payment-status-bypass` test endpoint. Ticket generation runs
  against `tsp-mock`; the test polls My Tickets until the order becomes
  viewable.
- **Locators.** Role/text-based selectors against the existing Angular
  templates (i18n `en.json` strings). No `data-testid` was added anywhere —
  if a selector proves brittle, document it here rather than patching a
  submodule.

## Adding tests

- User portal: `tests/user/<feature>/<name>.spec.ts`, tag every test.
- Admin portal (phase 2): `tests/admin/<feature>/…`, enable with
  `E2E_RUN_ADMIN=1` and `pwsh ./scripts/Setup-AdminPortal.ps1 -Start`.

## Known local-stack issue: booking order creation is rejected

The `@booking` test drives the full purchase UI correctly (registration →
login → profile → seat selection → checkout), but the Booking service
currently rejects every order with **"Simultaneous order is prohibited"**
(HTTP 400). Investigation showed its per-user distributed lock
(`user_booking:<userId>`) never reaches Redis — no lock key ever appears, no
order row is written — so no order can be created against the local stack,
with or without tests. This looks like a dead/broken Redis connection behind
`IDistributedLockFactory` in the Booking service and needs a backend-side fix
(submodule PR); the test fails with a pointer to this section until then.

Everything after the order POST (payment bypass → ticket signing via
tsp-mock → My Tickets) is already implemented and will run once order
creation works.

## Ground rule

Before finishing any session that touched this folder:

```bash
git submodule foreach 'git status --porcelain'
```

must print nothing.
