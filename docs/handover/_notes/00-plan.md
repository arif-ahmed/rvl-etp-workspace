# Working notes — GoBCB feature documentation (internal, not a deliverable)

THIS FILE IS AN INTERNAL WORKING NOTE for the docs/feature-documentation-v2 branch. The deliverables are only:
- `docs/handover/gobcb-feature-documentation-en.md`
- `docs/handover/gobcb-feature-documentation-bn.md`

## Approved plan (2026-10-22)

Deliver two Markdown files with identical content/structure (EN + BN, technical terms in English in the BN file).
Feature documentation of the whole GoBCB platform, every user-visible and system feature, mapped to technical
implementation, for a .NET tech lead new to microservices. Everything evidence-based from the 5 submodules
(read-only) and `docs/architecture/gobcb-aws-architecture.md`. Never invent payloads/flows. Anything unverifiable:
mark `[UNCONFIRMED]` at the spot + collect in an **Open queries** section at the end of each file (questions
written to be sent to BS23 as-is). Submodules must never be modified; before finishing, `git status --porcelain`
inside every submodule must be empty.

### Structure (both files)
- Part 0 — Orientation: repo map; 9 active services + 2 stubs; request path (client → API Gateway → NLB → EKS ingress
  path-prefix); auth 4 layers summary; DB topology (one Aurora DB, shared `etp` schema + read-only table mirrors —
  contradicts "one schema per service" claim → `[UNCONFIRMED]`); SQS queue catalog; explainer boxes at first use
  (path-prefix routing, token forwarding, SQS/FIFO/DLQ, shared schema/mirroring, RedLock distributed lock, Redis
  live-capacity, SignalR, Cognito pool + federation, CloudFront signed URL/cookie, VDS QR offline verification,
  idempotent consumer).
- Part 1 — Admin Portal (~27 features): dashboard; programs+settings+teams+venue-details sync; venue management;
  events (CRUD/publish/duplicate/segments/settings/venue details/seat pricing); ticket attributes; ticket layout;
  ticket pricing content; ticket generation & reservation console; ticket checker users; gate assignment + reports;
  promo codes; discounts; notices; landing/media configuration; header-footer/social; raffle draw; admin users;
  agent users; activity log; user issues console + chat; payment reconciliation; reports.
- Part 2 — User Web Portal (~10-13): home/landing; browse events; info pages; seat selection → booking
  (promo/discount/capacity); payment (DgePay redirect → callback); my bookings; ticket generation request; ticket
  details/downloads; OneID ticket sync; profile; issues+chat; language switch.
- Part 3 — User App (~10): splash/onboard; home/browse; seat selection+promo; booking+webview payment; my
  bookings/tickets; profile/settings; issues+chat; device token; push receipt.
- Part 4 — Checker App (~6): assigned event/gate; offline ticket download; QR scan validation; manual entry;
  ticket sync; manual ticket validation.
- Part 5 — System-initiated (~17): level capacity update; event live capacity; locked capacity refresh; scheduler
  capacity rollup; pending/failed booking cancel; booking status → generated; initiate user ticket generation;
  ticket signing (TSP); ticket merge/zip; VAT challan; firebase notification delivery; ticket-generated
  notification; device token cleanup; checked-ticket sync; gate download status cleanup; promo status; discount status.
- Part 6 — Cross-cutting (~26): admin login/forgot/change/session/provisioning; user registration, password login,
  OneID SSO, forgot password, session, delete account; checker login; agent pool; authz pool policies/roles/program
  scope/client-side; endpoints without auth; service-to-service; file storage; email SES; SMS notification; push
  firebase; activity logging; Redis; configuration.
- Open queries — every `[UNCONFIRMED]` as a standalone OQn question.

### Per-feature template (9 points, as in approved sample F2.4)
1 Name (EN+BN) + one-line purpose → 2 trigger/actor (client, pool, role) → 3 business flow numbered →
4 technical flow (each hop marked sync HTTP user-token / HTTP static key / SQS / background worker / external) →
5 involved components → 6 API contracts (method, full path with prefix, auth, real-DTO sample request/response,
main errors) → 7 data & side effects → 8 code references (repo + path) → 9 handover notes + `[UNCONFIRMED]`.

### Key [UNCONFIRMED] list (seed)
shared `etp` schema vs "one schema per service"; Ticketing uses `ConnectionStrings:Booking`; Identity API
(`user/register-cached`, `otp/*`, `my-profile`, `register-sso`, `allowed-app-version`) has no source in any repo;
SMS Notification service (`Notification:Endpoint`) has no source; SQS physical queue names/FIFO/DLQ in secrets;
internal endpoints without `[Authorize]` (Booking `not-notified-list`, whole PushNotification, `AgentUserController`);
Admin `/api/v1/token` reachable-but-unused; Swagger open in all envs; TSP cert validation disabled; Ticketing DynamoDB
`localhost:8000` hardcoded; SSLCommerz vs DgePay live-ness; `payment-status-bypass` in prod?; Innovatrics DOT unused;
Scheduler device-token cleanup target endpoint; checker-app demo movie screens.

## IMPORTANT: existing inspiration branch (DO NOT MODIFY)

Branch `docs/feature-documentation` (already on origin) contains a previous session's work:
`docs/handover/feature-docs/{en,bn}/…` — 222 files, most are 49-line skeletons, but these are COMPLETE and
high-quality (line-numbered code refs, bug notes, local-dev test guides, `[Q-nn]` open-query ids):
- `en/00-platform-primer.md` (238 lines)
- `en/README.md` (196 lines, contents + conventions)
- `en/60-cross-cutting/X-01` … `X-19` (97–179 lines each: admin login/forgot/change/session/provisioning,
  user registration/password/OneID/forgot/session/delete, checker login, agent pool, authz ×4,
  endpoints-without-auth, service-to-service)
Skeletons (49 lines): all A-01…A-31, P-01…P-13, U-01…U-10, C-01…C-06, S-01…S-17, X-20…X-26, and the whole `bn/` tree.

Rule from user (2026-10-22): take inspiration from those files, but NEVER modify them; work only on
`docs/feature-documentation-v2`. Read them with `git show docs/feature-documentation:<path>` (read-only).

## Working conventions on this branch
- Feature ids: Part-section numbering `F1.1…`, `F2.1…` etc. (not the A-/P-/U-/C-/S-/X- ids of the old tree,
  though mapping is 1:1 conceptually).
- Explainer boxes: blockquote `> 📦 **Explainer: …**` at first use of a concept.
- Dummy values in samples must be realistic; property names must come from real DTOs.
- Path prefixes as called by clients (lowercase): `/admin/api/v1/…`, `/booking/api/v1/…`, `/event/api/v1/…`,
  `/ticketing/api/v1/…`, `/ticketchecker/api/v1/…`, `/userissue/api/v1/…`, `/pushnotification/api/v1/…`,
  `/scheduler…` (none), plus SignalR hub `/userissue/chathub` (host `chat.gobcbticket.com.bd` in prod).
  (`Application:ServiceName` values are camelCase for some services; ASP.NET routing is case-insensitive.)
- Local dev ports (Aspire): Admin 5101, Booking 5102, Event 5103, Platform 5104, PushNotification 5105,
  Scheduler 5106, TicketChecker 5107, Ticketing 5108, UserAuth 5109, UserIssue 5110, Utility 5111.

## ENVIRONMENT WARNING (2026-10-22)

Something in the host environment periodically runs `git checkout main` in the workspace repo on its own (seen twice in reflog; cause unknown - IDE/sync tool suspected).
ALWAYS run `git branch --show-current` before editing/committing; if on main, `git checkout docs/feature-documentation-v2` first (committed files reappear).
Commit after every Part to minimize loss.
