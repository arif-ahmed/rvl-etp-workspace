# Real Live Experiences and Areas to Be Careful

Source: [Future Startup interview (Oct 20, 2025)](https://futurestartup.com/2025/10/20/brain-station-23-built-a-national-e-ticketing-platform-in-eight-weeks/) with Brain Station 23 (BS23) leadership about the BPL 2025 e-ticketing platform built for Relief Validation Limited (RVL) — the same platform this workspace develops (GoBCB / RVL ETP).

All incident figures are as stated in the article. Part 1 records what actually happened in the first season; Part 2 derives the areas to be careful about during UAT and live operation from those incidents.

**Evidence conventions.** Every "evidence" block below names the concrete client, service and file path in this workspace — verified against the code, not assumed:

- Repos: `rvl-gobcb-backend` (9 ASP.NET Core services), `rvl-gobcb-admin-portal`, `rvl-gobcb-user-portal`, `rvl-gobcb-user-app`, `rvl-gobcb-checker-app` — all read-only submodules.
- Feature-doc IDs: `A-xx` (admin portal), `P-xx` (user portal), `U-xx` (user app), `C-xx` (checker app), `S-xx` (system-initiated: queues, workers), `X-xx` (cross-cutting) → `docs/handover/feature-docs/bn/`. Each feature doc carries its own file:line code references.
- `Q-xx` = open queries from code analysis in `docs/handover/feature-docs/bn/99-open-queries.md` — verified code behaviours that are still unexplained or unfixed.
- AWS-level context: `docs/architecture/gobcb-aws-architecture.md`.

---

## Part 1 — Application Real Live Experiences

### Project context (from the article)

- First meeting with RVL: Oct 25. Work began Nov 1 on a verbal agreement; development started Nov 4; working prototype Nov 10; UAT began Dec 7; ticket sales went live Dec 23–24; matches began Dec 30. Total: about 8 weeks from start to live matches.
- 21-person team assembled in two days; the team worked 12–14 hours a day, seven days a week.
- Season scale: 46 matches, 24 events, 3 venues (Dhaka, Chattogram, Sylhet) over a 40-day tournament, roughly 25,000 tickets per day/match. Each gate handled 5,000–6,000 people through three to four gates.
- Revenue: nearly BDT 13 crore versus a historical 4–6 crore range. App store rating 4.2–4.5 stars.
- The platform was later reused for the Bangladesh vs. Pakistan, Netherlands, and New Zealand series.

### Incident 1 — Duplicate printed tickets tried at multiple gates

Fans photocopied the PDF tickets of the offline sales channel and attempted entry at different gates. In the first match, 500–1,000 duplicates appeared (a 2–4% failure rate). The trajectory then fell steadily: match two 200–300, match three under 100, match four single digits, and near-zero afterwards.

Fix: cryptographic signatures inside the QR code, offline validation on checker devices, and a standard 30-second sync across all devices.

**Where this lives in our codebase (evidence):**

- Checker app (verdict is decided entirely offline, no HTTP per scan): `rvl-gobcb-checker-app/lib/presentation/feature/qr_page/qr_page_view_model.dart:232-372` — scan → VDS signature verify → event/gate/already-used checks; QR decode in `data/lib/service/vds_qr_decoder.dart:8-77` (base64 → gzip → JSON: payload, signature, certSN, issuerDN); ECDSA verify on Android in `android/app/src/main/kotlin/com/mahfuznow/hello_flutter/MainActivity.kt` (SHA256withECDSA + certificate serial match). Feature doc C-03.
- Signature generation (the other half of the trust chain): Ticketing service, `TicketSigning` SQS queue, TSP/VDS gateway with `Cert/tspgw_client.pfx` (S-08).
- Offline sales channel ingestion: `rvl-gobcb-backend/Services/Ticketing/ETP.Ticketing.Service/Api/OfflineTicketSoldController.cs` (`POST /ticketing/api/v1/offline-sold-ticket`, Agent pool — X-13).
- Server-side check counters: `rvl-gobcb-backend/Services/TicketChecker/ETP.TicketChecker.Service/Api/TicketController.cs` (`sync-tickets`) writing Redis counters, flushed to DB by the Admin worker S-14 (`ETP.Admin.Domain/Managers/CheckedTicketManager.cs`).

### Incident 2 — Sync delay caused false rejections of valid tickets

On day one, the background sync between checker devices ran only every minute. The delay caused legitimate tickets to be rejected at the gates, creating customer-service pressure on the ground.

Fix: sync intervals were cut to 30 seconds.

**Where this lives in our codebase (evidence):**

- Sync loop: `rvl-gobcb-checker-app/lib/presentation/feature/qr_page/qr_page_view_model.dart:22` — `static const _refreshInterval = Duration(seconds: 90)`; `_syncData()` at `:102-140`; HTTP in `data/lib/remote/api_service/ticket_api_service/ticket_api_service_impl.dart:21-38` → `POST /ticketchecker/api/v1/tickets/sync-tickets`. Feature doc C-05. **Note: our interval is 90 seconds — three times the article's 30-second fix.**
- Counter authority: TicketChecker service keeps counters in Redis; Admin worker S-14 (`CheckedTicketManager.cs`) persists them; Redis flag `ticketCheckerDbSync` controls the flush (no expiry — Q-17).

### Incident 3 — Payment failures at scale (found in UAT)

UAT exposed a 20–30% payment failure rate when transacting at scale.

Fix: retry logic with 10-minute retry windows, and multiple payment gateways for redundancy so a failing gateway could be routed around.

**Where this lives in our codebase (evidence):**

- Payment integration: `rvl-gobcb-backend/Services/Booking/ETP.Booking.Domain/Managers/DgePayPaymentManager.cs` (+ `Models/Payment/DgePay*`), with the callback and a `payment-status-bypass` route in `ETP.Booking.Service/Api/UserBookingOrderController.cs` (P-06).
- SSLCommerz is present in the checkout form but its callback is disabled (Q-19) — so today there is effectively **one active gateway**, not the article's multi-gateway redundancy.
- Late/failed payment handling: Scheduler worker S-05 `PendingOrFailedBookingStatusUpdateService` re-checks pending/failed orders every 7–10 minutes; VAT challans flow via the `VatChallanProcessing` queue (S-10).
- Checkout UI: user portal `rvl-gobcb-user-portal/ETP-Web/src/app/modules/featured/tickets/components/complete-payment-modal/` and `payment-invoice/`.

### Incident 4 — Same seat sold to two buyers (race condition)

Testing caught the same seat being sold twice under concurrent load.

Fix: stronger database locking mechanisms, queue management, caching of capacity data, and background database syncing.

**Where this lives in our codebase (evidence):**

- Booking service, Redis-first capacity model (X-25): keys `level_live*` / `level_locked` with a **12-minute seat lock**, refreshed by `RefreshLockedCapacityService` under a RedLock distributed lock (S-03).
- Durable copies in the `Capacity` and `SeatReservation` tables, reconciled by the `EventCapacity` SQS queue → workers S-01 `LevelCapacityUpdateService` / S-02 `EventLiveCapacityUpdateService`; reservations exposed at `ETP.Booking.Service/Api/SeatReservationController.cs` (A-11).
- The 12-minute constant also appears at `ETP.Booking.Service/Workers/TaskManagers/InitiateUserTicketGenerationTaskManager.cs:69`.
- Queue fragility: none of the 6 SQS queues has a dead-letter queue, and the retry counter is never persisted — a poisoned message retries forever (Q-09).

### Incident 5 — Central-server validation was too slow: 30–60 seconds per scan

Initial architecture validated each QR against a central server, taking 30–60 seconds per scan. At 25,000 fans through four gates, that projected to six-plus hours to admit a crowd.

Fix: offline-first validation moved onto the checker devices (with a local SQLite cache), bringing scan times to sub-second. A later update cut scan time by a further 20%.

**Where this lives in our codebase (evidence):**

- Our platform already implements the fix, not the problem: one scan performs **zero HTTP calls** (C-03 §6); the full ticket set for the assigned gate is downloaded ahead of time (C-02) into the local drift/SQLite database (`rvl-gobcb-checker-app/data/lib/local/drift_database/`), and every verdict is computed locally against it.
- Scanning uses a vendored package (`rvl-gobcb-checker-app/flutter_barcode_scanner/`, path dependency in `pubspec.yaml`), not a pub.dev scanner.

### Incident 6 — Low-end personal devices failed under sustained use

Checkers initially used personal phones. Some had 2GB RAM and slowed after an hour; low-end devices crashed outright.

Fix: standardized dedicated validation devices.

**Where this lives in our codebase (evidence):**

- The whole offline pipeline runs on the device: drift/SQLite local DB, ECDSA signature verification via the Android method channel `certificate/methods` (`MainActivity.kt`), sound feedback via `audioplayers` (C-03).
- **iOS cannot verify any QR**: `rvl-gobcb-checker-app/ios/Runner/AppDelegate.swift:1-13` registers plugins only and has no channel handler — every `verifyQrData` call throws and returns null, so every ticket reads "incorrect QR" on iOS (Q-72). The checker app is Android-only for real validation.

### Incident 7 — UX defects caught in UAT

UAT surfaced: slow seat-map loading, unclear payment confirmation states, and ambiguous checker-app feedback (checkers could not tell whether a scan was valid, invalid, or duplicate).

Fix: UI improvements — but these were only caught because UAT exercised real user journeys, not just API correctness.

**Where this lives in our codebase (evidence):**

- Seat map: user portal `rvl-gobcb-user-portal/ETP-Web/src/app/modules/featured/tickets/pages/stadium-seat-page/stadium-seat-page.component.ts` (P-04), served from Redis `level_live` / `level_live_seats` keys.
- Payment confirmation: user portal `complete-payment-modal` component (P-06).
- Checker verdicts: C-03 defines distinct states — valid, already checked, wrong event, wrong gate, invalid ticket, incorrect QR — each with its own sound (`qrCheckStatus.soundAsset`) and haptics; the offline-purchased ticket gets a confirmation dialog.
- Localization caveat: database content is never translated; only the portal chrome changes language (Q-44).

### Incident 8 — Physical/offline ticket channel added at the last minute

The physical ticket requirement came in on December 15 — barely a week before ticket sales went live. It was implemented in about a week (code pushed at 3 AM, tested by dawn). This created a mixed online/offline issuance model validating under the same gates.

**Where this lives in our codebase (evidence):**

- Agent/offline channel: `POST /ticketing/api/v1/offline-sold-ticket` (`OfflineTicketSoldController.cs`, Agent pool — X-13). The `OfflineSoldTicket` table is written but **never read anywhere** (Q-07), and no agent client exists in this workspace — the offline issuance path is effectively outside our repos.
- Offline-bought ticket at the gate: C-03 shows a confirmation dialog ("purchased offline — does the credential include a physical ticket?") rather than a hard accept/reject.
- Reserved-seat flow for organizers: Booking `SeatReservation` (A-11), Admin portal reserved tickets (A-12), merge/zip by the Utility worker via the `TicketProcessing` queue (S-09).
- QR trust anchor: a single PEM certificate in the checker app `.env` key `VDS_CERTIFICATE` — rotating or adding a VDS certificate requires an app release; tickets signed with the previous certificate would fail (Q-73).

### Incident 9 — Human factor: checkers needed three matches to adapt

The biggest non-technical lesson: checkers took around three matches to become fluent with the devices and verdicts. The first day was the riskiest. A real-time monitoring dashboard (scan times, duplicate rates, throughput at each gate; gate-throughput analytics for staffing added in January) was the operational lifeline during live matches.

**Where this lives in our codebase (evidence):**

- Admin portal dashboard A-21 reads the Redis `capacity` hash directly for live numbers; gate reports A-19 read `CheckedTicket` (populated only after the S-14 Redis→DB flush — reports lag live state).
- Checker/gate management: A-17 ticket checker users, A-18 gate assignment (Redis `TicketCheckerLevelGateMap` consumed by the TicketChecker service), S-15 gate download-status cleanup.
- Mid-event change propagation: if an admin unassigns a checker, the scanning app stops only at the next sync tick — up to 90 seconds later, and only if the device has network (C-05 note 4).

---

## Part 2 — Areas to Be Careful (Derived from the Live Incidents)

Each area names its originating incident from Part 1, what to watch or test, the concrete codebase components involved, verified cautions from our code, and a proposed pass condition. Priorities: **P0** = must pass before any production release of that flow; **P1** = must pass before first live event; **P2** = operational readiness before first live event.

### Area 1 (P0) — Offline duplicate detection and multi-gate redemption
*Origin: Incident 1.*

- Same ticket scanned at two different gates/devices within the sync window; same gate repeatedly; multiple devices simultaneously.
- Photocopied / re-printed / screenshot QRs from the offline (agent) channel; tampered ticket identifiers; invalid signatures; another match's ticket.
- Post-reconnect conflict reconciliation: duplicates accepted offline must be detectable afterwards, with an audit trail.
- Accept the engineering limit honestly: with no shared state, pure offline mode cannot prevent all duplicates instantly. The article's simulated sync tests still showed a 2–3% duplicate rate — measure ours under the same conditions.

**Codebase components (evidence):** checker app C-03 (`qr_page_view_model.dart`, `vds_qr_decoder.dart`, `MainActivity.kt`), C-04 manual entry, C-06 manual ticket validation; TicketChecker service `TicketController.cs`; Ticketing signing S-08; offline ingestion X-13 `OfflineTicketSoldController.cs`.

**Verified cautions from our code:**

- Duplicate detection is **per-device local only** — the check is `ticketState.count > 0` in the device's own DB (C-03 note 4, Q-74). Two devices at the *same* gate sharing one download can both accept the same ticket until their counters merge via sync.
- **Manual ticket entry bypasses signature verification entirely** (C-06, Q-75) — the weakest validation path, exactly the one a crowd will find.
- A QR whose payload is missing an expected label (e.g. `Event ID`) **throws an exception** instead of showing "incorrect QR" (Q-71) — malformed or third-party QRs surface as crashes, not clean rejections.
- iOS devices cannot validate at all (Q-72) — any UAT device pool must be Android.

**Pass condition:** duplicates rejected wherever online coordination exists; offline conflicts identified after sync with an audit trail; residual offline duplicate rate measured, documented, and covered by an on-ground incident procedure.

### Area 2 (P0) — False rejection of valid tickets
*Origin: Incident 2.*

- A valid ticket must never be rejected because of sync lag. Measure the actual sync round-trip under stadium load — not the configured value.
- Clear "sync pending" state distinct from "invalid", so checkers never guess.
- On-ground support workflow when a legitimate ticket is falsely rejected (the worst live incident category in Part 1).

**Codebase components (evidence):** checker app C-05 (`qr_page_view_model.dart:22,102-140`, `ticket_api_service_impl.dart:21-38`); TicketChecker service `TicketController.cs`; S-14 flush worker (`CheckedTicketManager.cs`); Redis `ticketCheckerDbSync` flag.

**Verified cautions from our code:**

- Our sync interval is **90 seconds** (`qr_page_view_model.dart:22`) — the article cut theirs to 30 seconds precisely because longer intervals caused false rejections. Our offline conflict window is therefore 3× longer.
- The UI's "last sync time" updates **even when the sync call failed** (Q-76) — a checker can trust a timestamp that never actually synced.
- No retry backoff and no failure counter: the app blindly retries every 90 seconds through long outages.
- A checker unassigned mid-event keeps scanning for up to 90 seconds, and indefinitely if offline (C-05 note 4).

**Pass condition:** zero false rejections of valid tickets in testing; measured sync latency at or below target under load; the displayed sync state provably truthful; support procedure drilled.

### Area 3 (P0) — Payment consistency under failure
*Origin: Incident 3.*

- Gateway failure rate under concurrent load (20–30% at scale was the measured reality, not an edge case).
- Retry-window behaviour: seat held vs. released during retries; no double charge on repeated button presses; delayed and duplicate gateway callbacks handled safely.
- Money deducted but confirmation missing (browser timeout): order status recoverable without a second payment.
- Client-reported payment success never trusted as proof; verify against the gateway (`payment-status-bypass` must not become an attack path).
- Reconciliation: gateway records vs. orders vs. issued tickets (Admin Reconciliation report, A-23).

**Codebase components (evidence):** Booking service `DgePayPaymentManager.cs`, `UserBookingOrderController.cs` (callback + `payment-status-bypass`), `UserBookingOrder` table; Scheduler workers S-05 (pending/failed re-check, 7–10 min) and S-10 (VAT challan); user portal `complete-payment-modal` (P-06).

**Verified cautions from our code:**

- **Gateway redundancy does not exist yet**: SSLCommerz appears in the checkout form but its callback is disabled (Q-19). DgePay is the single active path — the article's fallback-gateway fix is not in place.
- The 7–10 minute S-05 re-check worker **can cancel an order that was actually paid late** (Q-11) — paid-but-cancelled is a live defect class, not a hypothesis.
- A late payment callback can **record VAT for an order that is still unpaid** (Q-15).

**Pass condition:** no duplicate charges or duplicate entitlements per logical payment; gateway, order, payment, and ticket states fully reconciled; the paid-late-cancellation and late-callback-VAT paths proven safe; refund/recovery path proven.

### Area 4 (P0) — Seat inventory race conditions
*Origin: Incident 4.*

- Concurrent purchase attempts on the same seat; bulk purchases with partial availability; mid-request failures and timeouts.
- Booking hold expiry: the seat returns to sale, and a late payment success must not conflict with a new buyer's confirmed seat.
- Cache vs. database capacity consistency, including `EventCapacity` queue propagation while sales are open.

**Codebase components (evidence):** Booking service Redis keys `level_live` / `level_live_seats` / `level_locked` (12-minute lock), `RefreshLockedCapacityService` with RedLock (S-03), `EventCapacity` queue → S-01/S-02 workers, `Capacity` / `SeatReservation` tables, `SeatReservationController.cs`.

**Verified cautions from our code:**

- The timing triangle must be tested together: **12-minute seat lock** (X-25) vs. **7–10 minute** pending-payment re-check (S-05) vs. the article's **10-minute** payment retry window. A payment that succeeds at minute 11 interacts with all three.
- No dead-letter queues and non-persisted retry counters on any queue (Q-09): a capacity message that fails to deserialize retries forever, silently.

**Pass condition:** at most one valid paid allocation per seat per event/session; expired holds always release; capacity, availability, and inventory remain mutually consistent after every change.

### Area 5 (P0) — Gate throughput and scan latency
*Origin: Incidents 5 and 6.*

- Sub-second scan target per person; sustained throughput per gate at a realistic 5,000–6,000 people per gate through 3–4 gates.
- Verdict feedback unmistakable: valid / already checked / wrong event / wrong gate / invalid / incorrect QR — no ambiguous results.
- Scan performance on low-end devices after hours of continuous use, not just on fresh high-end hardware.

**Codebase components (evidence):** checker app C-03 (fully local scan path, per-state sounds and haptics), vendored `flutter_barcode_scanner/`, drift local DB; the full-ticket download in C-02 that makes local verdicts possible.

**Verified cautions from our code:** Android-only verification (Q-72); certificate problems and bad QRs are indistinguishable to the checker — `verifyQrData` swallows inner errors to `debugPrint` and returns null (C-03 note 8), so a cert misconfiguration looks exactly like a fake ticket.

**Pass condition:** agreed per-gate throughput target met with clear verdicts and no device degradation over a full session.

### Area 6 (P1) — Checker device reliability
*Origin: Incident 6.*

- Endurance: hours of continuous scanning, battery drain, thermal throttling, app restart mid-shift.
- Local data (drift/SQLite) integrity: recovery after crash, corrupted cache, or storage full — without ever admitting on a guess.

**Codebase components (evidence):** checker app local DB `data/lib/local/drift_database/` (`qrTable`, `isSynced`, `isScannedFromOurApp` flags), `MainActivity.kt` crypto channel, restart reconstruction from `_getTicketList()` (C-05 note 6).

**Verified cautions from our code:** only rows flagged `isScannedFromOurApp` ever sync — any row created outside the normal scan path (e.g. by a restore or manual flow that skips the flag) is silently never uploaded (C-05 note 6).

**Pass condition:** recovery procedure exists for crash/corruption; scan results stay unambiguous; no device-specific state loss.

### Area 7 (P1) — Peak-load performance
*Origin: Incidents 3 and 5 (25,000 tickets/day scale).*

- On-sale-start spike (all buyers hitting search + seat map + checkout at once) — note that 25,000 tickets per day is not the same as 25,000 concurrent users; set load-test targets from RVL's real release windows.
- Seat-map rendering on low-end phones over weak networks (a UAT catch in Part 1, Incident 7).
- Database contention, connection saturation, background queue backlog recovery, and in-flight orders surviving a service restart or deployment.

**Codebase components (evidence):** Event service (public read views), Booking service, user portal `stadium-seat-page.component.ts` + user app U-04; SQS queues `OrderSuccess` / `EventCapacity` / `TicketSigning` / `TicketProcessing`; workers S-01…S-09.

**Verified cautions from our code:** `InitiateUserTicketGenerationService` runs a 15-minute loop that busy-waits when nothing qualifies (Q-12); no DLQ on any queue (Q-09) — backlog behaviour under poison messages is untested by design.

**Pass condition:** agreed numeric thresholds (API p95/p99, 5xx rate, booking correctness, queue lag) defined before UAT starts, then met.

### Area 8 (P1) — Late changes and mixed ticket channels
*Origin: Incident 8.*

- Online-issued and offline/agent-issued tickets validate identically under the same rules — mixed issuance is exactly where Incident 1's duplicates came from.
- Assume a ticket type will be added late (as physical tickets were, on Dec 15): new issuance path, layout/branding change, or gallery configuration change must not break QR integrity or scanning.
- Re-download / re-print of a ticket PDF yields another copy, not another entry entitlement.

**Codebase components (evidence):** X-13 `OfflineTicketSoldController.cs` + `OfflineSoldTicket` table; A-11 seat reservation, A-12 reserved tickets, S-09 merge/zip; A-13 ticket layouts (QR placement); C-03 offline-ticket confirmation dialog; P-09 downloads, P-10 OneID sync.

**Verified cautions from our code:**

- `OfflineSoldTicket` rows are **written but never read** (Q-07) and no agent client exists in the workspace — the offline channel's contribution to gate data cannot be verified from our repos; treat it as an external dependency in UAT planning.
- The VDS trust anchor is **one PEM certificate baked into `.env`** (`VDS_CERTIFICATE`); any certificate change on the signing side requires an app release, or every scan fails (Q-73) — exactly the "late change breaks validation" scenario.

**Pass condition:** all channels enforce one-ticket-one-entry; late configuration and ticket-type changes are safe without re-validating the entire chain manually.

### Area 9 (P2) — Operational readiness and the human factor
*Origin: Incident 9.*

- Dress rehearsal with real checkers on real (standardized) devices — not QA staff on good hardware; the article's checkers needed three matches to adapt, so the first live day is the riskiest.
- Real-time per-gate dashboard: scan times, duplicate rates, throughput — live during the event, not post-mortem.
- On-ground procedures: device swap mid-match, handling a false rejection at the gate, escalating a duplicate attempt.

**Codebase components (evidence):** Admin portal A-21 dashboard (Redis `capacity` hash), A-19 gate reports (`CheckedTicket`), A-17/A-18 checker + gate assignment (Redis `TicketCheckerLevelGateMap`); workers S-14 (Redis→DB flush), S-15 (download-status cleanup).

**Verified cautions from our code:** gate reports are only as current as the S-14 flush; unassignment of a live checker propagates within 90 seconds at best (C-05 note 4).

**Pass condition:** at least one full rehearsal completed with actual event staff; monitoring dashboard verified live; escalation procedures drilled.

### Additional areas from this workspace's architecture (not from the article)

These are not article-derived but follow from this repo's architecture and feature docs:

- **Auth dependency failures:** OneID Wallet SSO outage on a match day (X-08) — does the password login path still work (X-07)? SMS OTP/MFA delivery failures at scale (X-22; Admin 2FA is SMS-based).
- **Ticket email delivery:** SES failures or spam filtering must not block entry — the My Bookings download path (P-07/P-09) is the fallback (X-21).
- **Re-entry/exit rules:** whether a ticket permits exit-and-re-entry (e.g., galleries) is a product rule to confirm and test explicitly; it is not covered by the article.
- **Aurora failover:** the single-AZ vs multi-AZ question is still open with bs23 (`docs/architecture/gobcb-aws-architecture.md`, Q3); confirm failover behaviour before relying on it.

### Incident-to-area mapping

| Incident (Part 1) | Area (Part 2) | Priority | Key components (evidence) |
|---|---|---|---|
| 1. Duplicate printed tickets | Area 1 — Offline duplicate detection | P0 | Checker app C-03/C-04/C-06; TicketChecker `TicketController.cs`; Ticketing S-08; X-13 |
| 2. Sync-delay false rejections | Area 2 — False rejection | P0 | Checker app C-05 (90 s interval); S-14 worker; Q-76 |
| 3. Payment failures | Area 3 — Payment consistency | P0 | Booking `DgePayPaymentManager.cs`, `UserBookingOrderController.cs`; S-05/S-10; A-23 |
| 4. Same seat sold twice | Area 4 — Inventory race conditions | P0 | Booking Redis locks (S-03), `EventCapacity` queue (S-01/S-02), `SeatReservationController.cs` |
| 5. 30–60s scans | Area 5 — Throughput and latency | P0 | Checker app C-03 local path; drift DB; Q-72 |
| 6. Low-end devices | Area 6 — Device reliability | P1 | Checker app drift DB; `MainActivity.kt`; C-05 note 6 |
| 3 + 5. Scale (25k/day) | Area 7 — Peak load | P1 | Event service; Booking; portal `stadium-seat-page`; SQS queues; Q-09/Q-12 |
| 8. Physical tickets late | Area 8 — Mixed channels | P1 | X-13 `OfflineSoldTicketController.cs`; A-11/A-12/S-09; `.env VDS_CERTIFICATE` (Q-73) |
| 9. Checker adaptation | Area 9 — Operational readiness | P2 | Admin portal A-21/A-19/A-17/A-18; S-14/S-15 workers |
