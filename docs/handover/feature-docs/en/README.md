# GoBCB feature documentation (English)

[বাংলা সংস্করণ](../bn/README.md)

## 0. About this document

**Purpose.** For every business feature of the GoBCB (rvl-etp) event and ticketing platform, this document shows which screen
starts it, which endpoints and services handle it, which queues and workers continue it, which tables, Redis keys and files it
touches, which external systems it calls, and where the code is. It is written for RVL's tech lead: an experienced .NET developer
who has not worked on a microservices system before. Microservice concepts are explained once, in the
[platform primer](00-platform-primer.md), and every feature links to the explanation it needs.

**Who wrote it and from what.** It was written from the BS23 delivery side for the handover, from two sources only:

1. the source code of the five repositories (read-only), at the commits listed under [Evidence baseline](#evidence-baseline);
2. [`docs/architecture/gobcb-aws-architecture.md`](../../../architecture/gobcb-aws-architecture.md) for how the platform is hosted on AWS.

The developer test guides (section 11 of each feature) also use the local-development tooling in this workspace
(`docs/local-dev.md`, `docs/*-local.md`, `aspire/`, `floci/`, `postman/`, `scripts/`); see
[Appendix D](93-appendix-d-local-test-reference.md).

Nothing in this document is invented. Where the code does not answer a question, the text says so and carries a marker
`[UNCONFIRMED: Q-nn]` that links to the question in [Open queries](99-open-queries.md). An `[UNCONFIRMED]` statement is an
open question for BS23, not a fact.

### Evidence baseline

| Repository (submodule) | Commit |
|---|---|
| `rvl-gobcb-backend` | `430ec16d7554254ff4f6adfa21f9c0c10d3234b2` |
| `rvl-gobcb-admin-portal` | `f62d2756bd9bbd4bfaa92585ae3f999d9f4c213f` |
| `rvl-gobcb-user-portal` | `36aaf58c0dae070da9f958da09451d33e6e47c73` |
| `rvl-gobcb-user-app` | `365b8bee71454d94747b75bef7cb07e8b47b6f8a` |
| `rvl-gobcb-checker-app` | `e919c54dad40a33aecc9922a68637a4a887513e6` |

Line numbers in code references (`File.cs:123`) are valid for these commits. If a submodule moves, re-check the references of
the features you depend on.

## How to read a feature

Features are grouped by **what starts them**: a staff member in the admin portal (`A-xx`), a customer on the web portal
(`P-xx`) or in the app (`U-xx`), gate staff in the checker app (`C-xx`), the system itself on a timer or queue (`S-xx`), or a
concern shared by many features (`X-xx`, including all authentication and authorization). Each feature is one file with the
same eleven sections:

| # | Section | What it answers |
|---|---|---|
| 1 | Name and purpose | What the feature is for, in business terms (English and Bangla name) |
| 2 | Trigger and actor | Who starts it, from which client and screen, with which Cognito pool, role and program scope |
| 3 | Business flow | The steps as a business user sees them |
| 4 | Technical flow | The same steps as hops between components; every hop is tagged (see below) |
| 5 | Components | Clients, services, queues, workers, tables, Redis keys, buckets and external systems involved |
| 6 | API contracts | Every endpoint the feature uses (method, full path, auth, DTOs, main errors); full JSON samples for the main endpoint(s) only |
| 7 | Data and side effects | What is written: rows, queue messages, files, emails, pushes, cache entries |
| 8 | Code references | Where to start reading: controller, manager, worker, client file, with line numbers |
| 9 | Handover notes | Behaviour that is easy to miss, risks found in the code, and `[UNCONFIRMED: Q-nn]` items |
| 10 | Component relationships | A small diagram of this feature only, plus what it depends on and what depends on it |
| 11 | Developer test guide | How to run it locally: browser, emulator, Postman, Visual Studio debug, and how to verify the result |

**Hop tags used in section 4:**

| Tag | Meaning |
|---|---|
| **[HTTP + user token]** | Synchronous HTTP call that carries the caller's Cognito access token (from a client, or forwarded by a service) |
| **[HTTP, no token]** | Synchronous HTTP call without a token, usually from a background worker to an endpoint that has no `[Authorize]` |
| **[HTTP, static key]** | Synchronous HTTP call to an external system with a key from configuration |
| **[SQS: Name]** | A message put on, or read from, the SQS queue configured as `AWS:Queue:Name` |
| **[Worker: interval, lock]** | A background worker in a service, with its hard-coded interval and the Redis lock it takes (if any) |
| **[SignalR]** | WebSocket message through a SignalR hub |
| **[Shared table]** | One service reads a table that another service writes (same database, see [primer](00-platform-primer.md#explainer-shared-database)) |

**Paths.** Endpoint paths are written in full as the service exposes them, for example `/booking/api/v1/user-booking-order`.
The first segment is the service prefix (see [path-prefix routing](00-platform-primer.md#explainer-path-prefix-routing)).

## Contents

- [00 · Platform primer](00-platform-primer.md): services, clients, request path, error format, explainer boxes
- [01 · System map](01-system-map.md): every component and how they talk to each other
- [02 · Traceability matrix](02-traceability-matrix.md): feature → client → endpoint → service → async → data → external
- [03 · Component reverse index](03-component-reverse-index.md): component → features that depend on it
<!-- TOC:START -->
- **[10 · Admin Portal](10-admin-portal/README.md)**
  - [A-01 Program selection and program-scoped menu](10-admin-portal/A-01-program-selection.md)
  - [A-02 Programs](10-admin-portal/A-02-programs.md)
  - [A-03 Program settings](10-admin-portal/A-03-program-settings.md)
  - [A-04 Teams](10-admin-portal/A-04-teams.md)
  - [A-05 Venues and stadium layout](10-admin-portal/A-05-venues.md)
  - [A-06 Program–venue mapping and venue details](10-admin-portal/A-06-program-venue-mapping.md)
  - [A-07 Events (matches)](10-admin-portal/A-07-events.md)
  - [A-08 Event settings override](10-admin-portal/A-08-event-settings.md)
  - [A-09 Event venue details and per-level pricing](10-admin-portal/A-09-event-level-pricing.md)
  - [A-10 Event capacity adjustment](10-admin-portal/A-10-capacity-adjustment.md)
  - [A-11 Seat reservation (complimentary / partner)](10-admin-portal/A-11-seat-reservation.md)
  - [A-12 Reserved ticket generation and distribution](10-admin-portal/A-12-reserved-tickets.md)
  - [A-13 Ticket layouts and ticket attributes](10-admin-portal/A-13-ticket-layouts.md)
  - [A-14 Ticket-pricing content page](10-admin-portal/A-14-ticket-pricing-content.md)
  - [A-15 Promo codes](10-admin-portal/A-15-promo-codes.md)
  - [A-16 System discounts](10-admin-portal/A-16-discounts.md)
  - [A-17 Ticket-checker (gate staff) accounts](10-admin-portal/A-17-ticket-checker-users.md)
  - [A-18 Gate assignment and download control](10-admin-portal/A-18-gate-assignment.md)
  - [A-19 Gate (ticket-checker) reports](10-admin-portal/A-19-gate-reports.md)
  - [A-20 Raffle draw](10-admin-portal/A-20-raffle-draw.md)
  - [A-21 Dashboard](10-admin-portal/A-21-dashboard.md)
  - [A-22 Booking, sales, revenue and payment-discrepancy reports](10-admin-portal/A-22-reports.md)
  - [A-23 Reconciliation lookup](10-admin-portal/A-23-reconciliation.md)
  - [A-24 User issues and support chat (admin side)](10-admin-portal/A-24-user-issues-admin.md)
  - [A-25 Admin users](10-admin-portal/A-25-admin-users.md)
  - [A-26 Agent (seller) users](10-admin-portal/A-26-agent-users.md)
  - [A-27 Activity log viewer](10-admin-portal/A-27-activity-log.md)
  - [A-28 Media configuration (banners, gallery, contact, registration)](10-admin-portal/A-28-media-configuration.md)
  - [A-29 Content editor (T&C, FAQ, privacy, notice)](10-admin-portal/A-29-content-editor.md)
  - [A-30 Header/footer and social-media settings](10-admin-portal/A-30-header-footer-social.md)
  - [A-31 General notices](10-admin-portal/A-31-general-notices.md)
- **[20 · User Web Portal](20-user-portal/README.md)**
  - [P-01 Home page content](20-user-portal/P-01-home-content.md)
  - [P-02 Browse events and event details](20-user-portal/P-02-browse-events.md)
  - [P-03 Information pages (pricing, gallery, contact, policies)](20-user-portal/P-03-info-pages.md)
  - [P-04 Seat selection](20-user-portal/P-04-seat-selection.md)
  - [P-05 Apply promo code](20-user-portal/P-05-apply-promo-code.md)
  - [P-06 Booking order and online payment (DgePay)](20-user-portal/P-06-booking-payment.md)
  - [P-07 My bookings and generation status](20-user-portal/P-07-my-bookings.md)
  - [P-08 Ticket generation request](20-user-portal/P-08-ticket-generation-request.md)
  - [P-09 Ticket details, holder info, download, share, invoice](20-user-portal/P-09-ticket-details-downloads.md)
  - [P-10 Sync tickets to OneID wallet](20-user-portal/P-10-oneid-ticket-sync.md)
  - [P-11 Profile](20-user-portal/P-11-profile.md)
  - [P-12 Report an issue and chat with support](20-user-portal/P-12-issues-chat.md)
  - [P-13 Language switch (EN/BN)](20-user-portal/P-13-language-switch.md)
- **[30 · User App](30-user-app/README.md)**
  - [U-01 Splash, version gate and onboarding](30-user-app/U-01-splash-onboarding.md)
  - [U-02 Home and browse events](30-user-app/U-02-home-browse-events.md)
  - [U-03 Information pages (pricing, gallery, contact)](30-user-app/U-03-info-pages.md)
  - [U-04 Seat selection and promo code](30-user-app/U-04-seat-selection-promo.md)
  - [U-05 Booking and WebView payment](30-user-app/U-05-booking-webview-payment.md)
  - [U-06 My bookings and tickets](30-user-app/U-06-my-bookings-tickets.md)
  - [U-07 Profile and settings](30-user-app/U-07-profile-settings.md)
  - [U-08 Report an issue and support chat](30-user-app/U-08-issues-chat.md)
  - [U-09 Push device-token registration](30-user-app/U-09-device-token.md)
  - [U-10 Receiving push notifications](30-user-app/U-10-push-receipt.md)
- **[40 · Checker App](40-checker-app/README.md)**
  - [C-01 Assigned event and gate](40-checker-app/C-01-assigned-event-gate.md)
  - [C-02 Ticket download for offline checking](40-checker-app/C-02-offline-ticket-download.md)
  - [C-03 QR scan validation](40-checker-app/C-03-qr-scan-validation.md)
  - [C-04 Manual entry](40-checker-app/C-04-manual-entry.md)
  - [C-05 Scan sync](40-checker-app/C-05-ticket-sync.md)
  - [C-06 Signature-only ticket validation](40-checker-app/C-06-manual-ticket-validation.md)
- **[50 · System-initiated (workers and queues)](50-system-initiated/README.md)**
  - [S-01 Level capacity update (OrderSuccess queue)](50-system-initiated/S-01-level-capacity-update.md)
  - [S-02 Event live capacity (EventCapacity queue)](50-system-initiated/S-02-event-live-capacity.md)
  - [S-03 Locked-capacity refresh](50-system-initiated/S-03-locked-capacity-refresh.md)
  - [S-04 Scheduler capacity reconcile](50-system-initiated/S-04-scheduler-capacity-update.md)
  - [S-05 Pending/failed payment revalidation](50-system-initiated/S-05-pending-failed-revalidation.md)
  - [S-06 Booking status → Generated](50-system-initiated/S-06-booking-status-generated.md)
  - [S-07 Initiate user ticket generation](50-system-initiated/S-07-initiate-user-ticket-generation.md)
  - [S-08 Ticket signing via TSP (TicketSigning queue)](50-system-initiated/S-08-ticket-signing.md)
  - [S-09 Reserved ticket merge/zip (TicketProcessing queue)](50-system-initiated/S-09-ticket-merge-zip.md)
  - [S-10 VAT challan with NBR (VatChallanProcessing queue)](50-system-initiated/S-10-vat-challan.md)
  - [S-11 Push delivery to FCM (FirebaseNotification queue)](50-system-initiated/S-11-firebase-notification.md)
  - [S-12 Ticket-generated notification](50-system-initiated/S-12-ticket-generated-notification.md)
  - [S-13 Device-token cleanup](50-system-initiated/S-13-device-token-cleanup.md)
  - [S-14 Checked-ticket sync (Redis → database)](50-system-initiated/S-14-checked-ticket-sync.md)
  - [S-15 Gate download-status cleanup](50-system-initiated/S-15-gate-download-status-cleanup.md)
  - [S-16 Promo-code status update](50-system-initiated/S-16-promo-code-status.md)
  - [S-17 System-discount status update](50-system-initiated/S-17-discount-status.md)
- **[60 · Cross-cutting (authentication, authorization, platform services)](60-cross-cutting/README.md)**
  - [X-01 Admin login (phone OTP + password)](60-cross-cutting/X-01-admin-login.md)
  - [X-02 Admin forgot password](60-cross-cutting/X-02-admin-forgot-password.md)
  - [X-03 Admin change password and logout](60-cross-cutting/X-03-admin-change-password-logout.md)
  - [X-04 Admin session handling (token attach and refresh)](60-cross-cutting/X-04-admin-session.md)
  - [X-05 Staff account provisioning](60-cross-cutting/X-05-admin-provisioning.md)
  - [X-06 Customer registration](60-cross-cutting/X-06-user-registration.md)
  - [X-07 Customer login with phone and password](60-cross-cutting/X-07-user-password-login.md)
  - [X-08 OneID single sign-on](60-cross-cutting/X-08-oneid-sso.md)
  - [X-09 Customer forgot/reset password](60-cross-cutting/X-09-user-forgot-password.md)
  - [X-10 Customer change password, logout and token attach](60-cross-cutting/X-10-user-session.md)
  - [X-11 Delete account and app force-update](60-cross-cutting/X-11-delete-account-force-update.md)
  - [X-12 Checker login](60-cross-cutting/X-12-checker-login.md)
  - [X-13 Agent pool and offline-sold tickets](60-cross-cutting/X-13-agent-pool.md)
  - [X-14 Authorization layer 1: pool schemes and policies](60-cross-cutting/X-14-authz-pool-policies.md)
  - [X-15 Authorization layers 2–3: staff roles](60-cross-cutting/X-15-authz-roles.md)
  - [X-16 Authorization layer 4: program scope](60-cross-cutting/X-16-authz-program-scope.md)
  - [X-17 Client-side authorization (menus and guards)](60-cross-cutting/X-17-authz-client-side.md)
  - [X-18 Endpoints without authorization](60-cross-cutting/X-18-endpoints-without-auth.md)
  - [X-19 Service-to-service communication](60-cross-cutting/X-19-service-to-service.md)
  - [X-20 File storage (S3, CloudFront)](60-cross-cutting/X-20-file-storage.md)
  - [X-21 Email (SES)](60-cross-cutting/X-21-email-ses.md)
  - [X-22 SMS and the external notification service](60-cross-cutting/X-22-sms-notification.md)
  - [X-23 Push notifications (PushNotification service, Firebase)](60-cross-cutting/X-23-push-firebase.md)
  - [X-24 Activity logging (audit trail)](60-cross-cutting/X-24-activity-logging.md)
  - [X-25 Redis: cache, live capacity and locks](60-cross-cutting/X-25-redis.md)
  - [X-26 Configuration and secrets](60-cross-cutting/X-26-configuration.md)
<!-- TOC:END -->
- [90 · Appendix A: legacy, unused and dormant code](90-appendix-a-legacy.md)
- [91 · Appendix B: endpoint index](91-appendix-b-endpoint-index.md)
- [92 · Appendix C: coverage](92-appendix-c-coverage.md)
- [93 · Appendix D: local test reference](93-appendix-d-local-test-reference.md)
- [99 · Open queries](99-open-queries.md)

## Where to start

| If you are… | Read, in this order |
|---|---|
| **New to the platform** | [00 · Platform primer](00-platform-primer.md) → [01 · System map](01-system-map.md) → one feature from each section |
| **A .NET developer meeting microservices for the first time** | [00 · Platform primer](00-platform-primer.md) — the explainer boxes cover path-prefix routing, the shared database, queues and RedLock. Then [X-19](60-cross-cutting/X-19-service-to-service.md) and [X-25](60-cross-cutting/X-25-redis.md) |
| **Reviewing a security risk** | [01 §8](01-system-map.md#8-where-the-risk-is), then [X-18](60-cross-cutting/X-18-endpoints-without-auth.md), then [99 §5](99-open-queries.md#5-defects--code-that-appears-wrong) |
| **Picking up the backend** | [02 · Traceability matrix](02-traceability-matrix.md) §2, then [50 · System-initiated](50-system-initiated/README.md) |
| **Picking up a client** | [02](02-traceability-matrix.md) §2 for your client section, then [93 · Local test reference](93-appendix-d-local-test-reference.md) |
| **Changing a table, queue or Redis key** | [03 · Component reverse index](03-component-reverse-index.md) — it lists every reader |
| **Asked a question the code cannot answer** | [99 · Open queries](99-open-queries.md) — 75 items, each marked external, deployment, ambiguity or defect |
| **Setting up locally** | [`docs/local-dev.md`](../../../local-dev.md), then [93](93-appendix-d-local-test-reference.md) for what cannot work and why |
| **Deciding what to delete** | [90 · Appendix A](90-appendix-a-legacy.md) |

## The numbers

| | |
|---|---|
| Feature files | **103** (31 admin, 13 portal, 10 app, 6 checker, 17 system, 26 cross-cutting) |
| Backend services | 9 real + 2 stubs |
| HTTP endpoints indexed | 354 routes across 58 controllers |
| Background workers | 17 |
| SQS queues | 6 |
| Open queries | **75** (Q-01 … Q-77; Q-21 and Q-24 unused) |
| Findings rated "defect" | 23 — the ones to fix first |

## Corrections to earlier drafts

Two statements in earlier drafts were wrong and have been corrected against the code:

| Claim | Correction |
|---|---|
| "The user portal does not call `getAllGeneralNotices` — it has no caller." | It **is** called and the rows **are** fetched and filtered; `notices` is simply never bound in the template (`// Fetch notices but do not start the marquee`). See [P-01](20-user-portal/P-01-home-content.md) note 2 and [A-31](10-admin-portal/A-31-general-notices.md) note 2. |
| "The customer pricing page reads the ticket-pricing content an admin edits." | It reads `program-pricing` (live event prices). `getTicketPricingList()` has no caller, so nothing published in [A-14](10-admin-portal/A-14-ticket-pricing-content.md) is ever shown. |
