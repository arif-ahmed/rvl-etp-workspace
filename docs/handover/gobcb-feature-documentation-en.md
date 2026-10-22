# GoBCB Platform — Feature Documentation (Technical Handover)

> **Bangla version:** the identical document in Bangla is `gobcb-feature-documentation-bn.md` next to this file.
> **Hosting architecture:** `docs/architecture/gobcb-aws-architecture.md` (referenced throughout as "the architecture doc").

## 0. Orientation

### 0.1 Purpose, audience and how to read

**Purpose.** For every business feature of the GoBCB (rvl-etp) event and ticketing platform this document shows which screen starts it, which endpoints and services handle it, which queues and workers continue it, which tables, Redis keys and files it touches, which external systems it calls, and where the code is.

**Audience.** RVL's incoming tech lead: an experienced .NET developer who has **not worked on a microservices system before**. Microservice concepts are explained once, in this Part 0, in 📦 **explainer boxes**; features reference them instead of repeating.

**Sources.** Written from the BS23 delivery side for the handover, from two sources only:

1. the source code of the five repositories (read-only), at the commits below;
2. `docs/architecture/gobcb-aws-architecture.md` for how the platform is hosted on AWS.

Nothing here is invented. Where the code cannot answer a question, the text says so and carries a marker `[UNCONFIRMED]` that is collected in the **Open queries** section at the end of this document, written so each query can be sent to BS23 as-is.

### Evidence baseline

| Repository (submodule) | Commit |
|---|---|
| `rvl-gobcb-backend` | `430ec16d7554254ff4f6adfa21f9c0c10d3234b2` |
| `rvl-gobcb-admin-portal` | `f62d2756bd9bbd4bfaa92585ae3f999d9f4c213f` |
| `rvl-gobcb-user-portal` | `36aaf58c0dae070da9f958da09451d33e6e47c73` |
| `rvl-gobcb-user-app` | `365b8bee71454d94747b75bef7cb07e8b47b6f8a` |
| `rvl-gobcb-checker-app` | `e919c54dad40a33aecc9922a68637a4a887513e6` |

Line numbers in code references (`File.cs:123`) are valid for these commits. If a submodule moves, re-check the references of the features you depend on.

### Feature template

Features are grouped by **what starts them**: staff in the admin portal (F1.x), customers on the web portal (F2.x) or in the app (F3.x), gate staff in the checker app (F4.x), the system itself on a timer or queue (F5.x), or a concern shared by many features (F6.x, including all authentication and authorization). Every feature follows the same nine sections:

| # | Section | What it answers |
|---|---|---|
| 1 | Name and purpose | What the feature is for, in business terms (English and Bangla name) |
| 2 | Trigger and actor | Who starts it, from which client and screen, with which Cognito pool, role and program scope |
| 3 | Business flow | The steps as a business user sees them |
| 4 | Technical flow | The same steps as hops between components; every hop is tagged (below) |
| 5 | Components | Clients, services, queues, workers, tables, Redis keys, buckets and external systems involved |
| 6 | API contracts | The endpoints the feature uses (method, full path, auth, DTOs, main errors); full JSON samples for the main endpoint(s) |
| 7 | Data and side effects | What is written: rows, queue messages, files, emails, pushes, cache entries |
| 8 | Code references | Where to start reading: controller, manager, worker, client file |
| 9 | Handover notes | Behaviour that is easy to miss, risks found in the code, and `[UNCONFIRMED]` items |

**Hop tags used in section 4:**

| Tag | Meaning |
|---|---|
| **[HTTP + user token]** | Synchronous HTTP call that carries the caller's Cognito access token (from a client, or forwarded by a service) |
| **[HTTP, no token]** | Synchronous HTTP call without a token, usually from a background worker to an endpoint that has no `[Authorize]` |
| **[HTTP, static key]** | Synchronous HTTP call to an external/internal system with a key from configuration |
| **[SQS: Key]** | A message put on, or read from, the SQS queue configured as `AWS:Queue:Key` |
| **[Worker: interval, lock]** | A background worker in a service, with its hard-coded interval and the Redis lock it takes (if any) |
| **[SignalR]** | WebSocket message through a SignalR hub |
| **[Shared table]** | One service reads a table that another service writes (same database, see §0.8) |

**Paths** are written in full as clients call them, for example `/booking/api/v1/user-booking-order`; the first segment is the service prefix (§0.6).

### 0.2 The platform in one paragraph

GoBCB sells and checks tickets for Bangladesh Cricket Board events. Staff set up **programs** (a series or a tournament), the **venues** (stadium → gallery → block → level), the **events** (matches) with prices and capacity, promotions and ticket layouts in the **admin portal**. Customers browse and buy on the **user web portal** or the **user app**, pay through **DgePay**, and receive digitally signed PDF tickets with a QR code. Gate staff scan the QR codes offline with the **checker app**. The backend is a set of ASP.NET Core 8 web APIs ("services") in one repository, running on Amazon EKS behind API Gateway (architecture doc §0–§4).

### 0.3 Repositories

This workspace (`rvl-etp-workspace`) orchestrates five git submodules:

| Repo | What it is |
|---|---|
| `rvl-gobcb-backend` | .NET 8 backend: 11 service projects (9 active + 2 stubs) + shared `Core/` libraries |
| `rvl-gobcb-admin-portal` | Angular admin portal (staff) |
| `rvl-gobcb-user-portal` | Angular user web portal (app lives in the `ETP-Web/` subfolder) |
| `rvl-gobcb-user-app` | Flutter app for end users (clean architecture: `presentation/`, `domain/`, `data/` packages) |
| `rvl-gobcb-checker-app` | Flutter app for gate checkers |

### 0.4 Backend services

All services live in `rvl-gobcb-backend/Services/<Name>/`, each split into `ETP.<Name>.Service` (controllers, `Program.cs`, workers), `.Domain` (managers = business logic), `.Storage` (EF Core `DbContext`, repositories) and, for some, `.Client` (typed HTTP client other services use) and `.Integration`. Shared code is in `rvl-gobcb-backend/Core/` (`ETP.Core`, `ETP.Core.Web`, `ETP.Core.EntityFramework`, `ETP.Core.BlobStorage`, `ETP.Core.Storage`, `ETP.Core.Email`, `ETP.Core.SMS`, `ETP.Core.EventBus`).

| Service | Path prefix | Local port | What it does (from controllers and workers) | DB connection key | Background workers |
|---|---|---|---|---|---|
| Admin | `/admin` | 5101 | Master data and back office: programs, venues, events, settings, promo codes, discounts, ticket layouts, staff users (Cognito), gate assignment, raffle, notices, site content, activity log, dashboard | `ConnectionStrings:Admin` | `CheckedTicketService`, `PromoCodeStatusUpdateService`, `SystemDiscountStatusUpdateService`, `GateCheckerDownloadStatusCleanupService` |
| Booking | `/booking` | 5102 | Capacity and seats, booking orders, payment (DgePay), promo-code application, seat reservations, capacity adjustments, sales reports, VAT challan | `ConnectionStrings:Booking` | `BookingStatusUpdateService`, `InitiateUserTicketGenerationService`, `LevelCapacityUpdateService`, `RefreshLockedCapacityService`, `EventLiveCapacityUpdateService`, `VatChallanProcessingService` |
| Event | `/event` | 5103 | Public, read-only view of programs, events, venue details, landing images, header/footer and ticket pricing for the portals and app | `ConnectionStrings:Event` | none |
| Ticketing | `/ticketing` | 5108 | Tickets: generation, signing (TSP), PDFs, downloads, sharing, invoices, reserved tickets, OneID sync, offline-sold tickets | `ConnectionStrings:Booking` (sic — see §0.8) | `TicketGenerationService` |
| TicketChecker | `/ticketchecker` | 5107 | Sync endpoint for the checker app (scans in, scans out) | `ConnectionStrings:TicketChecker` | none |
| UserIssue | `/userissue` | 5110 | Customer issues and support chat; hosts the SignalR hub `/userissue/chathub` | `ConnectionStrings:UserIssue` | none |
| PushNotification | `/pushnotification` | 5105 | Device tokens and push send APIs (writes to a queue) | `ConnectionStrings:PushNotification` | none |
| Scheduler | `/scheduler` | 5106 | Workers only: push delivery to Firebase, payment revalidation, ticket-generated notices, capacity reconcile, device-token cleanup | none | `FirebaseNotificationService`, `PendingOrFailedBookingStatusUpdateService`, `SendNotificationAfterGeneratedTicketService`, `CapacityUpdateService`, `DeviceTokenCleanupService` |
| Utility | `/utility` | 5111 | Worker only: merges/zips reserved tickets | none | `TicketProcessingService` |
| Platform | `/platform` | 5104 | **Stub** — only a Visual Studio template `WeatherForecastController`; not in production use | none | none |
| UserAuth | `/userauth` | 5109 | **Stub** — no real controllers; the identity API that clients call at `AUTH_API_BASE_URL` / `services.identity` is **not** this project (see Open queries) | none | none |

Sources: `Services/*/ETP.*.Service/Program.cs` and `Configuration(s)/DependencyConfig.cs`, `Services/*/ETP.*.Service/appsettings.json` (`Application:ServiceName` is the path prefix; UserIssue has no committed `appsettings.json` — its prefix `userissue` comes from the hub mapping and the clients). Local ports from `aspire/README.md`. The `Application:ServiceName` values are camelCase for TicketChecker (`ticketChecker`) and capitalized for PushNotification (`PushNotification`); ASP.NET Core routing is case-insensitive and clients use the lowercase forms shown above. Local dev runs the same services via .NET Aspire (`aspire/Etp.AppHost`) or Docker.

> 📦 **Explainer: microservices in this codebase (30 seconds)**
> A monolith is one process with one database. Here, each row in the table above is a **separate deployable ASP.NET Core app** with its own controllers, its own EF Core `DbContext` and its own background workers, all deployed as pods on Amazon EKS. They communicate only over HTTP and SQS messages (§0.8) — no shared in-process code at runtime beyond the copied `Core/` libraries compiled into each service. Nothing "routes" inside the code: the first path segment of a URL decides which service answers (next box).

### 0.5 Clients

| Client | Repository | Tech | Signs in with | Calls |
|---|---|---|---|---|
| Admin portal | `rvl-gobcb-admin-portal` | Angular 18 | Admin pool (after an SMS OTP from the Serverless API — F6.1) | Admin, Booking, Ticketing, UserIssue; Serverless API for OTP |
| User web portal | `rvl-gobcb-user-portal/ETP-Web` | Angular 19 | User pool, or OneID through Cognito (F6.8) | Event, Booking, Ticketing, Admin (public endpoints), UserIssue; identity API |
| User app | `rvl-gobcb-user-app` | Flutter | User pool, or OneID through Cognito (F6.8) | Event, Booking, Ticketing, UserIssue, PushNotification, Admin; identity API |
| Checker app | `rvl-gobcb-checker-app` | Flutter | TicketChecker pool | Admin (`ticket-checker-gate/event-info`), TicketChecker (`tickets/sync-tickets`); identity API for the app version |

The **identity API** (`services.identity` in the user portal, `AUTH_API_BASE_URL` in the apps) handles customer registration, OTPs, profile and app versions. Its source is in **none of the five repositories** `[UNCONFIRMED]` — see Open queries.

### 0.6 How a request reaches a service

```mermaid
flowchart LR
  C["Client<br/>portal or app"] -->|"HTTPS + Bearer token"| R53["Route 53"] --> APIGW["API Gateway"] --> NLB["Network Load Balancer"]
  NLB --> ING["nginx ingress<br/>class nginx-second<br/>routes by path prefix"]
  ING -->|"/admin/..."| ADM["Admin pod"]
  ING -->|"/booking/..."| BKG["Booking pod"]
  ING -->|"/event, /ticketing, /ticketchecker,<br/>/scheduler, /userissue, /pushnotification"| OTH["other pods"]
  C -.->|"WebSocket, token in query string"| CHAT["chat.gobcbticket.com.bd<br/>(separate public ingress)"] -.-> UI["UserIssue pod<br/>/userissue/chathub"]
```

The hosting part of this picture (API Gateway, NLB, ingress) comes from the architecture doc §1 and §4.1. Whether API Gateway also validates tokens is reported but unverified there (architecture Q1/Q1b). The services always validate the token themselves (F6.14).

> 📦 **Explainer: path-prefix routing**
> In a monolith every controller lives under one host. Here each service is a separate process, but clients still use **one API host**. The first path segment decides which service gets the request: `/booking/api/v1/user-booking-order` goes to Booking, `/event/api/v1/events/list` to Event.
>
> Two pieces make this work:
> 1. **In the code**, `Core/ETP.Core/Conventions/GlobalRoutePrefixConvention.cs` prepends `Application:ServiceName` to every controller route (registered in each `Program.cs`). So the Booking controller's `[Route("api/v1/user-booking-order")]` is really served at `/booking/api/v1/user-booking-order`, even when you call the service directly on its own port.
> 2. **In the cluster**, an nginx ingress per service forwards `/<prefix>/...` to that service unchanged (architecture doc §4.1).
>
> Consequence for you: when you call a service locally (`http://localhost:5102`), you must still include the prefix: `http://localhost:5102/booking/api/v1/...`. Swagger is at `/<prefix>/swagger` (e.g. `/booking/swagger`).

### 0.7 Request and response conventions

| Topic | What the code does | Source |
|---|---|---|
| JSON property names | camelCase in every service. Booking, Event, Ticketing, TicketChecker, Scheduler, Utility, PushNotification, Platform and UserAuth set `PropertyNamingPolicy = CamelCase` explicitly; Admin and UserIssue use the ASP.NET Core default, which is also camelCase | `Services/*/ETP.*.Service/Program.cs` (`AddJsonOptions`) |
| Enums | Strings (`JsonStringEnumConverter`) in the services that call `AddJsonOptions`; **numbers** in Admin and UserIssue, which do not register the converter | same |
| Nulls | Omitted from responses (`WhenWritingNull`) in the services that call `AddJsonOptions`; Admin and UserIssue include them | same |
| Errors | `ErrorResponseExceptionFilter` turns exceptions into a `ProblemDetails`-style body (below) | `Core/ETP.Core.Web/Filters/ErrorResponseExceptionFilter.cs` |
| Pagination | Paged endpoints return a `PagedList` object: `{ "items": [ … ], "totalCount": 123 }`. (A helper `PagedOkResult` — array body + `X-Total-Count` header — exists in Core but **no controller uses it**) | `Core/ETP.Core/Collections/PagedList.cs`, `Core/ETP.Core.Web/Results/PagedOkResult.cs` (dead code) |
| Ids | Most tables use a `long Id`. Many also carry a public string/Guid id (for example `Event.EventId`, order `PublicId`), and endpoints accept one or the other — which is why pairs such as `events/{eventId}` and `events/EventLongId/{id}` exist | `Services/Admin/ETP.Admin.Storage/Models/Event.cs` |
| Time | Server-side comparisons use `DateTime.UtcNow` | e.g. `UserBookingOrderManager.cs` |

**Error responses.** Controllers throw; the filter maps the exception type to a status code and a body:

| Exception | Status | Body |
|---|---|---|
| `ArgumentException` (and subclasses) | 400 | `{ "status": 400, "title": "<exception message>" }` |
| `ApiException` | 400 | the exception's own `Details` (`ProblemDetails`) |
| `UnauthorizedAccessException` | 403 | `{ "status": 403, "title": "Unauthorized access", "detail": "<message>" }` |
| anything else | 500 | `{ "status": 500, "title": "An unexpected error occurred." }` (the real message in Development) |

In the Development environment a `stackTrace` field is added. Authentication failures (no or invalid token) never reach the filter: the JWT handler answers **401** with an empty body; a valid token from the wrong pool or without the required role answers **403** (F6.14). Two quirks worth knowing: `ApiException` is always mapped to **400** even when it carries a different status inside, and `BadHttpRequestException` — used by some Admin managers for validation ("Name must not exceed 60 characters.") — falls into the default branch and becomes **500**. Typical business rejections (`seat_limit_exceeded`, `no_seats_available`, `Invalid promo code…`) are thrown as `ArgumentException` → **400**.

```json
{
  "status": 400,
  "title": "Invalid promo code. Please enter a valid code."
}
```

### 0.8 Core concepts (explainers)

> 📦 **Explainer: token forwarding (how one service calls another for a user)**
> When a customer's request reaches Booking and Booking needs data from Event, Booking calls Event over HTTP. In this codebase that call **carries the customer's own Cognito access token**, not a service identity.
> - Each service registers typed `HttpClient`s (for example `services.AddHttpClient<IEventClient, EventClient>` with a base URL from `Services:<Name>` in `Configurations/DependencyConfig.cs`).
> - The client pipeline includes `DelegatedBearerAuthenticationHandler` (`Core/ETP.Core.Web/Security/DelegatedBearerAuthenticationHandler.cs`). It reads the access token that the JWT handler stored as a claim on the current user (`OnTokenValidated` in `Core/ETP.Core/Configuration/DefaultAuthenticationConfig.cs`) and copies it to `Authorization: Bearer` on the outgoing request.
> - The downstream service validates that token again with its **own** policy. If Booking calls an Admin endpoint that requires the Admin pool while the caller is a customer, the downstream call fails with 401/403.
> - Retries: most clients retry 3 times with exponential backoff (Polly).
> - **No user, no token.** A background worker has no HTTP request, so the handler finds no token and sends none. That is why the endpoints workers call have no `[Authorize]` (F6.18).
>
> Hop tags: **[HTTP + user token]** and **[HTTP, no token]**. Full details: F6.19.

> 📦 **Explainer: queue-driven processing (SQS)**
> Some work is too slow or too important to do inside the user's request: signing a ticket with the TSP, merging hundreds of PDFs, recording VAT with NBR, sending push messages, recalculating capacity. The request **publishes a message** to an Amazon SQS queue and returns; a **worker** in some service reads the queue later and does the work.
> - Publishing: `Core/ETP.Core/Queue/Services/SqsPublisher.cs` resolves the queue URL from its **name** (configured as `AWS:Queue:<Key>`, values in SSM/user-secrets), serializes the message as JSON and sends it. If the queue name ends in `fifo`, it also sets `MessageGroupId` and `MessageDeduplicationId` from the message.
> - Consuming: a `BackgroundService` loops, calls `ReceiveMessageAsync`, processes, and **deletes the message only on success**. A failed message becomes visible again and is retried (the code comments mention a dead-letter queue; its configuration is not in the repos `[UNCONFIRMED]`).
> - Messages hold business ids only. There is no user token in a message and no sender check: anyone with IAM permission to send to the queue can enqueue work (architecture doc §2.3 C).
> - MassTransit (`Core/ETP.Core.EventBus`) is registered in several services but no consumer or publisher uses it (dead code).
>
> Queue catalog (config key → message → producer → consumer):
>
> | `AWS:Queue:` key | Message DTO | Published by | Consumed by | Purpose |
> |---|---|---|---|---|
> | `OrderSuccess` | `LevelCapacityUpdate` | Booking (`UserBookingOrderManager`, `CapacityManager`) | Booking `LevelCapacityUpdateService` | Apply booked/released seats to level capacity (F5.1) |
> | `EventCapacity` | `EventLiveCapacityUpdate` | Booking (`CapacityManager`) | Booking `EventLiveCapacityUpdateService` | Recompute event live capacity (F5.2) |
> | `TicketSigning` | `SignedTicketGeneration` | Ticketing (`TicketManager`) | Ticketing `TicketGenerationService` | Sign ticket PDFs via TSP (F5.8) |
> | `TicketProcessing` | `TicketProcessingRequest` (Merge/Zip) | Ticketing (`TicketManager`) | Utility `TicketProcessingService` | Merge/zip reserved tickets (F5.9) |
> | `VatChallanProcessing` | `VatChallanProcessing` | Booking (`UserBookingOrderManager`) | Booking `VatChallanProcessingService` | Record VAT with NBR (F5.10) |
> | `FirebaseNotification` | `FirebaseNotificationRequest` | PushNotification (`NotificationManager`) | Scheduler `FirebaseNotificationService` | Deliver push via FCM (F5.11) |
>
> The Event service also registers `AWS:Queue:FirebaseNotification` but never publishes or consumes it (dead config). Physical queue names are secret values, so whether any queue is FIFO cannot be seen from the repos `[UNCONFIRMED]`.

> 📦 **Explainer: background workers (timers inside services)**
> Besides answering HTTP requests, several services run **hosted services** (`BackgroundService`) on a timer, registered with `services.AddHostedService<...>()`. The pattern is the same everywhere (example: `Services/Admin/ETP.Admin.Service/Workers/BackgroundServices/CheckedTicketService.cs`):
> 1. wait about a minute after start-up;
> 2. loop forever: try to take a Redis lock, and if it is taken, create a DI scope and run a **TaskManager** (`Workers/TaskManagers/*`) that holds the real logic;
> 3. sleep for a **hard-coded** interval (30 seconds to 1 day), longer after an error.
>
> The intervals are constants in the code, not configuration. Every replica (pod) of a service runs the same workers, which is why the lock matters (next box). Hop tag: **[Worker: interval, lock]**. Part 5 documents each worker.

> 📦 **Explainer: distributed locks (RedLock)**
> In production each service can run as several pods. Without coordination, every pod's worker would process the same orders at the same time. The code uses **RedLock** (`RedLockNet`) on Redis: before a job runs, the worker asks for a named lock (for example `checked_ticket`, expiry 20 minutes). Only the pod that gets it does the work; the others skip the cycle and log `Could NOT acquire lock ... Skipping this cycle` (a normal message, also seen locally).
>
> The same mechanism protects business operations that must not overlap, for example one booking at a time per customer (`user_booking:{userId}` in `UserBookingOrderManager.cs`) and capacity changes per level.
>
> Set-up: `Core/ETP.Core/Configuration/DistributedLockConfig.cs` (keys `DistributedLock:Redis:*`). Lock names and expiries are listed in F6.25.

> 📦 **Explainer: one database, shared tables and read models**
> A textbook microservice owns a private database. This codebase does not work that way:
> - Every `DbContext` uses the **same schema `etp`** (`DefaultSchema = "etp"` in each `*DbContext.cs`), and each service has its own connection-string key (`ConnectionStrings:Admin`, `:Booking`, …). Ticketing even uses `ConnectionStrings:Booking`. Locally all keys point at one database (`scripts/user-secrets.example.json`).
> - A table is **owned** by the service whose migrations create it. Other services map the same table again in their own `DbContext` with `ExcludeFromMigrations`, and read it (sometimes write it) directly. Example: Booking maps `PromoCodes`, `Discounts`, `EventVenueDetails`, `Events` from Admin as excluded tables (`Services/Booking/ETP.Booking.Storage/DbContexts/BookingDbContext.cs`).
> - The **Event** service owns almost nothing: it is a public, read-only view over Admin's and Booking's tables (`Services/Event/ETP.Event.Storage/DbContexts/EventDbContext.cs`).
>
> What this means for you: a column change in Admin can break Booking, Ticketing or Event at run time even though they compile separately. Search all `*DbContext.cs` files for a table name before you change it. The handover brief said "one schema per service"; the code says one schema for all. The production layout is open `[UNCONFIRMED]` — see Open queries.
>
> Hop tag: **[Shared table]**.

> 📦 **Explainer: Redis as the live seat counter**
> Seat availability changes every second during a sale, so Booking keeps **live counters in Redis** (key families such as `level_live`, `level_locked`, `event_live`, `level_live_seats`; constants in `Core/ETP.Core/Constant/AppConstant.cs`) and treats the database as the slower, durable copy. Orders lock capacity in Redis first; queue workers (F5.1, F5.2) and timers (F5.3) bring the database and Redis back in line. The gate-scan counters of the checker app work the same way (F4.5, F5.14).
>
> Consequence: if Redis is flushed during a sale, live numbers are rebuilt from the database by the next worker cycle. Details: F6.25.

### 0.9 External systems

| System | Used for | Called from | Feature |
|---|---|---|---|
| DgePay | Online card/payment-gateway checkout | Booking | F2.6, F3.5, F5.5 |
| SSLCommerz | Second payment gateway (code present) | Booking | `[UNCONFIRMED]` whether live — Open queries |
| NBR OpenAPI | VAT challan (record VAT, download challan) | Booking worker | F5.10 |
| OneID Wallet | SSO login (federated through Cognito) and ticket sync to wallet | Cognito; Ticketing | F6.8, F2.10 |
| TSP gateway (mTLS) | Digital signing of ticket PDFs | Ticketing worker | F5.8 |
| Firebase (FCM) | Push notifications | Scheduler worker | F5.11 |
| SES | Email (ticket zips) | Ticketing | F6.21 |
| "Serverless" API | Cognito user lookup, admin login 2FA OTP | several services + admin portal | F6.1, F6.22 — source not in repos `[UNCONFIRMED]` |
| "Notification" API | SMS sending (ticket-generated notice) | Scheduler | F5.12, F6.22 — source not in repos `[UNCONFIRMED]` |
| identity API | Registration, OTP, profile, app version | portals + apps | F6.6 etc. — source not in repos `[UNCONFIRMED]` |

### 0.10 Feature index

- **Part 1 — Admin Portal:** F1.1 program selection · F1.2 programs · F1.3 program settings · F1.4 teams · F1.5 venues and stadium layout · F1.6 program–venue mapping · F1.7 events · F1.8 event settings override · F1.9 event venue details and per-level pricing · F1.10 event capacity adjustment · F1.11 seat reservation · F1.12 reserved ticket generation and distribution · F1.13 ticket layouts and attributes · F1.14 ticket-pricing content page · F1.15 promo codes · F1.16 system discounts · F1.17 ticket-checker accounts · F1.18 gate assignment and download control · F1.19 gate reports · F1.20 raffle draw · F1.21 dashboard · F1.22 booking/sales/revenue reports · F1.23 reconciliation lookup · F1.24 user issues and support chat (admin) · F1.25 admin users · F1.26 agent users · F1.27 activity log viewer · F1.28 media configuration · F1.29 content editor · F1.30 header/footer and social media · F1.31 general notices
- **Part 2 — User Web Portal:** F2.1 home page content · F2.2 browse events · F2.3 information pages · F2.4 seat selection · F2.5 apply promo code · F2.6 booking order and online payment (DgePay) · F2.7 my bookings and generation status · F2.8 ticket generation request · F2.9 ticket details, holder info, download, share, invoice · F2.10 sync tickets to OneID · F2.11 profile · F2.12 report an issue and chat · F2.13 language switch
- **Part 3 — User App:** F3.1 splash, version gate and onboarding · F3.2 home and browse events · F3.3 information pages · F3.4 seat selection and promo code · F3.5 booking and WebView payment · F3.6 my bookings and tickets · F3.7 profile and settings · F3.8 report an issue and support chat · F3.9 push device-token registration · F3.10 receiving push notifications
- **Part 4 — Checker App:** F4.1 assigned event and gate · F4.2 ticket download for offline checking · F4.3 QR scan validation · F4.4 manual entry · F4.5 scan sync · F4.6 signature-only ticket validation
- **Part 5 — System-initiated:** F5.1 level capacity update · F5.2 event live capacity · F5.3 locked-capacity refresh · F5.4 scheduler capacity reconcile · F5.5 pending/failed payment revalidation · F5.6 booking status → Generated · F5.7 initiate user ticket generation · F5.8 ticket signing via TSP · F5.9 reserved ticket merge/zip · F5.10 VAT challan with NBR · F5.11 push delivery to FCM · F5.12 ticket-generated notification · F5.13 device-token cleanup · F5.14 checked-ticket sync · F5.15 gate download-status cleanup · F5.16 promo-code status update · F5.17 system-discount status update
- **Part 6 — Cross-cutting:** F6.1 admin login · F6.2 admin forgot password · F6.3 admin change password and logout · F6.4 admin session handling · F6.5 staff account provisioning · F6.6 customer registration · F6.7 customer login (phone + password) · F6.8 OneID SSO · F6.9 customer forgot/reset password · F6.10 customer session handling · F6.11 delete account and app force-update · F6.12 checker login · F6.13 agent pool and offline-sold tickets · F6.14 authorization layer 1 (pool policies) · F6.15 authorization layers 2–3 (roles) · F6.16 authorization layer 4 (program scope) · F6.17 client-side authorization · F6.18 endpoints without authorization · F6.19 service-to-service communication · F6.20 file storage (S3, CloudFront) · F6.21 email (SES) · F6.22 SMS and the external notification service · F6.23 push notifications · F6.24 activity logging · F6.25 Redis · F6.26 configuration and secrets

---

## 1. Admin Portal

Features started by BCB/BS23 staff in the Angular admin portal (`rvl-gobcb-admin-portal`), Admin Cognito pool. Sign-in itself is a cross-cutting feature (F6.1–F6.5); this part starts after login.

### F1.1 Program selection and the program-scoped menu

> **Bangla name:** প্রোগ্রাম নির্বাচন ও প্রোগ্রাম-ভিত্তিক মেনু

**1. Name and purpose.** After signing in, staff pick the **program** (a series or tournament) they will work on. The portal then adds an `X-Program-Id` header to every API call and shows the program menu; picking "global" mode (program id 0) shows a limited, program-independent menu.

**2. Trigger and actor.** Admin portal, top bar / program switcher, immediately after login and any time later. Actor: any staff role (`admin`, `event_manager`, `ticket_manager`, `ticket_operator`, `customer_support`) from the Admin pool.

**3. Business flow.**
1. After login the staff member lands on a program selection (or the program-management screen, depending on role).
2. Choosing a program stores it in the browser (`localStorage.globalProgramId`) and reloads the menu.
3. Most menu items (events, dashboard, issues, reports) now show data for that program only, because every request carries `X-Program-Id`.
4. Choosing global mode (program id 0) unlocks the limited menu (programs, venues, users, media).

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal `ProgramService` (BehaviorSubject + `localStorage.globalProgramId`) | — | Selection state kept client-side; guards `ProgramMenuGuard` (programId > 0) and `LimitedMenuGuard` (programId == 0) decide which routes are reachable |
| 2 | Portal → every admin API call | — | `program-id.interceptor.ts` adds the `X-Program-Id` header from `ProgramService` |
| 3 | Admin service | — | `ProgramIdMiddleware` copies the header into `HttpContext.Items["ProgramId"]`; `IProgramIdAccessor` exposes it to `AdminDbContext`, which applies a **global EF query filter** on every entity implementing `IHasProgramId` when ProgramId > 0 — the data scoping is done in SQL, not per endpoint |
| 4 | Admin service | — | On routes marked `[AuthorizeProgram]`, `AuthorizeProgramAttribute` also checks the header against the user's `program_id` claims (from Cognito `custom:program_ids`): 400 if the header is missing/invalid, 403 if the program is not allowed. Roles `admin` and `user` bypass |

**5. Components.** Admin portal (`ProgramService`, interceptors, guards); Admin service (middleware + EF filter + attribute); Cognito attribute `custom:program_ids`.

**6. API contracts.** The feature uses the programs list (F1.2 `GET /admin/api/v1/program`). Any admin endpoint documented in this part should be read as *"plus `X-Program-Id` header"* — the portal sends it on every request. Program scoping on the backend applies only where the code uses it (the EF filter and `[AuthorizeProgram]`; Booking/Ticketing take an explicit `programId` query parameter instead).

**7. Data and side effects.** None server-side; browser state only.

**8. Code references.**

| What | Where |
|---|---|
| Program state | `rvl-gobcb-admin-portal/src/app/core/services/program.service.ts` |
| Header interceptor | `rvl-gobcb-admin-portal/src/app/interceptors/program-id.interceptor.ts` |
| Menu guards | `rvl-gobcb-admin-portal/src/app/core/guard/program-menu.guard.ts`, `limited-menu.guard.ts` |
| Backend middleware | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Middleware/ProgramIdMiddleware.cs` |
| Program attribute | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Attributes/AuthorizeProgramAttribute.cs` |
| EF filter + accessor | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Storage/Repositories/ProgramIdAccessor.cs`, `AdminDbContext.cs` |

**9. Handover notes.** ① The `admin` role bypasses the program check and sees every program; other roles must be provisioned with `custom:program_ids` (F6.5). ② `[AuthorizeProgram]` is currently active on the dashboard controller; on `EventsController` it is present but **commented out** — events are today scoped only by the query parameters, not enforced per program. ③ Only the Admin service understands the header; other services ignore it.

### F1.2 Programs

> **Bangla name:** প্রোগ্রাম (সিরিজ/টুর্নামেন্ট) ব্যবস্থাপনা

**1. Name and purpose.** Create, edit and delete **programs** — the series or tournament (for example a tour or a league) that groups events and carries its own logo and dates.

**2. Trigger and actor.** Admin portal → `/program-management/program-create`, `/program-management/edit/:id`, `/settings/programs`. Roles: `admin`, `event_manager` (controller: `[Authorize(Roles = admin, event_manager, …)]`).

**3. Business flow.**
1. Staff open Program Management → Create Program.
2. They fill name, short name, start/end dates and upload a logo image.
3. Save creates the program; it now appears in the program switcher (F1.1) and can host teams, venues and events.
4. Edit updates the same fields; delete removes the program (the UI warns about running events via the venues screen's `has-running-events` check for venues; program-level guards are not visible in the code — see notes).

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal `programs.service.ts` → Admin `POST /admin/api/v1/program` | **[HTTP + user token]** | multipart form (logo file) |
| 2 | Admin `ProgramController` → `ProgramManager` | — | Saves program row; uploads logo via `AwsSimpleStorageMediaManager` to the media bucket (`AWS:Bucket:Name`), stores the CloudFront URL |
| 3 | Admin DB | **[Shared table]** | `Programs` table (schema `etp`); Event service and Booking read the same table through their own `DbContext` mirrors |
| 4 | Public side | **[Shared table]** | User portal/app list programs via Event service `GET /event/api/v1/events/programs` (F2.2) |

**5. Components.** Admin portal; Admin service; S3 media bucket + CloudFront; tables `Programs` (owner Admin).

**6. API contracts.** Base: `/admin/api/v1/program`. Auth: Admin pool; roles `admin`, `event_manager`.

| Method | Path | Request | Response |
|---|---|---|---|
| GET | `/admin/api/v1/program` | — | list of programs |
| GET | `/admin/api/v1/program/{id}` | — | one program |
| POST | `/admin/api/v1/program` | multipart `CreateOrUpdateProgram` | created program |
| PUT | `/admin/api/v1/program/{id}` | multipart `CreateOrUpdateProgram` | updated program |
| DELETE | `/admin/api/v1/program/{id}` | — | deleted program |

`CreateOrUpdateProgram` (`Services/Admin/ETP.Admin.Domain/Models/Settings/CreateOrUpdateProgram.cs`):

```json
// POST /admin/api/v1/program  (multipart/form-data; "Logo" is a file part)
{
  "Name": "Bangladesh Tour of Sri Lanka 2026",
  "ShortName": "BAN in SL 2026",
  "StartDateTime": "2026-07-01T00:00:00Z",
  "EndDateTime": "2026-07-28T00:00:00Z"
}
```

Main errors: standard envelope (§0.7) — 400 invalid dates/duplicate names as thrown by the manager.

**7. Data and side effects.** Table `Programs` insert/update/delete; one file written to the media bucket (logo); Redis-cached public lists (Event service) serve the stale logo/name until their TTL expires or cache keys are cleared.

**8. Code references.**

| What | Where |
|---|---|
| Portal service | `rvl-gobcb-admin-portal/src/app/features/program-settings/services/programs.service.ts` (also `program-management.service.ts`) |
| Controller | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/ProgramController.cs` |
| Manager | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Domain/Managers/ProgramManager.cs` |
| Media upload | `rvl-gobcb-backend/Core/ETP.Core.BlobStorage/AWSS3/AwsSimpleStorageMediaManager.cs` |

**9. Handover notes.** ① Deletion guards (e.g. "program has events") are not visible in the extracted code — verify before relying on delete in production. ② The same create form is reachable from two menus (`/settings/programs` and `/program-management`), backed by two near-duplicate Angular services.

### F1.3 Program settings

> **Bangla name:** প্রোগ্রাম সেটিংস

**1. Name and purpose.** The per-program commercial rules: payment gateway choice, purchase limits, selling/availability windows (hours relative to the event), VAT and service charge, and the ticket-number prefix.

**2. Trigger and actor.** Admin portal → `/program-management/configuration` (program settings update screen). Roles: `admin`, `event_manager` (`ProgramSettingsController`).

**3. Business flow.**
1. Staff open the settings of the selected program.
2. They set how many orders per user and seats per order are allowed, the ticket-selling window in hours, VAT (percent or fixed, inclusive or not), service charge, the "limited availability" threshold and the ticket-number prefix.
3. They choose the **payment gateway** for the program (DgePay or SSLCommerz).
4. Save stores the rules; every event of the program inherits them unless an event overrides them (F1.8).

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/program-settings/{programId}` | **[HTTP + user token]** | Current settings |
| 2 | Portal → Admin `PUT /admin/api/v1/program-settings` | **[HTTP + user token]** | JSON `ProgramSettings` |
| 3 | Admin DB + cache | — | `ProgramSettings` row (one per program); Redis key family `program_settings_details` caches reads used by other flows |

**5. Components.** Admin portal (`program-settings.service.ts`); Admin service; table `ProgramSettings`.

**6. API contracts.**

```json
// PUT /admin/api/v1/program-settings   (ProgramSettings, Services/Admin/ETP.Admin.Domain/Models/Settings/ProgramSettings.cs)
{
  "id": 19,
  "programId": 7,
  "limitedAvailabilityThreshold": 10.0,
  "allowableMaximumOrderPerUser": 2,
  "allowableMaximumSeatPerOrder": 4,
  "ticketSellingStartFromHour": 240,       // hours before the event
  "ticketSellingStopFromHour": 2,
  "ticketAvailableFromHour": 180,
  "ticketNumberPrefix": "BCB-ODI2-",
  "vat": 15.0,
  "isVatPercentage": true,
  "serviceCharge": 20.0,
  "isServiceChargePercentage": false,
  "isVatInclusive": false,
  "paymentGateway": 1                      // enum: DgePay = 1, SSLCommerz = 2
}
```

`GET program-settings/{programId}` returns the same shape. Errors: standard envelope.

**7. Data and side effects.** `ProgramSettings` upsert; Redis cache invalidation/refresh for the program settings key.

**8. Code references.**

| What | Where |
|---|---|
| Portal service | `rvl-gobcb-admin-portal/src/app/features/program-management/services/program-settings.service.ts` |
| Controller | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/ProgramSettingsController.cs` |

**9. Handover notes.** ① The `PaymentGateway` field means the active gateway is **per program** — this partially answers "DgePay vs SSLCommerz": both are selectable; which programs use which in production is data, not code `[UNCONFIRMED]`. ② `LimitedAvailabilityThreshold` drives the "limited seats left" badge logic; its exact consumer is Booking's capacity checks.

### F1.4 Teams

> **Bangla name:** টিম ব্যবস্থাপনা

**1. Name and purpose.** Maintain the teams (with logo and flag) that play in a program's events; used on event segments and public pages.

**2. Trigger and actor.** Admin portal → `/settings/program-teams`, `/program-management` team screens. Roles: `admin`, `event_manager` (`TeamsController`).

**3. Business flow.** Staff create a team under a program (name, short name, logo, flag), edit, toggle active, delete; event segments (F1.7) then reference the teams.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/teams` | **[HTTP + user token]** | multipart `CreateOrUpdateProgramTeam` |
| 2 | Admin manager | — | `ProgramTeams` row; logo/flag uploaded to the media bucket |
| 3 | Public side | **[Shared table]** | Event service includes team names in event segment responses (F2.2) |

**5. Components.** Admin portal; Admin service; S3 media bucket; table `ProgramTeams`.

**6. API contracts.** Base `/admin/api/v1/teams`: `GET program/{programId}`, `GET {id}`, `GET ` (paged), `GET list`, `POST` (multipart), `PUT {id}`, `DELETE {id}`, `PUT toggle-status/{id}`. `CreateOrUpdateProgramTeam` (`Models/Events/CreateOrUpdateProgramTeam.cs`): `Id, ProgramId, Name, ShortName, Logo (file, optional), IsFlag (bool?), IsActive, Flag (file, optional)`. Errors: standard envelope.

**7. Data and side effects.** `ProgramTeams` upsert/delete; files to the media bucket.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/program-management/services/teams-management.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/TeamsController.cs`.

**9. Handover notes.** `toggle-status` is a soft enable/disable used instead of delete for teams referenced by past events.

### F1.5 Venues and stadium/exhibition layout

> **Bangla name:** ভেন্যু ও স্টেডিয়াম/প্রদর্শনী লেআউট

**1. Name and purpose.** Define a venue (stadium or exhibition hall) with its SVG seat map and the hierarchy **gallery → block → level**, each with seat-mapping flags, sellability, ticket color and entry/mini gates. Everything downstream (pricing, capacity, checkers) hangs off this tree.

**2. Trigger and actor.** Admin portal → `/venue-management`, `/venue-management/create-venue`, `/venue-management/update-venue/:venueId`, `/venue-management/stadium-layout/:venueId` (stadium) or `/venue-management/exhibition-layout/:venueId` (exhibition), `/venue-management/gallery-details/:venueId`. Roles: `admin`, `event_manager` (`VenuesController`).

**3. Business flow.**
1. Staff create the venue: type (Stadium/ExhibitionHall), short and full name, location, the SVG map image and the SVG keys (regions in the map that become clickable galleries/blocks/levels).
2. In the layout editor they build galleries, blocks and levels; a level carries `SeatingCapacity`, optional literal seat list (`HasSeats`), sellability and a ticket color.
3. They attach **entry gates** and **mini gates** to block-levels.
4. `has-running-events/{venueId}` guards edits while an event is running.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/venues` | **[HTTP + user token]** | multipart `CreateOrUpdateVenue` (SVG map file + svg keys) |
| 2 | Portal → Admin `POST /admin/api/v1/venues/venueLayout` | **[HTTP + user token]** | JSON `CreateOrUpdateVenueLayout` — the whole gallery/block/level tree in one call |
| 3 | Portal → Admin `POST /admin/api/v1/venues/entry-gate` / `mini-gate` | **[HTTP + user token]** | Gate lists per block-level |
| 4 | Admin DB | **[Shared table]** | Tables `Venues`, `VenueGalleries`, `GalleryBlocks`, `BlockLevels`, `BlockLevelEntryGates`, `BlockLevelMiniGates`, `GalleryBlockEntryGates`; Event/Booking/TicketChecker read them via mirrors |

**5. Components.** Admin portal; Admin service; S3 media bucket (SVG maps); venue tables (owner Admin).

**6. API contracts.** Selected endpoints (`VenuesController`, base `/admin/api/v1/venues`):

```json
// POST /admin/api/v1/venues   (multipart CreateOrUpdateVenue)
{ "type": 1, "shortName": "SBNCS", "name": "Sher-e-Bangla National Cricket Stadium", "location": "Mirpur, Dhaka" }
// parts: SvgMapImageFile (file), SvgKeys (list of strings)

// POST /admin/api/v1/venues/venueLayout   (CreateOrUpdateVenueLayout)
{
  "venueId": 2,
  "venueGalleries": [
    {
      "id": 12, "name": "Grandstand", "seatType": "Seat", "isSeatMapped": true, "isSellable": true,
      "isActive": true, "svgKey": "grandstand-n", "ticketColor": "#1E7B4F",
      "galleryBlocks": [
        {
          "id": 7, "name": "Block B", "isSeatMapped": true, "isSellable": true, "isActive": true, "svgKey": "gs-n-b",
          "blockLevels": [
            { "id": 45, "name": "Level 1", "seatingCapacity": 1200, "hasSeats": true, "seats": "A1..A600,B1..B600",
              "isSeatMapped": true, "isSellable": true, "isActive": true, "svgKey": "gs-n-b-l1" }
          ]
        }
      ]
    }
  ]
}
```

Also: `GET {programId}`, `GET venue?venueId=`, `GET gallery` / `galleryBlocks` / `blockLevel`, `PUT venue/{venueId}`, `POST|PUT venueGallery|galleryBlocks|blockLevel`, `GET entry-gate|mini-gate`, `POST mini-gate`, `GET has-running-events/{venueId}`. Response entity shapes: `Venue` (`Models/Events/Venue.cs`) with nested `VenueGallery`/`GalleryBlock`/`BlockLevel` as in the layout sample above. Errors: standard envelope.

**7. Data and side effects.** Venue-tree tables written; SVG map uploaded; downstream caches (`event_venue_details` key family) go stale until refreshed.

**8. Code references.**

| What | Where |
|---|---|
| Portal service + pages | `rvl-gobcb-admin-portal/src/app/features/venue-management/services/venue-management.service.ts`, `pages/…` |
| Controller | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/VenuesController.cs` |

**9. Handover notes.** ① The layout editor sends the **entire tree** in one `venueLayout` call — a mistake in the editor overwrites siblings; the UI's unsaved-changes guard (`unsave-changes-guard`) is the main protection. ② `VenueType` enum: `Stadium = 1`, `ExhibitionHall = 2`; the portal shows a different layout editor per type (stadium vs exhibition). ③ A `BlockLevel` property is named `BlockLevelEntrieGates` (typo, kept for compatibility).

### F1.6 Program–venue mapping and venue details sync

> **Bangla name:** প্রোগ্রাম-ভেন্যু ম্যাপিং ও ভেন্যু ডিটেইলস সিঙ্ক

**1. Name and purpose.** Attach venues to a program and materialize the per-program **venue details**: for every gallery/block/level, program-level overrides (active/sellable flags, seating capacity, price per seat, seats). Events then copy from this (F1.9).

**2. Trigger and actor.** Admin portal → `/program-management/programVenueDetails`, `/settings/program-venues`. Roles: `admin`, `event_manager` (`ProgramVenueController`, `ProgramVenueDetailsController`).

**3. Business flow.**
1. Staff map a venue to the program (`ProgramVenue`).
2. "Generate" creates `ProgramVenueDetails` rows for every level of that venue (copy of the venue tree with editable price/capacity).
3. Staff edit per-level price, capacity, sellability; "Sync" re-pulls structure changes from the venue layout (the screen shows a **needs-sync** flag when the venue layout has changed).
4. Events created for the program start from these prices (F1.9).

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/programVenue` | **[HTTP + user token]** | `CreateOrUpdateProgramVenue { id, programId, venueId }` |
| 2 | Portal → Admin `POST /admin/api/v1/programVenueDetails/{programId}` | **[HTTP + user token]** | Generate details rows from the venue tree |
| 3 | Portal → Admin `POST /admin/api/v1/programVenueDetails/{programId}/{venueId}` | **[HTTP + user token]** | Sync structural changes |
| 4 | Portal → Admin `PUT /admin/api/v1/programVenueDetails/update/{id}` | **[HTTP + user token]** | Per-level `CreateOrUpdateProgramVenueDetails` |
| 5 | Admin DB | **[Shared table]** | Tables `ProgramVenues`, `ProgramVenueDetails` (owner Admin); Event service reads them |

**5. Components.** Admin portal; Admin service; tables `ProgramVenues`, `ProgramVenueDetails`.

**6. API contracts.**

```json
// PUT /admin/api/v1/programVenueDetails/update/{id}   (CreateOrUpdateProgramVenueDetails)
{
  "id": 918,
  "isGalleryActive": true, "isSeatMappedInGallery": true, "isGallerySellable": true,
  "isBlockActive": true,   "isSeatMappedInBlock": true,   "isBlockSellable": true,
  "isLevelActive": true,   "isSeatMappedInLevel": true,   "isLevelSellable": true,
  "seatingCapacity": 1200,
  "pricePerSeat": 500.0,
  "hasSeats": true,
  "seats": "A1..A600,B1..B600"
}
// GET /admin/api/v1/programVenueDetails/sync-status/{programId}/{venueId}
{ "needsSync": false }
```

Also `GET {programId}/{venueId}`, `GET venue-galleries/{programId}/{venueId}`, `GET venue-details/{programId}`, `GET programVenue/{programId}`. Errors: standard envelope.

**7. Data and side effects.** Program-venue tables written; no queues/emails.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/program-management/services/{program-venues-details,program-management}.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/{ProgramVenueController,ProgramVenueDetailsController}.cs`.

**9. Handover notes.** `needsSync` compares the venue layout's updated timestamp with the last sync — editing a venue layout (F1.5) makes every mapped program "need sync" until an admin syncs.

### F1.7 Events (matches)

> **Bangla name:** ইভেন্ট (ম্যাচ) ব্যবস্থাপনা

**1. Name and purpose.** Create, edit, segment, publish/unpublish, duplicate and enable/disable **events** — the matches customers buy tickets for, each belonging to a program and a venue with a cover image and one or more segments (innings/days/teams).

**2. Trigger and actor.** Admin portal → `/events`, `/events/create`, `/events/edit/:id`, `/events/event-details/:id`. Roles: `admin`, `event_manager`, `ticket_manager`, `ticket_operator` (class-level `[Authorize]` on `EventsController`).

**3. Business flow.**
1. Staff open Events (the list is filtered by the selected program, F1.1) and click Create.
2. They choose program, venue, name, start/end date-time, upload a cover image, and add **segments** (each with name, type, start/end, the two teams and a banner image).
3. Save creates the event in draft. On the details screen staff adjust settings (F1.8) and venue pricing (F1.9).
4. **Publish** makes the event visible on the public portal/app; **Unpublish** hides it; **toggle status** enables/disables it; **Duplicate** clones the event for the next match.
5. The activity log (F1.27) records the changes.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal `event.service.ts` → Admin `POST /admin/api/v1/events` | **[HTTP + user token]** | multipart `CreateEvent` (cover image + per-segment banner files) |
| 2 | Admin `EventsController` → `EventManager` | — | Creates `Events` + `EventSegments` rows; uploads images to the media bucket (CloudFront URLs stored on the rows) |
| 3 | Admin DB | **[Shared table]** | Tables `Events`, `EventSegments` (owner Admin); Event/Booking/Ticketing/TicketChecker services read them through mirrors |
| 4 | `PUT publish/{id}` | **[HTTP + user token]** | Sets `IsPublished`; the public Event service serves published events only (`published/list`) |
| 5 | `POST duplicate/{id}` | **[HTTP + user token]** | Copies the event row + segments into a new draft |
| 6 | Portal list | **[HTTP + user token]** | `GET /admin/api/v1/events` (paged, search/sort) or `GET program/{programId}/events` |

**5. Components.** Admin portal; Admin service; S3 media bucket + CloudFront; tables `Events`, `EventSegments`, `EventSettings`; Cognito Admin pool; program scope via `X-Program-Id` (list filtering).

**6. API contracts.** Base: `/admin/api/v1/events`. Auth: Admin pool; roles as in §2. Sample for the main endpoint:

`POST /admin/api/v1/events` — multipart `CreateEvent` (`Services/Admin/ETP.Admin.Domain/Models/Events/CreateEvent.cs`):

| Part | Type | Notes |
|---|---|---|
| `ProgramId` | long | owning program |
| `VenueId` | int | venue of the match |
| `Name` | string | |
| `StartDateTime` / `EndDateTime` | date-time | End nullable |
| `EventCoverImageFile` | file | cover image |
| `Segments[i].Name/SegmentType/StartDateTime/EndDateTime/Team1Id/Team2Id` | mixed | teams are optional |
| `Segments[i].BannerImageFile` | file | per-segment banner |

Success 200/201 — `Event` response (`Domain/Models/Events/Event.cs`):

```json
{
  "id": 1042,
  "eventId": "b8e6a9d2-3f1c-4e7a-9d5f-6c2b1a8e0d34",
  "programId": 7,
  "venueId": 2,
  "name": "2nd ODI — Bangladesh vs Sri Lanka",
  "startDateTime": "2026-07-08T14:00:00Z",
  "endDateTime": null,
  "ticketSellingStartDateTime": "2026-06-20T10:00:00Z",
  "ticketSellingStopDateTime": "2026-07-08T12:00:00Z",
  "ticketAvailabilityStartDateTime": "2026-06-25T10:00:00Z",
  "eventCoverImage": "https://<cloudfront>/<key>.jpg",
  "minimumPrice": 500.0,
  "isPublished": false,
  "isActive": true,
  "vat": 15.0,
  "isVatParcentage": true,
  "isVatInclusive": false,
  "venue": { "…": "see F1.5" },
  "program": { "…": "see F1.2" },
  "eventSettings": { "…": "see F1.8" },
  "segments": [
    { "name": "Match day", "segmentType": 1, "startDateTime": "2026-07-08T14:00:00Z", "endDateTime": "2026-07-08T22:00:00Z", "team1Id": 3, "team2Id": 5 }
  ]
}
```

Other endpoints: `PUT {id}` (multipart `UpdateEvent`), `DELETE {id}`, `PUT publish/{id}`, `PUT unpublish/{id}`, `PUT toggle-status/{id}`, `POST duplicate/{id}`, `GET ` (paged: `search,sortBy,sortOrder,pageOffset,pageSize`), `GET search?search=`, `GET list`, `GET published/list`, `GET {startDatetime}/{endDateTime}/{eventId?}`, `GET filtered-list/{status}/{count}`, `GET {id}` (long id), `GET by-public-id/{eventId}` (Guid), `GET program/{programId}/events`, `GET programs/{programId}/events/no-end-date-check`. Errors: standard envelope (§0.7); 401/403 per §0.7 auth rules.

**7. Data and side effects.** Tables `Events`, `EventSegments` (+ `EventSettings` via F1.8); images written to the media bucket; publishing flips `IsPublished` which the public Event service exposes through its Redis-cached lists (cache TTL means a short delay before the portal sees the change).

**8. Code references.**

| What | Where |
|---|---|
| Portal service | `rvl-gobcb-admin-portal/src/app/features/events/services/event.service.ts` |
| List/create/edit pages | `rvl-gobcb-admin-portal/src/app/features/events/pages/event-list/event-list.component.ts`, `event-create/event-create.component.ts` |
| Controller | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/EventsController.cs` |
| Manager | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Domain/Managers/EventManager.cs` |
| Public mirror | `rvl-gobcb-backend/Services/Event/ETP.Event.Service/Api/EventsController.cs` |

**9. Handover notes.** ① `[AuthorizeProgram]` is commented out on this controller — program scoping of the event list relies on the explicit `programId` parameters, not the attribute. ② `minimumPrice`, selling windows and VAT fields are maintained through settings flows (F1.3/F1.8/F1.9), not the create form. ③ Admin also exposes `GET /admin/api/v1/events/search` used by other admin screens (reports) — same controller.

### F1.8 Event settings override

> **Bangla name:** ইভেন্ট সেটিংস (ওভাররাইড)

**1. Name and purpose.** Override the program settings (F1.3) for a single event: selling windows, purchase limits, VAT/service charge, ticket prefix, payment gateway.

**2. Trigger and actor.** Admin portal → event details → Settings tab (`/events/event-details/:id`). Roles: same as F1.7. **Note:** `EventSettingsController` carries **no `[Authorize]` attribute** (see F6.18).

**3. Business flow.** Staff open the event's Settings tab, change any inherited rule (for example extend selling hours for a playoff), save; the event's own row wins over the program's from then on.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/event-settings/{eventId}` | **[HTTP + user token]** | Effective settings for the event |
| 2 | Portal → Admin `PUT /admin/api/v1/event-settings/{eventId}` | **[HTTP + user token]** | JSON `EventSettings` |
| 3 | Admin DB + cache | — | `EventSettings` row; Redis key family `event_settings_details` |

**5. Components.** Admin portal (`event-settings.service.ts`); Admin service; table `EventSettings`.

**6. API contracts.** `EventSettings` has the same field set as `ProgramSettings` (F1.3 sample) with `EventId` in place of `ProgramId`. Errors: standard envelope.

**7. Data and side effects.** `EventSettings` upsert; Ticketing reads the prefix when generating ticket numbers (F5.8: `{eventSettings.TicketNumberPrefix}{unique code}`).

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/events/services/event-settings.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/EventSettingsController.cs`.

**9. Handover notes.** The missing `[Authorize]` on this controller means network placement is the only guard — listed in F6.18.

### F1.9 Event venue details and per-level pricing

> **Bangla name:** ইভেন্ট ভেন্যু ডিটেইলস ও লেভেল-ভিত্তিক দাম

**1. Name and purpose.** See one event's venue tree and set the **price per seat** for a level; this is where the event's price map (and the public `MinimumPrice`) is decided.

**2. Trigger and actor.** Admin portal → event details / venue details screens. Roles: `admin`, `event_manager`, `ticket_manager`, `ticket_operator` (`EventsVenueDetailsController`).

**3. Business flow.**
1. Staff open the event's venue details: galleries → blocks → levels with capacities and gates.
2. They set a price for a level (one simple call per level).
3. The public event model recomputes `MinimumPrice` (F2.2) and the user seat map shows the new price.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/eventsVenueDetails/venue-details/{eventId}` | **[HTTP + user token]** | `EventVenueDetailsTree` |
| 2 | Portal → Admin `PUT /admin/api/v1/eventsVenueDetails/{eventId}/{levelId}/{price}` | **[HTTP + user token]** | Sets the level price |
| 3 | Admin DB | **[Shared table]** | `EventVenueDetails` (owner Admin) — the same table the Event service serves publicly (F2.4) |

**5. Components.** Admin portal (`event.service.ts`); Admin service; table `EventVenueDetails`.

**6. API contracts.** Also: `GET {eventId}?isForTicket=`, `GET get-level/{eventId}/{levelId}` → `UserLevelWithGates` (sample in F2.4), `POST galleries/by-event-ids` (body `List<long>`, returns the galleries of several events). Errors: standard envelope.

**7. Data and side effects.** `EventVenueDetails` price update; public venue-details cache (`event_venue_details`, TTL up to 15 days) delays visibility — see notes.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/events/services/event.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/EventsVenueDetailsController.cs`.

**9. Handover notes.** Because the public seat map is Redis-cached for a long TTL, price changes can take a while to appear on the portal — if you need an instant change, clear the cache keys (`event_venue_details*`) or confirm with BS23 how they handle it `[UNCONFIRMED]`.

### F1.10 Event capacity adjustment

> **Bangla name:** ইভেন্ট ক্যাপাসিটি সমন্বয়

**1. Name and purpose.** Increase or decrease the sellable capacity of a level for an event (allocate/deallocate), outside normal sales — e.g. open an extra block after tickets sell out.

**2. Trigger and actor.** Admin portal → event ticket console (`/events/event-ticket`). Roles: admin-pool endpoints in the **Booking** service (`EventCapacityAdjustmentController` carries no explicit roles — F6.18).

**3. Business flow.**
1. Staff open the event's capacity screen, pick a level and an action (Allocate/Deallocate) with a seat count.
2. Save records the adjustment and updates the level capacity.
3. A queue message recomputes the event's live capacity (F5.2) so the public counters follow.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Booking `POST /booking/api/v1/event-capacity-adjustment` | **[HTTP + user token]** | `EventCapacityAdjustment` (below) |
| 2 | Booking `CapacityManager` | — | Writes `EventCapacityAdjustments` row, updates `Capacities`; publishes **[SQS: OrderSuccess]** `LevelCapacityUpdate` and **[SQS: EventCapacity]** `EventLiveCapacityUpdate` |
| 3 | Workers | **[Worker]** | F5.1 updates DB+Redis level capacity; F5.2 the event live counter |

**5. Components.** Admin portal; Booking service; SQS `OrderSuccess` + `EventCapacity`; Redis `capacity` hash; tables `EventCapacityAdjustments`, `Capacities`.

**6. API contracts.**

```json
// POST /booking/api/v1/event-capacity-adjustment   (EventCapacityAdjustment)
{
  "id": 55, "eventId": 1042, "galleryId": 12, "blockId": 7, "levelId": 45,
  "ticketingCapacity": 100, "hasSeats": false, "seats": null, "availableSeats": null,
  "action": "Allocate",                 // enum string (Booking serializes enums as strings, §0.7)
  "adjustmentNumber": "ADJ-000123"
}
```

Also `GET by-event-level?eventId&levelId&action&programId`, `GET by-event?eventId`, `GET count/{eventId}?action=`. Errors: `no_seats_available` → 400 envelope (§0.7).

**7. Data and side effects.** Adjustment row + capacity update; two SQS messages; Redis counters refreshed by the workers.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/events/services/event.service.ts` (booking capacity-adjustment calls); `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/EventCapacityAdjustmentController.cs`, `…/Domain/Managers/CapacityManager.cs`.

**9. Handover notes.** Adjustments during an active sale race with user orders — the Redis locked-capacity keys (`level_locked:…`) are respected by the manager; treat big deallocates during a sale carefully.

### F1.11 Seat reservation (complimentary / partner)

> **Bangla name:** আসন রিজার্ভেশন (কমপ্লিমেন্টারি / পার্টনার)

**1. Name and purpose.** Hold seats outside online sale for **complimentary** (VIP/guests) or **partner** (sponsors/agents) use; reserved seats later become printed tickets (F1.12).

**2. Trigger and actor.** Admin portal → event ticket console. Roles: admin pool (Booking `SeatReservationController`).

**3. Business flow.**
1. Staff choose event + level and reserve a number of seats (or a percentage of the level) with a reservation type (Complimentary/Partner) and category (DigitalPrint / Printing / ReservedOnly).
2. The system creates a reservation with a reservation number and holds the seats.
3. The summary screens show requested / generated / remaining per reservation; seats can later be released.
4. Ticket generation for a reservation happens in F1.12.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Booking `POST /booking/api/v1/seat-reservation` | **[HTTP + user token]** | `SeatReservation` (below) |
| 2 | Portal → Booking `POST /booking/api/v1/seat-reservation/event/{eventId}?percentage=` | **[HTTP + user token]** | Bulk reserve a percentage of a level |
| 3 | Booking manager | — | `SeatReservations` row; capacity decremented; Redis locked/level keys updated |
| 4 | Summary | **[HTTP + user token]** | `GET summary/{eventId}` → `List<ReservationSummary>` |

**5. Components.** Admin portal; Booking service; tables `SeatReservations`, `Capacities`; Redis.

**6. API contracts.** `SeatReservation` (`Domain/Models/SeatReservation.cs`) — key fields: `EventId, GalleryId, BlockId, LevelId, NumberOfSeats, HasSeats, Seats, Action ("Allocate"/"Deallocate"), Status, Type (Complimentary/Partner), ReservationCategory (DigitalPrint/Printing/ReservedOnly), MergeStatus, ZipStatus, PublicId, ProgramId, ReservationNumber`. Enums (Booking, serialized as strings): `ReservationStatus {Draft, Generated, Requested, Closed, Locked, Merging, Merged}`, `ReservationType {Complimentary, Partner}`, `ReservationCategory {DigitalPrint, Printing, ReservedOnly}`, `MergeStatus {None, Requested, Merging, Merged, Failed}`, `ZipStatus {None, Requested, Zipping, Zipped, Failed}`. `ReservationSummary` (`Domain/Models/ReservationSummary.cs`):

```json
// GET /booking/api/v1/seat-reservation/summary/{eventId}?levelId=&programId=   (item)
{
  "id": 301, "publicId": "5f0c…-guid", "ref": "RES-000045",
  "eventId": 1042, "galleryId": 12, "blockId": 7, "levelId": 45, "programId": 7,
  "status": "Requested", "type": "Partner", "reservationCategory": "DigitalPrint",
  "mergeStatus": "None", "zipStatus": "None",
  "ticketGeneratedCount": 40, "generatedSeats": "A11..A50",
  "ticketRequestedCount": 40, "requestedSeats": "A11..A50",
  "reserved": 50, "remainingReserved": 10, "reservedSeats": "A1..A50",
  "released": 0, "releasedSeats": null,
  "blankTicketPreviewUrl": "https://<cloudfront>/tickets/reserved/…/preview.pdf"
}
```

Other endpoints: `GET by-event-level?eventId&levelId&actionType&programId`, `GET by-event`, `GET count/{eventId}?actionType=`, `GET remainingReserveCount/{eventId}`, `GET reservations-count?eventId&levelIds`. Errors: standard envelope (`no_seats_available` → 400).

**7. Data and side effects.** `SeatReservations` rows; capacity decrements; no queue messages from this call itself (F1.12/F5.9 continue the story).

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/events/services/event.service.ts` (seat-reservation calls); `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/SeatReservationController.cs`, `…/Managers/SeatReservationManager.cs`.

**9. Handover notes.** Several update endpoints on this controller (`update-reservation-status`, `update-merge-status`, `update-zip-status`, `event-id/{publicId}` …) exist for **workers and internal services** (F5.9) and carry no `[Authorize]` — F6.18.

### F1.12 Reserved ticket generation and distribution

> **Bangla name:** রিজার্ভড টিকিট তৈরি ও বিতরণ

**1. Name and purpose.** The "Generate Tickets" console: turn a reservation into real tickets — generate blank PDFs, sign them via TSP, merge/zip per reservation, download from the portal or email the zip to a partner.

**2. Trigger and actor.** Admin portal → `/events/event-ticket`, `/events/generate-ticket/:id`. Roles: admin pool; Ticketing endpoints marked `[Authorize(Policy = admin)]`.

**3. Business flow.**
1. Staff open the event's ticket console and create the reservation's tickets (count/seat list per level, ticket type; a "test" mode exists that only produces a preview PDF).
2. "Sign" sends the blanks through the TSP signing pipeline — tickets become `Generated`.
3. "Merge" combines the reservation's PDFs into merged PDFs; "Zip" packs individual PDFs into zips (both run in the Utility worker).
4. Staff download the merged/zip artifacts (a **signed token** or CloudFront cookies protect the download), or **email** the zip to a recipient.
5. The console also shows merged/zipped ticket-number lists per reservation.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Ticketing `POST /ticketing/api/v1/booking-order-ticket/reserve-ticket?eventId&levelId` | **[HTTP + user token]** | `List<ReservedTicketRequest>`; creates Ticket rows (`Status=Requested`, type default "Partner Sale"), blank PDFs to S3 `{BlankBase}/reserved/{orderPublicId}/{TicketNumber}.pdf`, publishes **[SQS: TicketSigning]** per ticket |
| 2 | Worker | **[Worker]** | F5.8 signs via TSP → `GenerateSignedTicketAsync` (for reserved type: draws ticket info onto the PDF, stores under `{SignedBase}/reserved/{CreatedBy}/{orderPublicId}/{TicketNumber}-{type}.pdf`) |
| 3 | Portal → Ticketing `POST …/sign-reserve-ticket?eventId&levelId` | **[HTTP + user token]** | Re-publishes unsigned requested tickets to the signing queue |
| 4 | Portal → Ticketing `GET …/merge-reserved/{reservationId}` | **[HTTP + user token]** | Publishes **[SQS: TicketProcessing]** `ProcessingType=Merge` (F5.9 Utility worker → `{MergeBase}/{reservationId}/{ReservationNumber}_Merged_PDF_{i}.pdf`) |
| 5 | Portal → Ticketing `GET …/zip-reserved/{reservationId}` | **[HTTP + user token]** | Same with `ProcessingType=Zip` → `{ReservationNumber}_Individual_Zipped_{i}.zip` |
| 6 | Portal → Ticketing `GET …/download-merged?reservationId&signedToken` / `POST …/download-reserved` | **[HTTP + user token]** | Streams the artifact; `signedToken` from `POST …/generate-signed-token` |
| 7 | Portal → Ticketing `POST …/send-reserved` | **[HTTP + user token]** | Emails the zip via SES (`AWS:Ticket:EmailSender`, default subject "Get your tickets"); ticket `Action` set to `emailed: {recipient}` |
| 8 | Login time | — | For roles `admin`, `ticket_manager`, `ticket_operator` the portal fetches `GET …/signed-cookie` (F6.1) so browser downloads can use CloudFront directly |

**5. Components.** Admin portal; Ticketing service; Utility service; SQS `TicketSigning` + `TicketProcessing`; TSP gateway; S3 ticket bucket (`AWS:Ticket:*` paths); CloudFront signed URLs/cookies; SES; tables `Tickets`, `SeatReservations`.

**6. API contracts.** Selected:

```json
// POST /ticketing/api/v1/booking-order-ticket/reserve-ticket?eventId=1042&levelId=45
[ { "id": 301, "amount": 40, "hasSeats": true, "seats": ["A11","A12"], "ticketType": "Partner Sale", "isTest": false } ]

// POST /ticketing/api/v1/booking-order-ticket/send-reserved   (TicketRequest)
{
  "ticketNumbers": ["BCB-ODI2-P0001","BCB-ODI2-P0002"],
  "fileName": "partner-batch-1",
  "email": { "recipient": "partner@example.com", "subject": "Your reserved tickets", "body": "Please find attached." }
}
```

Other endpoints: `GET|PUT reserve-ticket` (list/regenerate), `POST download-test-blank-reserved` (`BlankTicketRequest`), `GET merged-ticket-number/{reservationId}`, `GET zipped-ticket-number/{reservationId}`, `GET reserved-urls?reservationId`, `POST generate-signed-token`, `GET signed-cookie` (returns the cookie string — the **caller** sets the three `CloudFront-*` cookies). Errors: standard envelope; missing template → `ArgumentException` ("Ticket Layout Config … not found", 400).

**7. Data and side effects.** `Tickets` rows (`Status` Requested→Generated, `SignedTicketUrl`); `SeatReservations.MergeStatus/ZipStatus` transitions (None→Requested→Merging→Merged / Zipping→Zipped, Failed on error); S3 files (blank/signed/merged/zip); SES email; SQS messages.

**8. Code references.**

| What | Where |
|---|---|
| Portal service | `rvl-gobcb-admin-portal/src/app/features/events/services/event.service.ts` |
| Console pages | `…/features/events/pages/event-ticket/…`, `…/components/generate-ticket/…` |
| Controller | `rvl-gobcb-backend/Services/Ticketing/ETP.Ticketing.Service/Api/BookingOrderTicketController.cs` |
| Manager | `…/ETP.Ticketing.Domain/Managers/TicketManager.cs` (`CreateReservationTicketsAsync`, `PublishBulkTicketToSign`, `RequestMergeTicketsAsync`, `RequestZipTicketsAsync`, `SendReservedTicketsAsync`) |
| CloudFront | `rvl-gobcb-backend/Core/ETP.Core.BlobStorage/AWSS3/{S3CloudFrontStroge,TicketingCookieManager}.cs` |

**9. Handover notes.** ① Reserved-ticket QRs carry `Platform=offline` and a `Complimentary` field instead of Name/Phone — the checker app treats them specially (F4.3). ② The signed-cookie endpoint returns a **string**, not `Set-Cookie` headers — the portal writes the cookies with `document.cookie` (F6.1). ③ Test mode (`isTest`) only stores a preview URL on the reservation, no real tickets.

### F1.13 Ticket layouts and ticket attributes

> **Bangla name:** টিকিট লেআউট ও টিকিট অ্যাট্রিবিউট

**1. Name and purpose.** Maintain the **PDF templates** used to print tickets (per program/venue/gallery, six variants: single/multiple segment × user/partner/complimentary, plus a back page) and the **ticket attributes** (which fields appear on a ticket and in what order).

**2. Trigger and actor.** Admin portal → `/ticket-layout` (also `/program-management` layout screens). Roles: `admin`, `event_manager`, `ticket_manager`, `ticket_operator` (`TicketLayoutConfigsController`, `TicketAttributesController`).

**3. Business flow.**
1. Staff create a layout config: name, program, venue (optionally gallery), ticket size (drives QR position), default texts.
2. They upload the template PDFs (one per variant) and the back-page PDF; publish makes the config the one Ticketing uses.
3. Ticket attributes configure the visible fields (gallery/block/level/entry gate/mini gate/venue name/segment datetime) with show flags and ordering priorities; DITF (exhibition) variants add ticket type / entry / exit time.
4. `download-backpage/{eventId}` lets staff preview the effective back page for an event.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/ticket-layout` | **[HTTP + user token]** | `TicketLayoutConfigCreated` |
| 2 | Portal → Admin `POST /admin/api/v1/ticket-layout/upload/{id}?ticketLayoutType=` | **[HTTP + user token]** | multipart PDF upload → S3 media bucket; URL stored on the config |
| 3 | Admin DB | **[Shared table]** | `TicketLayoutConfigs` (owner Admin); Ticketing reads it (published config per program/venue/gallery drives template choice in F5.8) |
| 4 | Portal → Admin `PUT /admin/api/v1/ticket-attributes/{id}` / `GET program/{programId}` | **[HTTP + user token]** | `TicketAttributes` upsert/read |

**5. Components.** Admin portal; Admin service; S3 media bucket; Ticketing (consumer of published layouts); table `TicketLayoutConfigs`, `TicketAttributes`.

**6. API contracts.**

```json
// POST /admin/api/v1/ticket-layout   (TicketLayoutConfigCreated)
{ "id": 0, "ticketLayoutName": "SBNCS 2026 layouts", "ticketType": null,
  "defaultText": "Bangladesh Cricket Board", "ticketSize": "Default",
  "partnerSaleDefaultText": "Partner — not for sale", "programId": 7, "venueId": 2, "venueGalleryId": 12 }
```

`TicketLayoutType` enum (upload variant): `SingleSegmentUser(0), MultipleSegmentUser(1), SingleSegmentPartner(2), MultipleSegmentPartner(3), SingleSegmentComplimentary(4), MultipleSegmentComplimentary(5)`. Ticket attributes (`TicketAttributes`): show flags `ShowGallery, ShowBlock, ShowLevelRow, ShowEntryGate, ShowMiniGate, ShowVenueName, ShowSegmentDateTime` (+ DITF: `ShowTicketType, ShowEntryTime, ShowExitTime`) and matching `*Priority` order fields (defaults 1–8). Other endpoints: `GET ""` paged (`searchText`), `GET program/{programId}`, `GET venue/{programId}/{venueId}`, `GET configs/{programId}/{venueId}/{venueGalleryId}`, `GET published/…`, `GET back-page/…`, `GET {id}`, `PUT {id}` (`TicketLayoutConfigUpdated`), `DELETE {id}`, `PUT publish|unpublish|duplicate/{id}`, `POST upload/back-page/{id}`, `DELETE delete-pdf/{id}` (+ back-page), `GET {id}/{ticketLayoutType}` (URL), `GET download-backpage/{eventId}` (PDF stream). Errors: `ArgumentException("Ticket Layout Config with ID {id} not found.")` → 400.

**7. Data and side effects.** `TicketLayoutConfigs`/`TicketAttributes` rows; PDFs to S3; `TicketSize` maps to QR position (`Default/Vertical [900,650,650]`, `A4 [1650,915,650]`, `Horizontal [2494,1055,650]`) consumed in F5.8.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/ticket-layout-management/services/ticket-layout.service.ts` (near-duplicate also under `program-management/services/`); `…/program-management/services/ticket-attributes.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/{TicketLayoutConfigsController,TicketAttributesController}.cs`.

**9. Handover notes.** ① **Publishing** is what Ticketing consumes (`GetPublishedAsync(programId, venueId, galleryId)`); an uploaded but unpublished PDF is ignored. ② If no published template exists for a gallery's config, ticket generation throws (400) — publish layouts before opening sales.

### F1.14 Ticket-pricing content page

> **Bangla name:** টিকিট-প্রাইসিং কনটেন্ট পেজ

**1. Name and purpose.** Maintain the public "ticket pricing" information page (program/venue matrix of named price tiers) shown on the portal and app (F2.3).

**2. Trigger and actor.** Admin portal → `/content-editor/ticket-pricing`. Roles: `TicketPricingController` carries **no** `[Authorize]` (F6.18); the screen itself is admin-only in the portal.

**3. Business flow.** Staff create a pricing entry per program/venue with named attributes (tier name + price), publish/unpublish it; the public page (F2.3) lists published entries.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/ticket-pricing` | **[HTTP + user token]** | `CreateOrUpdateTicketPricing` |
| 2 | Admin DB | **[Shared table]** | `TicketPricings` + `TicketPricingAttributes`; Event service serves `list` publicly (Redis key `ticket_pricing_all`) |

**5. Components.** Admin portal (`content-editor.service.ts`); Admin service; Event service (public read); tables `TicketPricings`, `TicketPricingAttributes`.

**6. API contracts.**

```json
// POST /admin/api/v1/ticket-pricing   (CreateOrUpdateTicketPricing)
{
  "programName": "Bangladesh Tour of Sri Lanka 2026",
  "venueName": "Sher-e-Bangla National Cricket Stadium",
  "isPublished": false,
  "attributes": [
    { "attributeName": "Grandstand", "attributePrice": 500 },
    { "attributeName": "Premium", "attributePrice": 1500 }
  ]
}
```

Endpoints: `GET ""` paged, `GET list`, `GET {id}`, `PUT {id}`, `DELETE {id}`, `PUT publish/{id}`, `PUT unpublish/{id}`, `DELETE attribute/{attributeId}`. Public shape: `TicketPricingProgram` (sample in F2.3). Errors: standard envelope.

**7. Data and side effects.** Pricing tables upsert; Redis `ticket_pricing_all` cache goes stale until TTL.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/content-editor/services/content-editor.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/TicketPricingController.cs`; public side `…/Event.Service/Api/TicketPricingController.cs`.

**9. Handover notes.** This is **editorial** content (names + prices for display), separate from the real per-level prices that drive sales (F1.9) — they can drift apart; the old session's docs flag keeping them in sync manually.

### F1.15 Promo codes

> **Bangla name:** প্রোমো কোড ব্যবস্থাপনা

**1. Name and purpose.** Create **promo codes** (discount vouchers customers type at checkout) with a discount value, validity window, usage limits and assignment rules (which program / events / galleries they apply to).

**2. Trigger and actor.** Admin portal → `/promo-management`, `/promo-management/create`, `/promo-management/edit-promo/:promoCodeId`. Role: `admin` only (`[Authorize(Roles = admin)]` on `PromoCodeController`).

**3. Business flow.**
1. Staff open Promo Management → Create Promo Code.
2. They set the code, name, program, discount type (percentage/fixed), value, start/end date-time, total usage limit and per-user limit.
3. They assign the code to program/events/galleries (assign type + target lists).
4. Save activates the code for the validity window; a background worker (F5.16) auto-expires/reactivates it by date.
5. The list screen shows paged codes; `exists` checks are used by other screens before saving.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal `promo-management.service.ts` → Admin `POST /admin/api/v1/promo-codes` | **[HTTP + user token]** | JSON `CreateOrUpdatePromoCode` |
| 2 | Admin `PromoCodeController` → `PromoCodeManager` | — | Inserts `PromoCodes` + `PromoCodeAssigns` (+ `PromoCodeVenueEventGallery` join rows) |
| 3 | Checkout (user) | **[Shared table]** | Booking reads `PromoCodes`/`PromoCodeAssigns` through its own mirror when applying the code (F2.5) |
| 4 | Admin worker | **[Worker: 2 min]** | `PromoCodeStatusUpdateService` flips status by start/end dates (F5.16) |

**5. Components.** Admin portal; Admin service; Booking (read mirror); tables `PromoCodes`, `PromoCodeAssigns`, `PromoCodeVenueEventGallery`.

**6. API contracts.** Base: `/admin/api/v1/promo-codes`. Auth: Admin pool, role `admin`.

| Method | Path | Request | Response |
|---|---|---|---|
| GET | `` | `pageOffset,pageSize,sortBy,sortOrder` | paged promo codes (total in `X-Total-Count`) |
| GET | `list` | — | all codes (for dropdowns) |
| GET | `{id}` | — | one promo code |
| GET | `code/{code}/{eventId}` | — | lookup by code for an event |
| GET | `exists` | — | existence check |
| POST / PUT `{id}` | `` / `{id}` | `CreateOrUpdatePromoCode` | created/updated entity |
| DELETE | `{id}` | — | deleted entity |

`CreateOrUpdatePromoCode` (`Services/Admin/ETP.Admin.Domain/Models/PromoCodes/CreateOrUpdatePromoCode.cs`):

```json
// POST /admin/api/v1/promo-codes
{
  "code": "BCBWELCOME",
  "name": "Welcome offer",
  "programId": 7,
  "discountType": 1,            // DiscountType enum (Admin serializes enums as numbers, §0.7)
  "discountValue": 10.0,
  "discountAppliedTo": 1,       // DiscountAppliedType
  "startDateTime": "2026-06-20T00:00:00Z",
  "endDateTime": "2026-07-10T23:59:59Z",
  "totalUsageLimit": 5000,
  "limitPerUser": 2,
  "assignTo": [
    { "assignType": 1, "programId": 7, "eventIds": [1042], "galleryIds": [12] }
  ]
}
```

Main errors: standard envelope (§0.7); duplicate code → 400 from the manager.

**7. Data and side effects.** Tables above; no queue messages; no emails; F5.16 later updates `Status` on the same rows.

**8. Code references.**

| What | Where |
|---|---|
| Portal service | `rvl-gobcb-admin-portal/src/app/features/promo-management/services/promo-management.service.ts` |
| Pages | `rvl-gobcb-admin-portal/src/app/features/promo-management/pages/…` |
| Controller | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/PromoCodeController.cs` |
| Worker | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Workers/BackgroundServices/PromoCodeStatusUpdateService.cs` |
| Read mirror | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Storage/DbContexts/BookingDbContext.cs` |

**9. Handover notes.** ① Only role `admin` may manage promo codes, but every customer checkout depends on the same rows — check with BS23 whether that is intentional. ② The `DiscountType`/`AssignType` enum numeric values are serialized as numbers by Admin (§0.7); the Angular UI sends numbers.

### F1.16 System discounts

> **Bangla name:** সিস্টেম ডিসকাউন্ট ব্যবস্থাপনা

**1. Name and purpose.** Create **automatic discounts** (no code needed — for example an early-bird reduction) with value, validity window and assignment to program/events/galleries. The user portal reads the active discount when showing prices (F2.4).

**2. Trigger and actor.** Admin portal → `/promo-management/discount`, `/promo-management/discount/create-discount`, `…/edit-discount/:discountId`. Role: `admin` (`DiscountController`).

**3. Business flow.**
1. Staff open Discount Management → Create Discount.
2. They set name, program, discount type/value and validity window, and assign targets (events/galleries).
3. Save creates the discount; the public price endpoints apply it automatically during the window; worker F5.17 flips status by date.
4. There is also an anonymous read endpoint the user portal calls at checkout time to show the discount (`program/{programId}/{eventId}/{galleryId}`).

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/discount` | **[HTTP + user token]** | JSON `CreateOrUpdateDiscount` |
| 2 | Admin `DiscountController` → manager | — | Inserts `Discounts` + `DiscountAssigns` (+ join rows) |
| 3 | User portal at checkout | **[HTTP + user token]** (no auth needed — `[AllowAnonymous]`) | `GET /admin/api/v1/discount/program/{programId}/{eventId}/{galleryId}` returns the active discount for that scope |
| 4 | Booking price calculation | **[Shared table]** | Booking mirrors `Discounts`/`DiscountAssigns` and reduces `TotalCharge` (F2.6) |
| 5 | Admin worker | **[Worker: 2 min]** | `SystemDiscountStatusUpdateService` activates/expires by date (F5.17) |

**5. Components.** Admin portal; Admin service (owner); Booking (mirror); user portal (reader); tables `Discounts`, `DiscountAssigns`, `DiscountVenueEventGallery`.

**6. API contracts.** Base: `/admin/api/v1/discount`. Auth: Admin pool, role `admin` (except the public read).

| Method | Path | Auth | Request | Response |
|---|---|---|---|---|
| GET | `` | admin | paged query | paged discounts |
| GET | `list` / `{id}` / `exists?eventIds=&discountId=` | admin | — | list / one / check |
| POST / PUT `{id}` | | admin | `CreateOrUpdateDiscount` | entity |
| DELETE | `{id}` | admin | — | entity |
| GET | `program/{programId}/{eventId}/{galleryId}` | **anonymous** | — | active discount for scope |

`CreateOrUpdateDiscount` (`Services/Admin/ETP.Admin.Domain/Models/Discounts/CreateOrUpdateDiscount.cs`):

```json
// POST /admin/api/v1/discount
{
  "name": "Early bird — Grandstand",
  "programId": 7,
  "discountType": 1,
  "discountValue": 15.0,
  "startDateTime": "2026-06-20T00:00:00Z",
  "endDateTime": "2026-06-27T23:59:59Z",
  "discountAssigns": [
    { "assignType": 1, "eventIds": [1042], "galleryIds": [12] }
  ]
}
```

**7. Data and side effects.** Tables above; no queues/emails.

**8. Code references.**

| What | Where |
|---|---|
| Portal service | `rvl-gobcb-admin-portal/src/app/features/promo-management/services/promo-management.service.ts` |
| Controller | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/DiscountController.cs` |
| Public read from portal | `rvl-gobcb-user-portal/ETP-Web/src/app/modules/core/services/api/booking-api.service.ts` |
| Worker | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Workers/BackgroundServices/SystemDiscountStatusUpdateService.cs` |

**9. Handover notes.** ① The public discount endpoint is `[AllowAnonymous]` by design (the checkout page needs it before login in some flows) — it exposes only discount metadata. ② Interaction rules when a promo code AND a system discount both apply are decided inside Booking's price calculation (F2.6) — test before changing either feature.

### F1.17 Ticket-checker (gate staff) accounts

> **Bangla name:** টিকিট-চেকার (গেট স্টাফ) অ্যাকাউন্ট

**1. Name and purpose.** Create and manage the TicketChecker-pool accounts that gate staff use in the checker app: create (name+phone), rename, set/force password, disable/enable, delete.

**2. Trigger and actor.** Admin portal → `/ticket-checker`. Roles: `admin`, `event_manager`, `ticket_manager`, `ticket_operator` (`TicketCheckerController`).

**3. Business flow.** Staff add a checker with name and phone; the account gets a temporary password (set later via "set password"); the checker signs in on the app (F6.12); admins can disable an account mid-shift (`user_disabled_for_this_gate` appears in the app, F4.5).

**4. Technical flow.** Portal → Admin `POST /admin/api/v1/ticket-checker` **[HTTP + user token]** → `TicketCheckerCreateUser {name, phone}` → Cognito TicketChecker pool (`Integration/Services/…UserProvider`). Reads back via `TicketCheckerUserResponse`.

**5. Components.** Admin portal (`ticket-checker.service.ts`); Admin service; Cognito TicketChecker pool.

**6. API contracts.** Base `/admin/api/v1/ticket-checker`: `GET ""` / `{id}` → `TicketCheckerUserResponse { userId, name, email, phone, role, currentStatus, isActive, isPhoneNumberVerified }`; `POST` `{ "name": "Gate Checker 12", "phone": "+8801712345678" }`; `PUT {id}` `TicketCheckerUpdateUser {userId, name}`; `PUT change-password` `TicketCheckerChangePassword {accessToken, oldPassword, newPassword}`; `DELETE {id}`; `POST disable/{id}|enable/{id}`; `POST set-password` `TicketCheckerSetPasswordRequest {password, userId}`. Also `GET search?name=`, `GET search-by-userid?sub=` (used by gate assignment, F1.18). Errors: standard envelope.

**7. Data and side effects.** Cognito user CRUD; no ETP tables (gate-user links live in F1.18's `TicketCheckerGateUsers`).

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/ticket-checker/services/ticket-checker.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/TicketCheckerController.cs`, `…/Integration/Services/TicketCheckerUserProvider.cs`.

**9. Handover notes.** `change-password` takes the checker's own access token in the body — verify who calls it (the admin portal passes an admin token today; the checker app has no password-change screen).

### F1.18 Gate assignment and download control

> **Bangla name:** গেট অ্যাসাইনমেন্ট ও ডাউনলোড নিয়ন্ত্রণ

**1. Name and purpose.** Assign ticket checkers to an event's entry gates (multi-assign, force-assign/unassign) and control whether each checker may download tickets for offline checking (`IsDownloadEnable`).

**2. Trigger and actor.** Admin portal → `/ticket-checker` → assign-gate dialog (`components/event-assign-gate/`). Roles: admin pool; `TicketCheckerGateController` accepts both `admin` and `ticket-checker` schemes on different actions.

**3. Business flow.**
1. Staff pick an event; the screen shows the event's gates and the checkers on each.
2. They assign checkers to gates (or **force-assign/unassign** bulk lists); `event-info` (F4.1) immediately reflects it.
3. They can toggle a checker's download permission and remove a checker from a gate.
4. After an event ends, a worker automatically turns download access off (F5.15).

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/ticket-checker-gate` | **[HTTP + user token]** | `AssignTicketCheckerGate` (below) |
| 2 | Portal → Admin `POST …/force-assign` / `force-unassign` | **[HTTP + user token]** | `List<AssignTicketCheckerGate>` bulk |
| 3 | Admin DB | **[Shared table]** | `TicketCheckerGates` + `TicketCheckerGateUsers`; TicketChecker service reads them via mirror (F4.1) |
| 4 | `PUT …/update-download-status/{userId}/{gateId}/{status}` | **[HTTP + user token]** | Flips `IsDownloadEnable` |
| 5 | Redis | — | `TicketCheckerLevelGateMap` hash (level→gate) maintained by `TicketCheckerGateManager`, used by Ticketing when publishing signed tickets to the gate cache (F5.8 tail) |

**5. Components.** Admin portal; Admin service; tables `TicketCheckerGates`, `TicketCheckerGateUsers`; Redis map; checker app (consumer).

**6. API contracts.**

```json
// POST /admin/api/v1/ticket-checker-gate   (AssignTicketCheckerGate)
{
  "eventId": 1042,
  "entryGateName": "Gate 3 — North",
  "entryGateId": "3,4",
  "ticketCheckerUsers": [ { "userId": "a1b2c3d4-…", "name": "Gate Checker 12", "isEnabled": true } ]
}
```

Also: `GET {eventId}` (gate users of an event), `GET user/{userId}`, `DELETE remove-user/{id}`, `GET event-info` (policy `ticket-checker` — the checker app's own call, sample in F4.1). Errors: standard envelope.

**7. Data and side effects.** Gate/gate-user rows; Redis map updates; no queues.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/ticket-checker/services/ticket-checker-gate.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/TicketCheckerGateController.cs`, `…/Managers/TicketCheckerGateManager.cs`.

**9. Handover notes.** `EntryGateId` is a comma-separated id string (matches the TicketChecker storage entity) — parse, don't cast.

### F1.19 Gate (ticket-checker) reports

> **Bangla name:** গেট রিপোর্ট (চেকার)

**1. Name and purpose.** Per-event scan reports: entry counts per gate/checker, duplicate entries (same ticket scanned repeatedly), manual entries, and an Excel export for auditing.

**2. Trigger and actor.** Admin portal → `/report/checker`, `/report/ticket-duplicate`. Roles: `admin`, `event_manager`, `ticket_manager`, `ticket_operator` (`TicketCheckerGateController`).

**3. Business flow.**
1. Staff pick an event and see a tree of gates → checkers with entry/manual/duplicate counts.
2. Duplicate-entry report lists tickets with repeated scans (with a details drill-down).
3. Manual-entry report lists tickets admitted by typed number.
4. "Export" downloads the raw checked-ticket list as Excel.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/ticket-checker-gate/report/{eventId}` | **[HTTP + user token]** | `TicketCheckerGateReportData` tree |
| 2 | Portal → Admin `GET …/export/{eventId}` | **[HTTP + user token]** | Excel stream (rows = `CheckedTicketExportData`) |
| 3 | Portal → Admin `POST …/duplicate-tickets/{eventLongId}` / `manual-entry-tickets/{eventLongId}`; `GET reports/duplicate-entries[/details]` | **[HTTP + user token]** | Aggregations |
| 4 | Data source | **[Shared table]** | `CheckedTickets` table — filled by worker F5.14 from the checker Redis counters |

**5. Components.** Admin portal (`report.service.ts`); Admin service; table `CheckedTickets`; Excel via ClosedXML.

**6. API contracts.** `TicketCheckerGateReportData { eventId, ticketCheckerGateId (string), eventName, ticketCheckerGateName, ticketCheckerName, entryCount, manualEntryCount, duplicateEntryCount }` (tree nodes add `children`). Export row: `CheckedTicketExportData { ticketNumber, ticketCheckerGateName, ticketCheckerName, entryCount, ticketType }`. Errors: standard envelope.

**7. Data and side effects.** Read-only.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/reports/services/report.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/TicketCheckerGateController.cs`.

**9. Handover notes.** Reports lag live scanning by up to ~30 minutes (F5.14 drain cycle); during an event use the checker app's counters for live state.

### F1.20 Raffle draw

> **Bangla name:** র‍্যাফল ড্র

**1. Name and purpose.** Record raffle winners drawn from an event's valid ticket numbers, and look up a ticket's holder details for prize handover.

**2. Trigger and actor.** Admin portal → event screens (raffle draw winner dialog). Roles: `admin`, `event_manager` (`RaffleDrawController`).

**3. Business flow.** Staff draw a winning ticket externally (or pick a number), look it up (`details`), and record it as a winner; the list shows the event's winners and can be cleaned up.

**4. Technical flow.** Portal → Admin `POST /admin/api/v1/raffle-draw` **[HTTP + user token]** → `RaffleDraw` row (denormalized ticket + order info); `GET details/{eventId}/{ticketNumber}` resolves holder name/identification from the `Tickets` mirror (shared table).

**5. Components.** Admin portal (`raffle-draw-winner.service.ts`); Admin service; tables `RaffleDraws`, `Tickets` (mirror).

**6. API contracts.** `RaffleDraw { ticketNumber, ticketType, userId, ticketHolderName, ticketHolderIdentification, eventLongId, eventPublicId, bookingOrderId, bookingOrderPublicId, bookingOrderDateTime, orderNumber }`; endpoints `GET ?eventId=`, `GET details/{eventId}/{ticketNumber}`, `POST`, `DELETE {id}`. Errors: standard envelope.

**7. Data and side effects.** `RaffleDraws` rows only.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/events/services/raffle-draw-winner.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/RaffleDrawController.cs`.

**9. Handover notes.** The draw itself (random winner selection) is not implemented server-side — this feature only records results.

### F1.21 Dashboard

> **Bangla name:** ড্যাশবোর্ড

**1. Name and purpose.** The program dashboard: tiles (total events, unresolved issues) plus sales charts (ticket sales summary, last week/month seat sales, upcoming events).

**2. Trigger and actor.** Admin portal → `/` (dashboard). Roles: `admin`, `ticket_operator` + `[AuthorizeProgram]` on `DashboardController` (Admin) — the only controller where the program attribute is active.

**3. Business flow.** Staff see at a glance: how many events the program has, how many events are upcoming/running/past, total tickets sold and sales amount, a seven-day chart of recent sales.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/dashboard/get-tile-data?programId=` | **[HTTP + user token]** | `TileData { totalEvents, unResolveIssue }` |
| 2 | Portal → Admin `GET /admin/api/v1/dashboard/get-event-by-category` | **[HTTP + user token]** | `EventsByCategory { totalUpcoming, totalPast, totalRunning }` |
| 3 | Portal → Booking `GET /booking/api/v1/dashboard/get-ticket-sales-summary?programId=` | **[HTTP + user token]** | `TicketSalesSummary { numberOfTotalTicketSale, amountOfTotalTicketSale }` |
| 4 | Portal → Booking `GET …/get-upcomming-seven-events` / `get-last-week-seats-sale-amount` / `get-last-Month-seats-sale-amount` | **[HTTP + user token]** | `DashboardChartData { labels[], datasets[{ label, data[] }] }` |

**5. Components.** Admin portal (`dashboard.service.ts`, chart.js); Admin + Booking services; tables `Events`, `UserIssues` (Admin), `UserBookingOrders` (Booking).

**6. API contracts.** Shapes above; sample:

```json
// GET /booking/api/v1/dashboard/get-last-week-seats-sale-amount
{ "labels": ["Mon 29","Tue 30","Wed 01","Thu 02","Fri 03","Sat 04","Sun 05"],
  "datasets": [ { "label": "Seats sold", "data": [120, 340, 510, 80, 950, 1210, 430 ] } ] }
```

Errors: standard envelope; missing `X-Program-Id` on the Admin dashboard endpoints → 400 (F1.1).

**7. Data and side effects.** Read-only aggregations.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/dashboard/services/dashboard.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/DashboardController.cs`, `…/Booking.Service/Api/BookingReportController.cs`.

**9. Handover notes.** Tiles/charts come from **two services** (Admin + Booking) — program scoping differs (header vs query param, §F1.1).

### F1.22 Booking, sales, revenue and payment-discrepancy reports

> **Bangla name:** বুকিং, বিক্রয়, রাজস্ব ও পেমেন্ট-ডিসক্রিপ্যান্সি রিপোর্ট

**1. Name and purpose.** The Reports menu: per-event booking orders, booking metrics, event-wise/summary sales and revenue, day-wise revenue, payment discrepancy (gateway vs ledger), with Excel exports.

**2. Trigger and actor.** Admin portal → `/report/*` pages. Roles: admin pool; the Booking `ReportController` carries **no** `[Authorize]` (F6.18).

**3. Business flow.** Staff filter by program/event/date and view or export: booking order list, capacity/sales metrics per event, revenue (with/without VAT), and discrepancy between DgePay transactions and recorded payments.

**4. Technical flow.** Portal → Booking `GET /booking/api/v1/report/admin/…` **[HTTP + user token]** → `ReportController` (ClosedXML Excel for `export-booking-orders`) reading `UserBookingOrders`, `Capacities`, `SeatReservations`; portal also uses Admin `events/search` for pickers.

**5. Components.** Admin portal (`report.service.ts`, `booking-orders.service.ts`); Booking service; ClosedXML; tables `UserBookingOrders`, `Capacities`, `SeatReservations`.

**6. API contracts.** Endpoints (`/booking/api/v1/report/admin/`): `export-booking-orders?eventId&programId` (Excel), `revenue-report-list?startDate&endDate&eventId&programId`, `booking-metrics?eventId`, `event-revenue-summary?programId`, `event-sales-summary?programId`, `event-sales-details?id&programId`, `event-revenue-sales-details`, `payment-discrepancy?programId&eventId`. Shapes:

```json
// booking-metrics
{ "totalCapacity": 25000, "totalOnlineGeneratedTicket": 18200, "totalSoldTickets": 17900,
  "totalReservedTickets": 400, "availableTickets": 6700,
  "totalOrders": 9500, "totalPaidOrders": 9100, "totalPaidOrdersInPercentage": 95.8,
  "totalRequestedOrders": 120, "totalRequestedOrdersInPercentage": 1.3,
  "totalGeneratedOrders": 80, "totalGeneratedOrdersInPercentage": 0.8,
  "totalCancelledOrders": 280, "totalCancelledOrderInPercentage": 2.9,
  "totalSuccessfulOrders": 9080, "totalSuccessfulOrdersInPercentage": 95.6 }

// revenue-report-list (item)
{ "eventName": "2nd ODI — BAN vs SL", "eventDateTime": "08 Jul 2026 14:00", "date": "05 Jul 2026",
  "ticketsSold": 17900, "ticketRevenueWithoutVatCharge": 26850000.0,
  "vat": 4027500.0, "serviceCharge": 358000.0, "totalRevenue": 31235500.0 }
```

`event-sales-summary`/`event-revenue-summary` items: `{ eventName, totalCapacity, onlineCapacity, onlineCapacityPercentage, onlineSold, onlineSoldPercentage, remainingOnlineSeats[, onlineRevenue, vat] }`; details variants add reserved/FOC/partner-sale splits. Errors: standard envelope.

**7. Data and side effects.** Read-only; Excel files generated in-memory.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/reports/services/{report,booking-orders}.service.ts`; `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/ReportController.cs`, `…/Domain/Models/Report/…`.

**9. Handover notes.** "FOC" (free of charge) and partner-sale splits come from reservation types (F1.11); discrepancy logic compares payment-gateway records with order rows — its exact matching rules are data-dependent `[UNCONFIRMED]`.

### F1.23 Reconciliation lookup

> **Bangla name:** রিকনসিলিয়েশন সার্চ

**1. Name and purpose.** Customer-support search for one order by order number / transaction id / ticket number / phone — the entry point for resolving payment complaints ("I paid but got no tickets").

**2. Trigger and actor.** Admin portal → `/issues/reconciliation`. Roles: admin pool (`[Authorize(Policy = admin)]`).

**3. Business flow.** Staff choose a search type, type the value, and see the matching order with status, payment info and user; from there they open the issue console or the order's tickets.

**4. Technical flow.** Portal → Booking `GET /booking/api/v1/user-booking-order/admin/reconciliation/{searchType}/{searchText}` **[HTTP + user token]** → `UserBooking` (full shape in F2.7); phone search resolves users via the Serverless API (`user/get-bulk-users`), ticket-number search via the `Tickets` mirror.

**5. Components.** Admin portal (`reconciliation.service.ts`, `booking-orders.service.ts`); Booking service; Serverless API (user lookup).

**6. API contracts.** `searchType` enum: `OrderNumber | TransactionId | TicketNumber | PhoneNo`. Response: `UserBooking` (sample in F2.7). Errors: standard envelope (404-style message when not found).

**7. Data and side effects.** Read-only.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/issues/services/reconciliation.service.ts`; `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/UserBookingOrderController.cs` (`admin/reconciliation/…`).

**9. Handover notes.** This is the fastest tool for the "paid but not generated" class of complaints; pair it with F2.8's generate-request to re-trigger generation.

### F1.24 User issues and support chat (admin side)

> **Bangla name:** ইউজার ইস্যু ও সাপোর্ট চ্যাট (অ্যাডমিন পাশ)

**1. Name and purpose.** List customer issues per program/status, read and answer them in a real-time chat, update status/feedback, and see the customer's order + tickets in one view.

**2. Trigger and actor.** Admin portal → `/issues/list`, `/issues/:id/details`. Roles: `admin`, `customer_support` on the Admin proxy; UserIssue service uses policy `admin` (and `user` for customer calls).

**3. Business flow.**
1. Support opens Issues: a paged, filterable list (status, program, free search by order/issue/txn/phone).
2. Opening an issue shows the chat thread (with attachments), the customer's order summary and tickets.
3. Support replies in real time (typing indicator, read receipts), sets feedback and resolves the issue.
4. Resolution can trigger an SMS to the customer through the external Notification API (`SendIssueResolvedNotification`).

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/user-issue` | **[HTTP + user token]** | Paged issues (Admin proxies/enriches via `UserIssueClient`) |
| 2 | Portal → Admin `PUT /admin/api/v1/user-issue/{id}` | **[HTTP + user token]** | `UpdateUserIssue { feedback, status }` |
| 3 | Chat REST | **[HTTP + user token]** | `POST /admin/api/v1/user-issue-chat/send` (multipart), `GET {id}/messages|recent|last|unread-count`, `mark-read?receiverType=ADMIN`, attachment download |
| 4 | Chat real-time | **[SignalR]** | Admin portal connects to the **UserIssue hub** `{userissuehub}/userissue/chathub?access_token=…` (WebSocket-only) — the same hub customers use (F2.12) |
| 5 | Attachments | — | S3 media bucket `chat-attachments/{issueId}/{guid}{ext}` via `ICloudFrontMediaManager` |
| 6 | On resolve | **[HTTP, static key]** | Admin → Notification API `POST /notification/request` (`IssueResolvedNotification`) |

**5. Components.** Admin portal (`issue.service.ts`, `chat.service.ts`, @microsoft/signalr); Admin service (proxy + own `/admin/chathub` — legacy, see notes); UserIssue service (owner); S3; Notification API (external); SignalR public ingress `chat.gobcbticket.com.bd`.

**6. API contracts.** Main shapes (UserIssue service): `ReportedUserIssue { id, user (CognitoUser), issueNumber, orderNumber, transactionId, orderStatus, orderDate, publicOrderId, description, feedback, status ("Open"/"Resolved"), createdAt/…, resolvedAt/… }`, `ReportedUserIssueDetails` adds `eventName, paymentInfo, tickets[]`; chat message: `ReportedUserIssueChatMessage { id, reportedIssueId, message, senderType ("USER"/"ADMIN"), senderId, senderName, isRead, attachmentFileName/Path/ContentType/Size, createdAt }`. Hub methods: `SendMessage`, `JoinUserIssueChat`, `LeaveUserIssueChat`, `SendTypingIndicator`, `StopTyping`; client events: `NewMessage`, `MessagesRead`, `UserJoined`, `UserLeft`, `UserTyping`, `UserStoppedTyping`, `MessageError`. Errors: standard envelope.

**7. Data and side effects.** `ReportedIssues` / `ReportedIssueChatMessages` rows (owner UserIssue); S3 attachments; SMS on resolve.

**8. Code references.**

| What | Where |
|---|---|
| Portal services | `rvl-gobcb-admin-portal/src/app/features/issues/services/{issue,chat,reconciliation}.service.ts` |
| Admin proxy | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/{UserIssueController,UserIssueChatController}.cs` |
| Owner service | `rvl-gobcb-backend/Services/UserIssue/ETP.UserIssue.Service/Api/{ReportIssueController,ReportIssueChatController}.cs`, `Hubs/UserIssueChatHub.cs` |
| Notification | `rvl-gobcb-backend/Core/ETP.Core/ServiceClient/NotificationClient/NotificationClient.cs` |

**9. Handover notes.** ① The Admin service also hosts its own hub `/admin/chathub` (same hub class) — the portal uses the UserIssue hub, so the Admin hub appears **legacy** `[UNCONFIRMED]`. ② The UserIssue **chat REST controller has no `[Authorize]`** (F6.18) — the hub is authorized, the history/send endpoints rely on network placement. ③ `user-detail/{orderId}` is `[AllowAnonymous]` on the Admin proxy.

### F1.25 Admin users

> **Bangla name:** অ্যাডমিন ইউজার ব্যবস্থাপনা

**1. Name and purpose.** Create and manage staff accounts: name/phone/email, **role** (`admin`, `event_manager`, `ticket_manager`, `ticket_operator`, `customer_support`), program scope, enable/disable, set/force password, delete.

**2. Trigger and actor.** Admin portal → `/users`. Roles: `admin` only (`AdminUsersController`).

**3. Business flow.**
1. An admin creates a staff account with role and (optionally) allowed program ids.
2. The account gets a temporary Cognito password which the new staff member changes at first login (F6.1) or an admin sets via "set password".
3. Disable/enable keeps the account but blocks sign-in; "forgot password" (`forget-password?phoneNo=` + `set-forget-password`) resets via SMS.
4. Role and program changes take effect after the token/claim caches refresh (up to 55 min client-side, F6.4).

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/admin-users` | **[HTTP + user token]** | `AdminCreateUser { name, phone, email, role, programIds }` |
| 2 | Admin `Integration/Services/AdminUserProvider` | — | Cognito Admin-pool user creation; writes `custom:role` and `custom:program_ids` attributes |
| 3 | Portal → Admin `PUT {id}` / `disable/{id}` / `enable/{id}` / `set-password` | **[HTTP + user token]** | `AdminUpdateUser { userId, name, role, programIds }`, etc. — again Cognito |
| 4 | Forgot password | **[HTTP, no token]** (`[AllowAnonymous]`) | `GET forget-password?phoneNo=` (sends SMS OTP) → `POST set-forget-password { userId, password }` |

**5. Components.** Admin portal (`user.service.ts`); Admin service; Cognito Admin pool; Serverless API (SMS).

**6. API contracts.**

```json
// POST /admin/api/v1/admin-users
{ "name": "Nazmul Hasan", "phone": "+8801700000010", "email": "nazmul@bcb.gov.bd",
  "role": "event_manager", "programIds": "7,8" }

// GET /admin/api/v1/admin-users   (item: AdminUserResponse)
{ "userId": "e5f6…-cognito-sub", "name": "Nazmul Hasan", "email": "nazmul@bcb.gov.bd",
  "phone": "+8801700000010", "role": "event_manager", "programIds": "7,8",
  "currentStatus": "Enabled", "isActive": true, "isPhoneNumberVerified": true }
```

Also `GET {id}`, `DELETE {id}`, `POST disable/{id}`, `POST enable/{id}`, `POST set-password { userId }`, `GET forget-password?phoneNo=`, `POST set-forget-password { userId, password }`. Errors: standard envelope.

**7. Data and side effects.** Cognito user records only (no ETP table for staff).

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/users/services/user.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/AdminUsersController.cs`, `…/Integration/Services/AdminUserProvider.cs`.

**9. Handover notes.** ① Role semantics land in F6.15; program ids in F6.16. ② There is no registration UI — account creation is admin-only by design.

### F1.26 Agent (seller) users

> **Bangla name:** এজেন্ট (বিক্রেতা) ইউজার

**1. Name and purpose.** Manage **Agent-pool** accounts for offline sellers (name, phone, company/branch) who record offline-sold tickets (F6.13).

**2. Trigger and actor.** Admin portal → `/agent-user`. Roles: **none** — `AgentController` (`api/v1/agent-users`) has **no `[Authorize]`** (F6.18).

**3. Business flow.** Staff create an agent with company details, set a password, disable/enable or delete the account; agents then sign in (Agent pool) and mark tickets as sold offline.

**4. Technical flow.** Portal → Admin `POST /admin/api/v1/agent-users` **[HTTP — token attached but not enforced]** → `AgentCreateUser { name, phone, email?, companyName, companyBranch, branchLocation }` → Cognito Agent pool. Response `AgentUserResponse` adds `currentStatus/isActive/isPhoneNumberVerified` and echoes company fields.

**5. Components.** Admin portal (`agent-user.service.ts`); Admin service; Cognito Agent pool.

**6. API contracts.** Base `/admin/api/v1/agent-users`: `GET ""`, `GET {id}`, `POST`, `PUT {id}` (`AgentUpdateUser { userId, name }`), `DELETE {id}`, `POST disable/{id}|enable/{id}`, `POST set-password` (`AgentUserSetPasswordRequest { password, userId }`). Errors: standard envelope.

**7. Data and side effects.** Cognito Agent-pool records only.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/agent-user/services/agent-user.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/AgentUserController.cs`, `…/Integration/Services/AgentUserProvider.cs`.

**9. Handover notes.** The missing `[Authorize]` on this controller is one of the most security-relevant findings of the handover — anyone who can reach the service can create Agent accounts and set their passwords (F6.18, Open queries).

### F1.27 Activity log viewer

> **Bangla name:** অ্যাক্টিভিটি লগ ভিউয়ার

**1. Name and purpose.** Browse the audit trail of every entity change the services made (who changed what, old vs new values), per service/entity/event, paged.

**2. Trigger and actor.** Admin portal → `/activity-log` (global) and the event details Activity tab. Roles: `admin`, `event_manager` (`ActivityLogController`).

**3. Business flow.** Staff filter by service name, entity name(s) (or exclude some), entity id; the list shows action (Added/Modified/Deleted), old/new JSON, user, IP and time.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/activity-log` | **[HTTP + user token]** | Query: `serviceName, entityNames, entityNamesToExclude, entityId, pageOffset, pageSize` |
| 2 | Admin `ActivityLogsManager` | **[Shared table]** | Reads the shared `ActivityLogs` table written by **every** service's `ActivityLogInterceptor` (F6.24) |
| 3 | Other services | — | Read their own slices via `POST batch` (`ActivityLogsBatchRequest`), using the `ETP.Admin.Client` library |
| 4 | Event tab | **[HTTP + user token]** | `GET event/{eventId}` |

**5. Components.** Admin portal (`activity-log.service.ts`); Admin service; shared table `ActivityLogs` (LoggingDbContext, schema `etp`).

**6. API contracts.** Entry shape (`ActivityLog`): `{ serviceName, entityName, entityId, action ("Added"/"Modified"/"Deleted"), oldValues, newValues (JSON of changed props; file parts masked "[Image File]"), entityContext, transactionId, timestamp, userId, userName, ipAddress }`; paged envelope `{ items, totalCount }`. Batch request: `{ requests: [ { serviceName, entityName, entityId?, pageOffset, pageSize } ] }`. Errors: standard envelope.

**7. Data and side effects.** Read-only here; writes happen in F6.24.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/global-activity-log/services/activity-log.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/ActivityLogController.cs`; writer side `rvl-gobcb-backend/Core/ETP.Core.EntityFramework/Interceptors/ActivityLogInterceptor.cs`.

**9. Handover notes.** ① Inserts are logged **after** save (so the DB id is captured); updates log only changed properties. ② The `username` claim identifies the actor; background workers log as `System`.

### F1.28 Media configuration (banners, gallery, contact, registration)

> **Bangla name:** মিডিয়া কনফিগারেশন (ব্যানার, গ্যালারি, যোগাযোগ, রেজিস্ট্রেশন)

**1. Name and purpose.** Manage the images shown on the public site: hero banners, sponsor strips, graffiti/advertisement banners, the two gallery-page segments, contact-us and registration-page images — with ordering, publishing and duplication.

**2. Trigger and actor.** Admin portal → `/media-configuration` sub-pages. Roles: `admin`, `event_manager` (`LandingPageImageController`).

**3. Business flow.** Staff upload an image per **type**, set title/description/action URL and display order, publish/unpublish; the two gallery segments accept multiple images with segment titles; a swap-order action exchanges two images' order.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/landing-page-image` | **[HTTP + user token]** | multipart `CreateOrUpdateLandingPageImage` (image + optional thumbnail) |
| 2 | Admin manager | — | Upload to media bucket; `LandingPageImage` row with `Type`, `DisplayOrder`, publish flags |
| 3 | Public read | **[HTTP, no token]** | Event service `GET /event/api/v1/landing-page-image/public` (Redis key `landing_page_image_published`) |
| 4 | Gallery segments | **[HTTP + user token]** | `POST add-gallery-image` — `GalleryPageSegmentImages { firstSegmentTitle, firstSegmentImageFiles[], secondSegmentTitle, secondSegmentImageFiles[] }` |

**5. Components.** Admin portal (`media-configuration.service.ts`); Admin service; Event service; S3 media bucket; table `LandingPageImage`.

**6. API contracts.** `LandingPageImageType` values (wire strings): `Hero, Sponsors, Graffiti, Advertisement, Gallery_Page_Segment_1, Gallery_Page_Segment_2, Contact_Us, Registration, Notice, Terms_Condition, Privacy_Policy, FAQ`. Public item (`LandingPageImagePublic`): `{ title?, description?, actionUrl?, imageUrl, thumbnailUrl?, type, displayOrder, startDateTime?, endDateTime? }`. Endpoints: `GET ""`, `GET {id}`, `POST`, `PUT {id}`, `DELETE {id}`, `PUT publish/{id}|unpublish/{id}|duplicate/{id}`, `PUT display-order/{type}/{displayOrder1}/{displayOrder2}`, `POST add-gallery-image`. Errors: standard envelope.

**7. Data and side effects.** `LandingPageImage` rows; files to S3; public cache TTL delays visibility.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/media-configuration/services/media-configuration.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/LandingPageImageController.cs`.

**9. Handover notes.** ① The admin service also serves `GET /admin/api/v1/gallery` (static gallery list from the `GallerySettings` config section) used by some screens. ② The enum contains `Terms_Condition/Privacy_Policy/FAQ/Notice` image types — evidence that the legal pages were planned to be image/CMS-driven; the portal currently serves them from static assets (F2.3 note) `[UNCONFIRMED]`.

### F1.29 Content editor (T&C, FAQ, privacy, notice)

> **Bangla name:** কনটেন্ট এডিটর (শর্তাবলি, FAQ, প্রাইভেসি, নোটিশ)

**1. Name and purpose.** The admin screens for customer-facing content: terms & conditions, FAQ, privacy policy, notices and the ticket-pricing page.

**2. Trigger and actor.** Admin portal → `/content-editor/*`. Roles: screen reachable per portal menu; backends are the ticket-pricing controller (F1.14) and the general-notice controller (F1.31).

**3. Business flow.** Staff edit the ticket-pricing matrix (F1.14) and publish notices (F1.31); the T&C/FAQ/privacy screens exist in the UI.

**4. Technical flow.** Ticket pricing → F1.14; notices → F1.31. **No API calls were found for the T&C/FAQ/privacy editor screens** — no controller in any service serves such content.

**5. Components.** Admin portal (`content-editor/` components); Admin service (pricing + notice only).

**6. API contracts.** Only F1.14's and F1.31's.

**7. Data and side effects.** As in F1.14/F1.31.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/content-editor/components/…`, `services/content-editor.service.ts`.

**9. Handover notes.** The legal texts the customer sees come from static client assets (portal i18n; app strings), and the admin screens for them appear to be non-functional shells `[UNCONFIRMED]` — confirm with BS23 whether CMS-driven legal pages were planned (the image-type enum in F1.28 hints they were).

### F1.30 Header/footer and social-media settings

> **Bangla name:** হেডার/ফুটার ও সোশ্যাল-মিডিয়া সেটিংস

**1. Name and purpose.** Edit the public header/footer (brand logo, "powered by" logo, title, phone, email, office address) and the social-media links; also read-only system settings.

**2. Trigger and actor.** Admin portal → `/settings/footer-settings`. Roles: `admin` (`SocialMediaSettingsController`); `HeaderFooterController` has **no** `[Authorize]` (F6.18).

**3. Business flow.** Staff upload brand/powered-by images, fill contact fields and social URLs; save publishes to the header/footer on the public site.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `PUT /admin/api/v1/header-footer` | **[HTTP + user token]** | multipart `UpdateHeaderFooter` (brand/powered-by files + JSON fields) |
| 2 | Portal → Admin `GET /admin/api/v1/header-footer` | **[HTTP, no token]** (no auth on controller) | Current values |
| 3 | Public read | **[HTTP, no token]** | Event service `GET /event/api/v1/header-footer` (list) |
| 4 | Social | **[HTTP + user token]** | `GET|PUT /admin/api/v1/social-media-settings` |

**5. Components.** Admin portal (`footer-settings.service.ts`); Admin service; Event service; S3 media bucket; tables `HeaderFooter`, `SocialMediaSettings`.

**6. API contracts.** `HeaderFooter { brandImageUrl?, poweredByImageUrl?, facebookUrl?, instagramUrl?, linkedInUrl?, twitterUrl?, title, phoneNumber?, email?, officeAddress? }`; `SocialMediaSettings { facebookUrl?, instagramUrl?, linkedInUrl?, twitterUrl? }`; `SystemSettings { id, allowUserSignInWithUserPassword, seatLockTimeout }` (read-only `GET /admin/api/v1/system-settings`, role `admin`). Errors: standard envelope.

**7. Data and side effects.** Settings rows; image uploads; public cache refresh.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/program-settings/services/footer-settings.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/{HeaderFooterController,SocialMediaSettingsController,SystemSettingsController}.cs`.

**9. Handover notes.** `SystemSettings.SeatLockTimeout` exists as a setting while Booking's lock expiry is hard-coded at 12 minutes (F5.3) — whether the setting actually drives the window is `[UNCONFIRMED]`.

### F1.31 General notices

> **Bangla name:** সাধারণ নোটিশ

**1. Name and purpose.** Publish program-scoped notices (with a validity window) that the public portal shows on the home page.

**2. Trigger and actor.** Admin portal → `/settings/notice`. Roles: `admin`, `event_manager` (`GeneralNoticeController`).

**3. Business flow.** Staff write the notice text, set start/end date-times and publish; the portal home fetches the published notice (`GeneralNoticePublic { description }`).

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/general-notice` | **[HTTP + user token]** | `CreateOrUpdateGeneralNotice { programId, description, startDateTime, endDateTime, isPublished }` → `GeneralNotices` row |
| 2 | Public read | **[HTTP, no token]** | `GET /admin/api/v1/general-notice/public` `[AllowAnonymous]`; Redis key family `general_notice_published` caches it |

**5. Components.** Admin portal (`notice.service.ts`); Admin service; table `GeneralNotices`; Redis.

**6. API contracts.** `GeneralNotice { id, programId, description, startDateTime, endDateTime, isPublished, isDeleted, isActive, createdAt/By, updatedAt/By }`; endpoints `GET ""`, `GET public`, `GET {id}`, `POST`, `PUT {id}`, `DELETE {id}`. Errors: standard envelope.

**7. Data and side effects.** `GeneralNotices` rows; public cache TTL.

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/program-settings/services/notice.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/GeneralNoticeController.cs`; portal reader `rvl-gobcb-user-portal/ETP-Web/src/app/modules/core/services/api/event-api.service.ts`.

**9. Handover notes.** The notice text is a single description field (no rich text/bangla variant) — the portal renders it as-is.

## 4. Checker App

Features used by gate staff in the Flutter checker app (`rvl-gobcb-checker-app`), TicketChecker Cognito pool. The app is **offline-first**: it keeps the gate's tickets and the scan counters in a local database (drift/SQLite) and synchronizes with the backend on a timer. Login is F6.12.

> 📦 **Explainer: offline-first with a local database**
> On match day the stadium gate cannot depend on connectivity. The checker app downloads the valid ticket numbers once (F4.2), validates every scan **on the device** against that local list and a certificate embedded in the app (F4.3), records scans locally, and pushes/pulls counters to the backend every 90 seconds (F4.5). The backend keeps the same counters in Redis so other devices at the same gate converge.

### F4.1 Assigned event and gate

> **Bangla name:** নির্ধারিত ইভেন্ট ও গেট দেখা

**1. Name and purpose.** After login the checker sees the event(s) and entry gate(s) an administrator assigned to them, and picks the one to work on.

**2. Trigger and actor.** Checker app → `/eventPage` (event/gate picker). Actor: gate checker, TicketChecker pool (policy `ticket-checker`).

**3. Business flow.**
1. The checker signs in (F6.12) and opens the event page.
2. The app shows the assigned event(s) with cover image, dates, the entry gate name(s) and whether offline ticket download is enabled for them.
3. Choosing an event/gate opens the scanner dashboard (`/qrPage`).
4. The list is cached on the device so it still opens when offline.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | App → Admin `GET /admin/api/v1/ticket-checker-gate/event-info` | **[HTTP + user token]** | Returns the checker's `TicketCheckerEventInfo` (assigned event + gates + `IsDownloadEnabled`) |
| 2 | Admin service | — | Reads `TicketCheckerGates` / `TicketCheckerGateUsers` (owner Admin) for the signed-in `sub` |
| 3 | App storage | — | Response cached in shared preferences (`event-list`) for offline fallback; re-fetched on every sync cycle (F4.5) |

**5. Components.** Checker app; Admin service; TicketChecker pool; tables `TicketCheckerGates`, `TicketCheckerGateUsers`.

**6. API contracts.**

`GET /admin/api/v1/ticket-checker-gate/event-info` — auth: TicketChecker pool (policy `ticket-checker`).

```json
// 200
{
  "ticketCheckerGateId": 88,
  "eventId": "b8e6a9d2-3f1c-4e7a-9d5f-6c2b1a8e0d34",
  "eventLongId": 1042,
  "eventName": "2nd ODI — Bangladesh vs Sri Lanka",
  "eventCoverImage": "https://<cloudfront>/<key>.jpg",
  "eventStartDateTime": "2026-07-08T14:00:00Z",
  "eventEndDateTime": null,
  "isDownloadEnabled": true,
  "entryGateName": "Gate 3 — North",
  "entryGateIds": [3, 4],
  "userSubId": "a1b2c3d4-…",
  "userName": "Gate Checker 12"
}
```

Main errors: standard envelope; the app surfaces `ticket_checker_event_not_found` when the account has no assignment.

**7. Data and side effects.** None server-side; shared-preferences cache on device.

**8. Code references.**

| What | Where |
|---|---|
| Event page | `rvl-gobcb-checker-app/lib/presentation/feature/event_page/…` |
| API call | `rvl-gobcb-checker-app/data/lib/remote/api_service/ticket_api_service_impl.dart` |
| Controller | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/TicketCheckerGateController.cs` (`event-info`) |
| Assignment itself | F1.18 (admin-side gate assignment) |

**9. Handover notes.** ① Assignment is done by an admin in the admin portal (F1.18); a checker without an assignment sees no events. ② `EntryGateIds` is a list — one assignment can cover several physical gates; scans are validated against the list (F4.3).

### F4.2 Ticket download for offline checking

> **Bangla name:** অফলাইন টিকিট যাচাইয়ের জন্য টিকিট ডাউনলোড

**1. Name and purpose.** Fill the device's local database with the valid ticket numbers of the assigned event/gate, so validation works without network.

**2. Trigger and actor.** Checker app, first sync after choosing an event (and the manual "sync" button on the scanner dashboard). Actor: gate checker.

**3. Business flow.**
1. After picking the event/gate the app performs a sync (F4.5).
2. The backend answer contains the **full ticket-number map** for that event/gate — this is the download.
3. The app writes the numbers into its local drift database and is ready to scan offline.
4. Whether the checker may keep an offline copy is controlled by the `IsDownloadEnabled` flag (F4.1), which admins can reset (F1.18 update-download-status; cleanup worker F5.15).

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | App → TicketChecker `POST /ticketchecker/api/v1/tickets/sync-tickets` | **[HTTP + user token]** | Empty/small scan map; response = authoritative full ticket map (below) |
| 2 | TicketChecker `TicketsManager` | — | On first call per event/gate it hydrates the Redis hash `ticket_checker_tickets:event_{eventLongId}_gate_{gateId}` from the Ticketing service (`GET /ticketing/api/v1/booking-order-ticket/ticket-numbers?eventId=…&levelIds=…`), under RedLock `ticket_checker_gate_{gateId}` |
| 3 | TicketChecker DB | **[Shared table]** | Reads `Events`, `TicketCheckerGates`, `BlockLevelEntryGates` mirrors to resolve the checker's gates |
| 4 | App | — | Stores ticket numbers in the local drift DB (`QrDao`); subsequent syncs only update counters |

**5. Components.** Checker app (drift DB); TicketChecker service (Redis + lock); Ticketing service (ticket numbers); tables — none written by this flow.

**6. API contracts.** Same endpoint as F4.5 — `POST /ticketchecker/api/v1/tickets/sync-tickets`, body `{"<ticketNumber>": 0}` or the pending scans; response is the full map:

```json
// 200
{
  "BCB-ODI2-GL12-A1": 0,
  "BCB-ODI2-GL12-A2": 0,
  "BCB-ODI2-GL12-A3": 1
}
```

(count = how many times that ticket has already been used across devices at this gate.)

**7. Data and side effects.** Redis hash `ticket_checker_tickets:event_…_gate_…` created on first sync; local DB rows on the device; nothing in PostgreSQL (scans reach the DB via F5.14, not here).

**8. Code references.**

| What | Where |
|---|---|
| Sync + local DB | `rvl-gobcb-checker-app/data/lib/repository/qr_repository_impl.dart`, `data/lib/local/drift_database/…` |
| Manager | `rvl-gobcb-backend/Services/TicketChecker/ETP.TicketChecker.Domain/Managers/TicketsManager.cs` |
| Ticket source | `rvl-gobcb-backend/Core/ETP.Core/ServiceClient/TicketingClient/TicketingClient.cs` |

**9. Handover notes.** ① The Redis flag `ticketCheckerDbSync` makes the sync endpoint refuse calls while the Admin drain job (F5.14) is writing scans to the DB — during that window the app gets an error and retries. ② Ticket numbers of the whole gate (potentially tens of thousands) travel in one JSON map — keep an eye on payload size for big galleries.

### F4.3 QR scan validation

> **Bangla name:** QR স্ক্যান করে টিকিট যাচাই

**1. Name and purpose.** The core gate operation: scan a ticket's QR code and decide — offline, on the device — whether the holder may enter.

**2. Trigger and actor.** Checker app → `/qrPage` (scanner). Actor: gate checker.

**3. Business flow.** For each scan the app shows one of five results with a distinct sound:
1. **Valid** — ticket belongs to this event and gate, signature OK, not used before (entry recorded locally).
2. **Already checked** — the ticket was used before (on this or another device).
3. **Wrong event** — the QR's event id does not match the assigned event.
4. **Wrong gate** — the ticket's entry gate is not among the assigned gates.
5. **Invalid** — signature verification failed or the ticket is not in the local list (e.g. offline-sold ticket → the app asks for confirmation, F6.13).

**4. Technical flow.**

| # | Step | What happens |
|---|---|---|
| 1 | Scan | Forked `flutter_barcode_scanner` plugin reads the QR string |
| 2 | Decode | `vds_qr_decoder.dart` base64-decodes (gzip-aware) the **VDS** (Visible Digital Seal) payload: `payload`, `signature`, `certSN`, `issuerDN` |
| 3 | Verify signature | **Offline** via Kotlin `MethodChannel('certificate/methods').verifyCertificate` (android `MainActivity.kt`) against the PEM certificate from the `VDS_CERTIFICATE` env value |
| 4 | Check rules | Event id and entry gate compared with `TicketCheckerEventInfo` (F4.1); usage counter compared with the local DB (F4.2) |
| 5 | Record | Valid scan stored locally with `isSynced: false`; pushed by F4.5 |

> 📦 **Explainer: VDS QR and why verification is offline**
> Each ticket PDF carries a QR code in the EU VDS format, produced when the TSP signs the PDF (F5.8). The QR contains the ticket data plus a cryptographic signature made with the TSP's certificate. The app ships the **public** certificate (`VDS_CERTIFICATE`); verifying the signature is pure math on the device, so no network is needed to prove a QR is genuine. Gate/event rules are then simple comparisons against local data.

**5. Components.** Checker app (scanner plugin, VDS decoder, MethodChannel, drift DB, `assets/sounds/`); TSP certificate chain (created in F5.8).

**6. API contracts.** None — this feature is entirely offline.

**7. Data and side effects.** Local drift DB rows (scan + `isManual=false`); nothing sent until F4.5.

**8. Code references.**

| What | Where |
|---|---|
| Scan + states | `rvl-gobcb-checker-app/lib/presentation/feature/qr_page/qr_page_view_model.dart`, `qr_page/state/qr_check_state.dart` |
| VDS decode | `rvl-gobcb-checker-app/data/lib/service/vds_qr_decoder.dart` |
| Signature verify (Android) | `rvl-gobcb-checker-app/android/app/src/main/kotlin/com/mahfuznow/hello_flutter/MainActivity.kt` |

**9. Handover notes.** ① Only the Android (Kotlin) side of `verifyCertificate` was found — iOS parity is `[UNCONFIRMED]`. ② Rotating the TSP signing certificate requires shipping an app update with a new `VDS_CERTIFICATE` (or a multi-cert mechanism — none found). ③ `MethodChannel` name is `certificate/methods`.

### F4.4 Manual entry

> **Bangla name:** ম্যানুয়াল এন্ট্রি (টিকিট নম্বর টাইপ করে যাচাই)

**1. Name and purpose.** Admit a holder when the QR cannot be read: the checker types the ticket number and the app validates it against the same local rules.

**2. Trigger and actor.** Checker app → `/manualEntry` (and `/manualTicketValidation`, see F4.6). Actor: gate checker.

**3. Business flow.**
1. The scanner dashboard offers Manual Entry.
2. The checker types the ticket number.
3. The app applies the same checks as a QR scan (used before / event / gate) against the local DB and shows the result.
4. A manual admission is marked `isManual` and synced as **−1** (F4.5) so the backend can distinguish it (manual-entry reports, F1.19).

**4. Technical flow.** Same as F4.3 steps 4–5, with the typed number instead of a decoded QR; no signature check (nothing to verify without the QR).

**5. Components.** Checker app (manual_entry feature, drift DB).

**6. API contracts.** None directly; the −1 marker travels in F4.5's map.

**7. Data and side effects.** Local DB row with `isManual = true`.

**8. Code references.** `rvl-gobcb-checker-app/lib/presentation/feature/manual_entry/…`, `…/manual_ticket_validation/…`.

**9. Handover notes.** ① A manual entry cannot verify authenticity — it only checks the number against the downloaded list; offline-sold tickets (F6.13) also surface here as confirmable. ② The signed map value −1 vs +1 is the only manual/QR distinction server-side.

### F4.5 Scan sync (90-second heartbeat)

> **Bangla name:** স্ক্যান সিঙ্ক (৯০ সেকেন্ডের হার্টবিট)

**1. Name and purpose.** Upload this device's new scans, download the authoritative usage counters of all devices at the gate, and refresh event validity — every 90 seconds or on demand.

**2. Trigger and actor.** Checker app background timer (90 s) and the manual sync button. Actor: gate checker.

**3. Business flow.**
1. Every 90 seconds the app sends its unsent scans (ticket number → +1 for QR, −1 for manual).
2. The backend adds them to the gate's counters in Redis and returns the **complete** counter map.
3. The app replaces its local counters — so scans made on other devices at the same gate appear as "already checked".
4. The app also re-fetches event info (F4.1) each cycle and falls back to the cached copy offline.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | App → TicketChecker `POST /ticketchecker/api/v1/tickets/sync-tickets` | **[HTTP + user token]** | Body: pending scan map; auth policy `ticket-checker` |
| 2 | `TicketsManager.UpdateAndSyncTickets` | — | Refuses while Redis flag `ticketCheckerDbSync` is set (F5.14 draining); takes RedLock `ticket_checker_gate_{gateId}` (expiry 2 s, wait 5 s) |
| 3 | Redis | — | `HashIncrementAsync` per ticket (+1 or −1) on `ticket_checker_tickets:event_…_gate_…`; also maintains the per-checker cache `ticket_checker_checked_tickets:{eventLongId}_{gateId}_{userSubId}` (`ConcurrentDictionary<string, TicketInfo>`) |
| 4 | Response | — | Full hash returned (`HashGetAllAsync<int>`); app marks local scans `isSynced` and updates counters |

**5. Components.** Checker app; TicketChecker service; Redis (counters, flag, lock); Ticketing service (only for first hydration, F4.2).

**6. API contracts.** `POST /ticketchecker/api/v1/tickets/sync-tickets` — auth: TicketChecker pool (policy `ticket-checker`). Body `Dictionary<string,int>`:

```json
{ "BCB-ODI2-GL12-A7": 1, "BCB-ODI2-GL12-A9": -1 }
```

Response: the full counter map (sample in F4.2). Main errors: standard envelope; app-handled messages include `user_disabled_for_this_gate` (checker disabled for the gate mid-shift) and `ticket_checker_event_not_found`.

**7. Data and side effects.** Redis hashes updated; scans reach PostgreSQL only through the Admin drain worker (F5.14) which persists them to `CheckedTickets`.

**8. Code references.**

| What | Where |
|---|---|
| Timer + sync | `rvl-gobcb-checker-app/lib/presentation/feature/qr_page/qr_page_view_model.dart` |
| API service | `rvl-gobcb-checker-app/data/lib/remote/api_service/ticket_api_service_impl.dart` |
| Controller | `rvl-gobcb-backend/Services/TicketChecker/ETP.TicketChecker.Service/Api/TicketController.cs` |
| Manager | `rvl-gobcb-backend/Services/TicketChecker/ETP.TicketChecker.Domain/Managers/TicketsManager.cs` |

**9. Handover notes.** ① Counters live in Redis only until F5.14 drains them — reports in the admin portal (F1.19) read the DB table, so scans appear in reports with up to ~30 minutes delay. ② If the app is offline longer than the lock/flag windows, nothing is lost: scans queue locally and sync later; only the "already checked on another device" freshness suffers.

### F4.6 Signature-only ticket validation

> **Bangla name:** শুধু সিগনেচার যাচাই (ম্যানুয়াল টিকিট ভ্যালিডেশন)

**1. Name and purpose.** Check that a QR is a genuine signed ticket **without** applying gate/event rules and without recording an entry — used when staff want to inspect a suspicious QR.

**2. Trigger and actor.** Checker app → `/manualTicketValidation`. Actor: gate checker.

**3. Business flow.** The checker scans (or types) the ticket; the app decodes the VDS QR and verifies the signature offline exactly as in F4.3, but reports only genuine/fake — it does not compare event or gate and does not increment any counter.

**4. Technical flow.** F4.3 steps 1–3 only; no local counter write, nothing synced.

**5–7. Components / contracts / side effects.** Same as F4.3 minus rules and counters; no API calls, no data written.

**8. Code references.** `rvl-gobcb-checker-app/lib/presentation/feature/manual_ticket_validation/…`.

**9. Handover notes.** The distinction between this screen and F4.4 is easy to miss: F4.4 admits a holder (records an entry), this screen only verifies authenticity.

## 2. User Web Portal

Features started by customers in the Angular user web portal (`rvl-gobcb-user-portal/ETP-Web`), User Cognito pool (or OneID SSO). The portal is bilingual (`/:lang/en|bn` routes, F2.13) and stateless except for auth/session (F6.10). Registration and login are cross-cutting (F6.6–F6.10).

### F2.1 Home page content

> **Bangla name:** হোম পেজের কনটেন্ট

**1. Name and purpose.** The landing page: hero banners, upcoming events, notices, footer/social links and the program list — all administered in the admin portal (F1.28, F1.30, F1.31).

**2. Trigger and actor.** User portal `/:lang/` (`HomeEventsPageComponent`). Actor: anonymous visitor (no login needed).

**3. Business flow.**
1. The visitor opens the site and sees published landing images (banners) per page segment (home, gallery page, contact page…).
2. Upcoming events appear as cards (cover image, name, venue, starting price, date).
3. General notices (if any) show a banner/section.
4. Header/footer links (social media, contact) come from settings.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Event `GET /event/api/v1/landing-page-image/public` | **[HTTP, no token]** | Published landing images (public read) |
| 2 | Portal → Event `GET /event/api/v1/events/list?numberOfEvents=N` | **[HTTP, no token]** | Upcoming events (Redis-cached list) |
| 3 | Portal → Admin `GET /admin/api/v1/general-notice/public` | **[HTTP, no token]** | Published notices |
| 4 | Portal → Event `GET /event/api/v1/header-footer` | **[HTTP, no token]** | Footer/header content |
| 5 | Portal → Event `GET /event/api/v1/events/programs` | **[HTTP, no token]** | Active programs for the menu |

**5. Components.** User portal (`event-api`, `common-api`, `footer-api`, `image-api` services); Event service (public mirrors + Redis cache); Admin service (notices, gallery).

**6. API contracts.** All four are anonymous GETs; shapes: `LandingPageImagePublic`, `EventDetails.Event` list (sample in F2.2), `GeneralNoticePublic`, `HeaderFooter`. Paged/none. Errors: standard envelope.

```json
// GET /event/api/v1/events/list?numberOfEvents=6   (item shape)
{
  "eventId": "b8e6a9d2-3f1c-4e7a-9d5f-6c2b1a8e0d34",
  "name": "2nd ODI — Bangladesh vs Sri Lanka",
  "bannerImage": "https://<cloudfront>/<key>.jpg",
  "startingPrice": 500.0,
  "eventStartDateTime": "2026-07-08T14:00:00Z",
  "eventEndDateTime": null,
  "ticketSellingStartDateTime": "2026-06-20T10:00:00Z",
  "ticketSellingStopDateTime": "2026-07-08T12:00:00Z",
  "venue": { "id": 2, "name": "Sher-e-Bangla National Cricket Stadium" },
  "eventSegments": [ { "name": "Match day", "team1": "…", "team2": "…" } ]
}
```

**7. Data and side effects.** Read-only; Redis caches on the Event service (short TTL; new banners appear after cache expiry).

**8. Code references.**

| What | Where |
|---|---|
| Home page | `rvl-gobcb-user-portal/ETP-Web/src/app/modules/featured/events/pages/home-events-page/home-events-page.component.ts` |
| API services | `…/modules/core/services/api/{event-api,common-api,footer-api,image-api}.service.ts` |
| Public controllers | `rvl-gobcb-backend/Services/Event/ETP.Event.Service/Api/{LandingPageImageController,EventsController,HeaderFooterController}.cs`, `…/Admin/ETP.Admin.Service/Api/GeneralNoticeController.cs` |

**9. Handover notes.** The portal deliberately reads catalog data from the **Event** service (public, cacheable) rather than Admin — Admin stays staff-facing.

### F2.2 Browse events and event details

> **Bangla name:** ইভেন্ট ব্রাউজ ও বিস্তারিত

**1. Name and purpose.** List all published events (filterable by program), and show one event's detail page with its venue, segments, prices and the entry point to buying.

**2. Trigger and actor.** Portal `/:lang/events` (`AllEventListPageComponent`) and `/:lang/events/:id` (`EventDetailPageComponent`). Actor: anonymous visitor; buying requires login.

**3. Business flow.**
1. The events page lists published events (cards) with a program filter.
2. Opening an event shows cover image, name, date window, venue, segments (teams), ticket-selling window and starting price.
3. The page loads the event's **venue details tree** (galleries → blocks → levels with prices, colors, gates) which powers the seat-selection dialog (F2.4).
4. "Buy" leads to seat selection and then booking (F2.4, F2.6).

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Event `GET /event/api/v1/events/list` (optionally `?programId=`) | **[HTTP, no token]** | Published events (Redis-cached) |
| 2 | Portal → Event `GET /event/api/v1/events/{eventId}` | **[HTTP, no token]** | Full `Event` model (below) |
| 3 | Portal → Event `GET /event/api/v1/events/venue-details/{eventId}` | **[HTTP, no token]** | `EventVenueDetailsTree` (F2.4) |
| 4 | Event service DB | **[Shared table]** | Reads Admin's `Events`/`EventSegments`/venue tables and Booking's `Capacities` mirror; computes `AvailabilityStatus`, `MinimumPrice` |

**5. Components.** User portal; Event service (Redis cache); shared tables; Admin (owner of the data, via F1.7).

**6. API contracts.** `GET /event/api/v1/events/{eventId}` — anonymous. Response = Event service `Event` model (`Services/Event/ETP.Event.Domain/Models/Event.cs`):

```json
{
  "id": 1042,
  "eventId": "b8e6a9d2-3f1c-4e7a-9d5f-6c2b1a8e0d34",
  "eventName": "2nd ODI — Bangladesh vs Sri Lanka",
  "programId": 7,
  "venueId": 2,
  "programName": "Bangladesh Tour of Sri Lanka 2026",
  "programLogo": "https://<cloudfront>/logo.png",
  "programShortName": "BAN in SL 2026",
  "bannerImage": "https://<cloudfront>/<key>.jpg",
  "eventStartDateTime": "2026-07-08T14:00:00Z",
  "eventEndDateTime": null,
  "ticketSellingStartDateTime": "2026-06-20T10:00:00Z",
  "ticketSellingStopDateTime": "2026-07-08T12:00:00Z",
  "ticketAvailabilityStartDateTime": "2026-06-25T10:00:00Z",
  "minimumPrice": 500.0,
  "availabilityStatus": "Available",
  "vat": 15.0,
  "isVatPercentage": true,
  "serviceCharge": 20.0,
  "isServiceChargePercentage": false,
  "allowableMaximumSeatPerOrder": 4,
  "allowableMaximumOrderPerUser": 2,
  "isVatInclusive": false,
  "isPublished": true,
  "isActive": true,
  "venue": { "…": "venue object" },
  "segments": [ { "…": "segment with teams" } ]
}
```

Other endpoints: `GET /event/api/v1/events/published/list`, `GET list?numberOfEvents&programId`, `GET client-filtered-list/{status}/{count}?programId=`, `GET events/programs`. Errors: standard envelope; unknown id → 404-shaped error via envelope.

**7. Data and side effects.** Read-only + Redis cache fill.

**8. Code references.**

| What | Where |
|---|---|
| Portal pages | `…/events/pages/all-event-list-page/…`, `…/event-detail-page/…` |
| API service | `…/modules/core/services/api/event-api.service.ts` |
| Controller | `rvl-gobcb-backend/Services/Event/ETP.Event.Service/Api/EventsController.cs` |
| Availability logic | `rvl-gobcb-backend/Services/Event/ETP.Event.Domain/Managers/EventManager.cs` |

**9. Handover notes.** ① The Event service has **no class-level `[Authorize]`** — published event data is public by design; nothing customer-private is served here. ② `for-ticketing` and `EventLongId/{id}` endpoints on the same controller are internal helpers for other services, not used by the portal.

### F2.3 Information pages (pricing, gallery, contact, policies)

> **Bangla name:** তথ্য-পেজ (টিকিট মূল্য, গ্যালারি, যোগাযোগ, নীতিমালা)

**1. Name and purpose.** Static/semi-static pages: ticket pricing per program/event, photo gallery, contact page, terms & conditions, privacy policy, FAQ, ICC code pages.

**2. Trigger and actor.** Portal routes `/:lang/ticket-pricing`, `/:lang/gallery`, `/:lang/contact`, `/:lang/terms`, `/:lang/policy`, `/:lang/faq`, `/:lang/icc-anti-racism-code`, `/:lang/icc-anti-discrimination-code`, `/:lang/message-sent`. Actor: anonymous.

**3. Business flow.**
1. **Ticket pricing** shows a program-wise matrix of galleries/levels and prices, maintained in the admin portal (F1.14).
2. **Gallery** shows gallery-page images configured under Media Configuration (F1.28).
3. **Contact** shows contact info from header/footer settings (F1.30); the contact form shows a "message sent" confirmation.
4. Terms/privacy/FAQ/ICC pages show fixed legal text.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Event `GET /event/api/v1/ticket-pricing/list` | **[HTTP, no token]** | Published pricing matrix (Redis-cached) |
| 2 | Portal → Event `GET /event/api/v1/ticket-pricing/program-pricing?programId&eventId` | **[HTTP, no token]** | Per-program/event breakdown |
| 3 | Portal → Event `GET /event/api/v1/landing-page-image/public` | **[HTTP, no token]** | Gallery-page images (filtered by segment type `Gallery_Page_Segment_*`) |
| 4 | Portal → Event `GET /event/api/v1/header-footer` | **[HTTP, no token]** | Contact details |
| 5 | terms/policy/faq | — | Static content in the portal bundle (see notes) |

**5. Components.** User portal; Event service; Admin service (content owner via F1.14/F1.28/F1.30).

**6. API contracts.**

```json
// GET /event/api/v1/ticket-pricing/list   (item shape: TicketPricingProgram)
{
  "id": 3,
  "ticketPricingId": 1,
  "programName": "Bangladesh Tour of Sri Lanka 2026",
  "venueName": "Sher-e-Bangla National Cricket Stadium",
  "isPublished": true,
  "attributes": [
    { "id": 11, "ticketPricingProgramId": 3, "attributeName": "Grandstand", "attributePrice": 500 },
    { "id": 12, "ticketPricingProgramId": 3, "attributeName": "Premium", "attributePrice": 1500 }
  ]
}
```

`program-pricing` returns `ProgramPricingResponse` (`{ programId, programName, programStartDate, events: [{ eventId, eventName, venueId, venueName, galleryName, ticketType, price }] }`). All anonymous GETs; standard errors.

**7. Data and side effects.** Read-only.

**8. Code references.**

| What | Where |
|---|---|
| Portal pages | `…/events/pages/…` (ticket-pricing, gallery, contact, terms, policy, faq components) |
| API services | `…/modules/core/services/api/{event-api,common-api,footer-api}.service.ts` |
| Controllers | `rvl-gobcb-backend/Services/Event/ETP.Event.Service/Api/TicketPricingController.cs`, `LandingPageImageController.cs`, `HeaderFooterController.cs` |

**9. Handover notes.** ① The admin portal's Content Editor screen contains Terms/FAQ/Privacy pages, but its service only calls the ticket-pricing and general-notice endpoints — the legal texts themselves live in the clients (portal i18n assets / app strings) `[UNCONFIRMED: exact source of truth for legal texts]`. ② The user app reads the same pricing endpoints (F3.3).

### F2.4 Seat selection

> **Bangla name:** আসন নির্বাচন

**1. Name and purpose.** Pick the gallery → block → level (and specific seats for seat-mapped levels) with live availability, within the per-order/per-user limits.

**2. Trigger and actor.** Portal event detail page → buy dialog / `stadium-seat` map. Actor: customer (User pool token needed for the seat-level availability call).

**3. Business flow.**
1. The customer opens the venue tree: galleries (e.g. Grandstand) → blocks → levels with price per seat and color.
2. For seat-mapped levels a stadium map shows individual seats; live availability comes from the backend (green/free, taken/locked).
3. The customer selects up to `allowableMaximumSeatPerOrder` seats (or a quantity for non-mapped levels).
4. Continuing opens the booking dialog (F2.6) with price, VAT and discount breakdown.

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal → Event `GET /event/api/v1/events/venue-details/{eventId}` | **[HTTP, no token]** | `EventVenueDetailsTree` (structure + prices; Redis-cached ~15 days) |
| 2 | Portal → Admin `GET /admin/api/v1/eventsVenueDetails/get-level/{eventId}/{levelId}` | **[HTTP + user token]** | `UserLevelWithGates` for the chosen level (price, gate names, sellable flags) |
| 3 | Portal → Booking `GET /booking/api/v1/capacity/level-user-portal-seats…` | **[HTTP + user token]** | Live seat list/status for the level (Redis-backed) |
| 4 | Portal → Booking `GET /booking/api/v1/capacity/level-live-capacity?eventId&galleryId&blockId&levelId` | **[HTTP, no token]** (no class auth) | Remaining count |
| 5 | Booking Redis | — | Reads live counters (`level_live*`, §0.8) maintained by F2.6/F5.1/F5.3 |

**5. Components.** User portal; Event + Admin + Booking services; Redis live counters; shared tables `Capacities`, `SeatReservations`, venue tables.

**6. API contracts.** `UserLevelWithGates` (`Event` service; same model served by Admin `get-level`):

```json
// GET /event/api/v1/events/get-level/{eventId}/{levelId}
{
  "venueId": 2,
  "venueName": "Sher-e-Bangla National Cricket Stadium",
  "galleryId": 12, "gallery": "Grandstand", "isGalleryActive": true, "isGallerySellable": true,
  "blockId": 7, "block": "Block B", "isBlockActive": true, "isBlockSellable": true,
  "levelId": 45, "level": "Level 1", "isLevelActive": true, "isLevelSellable": true,
  "pricePerSeat": 500.0,
  "entryGate": "Gate 3 — North", "entryGateId": 3,
  "miniGate": "M2",
  "ticketColor": "#1E7B4F"
}
```

Capacity endpoints return plain numbers/seat lists (e.g. `level-live-capacity` → `int`). Errors: standard envelope; expired token → 401 with re-login (F6.10).

**7. Data and side effects.** Read-only at this stage; seats become **locked** only in F2.6 (Redis locked-capacity keys).

**8. Code references.**

| What | Where |
|---|---|
| Buy dialog / seat map | `…/events/pages/event-detail-page/…`, `…/tickets/pages/stadium-seat-page/…`, resolver `venue-details.resolver.service.ts` |
| API services | `…/modules/core/services/api/{event-api,booking-api}.service.ts` |
| Controllers | `…/Event.Service/Api/EventsController.cs` (`venue-details`, `get-level`), `…/Admin.Service/Api/EventsVenueDetailsController.cs`, `…/Booking.Service/Api/CapacityController.cs` |

**9. Handover notes.** ① Two sources of truth meet here: the tree (structure, cached up to 15 days) and the live counters (seconds) — price changes (F1.9) can take as long as the cache TTL to appear. ② `CapacityController` has **no** `[Authorize]`; it is treated as internal/public by network placement (F6.18).

### F2.6 Booking order and online payment (DgePay)

> **Bangla name:** বুকিং অর্ডার ও অনলাইন পেমেন্ট (DgePay)

**1. Name and purpose.** A signed-in customer turns the selected seats/quantity into an order, is redirected to DgePay's hosted checkout, pays, and comes back; the backend independently verifies the payment and starts ticket generation.

**2. Trigger and actor.** Portal buy dialog → `complete-payment-modal.component.ts`. Actor: customer, User pool (policy `user`).

**3. Business flow.**
1. From the seat selection (F2.4) the customer confirms: seats or quantity, holder details (name/phone per ticket), optionally a promo code (F2.5); the dialog shows price, VAT, discount and total.
2. On confirm the portal redirects the browser to the DgePay checkout URL returned by the backend.
3. The customer pays on DgePay; DgePay redirects the browser back to the portal payment-result page.
4. The backend re-checks the transaction with DgePay (`check_transaction_status`) and marks the order **Paid**.
5. Ticket PDFs are produced asynchronously (F5.7/F5.8); the customer tracks status in My Tickets (F2.7).

**4. Technical flow.**

| # | From → To | Hop | What happens |
|---|---|---|---|
| 1 | Portal `booking-api.service.ts` → Booking `POST /booking/api/v1/user-booking-order` | **[HTTP + user token]** | JSON `UserBookingOrder`; Booking validates live capacity under a per-user RedLock (`user_booking:{userId}`), applies promo/system discount, computes VAT, creates a `UserBookingOrders` row (Pending) |
| 2 | Booking → DgePay `POST {BaseUrl}/payment_gateway/initiate_payment` | **[HTTP, static key]** (`PaymentSettings:DgePay`; AES/RSA-signed request, token cached in Redis) | Returns the gateway checkout URL |
| 3 | Booking → customer | — | `201` with `publicId` + `checkoutUrl`; portal does `window.location.href = checkoutUrl` |
| 4 | Browser ← DgePay redirect → Booking `GET /booking/api/v1/user-booking-order/dgepay/payment-status?data=…` | **[HTTP, no token]** (anonymous by design) | Booking calls DgePay `check_transaction_status`, maps status ("3"/"Success" → **Paid**), updates the order |
| 5 | On success Booking → SQS | **[SQS: OrderSuccess]** `LevelCapacityUpdate` (GroupId `{eventLongId}_{galleryId}_{blockId}_{levelId}`) and **[SQS: VatChallanProcessing]** `VatChallanProcessing` | Consumers: F5.1 (capacity) and F5.10 (VAT challan) |
| 6 | Booking → Ticketing `GET /ticketing/api/v1/booking-order-ticket/initiate?orderId={publicId}` | **[HTTP, no token]** (internal endpoint) | Starts blank-PDF generation → signing pipeline (F5.8) |
| 7 | Booking worker | **[Worker: 15 min]** | `InitiateUserTicketGenerationService` also picks up paid orders whose event's `TicketAvailabilityStartDateTime` has passed (F5.7) — the safety net for step 6 |

**5. Components.** User portal; Booking service; DgePay; SQS `OrderSuccess` + `VatChallanProcessing` queues; Redis (live capacity, locks, DgePay token cache); Aurora tables `UserBookingOrders`, `Capacities`, `SeatReservations`, `BookedUserRecords`, `PromoCodes`/`Discounts` mirrors; Ticketing (downstream).

**6. API contracts.**

**`POST /booking/api/v1/user-booking-order`** — auth: User pool (policy `user`). Request = `UserBookingOrder` (`Services/Booking/ETP.Booking.Domain/Models/UserBookingOrder.cs`):

```json
{
  "eventId": "b8e6a9d2-3f1c-4e7a-9d5f-6c2b1a8e0d34",
  "galleryId": 12,
  "blockId": 7,
  "levelId": 45,
  "numberOfSeats": 2,
  "hasSeats": true,
  "seats": "A1,A2",
  "pricePerSeat": 1500.0,
  "promoCode": "BCBWELCOME",
  "totalCharge": 3000.0,
  "vat": 450.0,
  "bookedUserDetails": [
    { "userName": "Rahim Uddin", "phoneNumber": "+8801712345678" }
  ]
}
```

`201` — `UserBookingOrderResponse` (`{ publicId, checkoutUrl }`):

```json
{
  "publicId": "7c9f2e64-51ab-4d3e-b1f0-9a8d6e5c4b21",
  "checkoutUrl": "https://<dgepay>/payment_gateway/checkout?txn=DPX88312"
}
```

**`GET /booking/api/v1/user-booking-order/dgepay/payment-status?data={encrypted}`** — anonymous; verifies with DgePay, updates the order, and issues a `302` redirect to the portal payment-result page (redirect target configured backend-side in secrets).

Main errors: `401` (missing/expired User token on POST), `400` envelope for seat-already-taken / capacity / promo-invalid business failures.

**7. Data and side effects.** `UserBookingOrders` insert + status updates (payment transaction id, `OneIdUserId`); Redis seat locks; SQS messages of step 5; DgePay-side payment; no email/push here (those fire after generation — F5.12).

**8. Code references.**

| What | Where |
|---|---|
| Portal caller | `rvl-gobcb-user-portal/ETP-Web/src/app/modules/core/services/api/booking-api.service.ts`; `complete-payment-modal.component.ts` |
| Controller | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/UserBookingOrderController.cs` |
| Manager | `…/ETP.Booking.Domain/Managers/UserBookingOrderManager.cs` (SQS publishes on the payment-success paths) |
| DgePay client | `…/ETP.Booking.Domain/Managers/DgePayPaymentManager.cs` |
| Workers | `…/ETP.Booking.Service/Workers/BackgroundServices/{LevelCapacityUpdateService,VatChallanProcessingService,InitiateUserTicketGenerationService}.cs` |

**9. Handover notes.** ① A test endpoint `GET …/payment-status-bypass?rawData=` skips DgePay verification and directly initiates tickets — confirm it is unreachable/disabled in production `[UNCONFIRMED]`. ② Full **SSLCommerz** endpoints (`payment-success|fail|cancel|ipn`, `payment-methods`) exist next to DgePay; the architecture doc names only DgePay — confirm which gateways are live `[UNCONFIRMED]`. ③ Payment truth is the server-side status check, not the redirect. ④ The per-user lock means one concurrent order attempt per customer; a stuck lock delays that user's next attempt until it expires.

<!-- 🔄 CONTINUE -->
