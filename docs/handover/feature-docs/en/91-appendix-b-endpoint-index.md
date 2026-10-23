# 91 · Appendix B — Endpoint index

> **Bangla name:** এন্ডপয়েন্ট ইনডেক্স
>
> [← Contents](README.md) · [Open queries](99-open-queries.md)

A controller-level index of every HTTP endpoint in the backend, with the feature files that use it. This is the page to use when you have a request path and want to know **which screen caused it** or **which screen should be looking at it**.

## 1. How to read a path

An external URL is built from three parts:

```
/{Application:ServiceName}/{[Route] on the controller}/{[Http*] route}
```

so `TicketsController` with `[Route("api/v1/tickets")]` and `[HttpPost("sync-tickets")]` in TicketChecker (whose `ServiceName` is `ticketChecker`) is externally:

```
POST /ticketChecker/api/v1/tickets/sync-tickets
```

The prefix is added by `GlobalRoutePrefixConvention` in each `Program.cs` and terminated by the nginx ingress — see [00 · Platform primer](00-platform-primer.md) §2.

## 2. Index by service

Counts are route attributes found in the service's controllers.

### 2.1 Admin — `/admin`, port 5101, 33 controllers, 211 routes

| Controller | Route prefix | Routes | Feature |
|---|---|---|---|
| `ProgramController` | `api/v1/program` | 5 | [A-01](10-admin-portal/A-01-program-selection.md), [A-02](10-admin-portal/A-02-programs.md) |
| `ProgramSettingsController` | `api/v1/program-settings` | 3 | [A-03](10-admin-portal/A-03-program-settings.md) |
| `TeamsController` | `api/v1/teams` | 8 | [A-04](10-admin-portal/A-04-teams.md) |
| `VenuesController` | `api/v1/venues` | 20 | [A-05](10-admin-portal/A-05-venues.md) |
| `ProgramVenueController` | `api/v1/programVenue` | 2 | [A-06](10-admin-portal/A-06-program-venue-mapping.md) |
| `ProgramVenueDetailsController` | `api/v1/programVenueDetails` | 7 | [A-06](10-admin-portal/A-06-program-venue-mapping.md), [A-09](10-admin-portal/A-09-event-level-pricing.md) |
| `EventsController` | `api/v1/events` | 17 | [A-07](10-admin-portal/A-07-events.md) |
| `EventSettingsController` | `api/v1/event-settings` | 2 | [A-08](10-admin-portal/A-08-event-settings.md) |
| `EventsVenueDetailsController` | `api/v1/eventsVenueDetails` | 5 | [A-09](10-admin-portal/A-09-event-level-pricing.md) |
| `BlockLevelEntryGateController` | `api/v1/block-level-entry-gate` | 1 | [A-09](10-admin-portal/A-09-event-level-pricing.md) |
| `EventCapacityAdjustmentController` (Booking) | `api/v1/event-capacity-adjustment` | 4 | [A-10](10-admin-portal/A-10-capacity-adjustment.md) |
| `SeatReservationController` (Booking) | `api/v1/seat-reservation` | 15 | [A-11](10-admin-portal/A-11-seat-reservation.md), [A-12](10-admin-portal/A-12-reserved-tickets.md) |
| `TicketLayoutConfigsController` | `api/v1/ticket-layout` | 19 | [A-13](10-admin-portal/A-13-ticket-layouts.md) |
| `TicketAttributesController` | `api/v1/ticket-attributes` | 4 | [A-13](10-admin-portal/A-13-ticket-layouts.md) |
| `TicketPricingController` | `api/v1/ticket-pricing` | 9 | [A-14](10-admin-portal/A-14-ticket-pricing-content.md) — **not read by the customer pricing page** |
| `PromoCodeController` | `api/v1/promo-codes` | 8 | [A-15](10-admin-portal/A-15-promo-codes.md), [P-05](20-user-portal/P-05-apply-promo-code.md) |
| `DiscountController` | `api/v1/discount` | 8 | [A-16](10-admin-portal/A-16-discounts.md), [U-04](30-user-app/U-04-seat-selection-promo.md) |
| `TicketCheckerController` | `api/v1/ticket-checker` | 11 | [A-17](10-admin-portal/A-17-ticket-checker-users.md) |
| `TicketCheckerGateController` | `api/v1/ticket-checker-gate` | 14 | [A-18](10-admin-portal/A-18-gate-assignment.md), [C-01](40-checker-app/C-01-assigned-event-gate.md) |
| `RaffleDrawController` | `api/v1/raffle-draw` | 4 | [A-20](10-admin-portal/A-20-raffle-draw.md) |
| `DashboardController` | `api/v1/dashboard` | 2 | [A-21](10-admin-portal/A-21-dashboard.md) |
| `ReportController` (Booking) | `api/v1/report` | 8 | [A-22](10-admin-portal/A-22-reports.md) |
| `BookingReportController` (Booking) | `api/v1/dashboard` | 4 | [A-21](10-admin-portal/A-21-dashboard.md), [A-22](10-admin-portal/A-22-reports.md) |
| `UserIssueController` | `api/v1/user-issue` | 7 | [A-24](10-admin-portal/A-24-user-issues-admin.md) |
| `UserIssueChatController` | `api/v1/user-issue-chat` | 8 | **Legacy copy**, no auth — [Appendix A §2.1](90-appendix-a-legacy.md), [Q-46](99-open-queries.md) |
| `AdminUsersController` | `api/v1/admin-users` | 10 | [A-25](10-admin-portal/A-25-admin-users.md), [X-05](60-cross-cutting/X-05-admin-provisioning.md) |
| `AgentUserController` | `api/v1/agent-users` | 8 | [A-26](10-admin-portal/A-26-agent-users.md), [X-13](60-cross-cutting/X-13-agent-pool.md) |
| `ActivityLogController` | `api/v1/activity-log` | 3 | [A-27](10-admin-portal/A-27-activity-log.md), [X-24](60-cross-cutting/X-24-activity-logging.md) |
| `LandingPageImageController` | `api/v1/landing-page-image` | 11 | [A-28](10-admin-portal/A-28-media-configuration.md) |
| `GalleryController` | `api/v1/gallery` | 1 | [A-28](10-admin-portal/A-28-media-configuration.md) |
| `HeaderFooterController` | `api/v1/header-footer` | 2 | [A-30](10-admin-portal/A-30-header-footer-social.md) |
| `SocialMediaSettingsController` | `api/v1/social-media-settings` | 2 | **Legacy** record — [A-30](10-admin-portal/A-30-header-footer-social.md), [Q-34](99-open-queries.md) |
| `GeneralNoticeController` | `api/v1/general-notice` | 6 | [A-31](10-admin-portal/A-31-general-notices.md) — **not read by the portal** |
| `SystemSettingsController` | `api/v1/system-settings` | 1 | [X-26](60-cross-cutting/X-26-configuration.md) |
| `CurrencyController` | `api/v1/currency` | 1 | Dormant |
| `PortalUsersController` | `api/v1/portal-users` | 1 | Dormant |
| `TokenIssuerController` | `api/v1/token` | 1 | [X-04](60-cross-cutting/X-04-admin-session.md) |

### 2.2 Booking — `/booking`, port 5102, 6 controllers, 63 routes

| Controller | Route prefix | Routes | Feature |
|---|---|---|---|
| `UserBookingOrderController` | `api/v1/user-booking-order` | 23 | [P-06](20-user-portal/P-06-booking-payment.md), [P-07](20-user-portal/P-07-my-bookings.md), [P-08](20-user-portal/P-08-ticket-generation-request.md), [A-23](10-admin-portal/A-23-reconciliation.md), [U-05](30-user-app/U-05-booking-webview-payment.md), [U-06](30-user-app/U-06-my-bookings-tickets.md) |
| `CapacityController` | `api/v1/capacity` | 9 | [P-04](20-user-portal/P-04-seat-selection.md), [U-04](30-user-app/U-04-seat-selection-promo.md), [S-01](50-system-initiated/S-01-level-capacity-update.md) |
| `SeatReservationController` | `api/v1/seat-reservation` | 15 | [A-11](10-admin-portal/A-11-seat-reservation.md), [A-12](10-admin-portal/A-12-reserved-tickets.md) |
| `EventCapacityAdjustmentController` | `api/v1/event-capacity-adjustment` | 4 | [A-10](10-admin-portal/A-10-capacity-adjustment.md) |
| `ReportController` | `api/v1/report` | 8 | [A-22](10-admin-portal/A-22-reports.md) |
| `BookingReportController` | `api/v1/dashboard` | 4 | [A-21](10-admin-portal/A-21-dashboard.md) |

### 2.3 Event — `/event`, port 5103, 6 controllers, 16 routes

All public, no token. These are the endpoints the portals and app read to render content.

| Controller | Route prefix | Routes | Feature |
|---|---|---|---|
| `EventsController` | `api/v1/events` | 9 | [P-02](20-user-portal/P-02-browse-events.md), [U-02](30-user-app/U-02-home-browse-events.md) |
| `ProgramController` | `api/v1/events/programs` | 2 | [P-01](20-user-portal/P-01-home-content.md), [U-02](30-user-app/U-02-home-browse-events.md) |
| `LandingPageImageController` | `api/v1/landing-page-image` | 1 | [P-01](20-user-portal/P-01-home-content.md), [U-02](30-user-app/U-02-home-browse-events.md), [U-03](30-user-app/U-03-info-pages.md) — **shared with the gallery** ([Q-53](99-open-queries.md)) |
| `TicketPricingController` | `api/v1/ticket-pricing` | 2 | [P-03](20-user-portal/P-03-info-pages.md), [U-03](30-user-app/U-03-info-pages.md) (`program-pricing`) |
| `HeaderFooterController` | `api/v1/header-footer` | 1 | [P-01](20-user-portal/P-01-home-content.md) |
| `HomeController` | (root) | 1 | Home aggregate |

### 2.4 Ticketing — `/ticketing`, port 5108, 3 controllers, 35 routes

| Controller | Route prefix | Routes | Feature |
|---|---|---|---|
| `BookingOrderTicketController` | `api/v1/booking-order-ticket` | 33 | [P-08](20-user-portal/P-08-ticket-generation-request.md), [P-09](20-user-portal/P-09-ticket-details-downloads.md), [P-10](20-user-portal/P-10-oneid-ticket-sync.md), [U-06](30-user-app/U-06-my-bookings-tickets.md), [S-06](50-system-initiated/S-06-booking-status-generated.md), [S-07](50-system-initiated/S-07-initiate-user-ticket-generation.md), [S-08](50-system-initiated/S-08-ticket-signing.md), [S-09](50-system-initiated/S-09-ticket-merge-zip.md) |
| `OfflineTicketSoldController` | `api/v1/offline-sold-ticket` | 1 | Agent-only, no client — [X-13](60-cross-cutting/X-13-agent-pool.md), [Q-07](99-open-queries.md) |
| `TestTicketGeneratorController` | `api/TestTicketGenerator` | 1 | **Dead, no auth** — [Appendix A §3](90-appendix-a-legacy.md) |

### 2.5 TicketChecker — `/ticketChecker`, port 5107, 3 controllers, 4 routes

| Controller | Route prefix | Routes | Feature |
|---|---|---|---|
| `TicketController` | `api/v1/tickets` | 1 | [C-02](40-checker-app/C-02-offline-ticket-download.md), [C-05](40-checker-app/C-05-ticket-sync.md) (`POST sync-tickets`) |
| `TestingController` | `api/v1/testing` | 2 | **Dead, no auth** — [Appendix A §3](90-appendix-a-legacy.md) |
| `WeatherForecastController` | `api/[controller]` | 1 | Stub |

### 2.6 UserIssue — `/userissue`, port 5110, 2 controllers, 16 routes

Note: **no `Application:ServiceName`** in `appsettings.json`, so the prefix is added differently from the other services — confirm the deployed route.

| Controller | Route prefix | Routes | Feature |
|---|---|---|---|
| `ReportIssueController` | `api/v1/user-issue` | 8 | [P-12](20-user-portal/P-12-issues-chat.md), [U-08](30-user-app/U-08-issues-chat.md) |
| `ReportIssueChatController` | `api/v1/user-issue-chat` | 8 | [P-12](20-user-portal/P-12-issues-chat.md), [U-08](30-user-app/U-08-issues-chat.md) — **no auth** ([Q-46](99-open-queries.md)) |

### 2.7 PushNotification — `/pushnotification`, port 5105, 2 controllers, 9 routes

Authentication middleware is **disabled service-wide** — every route below is open ([Q-62](99-open-queries.md), [X-18](60-cross-cutting/X-18-endpoints-without-auth.md)).

| Controller | Route prefix | Routes | Feature |
|---|---|---|---|
| `DeviceTokenController` | `api/v1/device-token` | 5 | [U-09](30-user-app/U-09-device-token.md), [S-13](50-system-initiated/S-13-device-token-cleanup.md) |
| `NotificationController` | `api/v1/push-notification` | 4 | [X-23](60-cross-cutting/X-23-push-firebase.md), [S-11](50-system-initiated/S-11-firebase-notification.md) |

### 2.8 Services with no controllers

| Service | Prefix | Port | What it has |
|---|---|---|---|
| **Scheduler** | `/scheduler` | 5106 | Workers only — [S-11](50-system-initiated/S-11-firebase-notification.md) … [S-15](50-system-initiated/S-15-gate-download-status-cleanup.md) |
| **Utility** | `/utility` | 5111 | Worker only — [S-09](50-system-initiated/S-09-ticket-merge-zip.md) |
| **Platform** | `/platform` | 5104 | Stub |
| **UserAuth** | `/userAuth` | 5109 | Stub (`/health` only) |

## 3. Non-HTTP interfaces

Not endpoints, but the other ways a client reaches the platform.

| Kind | Where | Used by | Feature |
|---|---|---|---|
| **SignalR hub** | `/userissue/chathub`, `/admin/chathub` | Portal and app chat | [P-12](20-user-portal/P-12-issues-chat.md), [U-08](30-user-app/U-08-issues-chat.md) |
| **Method channel** | `certificate/methods` (`verifyCertificate`) | Checker app | [C-03](40-checker-app/C-03-qr-scan-validation.md) — **Android only**, iOS has no handler ([Q-72](99-open-queries.md)) |
| **SQS queue** | 6 queues | Services and workers | [50 · System-initiated](50-system-initiated/README.md) |
| **External identity API** | `user/*`, `otp/*` | Portal, app | [X-06](60-cross-cutting/X-06-user-registration.md), [P-11](20-user-portal/P-11-profile.md) — not in the workspace ([Q-01](99-open-queries.md)) |

## 4. The endpoints you will call first

If you are setting up a local environment or writing a smoke test, these nine cover most of the product.

| # | Endpoint | Why |
|---|---|---|
| 1 | `POST /admin/api/v1/program` | Create the program everything hangs off ([A-02](10-admin-portal/A-02-programs.md)) |
| 2 | `POST /admin/api/v1/venues` | Create a venue ([A-05](10-admin-portal/A-05-venues.md)) |
| 3 | `POST /admin/api/v1/ticket-layout` | Upload and **publish** a layout — required before an event ([A-13](10-admin-portal/A-13-ticket-layouts.md)) |
| 4 | `POST /admin/api/v1/events` | Create and publish an event ([A-07](10-admin-portal/A-07-events.md)) |
| 5 | `GET /event/api/v1/events/list` | Confirm the event is public ([P-02](20-user-portal/P-02-browse-events.md)) |
| 6 | `GET /booking/api/v1/capacity/level-user-portal-seats` | The seats a customer sees ([P-04](20-user-portal/P-04-seat-selection.md)) |
| 7 | `POST /booking/api/v1/user-booking-order` | Create an order ([P-06](20-user-portal/P-06-booking-payment.md)) |
| 8 | `POST /ticketChecker/api/v1/tickets/sync-tickets` | The checker's download and upload, the same endpoint ([C-02](40-checker-app/C-02-offline-ticket-download.md), [C-05](40-checker-app/C-05-ticket-sync.md)) |
| 9 | `GET /admin/api/v1/ticket-checker-gate/event-info` | The checker's assignment ([C-01](40-checker-app/C-01-assigned-event-gate.md)) |

## 5. Postman collections

The workspace ships collections under `postman/`, all against the local services:

| Collection | Covers |
|---|---|
| `services/etp-admin.postman_collection.json` | Admin service |
| `services/etp-booking.postman_collection.json` | Booking service |
| `services/etp-event.postman_collection.json` | Event service |
| `services/etp-ticketing.postman_collection.json` | Ticketing service |
| `services/etp-ticketchecker.postman_collection.json` | TicketChecker service |
| `services/etp-pushnotification.postman_collection.json` | PushNotification service |
| `services/etp-userissue.postman_collection.json` | UserIssue service |
| `services/etp-cognito-auth.postman_collection.json` | Cognito pool sign-in |
| `etp-login-all-pools.postman_collection.json` | Sign in to all four pools |

Environments: `etp-local-services.postman_environment.json`, `etp-local-floci.postman_environment.json`.

**No collection exists for:** the external identity API ([Q-01](99-open-queries.md)), the OneID wallet ([Q-06](99-open-queries.md)), or the PushNotification send endpoints beyond the tokens. Any feature whose test guide says "not in any collection" refers to these.

## 6. Component relationships

```mermaid
flowchart LR
  CLI["Client"] -->|"HTTP + bearer"| ING["nginx ingress<br/>strips the prefix"]
  ING --> SVC{"service"}
  SVC --> ADM["Admin 211"]
  SVC --> BKG["Booking 63"]
  SVC --> EVT["Event 16"]
  SVC --> TKT["Ticketing 35"]
  SVC --> CHK["TicketChecker 4"]
  SVC --> ISS["UserIssue 16"]
  SVC --> PSH["PushNotification 9<br/>NO AUTH"]
  SCH["Scheduler<br/>workers"] -.->|"SQS"| SVC
  CLI -.->|"Method channel"| CHK
  CLI -.->|"SignalR"| ISS
```

**Depends on:** [00 · Platform primer](00-platform-primer.md) (service list), [Appendix A](90-appendix-a-legacy.md) (which endpoints are dead). **Affects:** [02 · Traceability matrix](02-traceability-matrix.md) — this page is the endpoint half of it.