# GoBCB প্ল্যাটফর্ম — ফিচার ডকুমেন্টেশন (টেকনিক্যাল হ্যান্ডওভার)

> **English version:** অভিন্ন ইংরেজি সংস্করণ পাশের ফাইলে — `gobcb-feature-documentation-en.md`।
> **Hosting architecture:** `docs/architecture/gobcb-aws-architecture.md` (পুরো ডকুমেন্টে "architecture doc" নামে উল্লেখিত)।

**পড়ার বিধি:** এই ডকুমেন্ট বাংলায় লেখা, তবে টেকনিক্যাল টার্ম — service নাম, endpoint path, AWS service নাম, code identifier, config key — সব **ইংরেজিতে** রাখা হয়েছে, যাতরা কোডের সাথে সরাসরি মেলানো যায়। ইংরেজি সংস্করণের সাথে section-কাঠামো ১:1 identical।

## 0. Orientation (সূচনা)

### 0.1 উদ্দেশ্য, পাঠক ও পড়ার নিয়ম

**উদ্দেশ্য।** GoBCB (rvl-etp) ইভেন্ট ও টিকিটিং প্ল্যাটফর্মের প্রতিটি business feature-এর জন্য এই ডকুমেন্ট দেখায় — কোন screen থেকে শুরু হয়, কোন endpoint ও service হ্যান্ডেল করে, কোন queue ও worker পরে কাজটি এগিয়ে নেয়, কোন table, Redis key ও file ছোঁয়, কোন external system কল হয়, আর কোড কোথায়।

**পাঠক।** RVL-এর নতুন tech lead: অভিজ্ঞ .NET developer, যিনি আগে কখনো **microservices-ভিত্তিক সিস্টেমে কাজ করেননি**। Microservice ধারণাগুলো একবার, এই Part 0-তে, 📦 **explainer box**-এ ব্যাখ্যা করা হয়েছে; প্রতিটি feature সেগুলোর রেফারেন্স দেয়, পুনরাবৃত্তি করে না।

**উৎস।** BS23-এর delivery পক্ষ থেকে handover-এর জন্য লেখা, শুধু দুটি উৎস থেকে:

1. পাঁচটি repository-র source code (read-only), নিচের commit-গুলোতে;
2. AWS-এ প্ল্যাটফর্ম কীভাবে host করা তার বিবরণ — `docs/architecture/gobcb-aws-architecture.md`।

এখানে কিছু বানানো হয়নি। কোথাও কোড থেকে উত্তর মেলেনি, সেখানে তা স্পষ্টভাবে বলা হয়েছে এবং `[UNCONFIRMED]` মার্কার দেওয়া হয়েছে — ডকুমেন্টের শেষে **Open queries** section-এ সেগুলো একত্রিত, প্রতিটি প্রশ্ন এমনভাবে লেখা যেন BS23-কে as-is পাঠানো যায়।

### Evidence baseline

| Repository (submodule) | Commit |
|---|---|
| `rvl-gobcb-backend` | `430ec16d7554254ff4f6adfa21f9c0c10d3234b2` |
| `rvl-gobcb-admin-portal` | `f62d2756bd9bbd4bfaa92585ae3f999d9f4c213f` |
| `rvl-gobcb-user-portal` | `36aaf58c0dae070da9f958da09451d33e6e47c73` |
| `rvl-gobcb-user-app` | `365b8bee71454d94747b75bef7cb07e8b47b6f8a` |
| `rvl-gobcb-checker-app` | `e919c54dad40a33aecc9922a68637a4a887513e6` |

Code reference-এর line number (`File.cs:123`) এই commit-গুলোর জন্য বৈধ। Submodule এগিয়ে গেলে আপনার নির্ভরশীল feature-গুলোর reference আবার যাচাই করুন।

### Feature template

Feature-গুলো সাজানো **কী শুরু করে তার ভিত্তিতে**: admin portal-এ staff (F1.x), web portal-এ customer (F2.x) বা app-এ (F3.x), checker app-এ gate staff (F4.x), timer/queue-তে সিস্টেম নিজে (F5.x), আর অনেক feature-এর সাথে সম্পর্কিত বিষয় (F6.x — authentication/authorization সহ)। প্রতিটি feature একই নয়টি section মেনে চলে:

| # | Section | কী জানায় |
|---|---|---|
| 1 | Name and purpose | feature-টি কী কাজে, business ভাষায় (ইংরেজি ও বাংলা নাম) |
| 2 | Trigger and actor | কে শুরু করে, কোন client-screen থেকে, কোন Cognito pool, role, program scope দিয়ে |
| 3 | Business flow | business user যে ধাপগুলো দেখে |
| 4 | Technical flow | একই ধাপগুলো component-গুলোর মধ্যে hop হিসেবে; প্রতিটি hop tagged (নিচে) |
| 5 | Components | client, service, queue, worker, table, Redis key, bucket, external system |
| 6 | API contracts | feature-টি যে endpoint গুলো ব্যবহার করে (method, full path, auth, DTO, মূল error); মূল endpoint-এর জন্য পূর্ণ JSON sample |
| 7 | Data and side effects | কী লেখা হয়: row, queue message, file, email, push, cache entry |
| 8 | Code references | কোথা থেকে পড়া শুরু করবেন: controller, manager, worker, client file |
| 9 | Handover notes | সহজেই চোখ এড়ানো আচরণ, কোডে পাওয়া risk, `[UNCONFIRMED]` item |

**Section 4-এ ব্যবহৃত hop tag:**

| Tag | অর্থ |
|---|---|
| **[HTTP + user token]** | sync HTTP call যা caller-এর Cognito access token বহন করে (client থেকে, বা কোনো service forward করে) |
| **[HTTP, no token]** | token ছাড়া sync HTTP call — সাধারণত background worker থেকে `[Authorize]`-নেই এমন endpoint-এ |
| **[HTTP, static key]** | configuration-এর key দিয়ে external/internal system-এ sync HTTP call |
| **[SQS: Key]** | `AWS:Queue:Key` হিসেবে configured queue-তে message রাখা বা পড়া |
| **[Worker: interval, lock]** | কোনো service-এর background worker, তার hard-coded interval ও Redis lock-সহ |
| **[SignalR]** | SignalR hub দিয়ে WebSocket message |
| **[Shared table]** | এক service অন্য service-এর লেখা table পড়ে (একই database, §0.8 দ্রষ্টব্য) |

**Path** লেখা হয়েছে client যেভাবে ডাকে সেভাবে পূর্ণরূপে, যেমন `/booking/api/v1/user-booking-order`; প্রথম segment-টি service prefix (§0.6)।

### 0.2 এক অনুচ্ছেদে প্ল্যাটফর্ম

GoBCB বাংলাদেশ ক্রিকেট বোর্ডের ইভেন্টের টিকিট বিক্রি ও যাচাই করে। Staff-রা **admin portal**-এ সাজান **program** (সিরিজ/টুর্নামেন্ট), **venue** (স্টেডিয়াম → gallery → block → level), **event** (ম্যাচ) — দাম ও capacity-সহ, সাথে promotion ও ticket layout। Customer-রা **user web portal** বা **user app**-এ ব্রাউজ ও কেনেন, **DgePay** দিয়ে পরিশোধ করেন, আর QR-সহ ডিজিটালি signed PDF টিকিট পান। Gate-এর staff **checker app** দিয়ে offline QR স্ক্যান করেন। Backend হলো একই repository-র একগুচ্ছ ASP.NET Core 8 web API ("service") — Amazon EKS-এ API Gateway-এর পেছনে চলে (architecture doc §0–§4)।

### 0.3 Repository

এই workspace (`rvl-etp-workspace`) পাঁচটি git submodule পরিচালনা করে:

| Repo | কী |
|---|---|
| `rvl-gobcb-backend` | .NET 8 backend: ১১টি service project (৯টি active + ২টি stub) + shared `Core/` library |
| `rvl-gobcb-admin-portal` | Angular admin portal (staff) |
| `rvl-gobcb-user-portal` | Angular user web portal (app `ETP-Web/` subfolder-এ) |
| `rvl-gobcb-user-app` | End user-দের Flutter app (clean architecture: `presentation/`, `domain/`, `data/` package) |
| `rvl-gobcb-checker-app` | Gate checker-দের Flutter app |

### 0.4 Backend service

সব service `rvl-gobcb-backend/Services/<Name>/`-এ, প্রতিটি ভাগ করা `ETP.<Name>.Service` (controller, `Program.cs`, worker), `.Domain` (manager = business logic), `.Storage` (EF Core `DbContext`, repository) এবং কিছু ক্ষেত্রে `.Client` (অন্য service-এর ব্যবহারের typed HTTP client) ও `.Integration`। Shared code `rvl-gobcb-backend/Core/`-এ (`ETP.Core`, `ETP.Core.Web`, `ETP.Core.EntityFramework`, `ETP.Core.BlobStorage`, `ETP.Core.Storage`, `ETP.Core.Email`, `ETP.Core.SMS`, `ETP.Core.EventBus`)।

| Service | Path prefix | Local port | কী করে (controller ও worker থেকে) | DB connection key | Background worker |
|---|---|---|---|---|---|
| Admin | `/admin` | 5101 | Master data ও back office: program, venue, event, settings, promo code, discount, ticket layout, staff user (Cognito), gate assignment, raffle, notice, site content, activity log, dashboard | `ConnectionStrings:Admin` | `CheckedTicketService`, `PromoCodeStatusUpdateService`, `SystemDiscountStatusUpdateService`, `GateCheckerDownloadStatusCleanupService` |
| Booking | `/booking` | 5102 | Capacity ও seat, booking order, payment (DgePay), promo code apply, seat reservation, capacity adjustment, sales report, VAT challan | `ConnectionStrings:Booking` | `BookingStatusUpdateService`, `InitiateUserTicketGenerationService`, `LevelCapacityUpdateService`, `RefreshLockedCapacityService`, `EventLiveCapacityUpdateService`, `VatChallanProcessingService` |
| Event | `/event` | 5103 | Portal/app-এর জন্য program, event, venue detail, landing image, header/footer ও ticket pricing-এর public, read-only view | `ConnectionStrings:Event` | নেই |
| Ticketing | `/ticketing` | 5108 | টিকিট: generation, signing (TSP), PDF, download, share, invoice, reserved ticket, OneID sync, offline-sold ticket | `ConnectionStrings:Booking` (লক্ষ্য করুন — §0.8) | `TicketGenerationService` |
| TicketChecker | `/ticketchecker` | 5107 | Checker app-এর sync endpoint (scan যায়, scan আসে) | `ConnectionStrings:TicketChecker` | নেই |
| UserIssue | `/userissue` | 5110 | Customer issue ও support chat; SignalR hub `/userissue/chathub` host করে | `ConnectionStrings:UserIssue` | নেই |
| PushNotification | `/pushnotification` | 5105 | Device token ও push send API (queue-তে লেখে) | `ConnectionStrings:PushNotification` | নেই |
| Scheduler | `/scheduler` | 5106 | শুধু worker: Firebase-এ push delivery, payment revalidation, ticket-generated notice, capacity reconcile, device-token cleanup | নেই | `FirebaseNotificationService`, `PendingOrFailedBookingStatusUpdateService`, `SendNotificationAfterGeneratedTicketService`, `CapacityUpdateService`, `DeviceTokenCleanupService` |
| Utility | `/utility` | 5111 | শুধু worker: reserved ticket merge/zip | নেই | `TicketProcessingService` |
| Platform | `/platform` | 5104 | **Stub** — শুধু Visual Studio template-এর `WeatherForecastController`; production-এ ব্যবহৃত নয় | নেই | নেই |
| UserAuth | `/userauth` | 5109 | **Stub** — আসল controller নেই; client-রা `AUTH_API_BASE_URL` / `services.identity`-এ যে identity API ডাকে সেটি এই project নয় (Open queries দ্রষ্টব্য) | নেই | নেই |

উৎস: `Services/*/ETP.*.Service/Program.cs` ও `Configuration(s)/DependencyConfig.cs`, `Services/*/ETP.*.Service/appsettings.json` (`Application:ServiceName` = path prefix; UserIssue-এর `appsettings.json` commit করা নেই — তার prefix `userissue` hub mapping ও client থেকে এসেছে)। Local port `aspire/README.md` থেকে। `Application:ServiceName` মান TicketChecker-এ `ticketChecker` (camelCase), PushNotification-এ `PushNotification` (capital) — ASP.NET Core routing case-insensitive, client-রা ছোট হাতের রূপ ব্যবহার করে। Local dev-এ একই service .NET Aspire (`aspire/Etp.AppHost`) বা Docker-এ চলে।

> 📦 **Explainer: এই codebase-এ microservices (৩০ সেকেন্ডে)**
> Monolith মানে এক process, এক database। এখানে উপরের টেবিলের প্রতিটি row আলাদা **deployable ASP.NET Core app** — নিজস্ব controller, নিজস্ব EF Core `DbContext` ও নিজস্ব background worker-সহ, সব Amazon EKS-এ pod হিসেবে deploy। এরা শুধু HTTP ও SQS message-এ যোগাযোগ করে (§0.8) — runtime-এ compile-করা `Core/` library ছাড়া কোনো in-process shared code নেই। কোডের ভেতরে কিছু "route" হয় না: URL-এর প্রথম path segment ঠিক করে কোন service উত্তর দেবে (পরের box)।

### 0.5 Client

| Client | Repository | Tech | লগইন হয় | কাদের ডাকে |
|---|---|---|---|---|
| Admin portal | `rvl-gobcb-admin-portal` | Angular 18 | Admin pool (Serverless API-র SMS OTP-র পরে — F6.1) | Admin, Booking, Ticketing, UserIssue; OTP-র জন্য Serverless API |
| User web portal | `rvl-gobcb-user-portal/ETP-Web` | Angular 19 | User pool, বা Cognito-র মাধ্যমে OneID (F6.8) | Event, Booking, Ticketing, Admin (public endpoint), UserIssue; identity API |
| User app | `rvl-gobcb-user-app` | Flutter | User pool, বা Cognito-র মাধ্যমে OneID (F6.8) | Event, Booking, Ticketing, UserIssue, PushNotification, Admin; identity API |
| Checker app | `rvl-gobcb-checker-app` | Flutter | TicketChecker pool | Admin (`ticket-checker-gate/event-info`), TicketChecker (`tickets/sync-tickets`); app version-এর জন্য identity API |

**Identity API** (`services.identity` portal-এ, app-এ `AUTH_API_BASE_URL`) customer registration, OTP, profile ও app version সামলায়। এর source **পাঁচটি repository-র কোনোটিতেই নেই** `[UNCONFIRMED]` — Open queries দ্রষ্টব্য।

### 0.6 একটি request service পর্যন্ত কীভাবে পৌঁছায়

```mermaid
flowchart LR
  C["Client<br/>portal or app"] -->|"HTTPS + Bearer token"| R53["Route 53"] --> APIGW["API Gateway"] --> NLB["Network Load Balancer"]
  NLB --> ING["nginx ingress<br/>class nginx-second<br/>routes by path prefix"]
  ING -->|"/admin/..."| ADM["Admin pod"]
  ING -->|"/booking/..."| BKG["Booking pod"]
  ING -->|"/event, /ticketing, /ticketchecker,<br/>/scheduler, /userissue, /pushnotification"| OTH["other pods"]
  C -.->|"WebSocket, token in query string"| CHAT["chat.gobcbticket.com.bd<br/>(separate public ingress)"] -.-> UI["UserIssue pod<br/>/userissue/chathub"]
```

ছবির hosting অংশ (API Gateway, NLB, ingress) architecture doc §1 ও §4.1 থেকে। API Gateway নিজেও কি token validate করে তা reported-but-unverified (architecture Q1/Q1b)। Service-গুলো সবসময় নিজেরাই token validate করে (F6.14)।

> 📦 **Explainer: path-prefix routing**
> Monolith-এ সব controller এক host-এর নিচে। এখানে প্রতিটি service আলাদা process, কিন্তু client এখনো **একটাই API host** ব্যবহার করে। URL-এর প্রথম path segment ঠিক করে কোন service request পাবে: `/booking/api/v1/user-booking-order` যাবে Booking-কে, `/event/api/v1/events/list` Event-কে।
>
> দুটি জিনিস এটি সম্ভব করে:
> 1. **কোডে**, `Core/ETP.Core/Conventions/GlobalRoutePrefixConvention.cs` প্রতিটি controller route-এর আগে `Application:ServiceName` বসায় (প্রতিটি `Program.cs`-এ registered)। তাই Booking controller-এর `[Route("api/v1/user-booking-order")]` আসলে `/booking/api/v1/user-booking-order`-এ serve হয় — service-কে তার নিজের port-এ সরাসরি ডাকলেও।
> 2. **Cluster-এ**, প্রতি service-এর একটি nginx ingress `/<prefix>/...` অপরিবর্তিত রেখে সেই service-এ forward করে (architecture doc §4.1)।
>
> আপনার জন্য ফল: service-কে locally ডাকলে (`http://localhost:5102`) prefix দিতেই হবে: `http://localhost:5102/booking/api/v1/...`। Swagger পাবেন `/<prefix>/swagger`-এ (যেমন `/booking/swagger`)।

### 0.7 Request ও response-এর নিয়ম

| বিষয় | কোড যা করে | উৎস |
|---|---|---|
| JSON property নাম | সব service-এ camelCase। Booking, Event, Ticketing, TicketChecker, Scheduler, Utility, PushNotification, Platform, UserAuth `PropertyNamingPolicy = CamelCase` স্পষ্টভাবে সেট করে; Admin ও UserIssue ASP.NET Core default ব্যবহার করে — যেটাও camelCase | `Services/*/ETP.*.Service/Program.cs` (`AddJsonOptions`) |
| Enum | `AddJsonOptions` ব্যবহারকারী service-গুলোতে string (`JsonStringEnumConverter`); Admin ও UserIssue-তে (converter register করে না) **সংখ্যা** | একই |
| Null | `AddJsonOptions` ব্যবহারকারী service-গুলোতে response থেকে বাদ (`WhenWritingNull`); Admin ও UserIssue-তে থাকে | একই |
| Error | `ErrorResponseExceptionFilter` exception-কে `ProblemDetails`-স্টাইল body-তে রূপ দেয় (নিচে) | `Core/ETP.Core.Web/Filters/ErrorResponseExceptionFilter.cs` |
| Pagination | Paged endpoint `PagedList` object ফেরায়: `{ "items": [ … ], "totalCount": 123 }`। (array body + `X-Total-Count` header-এর helper `PagedOkResult` Core-এ আছে, কিন্তু **কোনো controller তা ব্যবহার করে না**) | `Core/ETP.Core/Collections/PagedList.cs`, `Core/ETP.Core.Web/Results/PagedOkResult.cs` (dead code) |
| Id | বেশিরভাগ table-এ `long Id`। অনেকে সাথে public string/Guid id রাখে (যেমন `Event.EventId`, order-এর `PublicId`), endpoint একটিকে বা অন্যটিকে নেয় — এ কারণেই `events/{eventId}` আর `events/EventLongId/{id}`-এর মতো জোড়া আছে | `Services/Admin/ETP.Admin.Storage/Models/Event.cs` |
| সময় | Server-side comparison-এ `DateTime.UtcNow` | যেমন `UserBookingOrderManager.cs` |

**Error response।** Controller throw করে; filter exception-এর ধরন অনুযায়ী status code ও body দেয়:

| Exception | Status | Body |
|---|---|---|
| `ArgumentException` (subclass-সহ) | 400 | `{ "status": 400, "title": "<exception message>" }` |
| `ApiException` | 400 | exception-এর নিজের `Details` (`ProblemDetails`) |
| `UnauthorizedAccessException` | 403 | `{ "status": 403, "title": "Unauthorized access", "detail": "<message>" }` |
| অন্য যেকোনো | 500 | `{ "status": 500, "title": "An unexpected error occurred." }` (Development-এ আসল message) |

Development environment-এ `stackTrace` field যোগ হয়। Authentication failure (token নেই/invalid) filter পর্যন্ত পৌঁছায় না: JWT handler **401** দেয় খালি body-তে; ভুল pool বা role-এর বৈধ token পেলে **403** (F6.14)। দুটি quirk জেনে রাখুন: `ApiException` ভেতরে ভিন্ন status থাকলেও সবসময় **400**-এ যায়, আর কিছু Admin manager validation-এ ব্যবহৃত `BadHttpRequestException` (যেমন "Name must not exceed 60 characters.") default branch-এ পড়ে **500** হয়ে যায়। সাধারণ business ব্যর্থতা (`seat_limit_exceeded`, `no_seats_available`, `Invalid promo code…`) `ArgumentException` হিসেবে throw হয় → **400**।

```json
{
  "status": 400,
  "title": "Invalid promo code. Please enter a valid code."
}
```

### 0.8 মূল ধারণা (explainer)

> 📦 **Explainer: token forwarding (এক service কীভাবে user-এর জন্য আরেক service কল করে)**
> Customer-এর request Booking-এ পৌঁছেছে, আর Booking-এর Event-এর data দরকার — Booking তখন Event-কে HTTP কল দেয়। এই codebase-এ সেই কল **customer-এর নিজের Cognito access token** বহন করে, কোনো service identity নয়।
> - প্রতিটি service typed `HttpClient` register করে (যেমন `services.AddHttpClient<IEventClient, EventClient>`, base URL `Services:<Name>` থেকে — প্রতিটি `Configurations/DependencyConfig.cs`-এ)।
> - Client pipeline-এ `DelegatedBearerAuthenticationHandler` থাকে (`Core/ETP.Core.Web/Security/DelegatedBearerAuthenticationHandler.cs`)। সে JWT handler বর্তমান user-এর claim-এ রাখা access token (`OnTokenValidated`, `Core/ETP.Core/Configuration/DefaultAuthenticationConfig.cs`) পড়ে outgoing request-এ `Authorization: Bearer` হিসেবে বসায়।
> - Downstream service সেই token **নিজের policy দিয়ে আবার** validate করে। Customer থাকা অবস্থায় Booking যদি Admin-pool-দাবি করা endpoint কল করে, downstream call 401/403-এ ব্যর্থ হবে।
> - Retry: বেশিরভাগ client ৩ বার exponential backoff-সহ retry করে (Polly)।
> - **User নেই মানে token নেই।** Background worker-এ HTTP request থাকে না, তাই handler কিছু পায় না এবং কিছু পাঠায় না। এ কারণেই worker-দের ডাকা endpoint-গুলোতে `[Authorize]` নেই (F6.18)।
>
> Hop tag: **[HTTP + user token]** ও **[HTTP, no token]**। বিস্তারিত: F6.19।

> 📦 **Explainer: queue-driven processing (SQS)**
> কিছু কাজ user-এর request-এর ভেতরে করার মতো দ্রুত বা নিরাপদ নয়: TSP দিয়ে টিকিট sign, শত শত PDF merge, NBR-এ VAT record, push message, capacity recompute। Request **একটি message publish করে** Amazon SQS queue-তে আর ফিরে আসে; কোনো এক service-এর **worker** পরে queue পড়ে কাজটি করে।
> - Publishing: `Core/ETP.Core/Queue/Services/SqsPublisher.cs` queue-এর **নাম** থেকে (configured `AWS:Queue:<Key>`; মান SSM/user-secrets-এ) URL বের করে, message JSON serialize করে পাঠায়। Queue-এর নাম `fifo`-তে শেষ হলে `MessageGroupId` ও `MessageDeduplicationId`-ও সেট করে।
> - Consuming: একটি `BackgroundService` loop করে, `ReceiveMessageAsync` ডাকে, প্রসেস করে, আর **সফল হলেই message delete করে**। ব্যর্থ message আবার visible হয় এবং retry হয় (কোডের মন্তব্যে dead-letter queue-এর কথা; তার configuration repo-তে নেই `[UNCONFIRMED]`)।
> - Message-এ শুধু business id থাকে। ভেতরে user token নেই, sender যাচাই নেই: queue-তে SendMessage-এর IAM permission থাকা যে কেউ কাজ enqueue করতে পারে (architecture doc §2.3 C)।
> - MassTransit (`Core/ETP.Core.EventBus`) কয়েকটি service-এ registered, কিন্তু কোনো consumer/publisher তা ব্যবহার করে না (dead code)।
>
> Queue ক্যাটালগ (config key → message → producer → consumer):
>
> | `AWS:Queue:` key | Message DTO | Published by | Consumed by | কাজ |
> |---|---|---|---|---|
> | `OrderSuccess` | `LevelCapacityUpdate` | Booking (`UserBookingOrderManager`, `CapacityManager`) | Booking `LevelCapacityUpdateService` | booked/released seat কে level capacity-তে প্রয়োগ (F5.1) |
> | `EventCapacity` | `EventLiveCapacityUpdate` | Booking (`CapacityManager`) | Booking `EventLiveCapacityUpdateService` | event live capacity recompute (F5.2) |
> | `TicketSigning` | `SignedTicketGeneration` | Ticketing (`TicketManager`) | Ticketing `TicketGenerationService` | TSP দিয়ে টিকিট PDF sign (F5.8) |
> | `TicketProcessing` | `TicketProcessingRequest` (Merge/Zip) | Ticketing (`TicketManager`) | Utility `TicketProcessingService` | reserved টিকিট merge/zip (F5.9) |
> | `VatChallanProcessing` | `VatChallanProcessing` | Booking (`UserBookingOrderManager`) | Booking `VatChallanProcessingService` | NBR-এ VAT record (F5.10) |
> | `FirebaseNotification` | `FirebaseNotificationRequest` | PushNotification (`NotificationManager`) | Scheduler `FirebaseNotificationService` | FCM দিয়ে push delivery (F5.11) |
>
> Event service `AWS:Queue:FirebaseNotification` register করে কিন্তু কখনো publish/consume করে না (dead config)। Physical queue নাম secret মান, তাই কোনো queue FIFO কিনা repo থেকে বোঝা যায় না `[UNCONFIRMED]`।

> 📦 **Explainer: background worker (service-এর ভেতরের timer)**
> HTTP request-এর পাশাপাশি কয়েকটি service **hosted service** (`BackgroundService`) timer-এ চালায় — `services.AddHostedService<...>()` দিয়ে registered। প্যাটার্ন সবখানে একই (উদাহরণ: `Services/Admin/ETP.Admin.Service/Workers/BackgroundServices/CheckedTicketService.cs`):
> 1. start-up-এর প্রায় এক মিনিট পর;
> 2. চিরকাল loop: Redis lock নেওয়ার চেষ্টা, পেলে একটি DI scope খুলে **TaskManager** (`Workers/TaskManagers/*`) চালায় — আসল logic সেখানে;
> 3. **hard-coded** interval-এ ঘুমায় (৩০ সেকেন্ড থেকে ১ দিন), error-এর পরে বেশি।
>
> Interval-গুলো কোডের ধ্রুবক, configuration নয়। Service-এর প্রতিটি replica (pod) একই worker চালায় — এ কারণেই lock দরকার (পরের box)। Hop tag: **[Worker: interval, lock]**। প্রতিটি worker-এর বিবরণ Part 5-এ।

> 📦 **Explainer: distributed lock (RedLock)**
> Production-এ প্রতিটি service একাধিক pod-এ চলতে পারে। Coordinat‌ion ছাড়া প্রতিটি pod-এর worker একই order একসাথে প্রসেস করত। কোড Redis-এ **RedLock** (`RedLockNet`) ব্যবহার করে: job চালানোর আগে worker নাম-দেওয়া lock চায় (যেমন `checked_ticket`, ২০ মিনিট expiry)। যে pod পায় শুধু সে কাজ করে; বাকিরা cycle skip করে আর log করে `Could NOT acquire lock ... Skipping this cycle` (স্বাভাবিক বার্তা, locally-ও দেখা যায়)।
>
> একই mechanism business operation-ও রক্ষা করে যেগুলো একসাথে চলা চলবে না — যেমন প্রতি customer একবারে একটি booking (`user_booking:{userId}`, `UserBookingOrderManager.cs`) এবং level-প্রতি capacity change।
>
> Setup: `Core/ETP.Core/Configuration/DistributedLockConfig.cs` (key `DistributedLock:Redis:*`)। Lock-এর নাম ও expiry তালিকা F6.25-এ।

> 📦 **Explainer: একটাই database, শেয়ার্ড table ও read model**
> পাঠ্যবইয়ের microservice-এর নিজস্ব ব্যক্তিগত database থাকে। এই codebase সেভাবে চলে না:
> - প্রতিটি `DbContext` **একই schema `etp`** ব্যবহার করে (প্রতিটি `*DbContext.cs`-এ `DefaultSchema = "etp"`), আর প্রতিটি service-এর নিজের connection-string key (`ConnectionStrings:Admin`, `:Booking`, …)। Ticketing তো `ConnectionStrings:Booking`-ই ব্যবহার করে। Locally সব key এক database-এর দিকে যায় (`scripts/user-secrets.example.json`)।
> - যে service-এর migration কোনো table বানায়, table-টির **মালিক** সে। অন্য service-গুলো একই table নিজেদের `DbContext`-এ `ExcludeFromMigrations` দিয়ে map করে সরাসরি পড়ে (কখনো লেখে)। উদাহরণ: Booking অন্যের `PromoCodes`, `Discounts`, `EventVenueDetails`, `Events` mirror করে (`Services/Booking/ETP.Booking.Storage/DbContexts/BookingDbContext.cs`)।
> - **Event** service প্রায় কিছুরই মালিক নয়: সে Admin ও Booking-এর table-গুলোর উপর public, read-only view (`Services/Event/ETP.Event.Storage/DbContexts/EventDbContext.cs`)।
>
> আপনার জন্য অর্থ: Admin-এ কোনো column বদলালে compile আলাদা হলেও runtime-এ Booking, Ticketing বা Event ভেঙে যেতে পারে। কোনো table বদলানোর আগে সব `*DbContext.cs`-এ তার নাম খুঁজুন। Handover brief-এ বলা হয়েছিল "one schema per service"; কোড বলছে সবার জন্য একটাই schema। Production-এর প্রকৃত বিন্যাস অজানা `[UNCONFIRMED]` — Open queries দ্রষ্টব্য।
>
> Hop tag: **[Shared table]**।

> 📦 **Explainer: live seat counter হিসেবে Redis**
> বিক্রি চলাকালে seat availability প্রতি সেকেন্ডে বদলায়, তাই Booking **live counter রাখে Redis-এ** (key family যেমন `level_live`, `level_locked`, `event_live`, `level_live_seats`; constant `Core/ETP.Core/Constant/AppConstant.cs`) আর database-কে ধীর, durable কপি হিসেবে ব্যবহার করে। Order প্রথমে Redis-এ capacity lock করে; queue worker (F5.1, F5.2) ও timer (F5.3) database ও Redis-কে মিলিয়ে রাখে। Checker app-এর gate-scan counter-ও একই ভাবে চলে (F4.5, F5.14)।
>
> ফল: বিক্রির মধ্যে Redis flush হলে live সংখ্যা পরের worker cycle-এ database থেকে আবার তৈরি হয়। বিস্তারিত: F6.25।

### 0.9 External system

| System | কী কাজে | কোথা থেকে ডাকে | Feature |
|---|---|---|---|
| DgePay | Online card/payment-gateway checkout | Booking | F2.6, F3.5, F5.5 |
| SSLCommerz | দ্বিতীয় payment gateway (কোড আছে) | Booking | live কিনা `[UNCONFIRMED]` — Open queries |
| NBR OpenAPI | VAT challan (VAT record, challan download) | Booking worker | F5.10 |
| OneID Wallet | SSO login (Cognito-তে federated) ও wallet-এ টিকিট sync | Cognito; Ticketing | F6.8, F2.10 |
| TSP gateway (mTLS) | টিকিট PDF-এর ডিজিটাল signing | Ticketing worker | F5.8 |
| Firebase (FCM) | Push notification | Scheduler worker | F5.11 |
| SES | Email (টিকিট zip) | Ticketing | F6.21 |
| "Serverless" API | Cognito user lookup, admin login 2FA OTP | কয়েকটি service + admin portal | F6.1, F6.22 — source repo-তে নেই `[UNCONFIRMED]` |
| "Notification" API | SMS পাঠানো (ticket-generated notice) | Scheduler | F5.12, F6.22 — source repo-তে নেই `[UNCONFIRMED]` |
| identity API | Registration, OTP, profile, app version | portal + app | F6.6 প্রভৃতি — source repo-তে নেই `[UNCONFIRMED]` |

### 0.10 Feature index (সূচি)

- **Part 1 — Admin Portal:** F1.1 program selection · F1.2 program · F1.3 program settings · F1.4 team · F1.5 venue ও stadium layout · F1.6 program–venue mapping · F1.7 event · F1.8 event settings override · F1.9 event venue details ও level-প্রতি pricing · F1.10 event capacity adjustment · F1.11 seat reservation · F1.12 reserved ticket generation ও distribution · F1.13 ticket layout ও attribute · F1.14 ticket-pricing content page · F1.15 promo code · F1.16 system discount · F1.17 ticket-checker account · F1.18 gate assignment ও download control · F1.19 gate report · F1.20 raffle draw · F1.21 dashboard · F1.22 booking/sales/revenue report · F1.23 reconciliation search · F1.24 user issue ও support chat (admin) · F1.25 admin user · F1.26 agent user · F1.27 activity log viewer · F1.28 media configuration · F1.29 content editor · F1.30 header/footer ও social media · F1.31 general notice
- **Part 2 — User Web Portal:** F2.1 home content · F2.2 event browse · F2.3 information page · F2.4 seat selection · F2.5 promo code apply · F2.6 booking order ও online payment (DgePay) · F2.7 আমার booking ও generation status · F2.8 ticket generation request · F2.9 ticket details, holder তথ্য, download, share, invoice · F2.10 OneID-তে টিকিট sync · F2.11 profile · F2.12 issue জানানো ও chat · F2.13 ভাষা পরিবর্তন
- **Part 3 — User App:** F3.1 splash, version gate ও onboarding · F3.2 home ও event browse · F3.3 information page · F3.4 seat selection ও promo code · F3.5 booking ও WebView payment · F3.6 আমার booking ও টিকিট · F3.7 profile ও settings · F3.8 issue জানানো ও support chat · F3.9 push device-token registration · F3.10 push গ্রহণ
- **Part 4 — Checker App:** F4.1 assigned event ও gate · F4.2 offline যাচাইয়ের টিকিট download · F4.3 QR scan validation · F4.4 manual entry · F4.5 scan sync · F4.6 শুধু signature যাচাই
- **Part 5 — System-initiated:** F5.1 level capacity update · F5.2 event live capacity · F5.3 locked-capacity refresh · F5.4 scheduler capacity reconcile · F5.5 pending/failed payment পুনঃযাচাই · F5.6 booking status → Generated · F5.7 user ticket generation শুরু · F5.8 TSP-তে টিকিট signing · F5.9 reserved টিকিট merge/zip · F5.10 NBR-এ VAT challan · F5.11 FCM-এ push delivery · F5.12 ticket-generated notification · F5.13 device-token cleanup · F5.14 checked-ticket sync · F5.15 gate download-status cleanup · F5.16 promo-code status update · F5.17 system-discount status update
- **Part 6 — Cross-cutting:** F6.1 admin login · F6.2 admin forgot password · F6.3 admin change password ও logout · F6.4 admin session · F6.5 staff account provisioning · F6.6 গ্রাহক registration · F6.7 গ্রাহক login (phone + password) · F6.8 OneID SSO · F6.9 গ্রাহক forgot/reset password · F6.10 গ্রাহক session · F6.11 account delete ও app force-update · F6.12 checker login · F6.13 Agent pool ও offline-sold ticket · F6.14 authorization স্তর ১ (pool policy) · F6.15 স্তর ২–৩ (role) · F6.16 স্তর ৪ (program scope) · F6.17 client-side authorization · F6.18 authorization-নেই এমন endpoint · F6.19 service-to-service communication · F6.20 file storage (S3, CloudFront) · F6.21 email (SES) · F6.22 SMS ও external notification service · F6.23 push notification · F6.24 activity logging · F6.25 Redis · F6.26 configuration ও secret
- **Part 7 — Open queries:** OQ1–OQ22

---

## 1. Admin Portal

BCB/BS23-এর staff-রা Angular admin portal-এ (`rvl-gobcb-admin-portal`) যে feature-গুলো শুরু করেন, Admin Cognito pool। লগইন নিজে cross-cutting (F6.1–F6.5); এই part লগইনের পরে শুরু হয়।

### F1.1 Program selection ও program-scoped menu

> **Bangla name:** প্রোগ্রাম নির্বাচন ও প্রোগ্রাম-ভিত্তিক মেনু

**1. Name and purpose.** লগইনের পর staff বেছে নেন কোন **program**-এ (সিরিজ/টুর্নামেন্ট) কাজ করবেন। Portal তখন থেকে প্রতিটি API call-এ `X-Program-Id` header পাঠায় ও program menu দেখায়; "global" mode (program id 0) বেছে নিলে সীমিত, program-নিরপেক্ষ মেনু আসে।

**2. Trigger and actor.** Admin portal-এর top bar / program switcher — লগইনের ঠিক পরে এবং যেকোনো সময়। Actor: যেকোনো staff role (`admin`, `event_manager`, `ticket_manager`, `ticket_operator`, `customer_support`), Admin pool থেকে।

**3. Business flow.**
1. লগইনের পর staff program selection-এ (বা role অনুযায়ী program-management screen-এ) পড়েন।
2. Program বেছে নিলে তা browser-এ জমা হয় (`localStorage.globalProgramId`) আর menu রিলোড হয়।
3. বেশিরভাগ menu item (events, dashboard, issues, reports) এখন শুধু সেই program-এর data দেখায় — কারণ প্রতিটি request `X-Program-Id` বহন করে।
4. Global mode (program id 0) বেছে নিলে limited menu খোলে (program, venue, user, media)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal-এর `ProgramService` (BehaviorSubject + `localStorage.globalProgramId`) | — | নির্বাচন state client-side; guard `ProgramMenuGuard` (programId > 0) ও `LimitedMenuGuard` (programId == 0) ঠিক করে কোন route যাওয়া যাবে |
| 2 | Portal → প্রতিটি admin API call | — | `program-id.interceptor.ts` `ProgramService` থেকে `X-Program-Id` header যোগ করে |
| 3 | Admin service | — | `ProgramIdMiddleware` header-টি `HttpContext.Items["ProgramId"]`-এ কপি করে; `IProgramIdAccessor` তা `AdminDbContext`-কে দেয়, যেখানে ProgramId > 0 হলে `IHasProgramId` implement করা প্রতিটি entity-তে **global EF query filter** বসে — data scoping SQL-এ হয়, endpoint-প্রতি নয় |
| 4 | Admin service | — | `[AuthorizeProgram]`-চিহ্নিত route-এ `AuthorizeProgramAttribute` header-টি user-এর `program_id` claim-এর সাথেও মেলায় (claim আসে Cognito `custom:program_ids` থেকে): header নেই/invalid হলে 400, program অনুমোদিত না হলে 403। `admin` ও `user` role bypass করে |

**5. Components.** Admin portal (`ProgramService`, interceptor, guard); Admin service (middleware + EF filter + attribute); Cognito attribute `custom:program_ids`।

**6. API contracts.** এই feature program তালিকা ব্যবহার করে (F1.2-এর `GET /admin/api/v1/program`)। এই part-এর যেকোনো admin endpoint পড়ুন *"সাথে `X-Program-Id` header"* — portal প্রতিটি request-এ পাঠায়। Backend-এ program scoping শুধু সেখানেই যেখানে কোড তা ব্যবহার করে (EF filter ও `[AuthorizeProgram]`; Booking/Ticketing বরং স্পষ্ট `programId` query parameter নেয়)।

**7. Data and side effects.** Server-এ কিছু নয়; শুধু browser state।

**8. Code references.**

| কী | কোথায় |
|---|---|
| Program state | `rvl-gobcb-admin-portal/src/app/core/services/program.service.ts` |
| Header interceptor | `rvl-gobcb-admin-portal/src/app/interceptors/program-id.interceptor.ts` |
| Menu guard | `rvl-gobcb-admin-portal/src/app/core/guard/program-menu.guard.ts`, `limited-menu.guard.ts` |
| Backend middleware | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Middleware/ProgramIdMiddleware.cs` |
| Program attribute | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Attributes/AuthorizeProgramAttribute.cs` |
| EF filter + accessor | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Storage/Repositories/ProgramIdAccessor.cs`, `AdminDbContext.cs` |

**9. Handover notes.** ① `admin` role program যাচাই bypass করে সব program দেখে; অন্যদের `custom:program_ids` দিয়ে provision করতে হয় (F6.5)। ② `[AuthorizeProgram]` এখন শুধু dashboard controller-এ active; `EventsController`-এ আছে কিন্তু **comment out** — events আজকে শুধু query parameter দিয়ে scoped, program-ভিত্তিক enforce হয় না। ③ Header শুধু Admin service বোঝে; বাকিরা উপেক্ষা করে।

### F1.2 Program

> **Bangla name:** প্রোগ্রাম (সিরিজ/টুর্নামেন্ট) ব্যবস্থাপনা

**1. Name and purpose.** **Program** তৈরি, সম্পাদনা ও মুছে ফেলা — সেই সিরিজ বা টুর্নামেন্ট যা event-গুলোকে ধারণ করে এবং নিজের logo ও তারিখ বহন করে।

**2. Trigger and actor.** Admin portal → `/program-management/program-create`, `/program-management/edit/:id`, `/settings/programs`। Role: `admin`, `event_manager` (controller: `[Authorize(Roles = admin, event_manager, …)]`)।

**3. Business flow.**
1. Staff Program Management → Create Program খোলেন।
2. নাম, সংক্ষিপ্ত নাম, শুরু/শেষ তারিখ দেন ও logo image upload করেন।
3. Save করলে program তৈরি হয়; সে এখন program switcher-এ (F1.1) দেখা যায় এবং team, venue ও event ধারণ করতে পারে।
4. Edit একই field বদলায়; delete মুছে ফেলে (venue screen-এর `has-running-events` যাচাই venue-এর জন্য; program-level guard কোডে দৃশ্যমান নয় — note দ্রষ্টব্য)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal `programs.service.ts` → Admin `POST /admin/api/v1/program` | **[HTTP + user token]** | multipart form (logo file) |
| 2 | Admin `ProgramController` → `ProgramManager` | — | Program row save; logo `AwsSimpleStorageMediaManager` দিয়ে media bucket-এ (`AWS:Bucket:Name`), CloudFront URL save |
| 3 | Admin DB | **[Shared table]** | `Programs` table (schema `etp`); Event service ও Booking নিজেদের `DbContext` mirror দিয়ে একই table পড়ে |
| 4 | Public দিক | **[Shared table]** | User portal/app Event service-এর `GET /event/api/v1/events/programs` (F2.2) দিয়ে program দেখায় |

**5. Components.** Admin portal; Admin service; S3 media bucket + CloudFront; `Programs` table (মালিক Admin)।

**6. API contracts.** Base: `/admin/api/v1/program`। Auth: Admin pool; role `admin`, `event_manager`।

| Method | Path | Request | Response |
|---|---|---|---|
| GET | `/admin/api/v1/program` | — | program-এর তালিকা |
| GET | `/admin/api/v1/program/{id}` | — | একটি program |
| POST | `/admin/api/v1/program` | multipart `CreateOrUpdateProgram` | তৈরি হওয়া program |
| PUT | `/admin/api/v1/program/{id}` | multipart `CreateOrUpdateProgram` | হালনাগাদ program |
| DELETE | `/admin/api/v1/program/{id}` | — | মুছে ফেলা program |

`CreateOrUpdateProgram` (`Services/Admin/ETP.Admin.Domain/Models/Settings/CreateOrUpdateProgram.cs`):

```json
// POST /admin/api/v1/program  (multipart/form-data; "Logo" একটি file part)
{
  "Name": "Bangladesh Tour of Sri Lanka 2026",
  "ShortName": "BAN in SL 2026",
  "StartDateTime": "2026-07-01T00:00:00Z",
  "EndDateTime": "2026-07-28T00:00:00Z"
}
```

মূল error: standard envelope (§0.7) — manager-এর throw করা invalid date/একই নামের ক্ষেত্রে 400।

**7. Data and side effects.** `Programs` table-এ insert/update/delete; media bucket-এ একটি file (logo); Redis-cached public তালিকায় (Event service) TTL শেষ না হওয়া পর্যন্ত পুরোনো নাম/logo।

**8. Code references.**

| কী | কোথায় |
|---|---|
| Portal service | `rvl-gobcb-admin-portal/src/app/features/program-settings/services/programs.service.ts` (`program-management.service.ts`-ও) |
| Controller | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/ProgramController.cs` |
| Manager | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Domain/Managers/ProgramManager.cs` |
| Media upload | `rvl-gobcb-backend/Core/ETP.Core.BlobStorage/AWSS3/AwsSimpleStorageMediaManager.cs` |

**9. Handover notes.** ① Deletion guard (যেমন "program-এ event আছে") extract করা কোডে দেখা যায়নি — production-এ delete নির্ভর করার আগে যাচাই করুন। ② একই create form দুই মেনু থেকে (`/settings/programs` ও `/program-management`) — দুটি কাছাকাছি Angular service পেছনে।

### F1.3 Program settings

> **Bangla name:** প্রোগ্রাম সেটিংস

**1. Name and purpose.** Program-প্রতি বাণিজ্যিক নিয়ম: payment gateway নির্বাচন, কেনাকাটার সীমা, selling/availability সময় (ঘণ্টায়), VAT ও service charge, আর ticket-number prefix।

**2. Trigger and actor.** Admin portal → `/program-management/configuration`। Role: `admin`, `event_manager` (`ProgramSettingsController`)।

**3. Business flow.**
1. Staff নির্বাচিত program-এর settings খোলেন।
2. Per user কত order, per order কত seat অনুমোদিত, ঘণ্টায় selling window, VAT (শতাংশ/ফিক্সড, inclusive কিনা), service charge, "limited availability" threshold ও ticket-number prefix সেট করেন।
3. Program-এর **payment gateway** বেছে নেন (DgePay বা SSLCommerz)।
4. Save করলে নিয়ম জমা হয়; event নিজস্ব override না দিলে (F1.8) program-এর প্রতিটি event এগুলো পায়।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/program-settings/{programId}` | **[HTTP + user token]** | বর্তমান settings |
| 2 | Portal → Admin `PUT /admin/api/v1/program-settings` | **[HTTP + user token]** | JSON `ProgramSettings` |
| 3 | Admin DB + cache | — | `ProgramSettings` row (প্রতি program একটি); Redis key family `program_settings_details` অন্যান্য flow-এর read cache করে |

**5. Components.** Admin portal (`program-settings.service.ts`); Admin service; `ProgramSettings` table।

**6. API contracts.**

```json
// PUT /admin/api/v1/program-settings   (ProgramSettings, Services/Admin/ETP.Admin.Domain/Models/Settings/ProgramSettings.cs)
{
  "id": 19,
  "programId": 7,
  "limitedAvailabilityThreshold": 10.0,
  "allowableMaximumOrderPerUser": 2,
  "allowableMaximumSeatPerOrder": 4,
  "ticketSellingStartFromHour": 240,       // event-এর আগে কত ঘণ্টা
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

`GET program-settings/{programId}` একই shape ফেরায়। Error: standard envelope।

**7. Data and side effects.** `ProgramSettings` upsert; program settings key-এর Redis cache refresh।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/program-management/services/program-settings.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/ProgramSettingsController.cs`।

**9. Handover notes.** ① `PaymentGateway` field মানে active gateway **program-অনুযায়ী** — এটা আংশিক উত্তর দেয় "DgePay নাকি SSLCommerz" প্রশ্নের: দুটোই নির্বাচনযোগ্য; production-এ কোন program-এ কোনটা, সেটা data, কোড নয় `[UNCONFIRMED]`। ② `LimitedAvailabilityThreshold` "limited seats left" badge-এর logic চালায়; এর প্রকৃত ভোক্তা Booking-এর capacity check।

### F1.4 Team

> **Bangla name:** টিম ব্যবস্থাপনা

**1. Name and purpose.** Program-এর event-গুলোতে যে টিমগুলো খেলে তাদের (logo ও flag-সহ) রক্ষণাবেক্ষণ; event segment ও public page-এ ব্যবহৃত।

**2. Trigger and actor.** Admin portal → `/settings/program-teams`, `/program-management`-এর team screen। Role: `admin`, `event_manager` (`TeamsController`)।

**3. Business flow.** Staff program-এর অধীনে টিম বানান (নাম, সংক্ষিপ্ত নাম, logo, flag), সম্পাদনা, toggle, মুছে ফেলা; event segment (F1.7) তখন টিম রেফার করে।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/teams` | **[HTTP + user token]** | multipart `CreateOrUpdateProgramTeam` |
| 2 | Admin manager | — | `ProgramTeams` row; logo/flag media bucket-এ |
| 3 | Public দিক | **[Shared table]** | Event service event segment response-এ টিমের নাম দেয় (F2.2) |

**5. Components.** Admin portal; Admin service; S3 media bucket; `ProgramTeams` table।

**6. API contracts.** Base `/admin/api/v1/teams`: `GET program/{programId}`, `GET {id}`, `GET ` (paged), `GET list`, `POST` (multipart), `PUT {id}`, `DELETE {id}`, `PUT toggle-status/{id}`। `CreateOrUpdateProgramTeam` (`Models/Events/CreateOrUpdateProgramTeam.cs`): `Id, ProgramId, Name, ShortName, Logo (file, optional), IsFlag (bool?), IsActive, Flag (file, optional)`। Error: standard envelope।

**7. Data and side effects.** `ProgramTeams` upsert/delete; media bucket-এ file।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/program-management/services/teams-management.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/TeamsController.cs`।

**9. Handover notes.** অতীত event-এ রেফার করা টিমের জন্য delete-এর বদলে `toggle-status` soft enable/disable ব্যবহৃত হয়।

### F1.5 Venue ও stadium/exhibition layout

> **Bangla name:** ভেন্যু ও স্টেডিয়াম/প্রদর্শনী লেআউট

**1. Name and purpose.** Venue সংজ্ঞায়িত করা (স্টেডিয়াম বা exhibition hall) — SVG seat map ও **gallery → block → level** অনুক্রমসহ, প্রতিটিতে seat-mapping flag, sellability, ticket color ও entry/mini gate। এই গাছের উপরেই পরের সব (pricing, capacity, checker) দাঁড়িয়ে।

**2. Trigger and actor.** Admin portal → `/venue-management`, `create-venue`, `update-venue/:venueId`, `stadium-layout/:venueId` বা `exhibition-layout/:venueId`, `gallery-details/:venueId`। Role: `admin`, `event_manager` (`VenuesController`)।

**3. Business flow.**
1. Staff venue বানান: type (Stadium/ExhibitionHall), সংক্ষিপ্ত ও পূর্ণ নাম, location, SVG map image ও SVG key (map-এর যে অঞ্চলগুলো gallery/block/level হবে)।
2. Layout editor-এ gallery, block, level গড়েন; level-এ `SeatingCapacity`, ঐচ্ছিক আসনের তালিকা (`HasSeats`), sellability ও ticket color থাকে।
3. Block-level-এ **entry gate** ও **mini gate** যুক্ত করেন।
4. Event চলাকালীন সম্পাদনা আটকায় `has-running-events/{venueId}`।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/venues` | **[HTTP + user token]** | multipart `CreateOrUpdateVenue` (SVG map file + svg key) |
| 2 | Portal → Admin `POST /admin/api/v1/venues/venueLayout` | **[HTTP + user token]** | JSON `CreateOrUpdateVenueLayout` — এক call-এ পুরো gallery/block/level গাছ |
| 3 | Portal → Admin `POST /admin/api/v1/venues/entry-gate` / `mini-gate` | **[HTTP + user token]** | Block-level-প্রতি gate তালিকা |
| 4 | Admin DB | **[Shared table]** | `Venues`, `VenueGalleries`, `GalleryBlocks`, `BlockLevels`, `BlockLevelEntryGates`, `BlockLevelMiniGates`, `GalleryBlockEntryGates`; Event/Booking/TicketChecker mirror দিয়ে পড়ে |

**5. Components.** Admin portal; Admin service; S3 media bucket (SVG map); venue টেবিল (মালিক Admin)।

**6. API contracts.** নির্বাচিত endpoint (`VenuesController`, base `/admin/api/v1/venues`):

```json
// POST /admin/api/v1/venues   (multipart CreateOrUpdateVenue)
{ "type": 1, "shortName": "SBNCS", "name": "Sher-e-Bangla National Cricket Stadium", "location": "Mirpur, Dhaka" }
// part: SvgMapImageFile (file), SvgKeys (string তালিকা)

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

আরও: `GET {programId}`, `GET venue?venueId=`, `GET gallery` / `galleryBlocks` / `blockLevel`, `PUT venue/{venueId}`, `POST|PUT venueGallery|galleryBlocks|blockLevel`, `GET entry-gate|mini-gate`, `POST mini-gate`, `GET has-running-events/{venueId}`। Response entity: `Venue` (`Models/Events/Venue.cs`) — nested `VenueGallery`/`GalleryBlock`/`BlockLevel` উপরের sample-এর মতো। Error: standard envelope।

**7. Data and side effects.** Venue-গাছের টেবিলে লেখা; SVG map upload; downstream cache (`event_venue_details` key family) refresh না হওয়া পর্যন্ত পুরোনো।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/venue-management/services/venue-management.service.ts`, `pages/…`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/VenuesController.cs`।

**9. Handover notes.** ① Layout editor **পুরো গাছ** এক `venueLayout` call-এ পাঠায় — editor-এর ভুল sibling-ও মুছে দিতে পারে; UI-র unsaved-changes guard (`unsave-changes-guard`) মূল সুরক্ষা। ② `VenueType` enum: `Stadium = 1`, `ExhibitionHall = 2`; type অনুযায়ী portal ভিন্ন layout editor দেখায়। ③ একটি `BlockLevel` property-র নাম `BlockLevelEntrieGates` (typo, compatibility-র জন্য রাখা)।

### F1.6 Program–venue mapping ও venue details sync

> **Bangla name:** প্রোগ্রাম-ভেন্যু ম্যাপিং ও ভেন্যু ডিটেইলস সিঙ্ক

**1. Name and purpose.** Venue-কে program-এ যুক্ত করা এবং program-প্রতি **venue details** তৈরি করা: প্রতিটি gallery/block/level-এর জন্য override (active/sellable flag, seating capacity, price per seat, seats)। Event পরে এখান থেকেই শুরু হয় (F1.9)।

**2. Trigger and actor.** Admin portal → `/program-management/programVenueDetails`, `/settings/program-venues`। Role: `admin`, `event_manager` (`ProgramVenueController`, `ProgramVenueDetailsController`)।

**3. Business flow.**
1. Staff venue-কে program-এর সাথে map করেন (`ProgramVenue`)।
2. "Generate" সেই venue-র প্রতিটি level-এর জন্য `ProgramVenueDetails` row বানায় (venue গাছের সম্পাদনাযোগ্য কপি — দাম/capacity-সহ)।
3. Staff level-প্রতি দাম, capacity, sellability সম্পাদনা করেন; "Sync" venue layout-এর গঠনগত পরিবর্তন আবার টেনে আনে (venue layout বদলালে screen-এ **needs-sync** flag দেখায়)।
4. এই program-এর তৈরি event এই দাম থেকে শুরু হয় (F1.9)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/programVenue` | **[HTTP + user token]** | `CreateOrUpdateProgramVenue { id, programId, venueId }` |
| 2 | Portal → Admin `POST /admin/api/v1/programVenueDetails/{programId}` | **[HTTP + user token]** | venue গাছ থেকে details row generate |
| 3 | Portal → Admin `POST /admin/api/v1/programVenueDetails/{programId}/{venueId}` | **[HTTP + user token]** | গঠনগত পরিবর্তন sync |
| 4 | Portal → Admin `PUT /admin/api/v1/programVenueDetails/update/{id}` | **[HTTP + user token]** | level-প্রতি `CreateOrUpdateProgramVenueDetails` |
| 5 | Admin DB | **[Shared table]** | `ProgramVenues`, `ProgramVenueDetails` (মালিক Admin); Event service পড়ে |

**5. Components.** Admin portal; Admin service; `ProgramVenues`, `ProgramVenueDetails` টেবিল।

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

আরও `GET {programId}/{venueId}`, `GET venue-galleries/{programId}/{venueId}`, `GET venue-details/{programId}`, `GET programVenue/{programId}`। Error: standard envelope।

**7. Data and side effects.** Program-venue টেবিলে লেখা; queue/email নেই।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/program-management/services/{program-venues-details,program-management}.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/{ProgramVenueController,ProgramVenueDetailsController}.cs`।

**9. Handover notes.** `needsSync` venue layout-এর updated timestamp-কে শেষ sync-এর সাথে মেলায় — venue layout (F1.5) সম্পাদনা করলে map করা প্রতিটি program "need sync" হয়ে যায়, যতক্ষণ না কোনো admin sync করেন।

### F1.7 Event (ম্যাচ)

> **Bangla name:** ইভেন্ট (ম্যাচ) ব্যবস্থাপনা

**1. Name and purpose.** **Event** — যে ম্যাচের টিকিট customer কেনে — তৈরি, সম্পাদনা, segment যোগ, publish/unpublish, duplicate ও enable/disable; প্রতিটি event একটি program ও venue-র অধীনে, cover image ও একাধিক segment-সহ (innings/days/team)।

**2. Trigger and actor.** Admin portal → `/events`, `/events/create`, `/events/edit/:id`, `/events/event-details/:id`। Role: `admin`, `event_manager`, `ticket_manager`, `ticket_operator` (`EventsController`-এ class-level `[Authorize]`)।

**3. Business flow.**
1. Staff Events খোলেন (তালিকা নির্বাচিত program-এ সীমিত, F1.1) এবং Create চাপেন।
2. Program, venue, নাম, শুরু/শেষ date-time বেছে নেন, cover image দেন, **segment** যোগ করেন (প্রতিটিতে নাম, type, শুরু/শেষ, দুই টিম ও banner)।
3. Save করলে draft event তৈরি হয়। Details screen-এ staff settings (F1.8) ও venue pricing (F1.9) ঠিক করেন।
4. **Publish** করলে event public portal/app-এ দেখা যায়; **Unpublish** লুকায়; **toggle status** enable/disable করে; **Duplicate** পরের ম্যাচের জন্য event ক্লোন করে।
5. পরিবর্তনগুলো activity log-এ (F1.27) জমা পড়ে।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal `event.service.ts` → Admin `POST /admin/api/v1/events` | **[HTTP + user token]** | multipart `CreateEvent` (cover image + segment-প্রতি banner file) |
| 2 | Admin `EventsController` → `EventManager` | — | `Events` + `EventSegments` row; image media bucket-এ (row-তে CloudFront URL) |
| 3 | Admin DB | **[Shared table]** | `Events`, `EventSegments` (মালিক Admin); Event/Booking/Ticketing/TicketChecker mirror দিয়ে পড়ে |
| 4 | `PUT publish/{id}` | **[HTTP + user token]** | `IsPublished` set; public Event service শুধু published event দেখায় (`published/list`) |
| 5 | `POST duplicate/{id}` | **[HTTP + user token]** | event row + segment নতুন draft-এ কপি |
| 6 | Portal তালিকা | **[HTTP + user token]** | `GET /admin/api/v1/events` (paged, search/sort) বা `GET program/{programId}/events` |

**5. Components.** Admin portal; Admin service; S3 media bucket + CloudFront; `Events`, `EventSegments`, `EventSettings` টেবিল; Cognito Admin pool; `X-Program-Id` দিয়ে program scope (তালিকা ছাঁকাই)।

**6. API contracts.** Base: `/admin/api/v1/events`। Auth: Admin pool; §2-এর মতো role। মূল endpoint-এর sample:

`POST /admin/api/v1/events` — multipart `CreateEvent` (`Services/Admin/ETP.Admin.Domain/Models/Events/CreateEvent.cs`):

| Part | Type | নোট |
|---|---|---|
| `ProgramId` | long | মালিক program |
| `VenueId` | int | ম্যাচের venue |
| `Name` | string | |
| `StartDateTime` / `EndDateTime` | date-time | End nullable |
| `EventCoverImageFile` | file | cover image |
| `Segments[i].Name/SegmentType/StartDateTime/EndDateTime/Team1Id/Team2Id` | mixed | টিম optional |
| `Segments[i].BannerImageFile` | file | segment-প্রতি banner |

সফল 200/201 — `Event` response (`Domain/Models/Events/Event.cs`):

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
  "venue": { "…": "F1.5 দ্রষ্টব্য" },
  "program": { "…": "F1.2 দ্রষ্টব্য" },
  "eventSettings": { "…": "F1.8 দ্রষ্টব্য" },
  "segments": [
    { "name": "Match day", "segmentType": 1, "startDateTime": "2026-07-08T14:00:00Z", "endDateTime": "2026-07-08T22:00:00Z", "team1Id": 3, "team2Id": 5 }
  ]
}
```

অন্যান্য endpoint: `PUT {id}` (multipart `UpdateEvent`), `DELETE {id}`, `PUT publish/{id}`, `PUT unpublish/{id}`, `PUT toggle-status/{id}`, `POST duplicate/{id}`, `GET ` (paged: `search,sortBy,sortOrder,pageOffset,pageSize`), `GET search?search=`, `GET list`, `GET published/list`, `GET {startDatetime}/{endDateTime}/{eventId?}`, `GET filtered-list/{status}/{count}`, `GET {id}` (long id), `GET by-public-id/{eventId}` (Guid), `GET program/{programId}/events`, `GET programs/{programId}/events/no-end-date-check`। Error: standard envelope (§0.7); 401/403 §0.7-এর auth নিয়মে।

**7. Data and side effects.** `Events`, `EventSegments` (+F1.8-এর মাধ্যমে `EventSettings`); media bucket-এ image; publish করলে `IsPublished` ওল্টায়, যা public Event service Redis-cached তালিকায় ছোট বিলম্বে দেখা যায়।

**8. Code references.**

| কী | কোথায় |
|---|---|
| Portal service | `rvl-gobcb-admin-portal/src/app/features/events/services/event.service.ts` |
| তালিকা/তৈরি/সম্পাদনা page | `rvl-gobcb-admin-portal/src/app/features/events/pages/event-list/event-list.component.ts`, `event-create/event-create.component.ts` |
| Controller | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/EventsController.cs` |
| Manager | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Domain/Managers/EventManager.cs` |
| Public mirror | `rvl-gobcb-backend/Services/Event/ETP.Event.Service/Api/EventsController.cs` |

**9. Handover notes.** ① এই controller-এ `[AuthorizeProgram]` comment out — event তালিকার program scoping attribute নয়, স্পষ্ট `programId` parameter-এর উপর নির্ভর করে। ② `minimumPrice`, selling window ও VAT field settings flow-এ (F1.3/F1.8/F1.9) রক্ষিত, create form-এ নয়। ③ Admin-এ `GET /admin/api/v1/events/search`-ও আছে (অন্য admin screen ব্যবহার করে) — একই controller।

### F1.8 Event settings override

> **Bangla name:** ইভেন্ট সেটিংস (ওভাররাইড)

**1. Name and purpose.** একটি event-এর জন্য program settings (F1.3) override করা: selling window, কেনাকাটার সীমা, VAT/service charge, ticket prefix, payment gateway।

**2. Trigger and actor.** Admin portal → event details-এর Settings tab (`/events/event-details/:id`)। Role: F1.7-এর মতো। **নোট:** `EventSettingsController`-এ **কোনো `[Authorize]` নেই** (F6.18 দ্রষ্টব্য)।

**3. Business flow.** Staff event-এর Settings tab খুলে উত্তরাধিকার-পাওয়া যেকোনো নিয়ম বদলান (যেমন playoff-এর জন্য selling ঘণ্টা বাড়ান), save করেন; এরপর থেকে program-এর বদলে event-এর নিজের row প্রযোজ্য হয়।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/event-settings/{eventId}` | **[HTTP + user token]** | event-এর কার্যকর settings |
| 2 | Portal → Admin `PUT /admin/api/v1/event-settings/{eventId}` | **[HTTP + user token]** | JSON `EventSettings` |
| 3 | Admin DB + cache | — | `EventSettings` row; Redis key family `event_settings_details` |

**5. Components.** Admin portal (`event-settings.service.ts`); Admin service; `EventSettings` টেবিল।

**6. API contracts.** `EventSettings`-এর field F1.3-এর `ProgramSettings`-এর মতোই, `ProgramId`-এর জায়গায় `EventId`। Error: standard envelope।

**7. Data and side effects.** `EventSettings` upsert; Ticketing টিকিট নম্বর বানানোর সময় prefix পড়ে (F5.8: `{eventSettings.TicketNumberPrefix}{unique code}`)।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/events/services/event-settings.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/EventSettingsController.cs`।

**9. Handover notes.** Controller-এ `[Authorize]` নেই মানে নিরাপত্তা শুধু network placement — F6.18-এর তালিকায়।

### F1.9 Event venue details ও level-প্রতি pricing

> **Bangla name:** ইভেন্ট ভেন্যু ডিটেইলস ও লেভেল-ভিত্তিক দাম

**1. Name and purpose.** এক event-এর venue গাছ দেখা এবং কোনো level-এর **price per seat** সেট করা — event-এর price map (ও public `MinimumPrice`) এখানেই নির্ধারিত হয়।

**2. Trigger and actor.** Admin portal → event details / venue details screen। Role: `admin`, `event_manager`, `ticket_manager`, `ticket_operator` (`EventsVenueDetailsController`)।

**3. Business flow.**
1. Staff event-এর venue details খোলেন: gallery → block → level, capacity ও gate-সহ।
2. একটি level-এর দাম দেন (level-প্রতি একটি সহজ call)।
3. Public event model-এ `MinimumPrice` নতুন হিসাব হয় (F2.2) ও user seat map-এ নতুন দাম দেখায়।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/eventsVenueDetails/venue-details/{eventId}` | **[HTTP + user token]** | `EventVenueDetailsTree` |
| 2 | Portal → Admin `PUT /admin/api/v1/eventsVenueDetails/{eventId}/{levelId}/{price}` | **[HTTP + user token]** | level-এর দাম set |
| 3 | Admin DB | **[Shared table]** | `EventVenueDetails` (মালিক Admin) — Event service publicly একই table serve করে (F2.4) |

**5. Components.** Admin portal (`event.service.ts`); Admin service; `EventVenueDetails` টেবিল।

**6. API contracts.** আরও: `GET {eventId}?isForTicket=`, `GET get-level/{eventId}/{levelId}` → `UserLevelWithGates` (sample F2.4-এ), `POST galleries/by-event-ids` (body `List<long>`, কয়েক event-এর gallery)। Error: standard envelope।

**7. Data and side effects.** `EventVenueDetails`-এ দাম বদল; public venue-details cache (`event_venue_details`, TTL ১৫ দিন পর্যন্ত) বিলম্ব তৈরি করে — note দ্রষ্টব্য।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/events/services/event.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/EventsVenueDetailsController.cs`।

**9. Handover notes.** Public seat map অনেকদিন Redis cache-এ থাকায় দাম বদলালে portal-এ দেখতে দেরি হতে পারে — তাৎক্ষণিক দরকার হলে cache key (`event_venue_details*`) মুছুন, নয়তো BS23 কীভাবে সামলায় জেনে নিন `[UNCONFIRMED]`।

### F1.10 Event capacity adjustment

> **Bangla name:** ইভেন্ট ক্যাপাসিটি সমন্বয়

**1. Name and purpose.** স্বাভাবিক বিক্রির বাইরে কোনো level-এর sellable capacity বাড়ানো/কমানো (allocate/deallocate) — যেমন টিকিট শেষ হওয়ার পর অতিরিক্ত block খোলা।

**2. Trigger and actor.** Admin portal → event ticket console (`/events/event-ticket`)। Role: **Booking** service-এর admin-pool endpoint (`EventCapacityAdjustmentController`-এ স্পষ্ট role নেই — F6.18)।

**3. Business flow.**
1. Staff event-এর capacity screen-এ level ও action (Allocate/Deallocate) ও seat সংখ্যা দেন।
2. Save করলে adjustment রেকর্ড হয় ও level capacity বদলায়।
3. Queue message event-এর live capacity recompute করে (F5.2), public counter-ও সেটি অনুসরণ করে।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Booking `POST /booking/api/v1/event-capacity-adjustment` | **[HTTP + user token]** | `EventCapacityAdjustment` (নিচে) |
| 2 | Booking `CapacityManager` | — | `EventCapacityAdjustments` row লেখে, `Capacities` হালনাগাদ করে; **[SQS: OrderSuccess]** `LevelCapacityUpdate` ও **[SQS: EventCapacity]** `EventLiveCapacityUpdate` publish করে |
| 3 | Worker | **[Worker]** | F5.1 DB+Redis level capacity হালনাগাদ করে; F5.2 event live counter |

**5. Components.** Admin portal; Booking service; SQS `OrderSuccess` + `EventCapacity`; Redis `capacity` hash; `EventCapacityAdjustments`, `Capacities` টেবিল।

**6. API contracts.**

```json
// POST /booking/api/v1/event-capacity-adjustment   (EventCapacityAdjustment)
{
  "id": 55, "eventId": 1042, "galleryId": 12, "blockId": 7, "levelId": 45,
  "ticketingCapacity": 100, "hasSeats": false, "seats": null, "availableSeats": null,
  "action": "Allocate",                 // enum string (Booking-এ enum string হিসেবে serialize, §0.7)
  "adjustmentNumber": "ADJ-000123"
}
```

আরও `GET by-event-level?eventId&levelId&action&programId`, `GET by-event?eventId`, `GET count/{eventId}?action=`। Error: `no_seats_available` → 400 envelope (§0.7)।

**7. Data and side effects.** Adjustment row + capacity হালনাগাদ; দুটি SQS message; worker-দের দ্বারা Redis counter refresh।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/events/services/event.service.ts` (booking capacity-adjustment call); `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/EventCapacityAdjustmentController.cs`, `…/Domain/Managers/CapacityManager.cs`।

**9. Handover notes.** চলমান বিক্রির মধ্যে adjustment user order-এর সাথে প্রতিযোগিতা করে — manager Redis locked-capacity key (`level_locked:…`) সম্মান করে; বিক্রির মধ্যে বড় deallocate সাবধানে করুন।

### F1.11 Seat reservation (complimentary / partner)

> **Bangla name:** আসন রিজার্ভেশন (কমপ্লিমেন্টারি / পার্টনার)

**1. Name and purpose.** Online বিক্রির বাইরে আসন ধরে রাখা **complimentary** (VIP/অতিথি) বা **partner** (sponsor/agent)-এর জন্য; reserved আসন পরে ছাপা টিকিট হয় (F1.12)।

**2. Trigger and actor.** Admin portal → event ticket console। Role: admin pool (Booking `SeatReservationController`)।

**3. Business flow.**
1. Staff event + level বেছে সংখ্যক আসন (বা level-এর শতাংশ) reserve করেন — reservation type (Complimentary/Partner) ও category (DigitalPrint / Printing / ReservedOnly)-সহ।
2. সিস্টেম reservation number-সহ reservation বানায় ও আসন ধরে রাখে।
3. Summary screen-এ reservation-প্রতি requested / generated / remaining দেখায়; আসন পরে ছাড়াও যায়।
4. Reservation-এর টিকিট তৈরি হয় F1.12-তে।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Booking `POST /booking/api/v1/seat-reservation` | **[HTTP + user token]** | `SeatReservation` (নিচে) |
| 2 | Portal → Booking `POST /booking/api/v1/seat-reservation/event/{eventId}?percentage=` | **[HTTP + user token]** | এক level-এর শতাংশ bulk reserve |
| 3 | Booking manager | — | `SeatReservations` row; capacity কমে; Redis locked/level key হালনাগাদ |
| 4 | Summary | **[HTTP + user token]** | `GET summary/{eventId}` → `List<ReservationSummary>` |

**5. Components.** Admin portal; Booking service; `SeatReservations`, `Capacities` টেবিল; Redis।

**6. API contracts.** `SeatReservation` (`Domain/Models/SeatReservation.cs`) — মূল field: `EventId, GalleryId, BlockId, LevelId, NumberOfSeats, HasSeats, Seats, Action ("Allocate"/"Deallocate"), Status, Type (Complimentary/Partner), ReservationCategory (DigitalPrint/Printing/ReservedOnly), MergeStatus, ZipStatus, PublicId, ProgramId, ReservationNumber`। Enum (Booking, string হিসেবে): `ReservationStatus {Draft, Generated, Requested, Closed, Locked, Merging, Merged}`, `ReservationType {Complimentary, Partner}`, `ReservationCategory {DigitalPrint, Printing, ReservedOnly}`, `MergeStatus {None, Requested, Merging, Merged, Failed}`, `ZipStatus {None, Requested, Zipping, Zipped, Failed}`। `ReservationSummary` (`Domain/Models/ReservationSummary.cs`):

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

অন্যান্য endpoint: `GET by-event-level?eventId&levelId&actionType&programId`, `GET by-event`, `GET count/{eventId}?actionType=`, `GET remainingReserveCount/{eventId}`, `GET reservations-count?eventId&levelIds`। Error: standard envelope (`no_seats_available` → 400)।

**7. Data and side effects.** `SeatReservations` row; capacity কমে; এই call থেকে নিজে কোনো queue message নয় (F1.12/F5.9 গল্প এগিয়ে নেয়)।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/events/services/event.service.ts` (seat-reservation call); `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/SeatReservationController.cs`, `…/Managers/SeatReservationManager.cs`।

**9. Handover notes.** এই controller-এর কিছু update endpoint (`update-reservation-status`, `update-merge-status`, `update-zip-status`, `event-id/{publicId}` …) **worker ও internal service-এর জন্য** (F5.9) এবং তাদের `[Authorize]` নেই — F6.18।

### F1.12 Reserved ticket generation ও distribution

> **Bangla name:** রিজার্ভড টিকিট তৈরি ও বিতরণ

**1. Name and purpose.** "Generate Tickets" console: reservation-কে আসল টিকিটে রূপ দেওয়া — blank PDF তৈরি, TSP দিয়ে sign, reservation-প্রতি merge/zip, portal থেকে download, বা partner-কে zip email।

**2. Trigger and actor.** Admin portal → `/events/event-ticket`, `/events/generate-ticket/:id`। Role: admin pool; Ticketing endpoint-গুলো `[Authorize(Policy = admin)]`।

**3. Business flow.**
1. Staff event-এর ticket console খুলে reservation-এর টিকিট বানান (level-প্রতি সংখ্যা/আসন, ticket type; "test" mode আছে যা শুধু preview PDF বানায়)।
2. "Sign" blank-গুলো TSP signing pipeline-এ পাঠায় — টিকিট `Generated` হয়।
3. "Merge" reservation-এর PDF একত্র করে; "Zip" আলাদা PDF গুলো zip করে (দুটোই Utility worker-এ চলে)।
4. Staff merged/zip artifact download করেন (**signed token** বা CloudFront cookie দিয়ে সুরক্ষিত), বা zip **email** করেন।
5. Console reservation-প্রতি merged/zipped টিকিট-নম্বরের তালিকাও দেখায়।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Ticketing `POST /ticketing/api/v1/booking-order-ticket/reserve-ticket?eventId&levelId` | **[HTTP + user token]** | `List<ReservedTicketRequest>`; Ticket row তৈরি (`Status=Requested`, type default "Partner Sale"), blank PDF S3-এ `{BlankBase}/reserved/{orderPublicId}/{TicketNumber}.pdf`, প্রতিটির জন্য **[SQS: TicketSigning]** publish |
| 2 | Worker | **[Worker]** | F5.8 TSP দিয়ে sign → `GenerateSignedTicketAsync` (reserved type-এ টিকিটের তথ্য PDF-এ আঁকা হয়, `{SignedBase}/reserved/{CreatedBy}/{orderPublicId}/{TicketNumber}-{type}.pdf`-এ সংরক্ষণ) |
| 3 | Portal → Ticketing `POST …/sign-reserve-ticket?eventId&levelId` | **[HTTP + user token]** | sign-না-হওয়া requested টিকিট আবার signing queue-তে |
| 4 | Portal → Ticketing `GET …/merge-reserved/{reservationId}` | **[HTTP + user token]** | **[SQS: TicketProcessing]** `ProcessingType=Merge` (F5.9 Utility worker → `{MergeBase}/{reservationId}/{ReservationNumber}_Merged_PDF_{i}.pdf`) |
| 5 | Portal → Ticketing `GET …/zip-reserved/{reservationId}` | **[HTTP + user token]** | একই ভাবে `ProcessingType=Zip` → `{ReservationNumber}_Individual_Zipped_{i}.zip` |
| 6 | Portal → Ticketing `GET …/download-merged?reservationId&signedToken` / `POST …/download-reserved` | **[HTTP + user token]** | artifact stream; `signedToken` আসে `POST …/generate-signed-token` থেকে |
| 7 | Portal → Ticketing `POST …/send-reserved` | **[HTTP + user token]** | SES দিয়ে zip email (`AWS:Ticket:EmailSender`, default subject "Get your tickets"); টিকিটের `Action` = `emailed: {recipient}` |
| 8 | লগইনের সময় | — | `admin`, `ticket_manager`, `ticket_operator` role-দের জন্য portal `GET …/signed-cookie` আনে (F6.1) যাতে browser সরাসরি CloudFront থেকে নামাতে পারে |

**5. Components.** Admin portal; Ticketing service; Utility service; SQS `TicketSigning` + `TicketProcessing`; TSP gateway; S3 ticket bucket (`AWS:Ticket:*` path); CloudFront signed URL/cookie; SES; `Tickets`, `SeatReservations` টেবিল।

**6. API contracts.** নির্বাচিত:

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

অন্যান্য endpoint: `GET|PUT reserve-ticket` (তালিকা/পুনরায় তৈরি), `POST download-test-blank-reserved` (`BlankTicketRequest`), `GET merged-ticket-number/{reservationId}`, `GET zipped-ticket-number/{reservationId}`, `GET reserved-urls?reservationId`, `POST generate-signed-token`, `GET signed-cookie` (cookie string ফেরায় — **caller** নিজে তিনটি `CloudFront-*` cookie বসায়)। Error: standard envelope; template না পেলে `ArgumentException` ("Ticket Layout Config … not found", 400)।

**7. Data and side effects.** `Tickets` row (`Status` Requested→Generated, `SignedTicketUrl`); `SeatReservations.MergeStatus/ZipStatus` transition (None→Requested→Merging→Merged / Zipping→Zipped, error-এ Failed); S3 file (blank/signed/merged/zip); SES email; SQS message।

**8. Code references.**

| কী | কোথায় |
|---|---|
| Portal service | `rvl-gobcb-admin-portal/src/app/features/events/services/event.service.ts` |
| Console page | `…/features/events/pages/event-ticket/…`, `…/components/generate-ticket/…` |
| Controller | `rvl-gobcb-backend/Services/Ticketing/ETP.Ticketing.Service/Api/BookingOrderTicketController.cs` |
| Manager | `…/ETP.Ticketing.Domain/Managers/TicketManager.cs` (`CreateReservationTicketsAsync`, `PublishBulkTicketToSign`, `RequestMergeTicketsAsync`, `RequestZipTicketsAsync`, `SendReservedTicketsAsync`) |
| CloudFront | `rvl-gobcb-backend/Core/ETP.Core.BlobStorage/AWSS3/{S3CloudFrontStroge,TicketingCookieManager}.cs` |

**9. Handover notes.** ① Reserved টিকিটের QR-তে `Platform=offline` ও Name/Phone-এর বদলে `Complimentary` field — checker app সেগুলো বিশেষভাবে দেখে (F4.3)। ② signed-cookie endpoint `Set-Cookie` header নয়, **string** ফেরায় — portal `document.cookie` দিয়ে cookie লেখে (F6.1)। ③ Test mode (`isTest`) শুধু reservation-এ preview URL রাখে, আসল টিকিট হয় না।

### F1.13 Ticket layout ও ticket attributes

> **Bangla name:** টিকিট লেআউট ও টিকিট অ্যাট্রিবিউট

**1. Name and purpose.** টিকিট ছাপার **PDF template** রক্ষণাবেক্ষণ (program/venue/gallery-প্রতি, ছয় রকম variant: single/multiple segment × user/partner/complimentary, সাথে back page) এবং **ticket attributes** (টিকিটে কোন field দেখাবে ও কোন ক্রমে)।

**2. Trigger and actor.** Admin portal → `/ticket-layout` (`/program-management`-এর layout screen-ও)। Role: `admin`, `event_manager`, `ticket_manager`, `ticket_operator` (`TicketLayoutConfigsController`, `TicketAttributesController`)।

**3. Business flow.**
1. Staff layout config বানান: নাম, program, venue (ঐচ্ছিক gallery), ticket size (QR-এর অবস্থান ঠিক করে), default text।
2. Template PDF upload করেন (variant-প্রতি একটি) ও back-page PDF; publish করলেই সেটিই Ticketing ব্যবহার করে।
3. Ticket attributes দৃশ্যমান field ঠিক করে (gallery/block/level/entry gate/mini gate/venue name/segment datetime) — show flag ও ordering priority-সহ; DITF (exhibition) variant-এ ticket type / entry / exit time যোগ।
4. `download-backpage/{eventId}` দিয়ে event-এর কার্যকর back page দেখা যায়।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/ticket-layout` | **[HTTP + user token]** | `TicketLayoutConfigCreated` |
| 2 | Portal → Admin `POST /admin/api/v1/ticket-layout/upload/{id}?ticketLayoutType=` | **[HTTP + user token]** | multipart PDF upload → S3 media bucket; URL config-এ |
| 3 | Admin DB | **[Shared table]** | `TicketLayoutConfigs` (মালিক Admin); Ticketing পড়ে (published config program/venue/gallery-প্রতি F5.8-এর template নির্বাচন চালায়) |
| 4 | Portal → Admin `PUT /admin/api/v1/ticket-attributes/{id}` / `GET program/{programId}` | **[HTTP + user token]** | `TicketAttributes` upsert/read |

**5. Components.** Admin portal; Admin service; S3 media bucket; Ticketing (published layout-এর ভোক্তা); `TicketLayoutConfigs`, `TicketAttributes` টেবিল।

**6. API contracts.**

```json
// POST /admin/api/v1/ticket-layout   (TicketLayoutConfigCreated)
{ "id": 0, "ticketLayoutName": "SBNCS 2026 layouts", "ticketType": null,
  "defaultText": "Bangladesh Cricket Board", "ticketSize": "Default",
  "partnerSaleDefaultText": "Partner — not for sale", "programId": 7, "venueId": 2, "venueGalleryId": 12 }
```

`TicketLayoutType` enum (upload variant): `SingleSegmentUser(0), MultipleSegmentUser(1), SingleSegmentPartner(2), MultipleSegmentPartner(3), SingleSegmentComplimentary(4), MultipleSegmentComplimentary(5)`। Ticket attributes (`TicketAttributes`): show flag `ShowGallery, ShowBlock, ShowLevelRow, ShowEntryGate, ShowMiniGate, ShowVenueName, ShowSegmentDateTime` (+ DITF: `ShowTicketType, ShowEntryTime, ShowExitTime`) ও সংশ্লিষ্ট `*Priority` ক্রম field (default 1–8)। অন্যান্য endpoint: `GET ""` paged (`searchText`), `GET program/{programId}`, `GET venue/{programId}/{venueId}`, `GET configs/{programId}/{venueId}/{venueGalleryId}`, `GET published/…`, `GET back-page/…`, `GET {id}`, `PUT {id}` (`TicketLayoutConfigUpdated`), `DELETE {id}`, `PUT publish|unpublish|duplicate/{id}`, `POST upload/back-page/{id}`, `DELETE delete-pdf/{id}` (+ back-page), `GET {id}/{ticketLayoutType}` (URL), `GET download-backpage/{eventId}` (PDF stream)। Error: `ArgumentException("Ticket Layout Config with ID {id} not found.")` → 400।

**7. Data and side effects.** `TicketLayoutConfigs`/`TicketAttributes` row; S3-এ PDF; `TicketSize` QR position-এ ম্যাপ করে (`Default/Vertical [900,650,650]`, `A4 [1650,915,650]`, `Horizontal [2494,1055,650]`) — F5.8-এ ব্যবহৃত।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/ticket-layout-management/services/ticket-layout.service.ts` (`program-management/services/`-এ কাছাকাছি আরেকটি আছে); `…/program-management/services/ticket-attributes.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/{TicketLayoutConfigsController,TicketAttributesController}.cs`।

**9. Handover notes.** ① Ticketing **published** config-ই ব্যবহার করে (`GetPublishedAsync(programId, venueId, galleryId)`); upload-করা কিন্তু unpublished PDF উপেক্ষিত। ② কোনো gallery-র published template না থাকলে টিকিট তৈরির সময় exception (400) — বিক্রি খোলার আগে layout publish করুন।

### F1.14 Ticket-pricing content page

> **Bangla name:** টিকিট-প্রাইসিং কনটেন্ট পেজ

**1. Name and purpose.** Public "ticket pricing" page-এর editorial content (program/venue অনুযায়ী নাম-দেওয়া দামের স্তর) রক্ষণাবেক্ষণ — portal ও app-এ দেখায় (F2.3)।

**2. Trigger and actor.** Admin portal → `/content-editor/ticket-pricing`। Role: `TicketPricingController`-এ **কোনো `[Authorize]` নেই** (F6.18); portal-এ screen-টি admin-only।

**3. Business flow.** Staff program/venue-প্রতি pricing entry বানান — নাম-দেওয়া attribute (স্তরের নাম + দাম) সহ — publish/unpublish করেন; public page (F2.3) published entry দেখায়।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/ticket-pricing` | **[HTTP + user token]** | `CreateOrUpdateTicketPricing` |
| 2 | Admin DB | **[Shared table]** | `TicketPricings` + `TicketPricingAttributes`; Event service `list` publicly দেয় (Redis key `ticket_pricing_all`) |

**5. Components.** Admin portal (`content-editor.service.ts`); Admin service; Event service (public read); `TicketPricings`, `TicketPricingAttributes` টেবিল।

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

Endpoint: `GET ""` paged, `GET list`, `GET {id}`, `PUT {id}`, `DELETE {id}`, `PUT publish/{id}`, `PUT unpublish/{id}`, `DELETE attribute/{attributeId}`। Public shape: `TicketPricingProgram` (sample F2.3-এ)। Error: standard envelope।

**7. Data and side effects.** Pricing টেবিল upsert; Redis `ticket_pricing_all` cache TTL পর্যন্ত পুরোনো।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/content-editor/services/content-editor.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/TicketPricingController.cs`; public দিক `…/Event.Service/Api/TicketPricingController.cs`।

**9. Handover notes.** এটি **editorial** content (দেখানোর নাম ও দাম), বিক্রি চালানো আসল level-দাম (F1.9) থেকে আলাদা — দুটি একসাথে না রাখলে আলাদা হয়ে যেতে পারে; হাতে মিলিয়ে রাখতে হয়।

### F1.15 Promo code

> **Bangla name:** প্রোমো কোড ব্যবস্থাপনা

**1. Name and purpose.** **Promo code** তৈরি (checkout-এ customer যে ছাড়ের কোড লেখে) — ছাড়ের মান, মেয়াদ, ব্যবহারের সীমা ও assignment (কোন program/event/gallery-তে প্রযোজ্য) সহ।

**2. Trigger and actor.** Admin portal → `/promo-management`, `/promo-management/create`, `/promo-management/edit-promo/:promoCodeId`। Role: শুধু `admin` (`PromoCodeController`-এ `[Authorize(Roles = admin)]`)।

**3. Business flow.**
1. Staff Promo Management → Create Promo Code খোলেন।
2. Code, নাম, program, discount type (শতাংশ/ফিক্সড), মান, শুরু/শেষ date-time, মোট ব্যবহারের সীমা ও per-user সীমা দেন।
5. Code-টি program/event/gallery-তে assign করেন (assign type + টার্গেট তালিকা)।
4. Save করলে মেয়াদের জন্য code active; background worker (F5.16) তারিখ অনুযায়ী auto expire/reactivate করে।
5. তালিকায় paged code দেখায়; অন্য screen-এ save-এর আগে `exists` যাচাই।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal `promo-management.service.ts` → Admin `POST /admin/api/v1/promo-codes` | **[HTTP + user token]** | JSON `CreateOrUpdatePromoCode` |
| 2 | Admin `PromoCodeController` → `PromoCodeManager` | — | `PromoCodes` + `PromoCodeAssigns` (+ `PromoCodeVenueEventGallery` join row) insert |
| 3 | Checkout (user) | **[Shared table]** | Booking কোড apply-এর সময় নিজের mirror দিয়ে `PromoCodes`/`PromoCodeAssigns` পড়ে (F2.5) |
| 4 | Admin worker | **[Worker: 2 min]** | `PromoCodeStatusUpdateService` তারিখ অনুযায়ী status ওল্টায় (F5.16) |

**5. Components.** Admin portal; Admin service; Booking (read mirror); `PromoCodes`, `PromoCodeAssigns`, `PromoCodeVenueEventGallery` টেবিল।

**6. API contracts.** Base: `/admin/api/v1/promo-codes`। Auth: Admin pool, role `admin`।

| Method | Path | Request | Response |
|---|---|---|---|
| GET | `` | `pageOffset,pageSize,sortBy,sortOrder` | paged promo code (মোট `X-Total-Count` নয় — `{items,totalCount}`) |
| GET | `list` | — | সব code (dropdown-এর জন্য) |
| GET | `{id}` | — | একটি promo code |
| GET | `code/{code}/{eventId}` | — | event-এ কোড অনুসন্ধান |
| GET | `exists` | — | অস্তিত্ব যাচাই |
| POST / PUT `{id}` | `` / `{id}` | `CreateOrUpdatePromoCode` | তৈরি/হালনাগাদ entity |
| DELETE | `{id}` | — | মোছা entity |

`CreateOrUpdatePromoCode` (`Services/Admin/ETP.Admin.Domain/Models/PromoCodes/CreateOrUpdatePromoCode.cs`):

```json
// POST /admin/api/v1/promo-codes
{
  "code": "BCBWELCOME",
  "name": "Welcome offer",
  "programId": 7,
  "discountType": 1,            // DiscountType enum (Admin-এ enum সংখ্যা হিসেবে, §0.7)
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

মূল error: standard envelope (§0.7); একই code → manager থেকে 400।

**7. Data and side effects.** উপরের টেবিল; queue message নেই; email নেই; F5.16 পরে একই row-তে `Status` হালনাগাদ করে।

**8. Code references.**

| কী | কোথায় |
|---|---|
| Portal service | `rvl-gobcb-admin-portal/src/app/features/promo-management/services/promo-management.service.ts` |
| Page | `rvl-gobcb-admin-portal/src/app/features/promo-management/pages/…` |
| Controller | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/PromoCodeController.cs` |
| Worker | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Workers/BackgroundServices/PromoCodeStatusUpdateService.cs` |
| Read mirror | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Storage/DbContexts/BookingDbContext.cs` |

**9. Handover notes.** ① শুধু `admin` role promo code সামলাতে পারে, অথচ প্রতিটি customer checkout একই row-এর উপর নির্ভরশীল — BS23-এর কাছে ইচ্ছাকৃত কিনা যাচাই করুন। ② `DiscountType`/`AssignType` enum-এর সংখ্যা Admin সংখ্যা হিসেবে serialize করে (§0.7); Angular UI সংখ্যা পাঠায়।

### F1.16 System discount

> **Bangla name:** সিস্টেম ডিসকাউন্ট ব্যবস্থাপনা

**1. Name and purpose.** **স্বয়ংক্রিয় ছাড়** তৈরি (কোড লাগে না — যেমন early-bird) — মান, মেয়াদ ও program/event/gallery assignment-সহ। User portal মেয়াদের ভেতরে দাম দেখানোর সময় স্বয়ংক্রিয়ভাবে প্রয়োগ করে (F2.4)।

**2. Trigger and actor.** Admin portal → `/promo-management/discount`, `…/create-discount`, `…/edit-discount/:discountId`। Role: `admin` (`DiscountController`)।

**3. Business flow.**
1. Staff Discount Management → Create Discount খোলেন।
2. নাম, program, discount type/মান ও মেয়াদ দেন, টার্গেট assign করেন (event/gallery)।
3. Save করলে discount তৈরি; মেয়াদে public price endpoint স্বয়ংক্রিয়ভাবে প্রয়োগ করে; worker F5.17 তারিখে status ওল্টায়।
4. Checkout-এর সময় user portal-এর পড়ার জন্য একটি anonymous read endpoint-ও আছে (`program/{programId}/{eventId}/{galleryId}`)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/discount` | **[HTTP + user token]** | JSON `CreateOrUpdateDiscount` |
| 2 | Admin `DiscountController` → manager | — | `Discounts` + `DiscountAssigns` (+ join row) insert |
| 3 | Checkout-এ user portal | **[HTTP + user token]** (auth লাগে না — `[AllowAnonymous]`) | `GET /admin/api/v1/discount/program/{programId}/{eventId}/{galleryId}` সেই scope-এর active discount |
| 4 | Booking-এর দাম হিসাব | **[Shared table]** | Booking `Discounts`/`DiscountAssigns` mirror করে ও `TotalCharge` কমায় (F2.6) |
| 5 | Admin worker | **[Worker: 2 min]** | `SystemDiscountStatusUpdateService` তারিখে activate/expire করে (F5.17) |

**5. Components.** Admin portal; Admin service (মালিক); Booking (mirror); user portal (পাঠক); `Discounts`, `DiscountAssigns`, `DiscountVenueEventGallery` টেবিল।

**6. API contracts.** Base: `/admin/api/v1/discount`। Auth: Admin pool, role `admin` (public read ছাড়া)।

| Method | Path | Auth | Request | Response |
|---|---|---|---|---|
| GET | `` | admin | paged query | paged discount |
| GET | `list` / `{id}` / `exists?eventIds=&discountId=` | admin | — | তালিকা / একটি / যাচাই |
| POST / PUT `{id}` | | admin | `CreateOrUpdateDiscount` | entity |
| DELETE | `{id}` | admin | — | entity |
| GET | `program/{programId}/{eventId}/{galleryId}` | **anonymous** | — | scope-এর active discount |

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

**7. Data and side effects.** উপরের টেবিল; queue/email নেই।

**8. Code references.**

| কী | কোথায় |
|---|---|
| Portal service | `rvl-gobcb-admin-portal/src/app/features/promo-management/services/promo-management.service.ts` |
| Controller | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/DiscountController.cs` |
| Portal থেকে public read | `rvl-gobcb-user-portal/ETP-Web/src/app/modules/core/services/api/booking-api.service.ts` |
| Worker | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Workers/BackgroundServices/SystemDiscountStatusUpdateService.cs` |

**9. Handover notes.** ① Public discount endpoint ইচ্ছাকৃতভাবে `[AllowAnonymous]` (checkout page-এ কোনোক্রমে লগইনের আগে দরকার) — শুধু discount metadata দেয়। ② Promo code ও system discount একসাথে প্রযোজ্য হলে নিয়ম Booking-এর দাম হিসাবের ভেতরে (F2.6) — কোনোটি বদলানোর আগে পরীক্ষা করুন।

### F1.17 Ticket-checker (gate staff) account

> **Bangla name:** টিকিট-চেকার (গেট স্টাফ) অ্যাকাউন্ট

**1. Name and purpose.** Gate staff-দের TicketChecker-pool account তৈরি ও ব্যবস্থাপনা — নাম+ফোন দিয়ে তৈরি, নাম বদল, set/force password, disable/enable, delete।

**2. Trigger and actor.** Admin portal → `/ticket-checker`। Role: `admin`, `event_manager`, `ticket_manager`, `ticket_operator` (`TicketCheckerController`)।

**3. Business flow.** Staff নাম ও ফোন দিয়ে checker যোগ করেন; account-এ অস্থায়ী password আসে (পরে "set password"); checker app-এ সাইন-ইন করেন (F6.12); admin শিফটের মধ্যে account disable করলে app-এ `user_disabled_for_this_gate` দেখায় (F4.5)।

**4. Technical flow.** Portal → Admin `POST /admin/api/v1/ticket-checker` **[HTTP + user token]** → `TicketCheckerCreateUser {name, phone}` → Cognito TicketChecker pool (`Integration/Services/…UserProvider`)। ফেরত আসে `TicketCheckerUserResponse`।

**5. Components.** Admin portal (`ticket-checker.service.ts`); Admin service; Cognito TicketChecker pool।

**6. API contracts.** Base `/admin/api/v1/ticket-checker`: `GET ""` / `{id}` → `TicketCheckerUserResponse { userId, name, email, phone, role, currentStatus, isActive, isPhoneNumberVerified }`; `POST` `{ "name": "Gate Checker 12", "phone": "+8801712345678" }`; `PUT {id}` `TicketCheckerUpdateUser {userId, name}`; `PUT change-password` `TicketCheckerChangePassword {accessToken, oldPassword, newPassword}`; `DELETE {id}`; `POST disable/{id}|enable/{id}`; `POST set-password` `TicketCheckerSetPasswordRequest {password, userId}`। আরও `GET search?name=`, `GET search-by-userid?sub=` (gate assignment-এ, F1.18)। Error: standard envelope।

**7. Data and side effects.** Cognito user CRUD; ETP টেবিল নেই (gate-user সম্পর্ক F1.18-এর `TicketCheckerGateUsers`-এ)।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/ticket-checker/services/ticket-checker.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/TicketCheckerController.cs`, `…/Integration/Services/TicketCheckerUserProvider.cs`।

**9. Handover notes.** `change-password` body-তে checker-এর নিজের access token নেয় — কে ডাকে যাচাই করুন (এখন admin portal admin token পাঠায়; checker app-এ password-change screen নেই)।

### F1.18 Gate assignment ও download control

> **Bangla name:** গেট অ্যাসাইনমেন্ট ও ডাউনলোড নিয়ন্ত্রণ

**1. Name and purpose.** Ticket checker-দের event-এর entry gate-এ যুক্ত করা (multi-assign, force-assign/unassign) এবং প্রত্যেক checker-এর offline download অনুমতি (`IsDownloadEnable`) নিয়ন্ত্রণ।

**2. Trigger and actor.** Admin portal → `/ticket-checker` → assign-gate dialog (`components/event-assign-gate/`)। Role: admin pool; `TicketCheckerGateController` ভিন্ন action-এ `admin` ও `ticket-checker` উভয় scheme নেয়।

**3. Business flow.**
1. Staff event বেছে নেন; screen-এ event-এর gate ও প্রতিটিতে কোন checker আছে দেখায়।
2. Checker-দের gate-এ assign করেন (বা **force-assign/unassign** bulk তালিকা); `event-info` (F4.1) সাথে সাথে আপডেট হয়।
3. Checker-এর download অনুমতি toggle করতে পারেন ও gate থেকে সরাতে পারেন।
4. Event শেষ হলে worker স্বয়ংক্রিয়ভাবে download access বন্ধ করে (F5.15)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/ticket-checker-gate` | **[HTTP + user token]** | `AssignTicketCheckerGate` (নিচে) |
| 2 | Portal → Admin `POST …/force-assign` / `force-unassign` | **[HTTP + user token]** | `List<AssignTicketCheckerGate>` bulk |
| 3 | Admin DB | **[Shared table]** | `TicketCheckerGates` + `TicketCheckerGateUsers`; TicketChecker service mirror দিয়ে পড়ে (F4.1) |
| 4 | `PUT …/update-download-status/{userId}/{gateId}/{status}` | **[HTTP + user token]** | `IsDownloadEnable` ওল্টায় |
| 5 | Redis | — | `TicketCheckerLevelGateMap` hash (level→gate) `TicketCheckerGateManager` রাখে; Ticketing signed টিকিট gate cache-এ দেওয়ার সময় ব্যবহার করে (F5.8-এর শেষ ধাপ) |

**5. Components.** Admin portal; Admin service; `TicketCheckerGates`, `TicketCheckerGateUsers` টেবিল; Redis map; checker app (ভোক্তা)।

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

আরও: `GET {eventId}` (event-এর gate user), `GET user/{userId}`, `DELETE remove-user/{id}`, `GET event-info` (policy `ticket-checker` — checker app-এর নিজের call, sample F4.1-এ)। Error: standard envelope।

**7. Data and side effects.** Gate/gate-user row; Redis map হালনাগাদ; queue নেই।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/ticket-checker/services/ticket-checker-gate.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/TicketCheckerGateController.cs`, `…/Managers/TicketCheckerGateManager.cs`।

**9. Handover notes.** `EntryGateId` কমা-দিয়ে-লেখা id string (TicketChecker storage entity-র সাথে মেলে) — cast নয়, parse করুন।

### F1.19 Gate (ticket-checker) report

> **Bangla name:** গেট রিপোর্ট (চেকার)

**1. Name and purpose.** Event-প্রতি scan report: gate/checker-প্রতি entry সংখ্যা, duplicate entry (একই টিকিট বারবার scan), manual entry, আর audit-এর জন্য Excel export।

**2. Trigger and actor.** Admin portal → `/report/checker`, `/report/ticket-duplicate`। Role: `admin`, `event_manager`, `ticket_manager`, `ticket_operator` (`TicketCheckerGateController`)।

**3. Business flow.**
1. Staff event বেছে gate → checker অনুযায়ী entry/manual/duplicate সংখ্যার গাছ দেখেন।
2. Duplicate-entry report বারবার scan হওয়া টিকিটের তালিকা দেয় (details drill-down-সহ)।
3. Manual-entry report টাইপ করা নম্বরে ঢোকানো টিকিট দেয়।
4. "Export" checked-ticket তালিকা Excel-এ নামায়।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/ticket-checker-gate/report/{eventId}` | **[HTTP + user token]** | `TicketCheckerGateReportData` গাছ |
| 2 | Portal → Admin `GET …/export/{eventId}` | **[HTTP + user token]** | Excel stream (row = `CheckedTicketExportData`) |
| 3 | Portal → Admin `POST …/duplicate-tickets/{eventLongId}` / `manual-entry-tickets/{eventLongId}`; `GET reports/duplicate-entries[/details]` | **[HTTP + user token]** | aggregate |
| 4 | Data source | **[Shared table]** | `CheckedTickets` টেবিল — worker F5.14 checker-দের Redis counter থেকে ভরে |

**5. Components.** Admin portal (`report.service.ts`); Admin service; `CheckedTickets` টেবিল; ClosedXML।

**6. API contracts.** `TicketCheckerGateReportData { eventId, ticketCheckerGateId (string), eventName, ticketCheckerGateName, ticketCheckerName, entryCount, manualEntryCount, duplicateEntryCount }` (গাছের node-এ `children`)। Export row: `CheckedTicketExportData { ticketNumber, ticketCheckerGateName, ticketCheckerName, entryCount, ticketType }`। Error: standard envelope।

**7. Data and side effects.** শুধু পাঠ।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/reports/services/report.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/TicketCheckerGateController.cs`।

**9. Handover notes.** Report লাইভ স্ক্যানের চেয়ে ~৩০ মিনিট পেছনে (F5.14 drain cycle); ইভেন্ট চলাকালে লাইভ অবস্থা জানতে checker app-এর counter দেখুন।

### F1.20 Raffle draw

> **Bangla name:** র‍্যাফল ড্র

**1. Name and purpose.** কোনো event-এর বৈধ টিকিট নম্বর থেকে রাজ্য পুরস্কারের বিজয়ী রেকর্ড করা এবং পুরস্কার হস্তান্তরে টিকিটের holder-এর তথ্য খোঁজা।

**2. Trigger and actor.** Admin portal → event screen-এর raffle draw winner dialog। Role: `admin`, `event_manager` (`RaffleDrawController`)।

**3. Business flow.** Staff বাইরে একটি বিজয়ী টিকিট টানেন (বা নম্বর বাছেন), খুঁজে দেখেন (`details`), বিজয়ী হিসেবে রেকর্ড করেন; তালিকায় event-এর বিজয়ীরা থাকে, মুছে ফেলাও যায়।

**4. Technical flow.** Portal → Admin `POST /admin/api/v1/raffle-draw` **[HTTP + user token]** → `RaffleDraw` row (denormalized টিকিট + order তথ্য); `GET details/{eventId}/{ticketNumber}` `Tickets` mirror থেকে holder-এর নাম/পরিচয় বের করে (shared table)।

**5. Components.** Admin portal (`raffle-draw-winner.service.ts`); Admin service; `RaffleDraws`, `Tickets` (mirror) টেবিল।

**6. API contracts.** `RaffleDraw { ticketNumber, ticketType, userId, ticketHolderName, ticketHolderIdentification, eventLongId, eventPublicId, bookingOrderId, bookingOrderPublicId, bookingOrderDateTime, orderNumber }`; endpoint `GET ?eventId=`, `GET details/{eventId}/{ticketNumber}`, `POST`, `DELETE {id}`। Error: standard envelope।

**7. Data and side effects.** শুধু `RaffleDraws` row।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/events/services/raffle-draw-winner.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/RaffleDrawController.cs`।

**9. Handover notes.** ড্র নিজে (র‍্যান্ডম বাছাই) server-এ নেই — এই feature শুধু ফলাফল রেকর্ড করে।

### F1.21 Dashboard

> **Bangla name:** ড্যাশবোর্ড

**1. Name and purpose.** Program dashboard: tile (মোট event, অমীমাংসিত issue) ও বিক্রয় চার্ট (টিকিট বিক্রয় সারসংক্ষেপ, শেষ সপ্তাহ/মাসের আসন বিক্রি, আসন্ন event)।

**2. Trigger and actor.** Admin portal → `/` (dashboard)। Role: `admin`, `ticket_operator` + `[AuthorizeProgram]` (Admin-এর `DashboardController`) — program attribute active একমাত্র এই controller-এ।

**3. Business flow.** Staff একনজরে দেখেন: program-এ কত event, কতটি upcoming/running/past, মোট বিক্রি ও পরিমাণ, সাত দিনের বিক্রয় চার্ট।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/dashboard/get-tile-data?programId=` | **[HTTP + user token]** | `TileData { totalEvents, unResolveIssue }` |
| 2 | Portal → Admin `GET /admin/api/v1/dashboard/get-event-by-category` | **[HTTP + user token]** | `EventsByCategory { totalUpcoming, totalPast, totalRunning }` |
| 3 | Portal → Booking `GET /booking/api/v1/dashboard/get-ticket-sales-summary?programId=` | **[HTTP + user token]** | `TicketSalesSummary { numberOfTotalTicketSale, amountOfTotalTicketSale }` |
| 4 | Portal → Booking `GET …/get-upcomming-seven-events` / `get-last-week-seats-sale-amount` / `get-last-Month-seats-sale-amount` | **[HTTP + user token]** | `DashboardChartData { labels[], datasets[{ label, data[] }] }` |

**5. Components.** Admin portal (`dashboard.service.ts`, chart.js); Admin + Booking service; `Events`, `UserIssues` (Admin), `UserBookingOrders` (Booking) টেবিল।

**6. API contracts.** উপরের shape; sample:

```json
// GET /booking/api/v1/dashboard/get-last-week-seats-sale-amount
{ "labels": ["Mon 29","Tue 30","Wed 01","Thu 02","Fri 03","Sat 04","Sun 05"],
  "datasets": [ { "label": "Seats sold", "data": [120, 340, 510, 80, 950, 1210, 430 ] } ] }
```

Error: standard envelope; Admin dashboard endpoint-এ `X-Program-Id` না থাকলে 400 (F1.1)।

**7. Data and side effects.** শুধু-পাঠ aggregate।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/dashboard/services/dashboard.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/DashboardController.cs`, `…/Booking.Service/Api/BookingReportController.cs`।

**9. Handover notes.** Tile/চার্ট **দুই service** থেকে আসে (Admin + Booking) — program scoping ভিন্নভাবে (header বনাম query param, §F1.1)।

### F1.22 Booking, sales, revenue ও payment-discrepancy report

> **Bangla name:** বুকিং, বিক্রয়, রাজস্ব ও পেমেন্ট-ডিসক্রিপ্যান্সি রিপোর্ট

**1. Name and purpose.** Reports menu: event-প্রতি booking order, booking metrics, event-wise/summary বিক্রি ও রাজস্ব, day-wise revenue, payment discrepancy (gateway বনাম ledger) — Excel export-সহ।

**2. Trigger and actor.** Admin portal → `/report/*` page। Role: admin pool; Booking-এর `ReportController`-এ **কোনো `[Authorize]` নেই** (F6.18)।

**3. Business flow.** Staff program/event/তারিখ দিয়ে ফিল্টার করে দেখেন বা export করেন: booking order তালিকা, event-প্রতি capacity/বিক্রি metrics, রাজস্ব (VAT-সহ/ছাড়া), DgePay transaction ও রেকর্ড করা payment-এর অসঙ্গতি।

**4. Technical flow.** Portal → Booking `GET /booking/api/v1/report/admin/…` **[HTTP + user token]** → `ReportController` (`export-booking-orders`-এ ClosedXML Excel) — `UserBookingOrders`, `Capacities`, `SeatReservations` পড়ে; portal picker-এ Admin `events/search`-ও ব্যবহার করে।

**5. Components.** Admin portal (`report.service.ts`, `booking-orders.service.ts`); Booking service; ClosedXML; `UserBookingOrders`, `Capacities`, `SeatReservations` টেবিল।

**6. API contracts.** Endpoint (`/booking/api/v1/report/admin/`): `export-booking-orders?eventId&programId` (Excel), `revenue-report-list?startDate&endDate&eventId&programId`, `booking-metrics?eventId`, `event-revenue-summary?programId`, `event-sales-summary?programId`, `event-sales-details?id&programId`, `event-revenue-sales-details`, `payment-discrepancy?programId&eventId`। Shape:

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

`event-sales-summary`/`event-revenue-summary` item: `{ eventName, totalCapacity, onlineCapacity, onlineCapacityPercentage, onlineSold, onlineSoldPercentage, remainingOnlineSeats[, onlineRevenue, vat] }`; details variant-এ reserved/FOC/partner-sale ভাগ যোগ। Error: standard envelope।

**7. Data and side effects.** শুধু-পাঠ; Excel in-memory তৈরি।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/reports/services/{report,booking-orders}.service.ts`; `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/ReportController.cs`, `…/Domain/Models/Report/…`।

**9. Handover notes.** "FOC" (free of charge) ও partner-sale ভাগ reservation type (F1.11) থেকে আসে; discrepancy logic gateway record ও order row মেলায় — এর সঠিক matching নিয়ম data-নির্ভর `[UNCONFIRMED]`।

### F1.23 Reconciliation search

> **Bangla name:** রিকনসিলিয়েশন সার্চ

**1. Name and purpose.** Customer support-এর এক অর্ডার খোঁজা — order number / transaction id / ticket number / phone দিয়ে; পেমেন্ট অভিযোগ ("টাকা দিয়েছি টিকিট পাইনি") নিষ্পত্তির প্রবেশদ্বার।

**2. Trigger and actor.** Admin portal → `/issues/reconciliation`। Role: admin pool (`[Authorize(Policy = admin)]`)।

**3. Business flow.** Staff search type বেছে value লেখেন; মিলে যাওয়া order status, payment তথ্য ও user-সহ দেখেন; সেখান থেকে issue console বা order-এর টিকিট খোলেন।

**4. Technical flow.** Portal → Booking `GET /booking/api/v1/user-booking-order/admin/reconciliation/{searchType}/{searchText}` **[HTTP + user token]** → ফেরে `UserBooking` (পূর্ণ shape F2.7-এ); phone দিয়ে খুঁজলে Serverless API (`user/get-bulk-users`) user বের করে, ticket-number দিয়ে খুঁজলে `Tickets` mirror।

**5. Components.** Admin portal (`reconciliation.service.ts`, `booking-orders.service.ts`); Booking service; Serverless API (user lookup)।

**6. API contracts.** `searchType` enum: `OrderNumber | TransactionId | TicketNumber | PhoneNo`। Response: `UserBooking` (sample F2.7-এ)। Error: standard envelope (না পেলে 404-স্টাইল বার্তা)।

**7. Data and side effects.** শুধু-পাঠ।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/issues/services/reconciliation.service.ts`; `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/UserBookingOrderController.cs` (`admin/reconciliation/…`)।

**9. Handover notes.** "paid but not generated" জাতীয় অভিযোগের দ্রুততম হাতিয়ার; F2.8-এর generate-request-এর সাথে মিলিয়ে ব্যবহার করুন।

### F1.24 User issue ও support chat (admin পাশ)

> **Bangla name:** ইউজার ইস্যু ও সাপোর্ট চ্যাট (অ্যাডমিন পাশ)

**1. Name and purpose.** Program/অবস্থা অনুযায়ী customer issue-এর তালিকা, রিয়েল-টাইম chat-এ উত্তর, status/feedback হালনাগাদ, এবং এক জায়গায় customer-এর order + টিকিট দেখা।

**2. Trigger and actor.** Admin portal → `/issues/list`, `/issues/:id/details`। Role: Admin proxy-তে `admin`, `customer_support`; UserIssue service-তে policy `admin` (customer call-এ `user`)।

**3. Business flow.**
1. Support Issues খোলেন: paged, filter-যোগ্য তালিকা (status, program, order/issue/txn/phone দিয়ে সার্চ)।
2. Issue খুললে chat thread (attachment-সহ), customer-এর order সারসংক্ষেপ ও টিকিট দেখায়।
3. Support রিয়েল-টাইমে উত্তর দেন (typing indicator, read receipt), feedback দেন ও issue resolve করেন।
4. Resolve করলে external Notification API-র মাধ্যমে customer-কে SMS যেতে পারে (`SendIssueResolvedNotification`)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/user-issue` | **[HTTP + user token]** | paged issue (Admin `UserIssueClient` দিয়ে proxy/enrich করে) |
| 2 | Portal → Admin `PUT /admin/api/v1/user-issue/{id}` | **[HTTP + user token]** | `UpdateUserIssue { feedback, status }` |
| 3 | Chat REST | **[HTTP + user token]** | `POST /admin/api/v1/user-issue-chat/send` (multipart), `GET {id}/messages|recent|last|unread-count`, `mark-read?receiverType=ADMIN`, attachment download |
| 4 | Chat রিয়েল-টাইম | **[SignalR]** | Admin portal **UserIssue hub**-এ যুক্ত হয় `{userissuehub}/userissue/chathub?access_token=…` (শুধু WebSocket) — customer-রা যে hub ব্যবহার করে (F2.12) সেটিই |
| 5 | Attachment | — | S3 media bucket `chat-attachments/{issueId}/{guid}{ext}`, `ICloudFrontMediaManager` দিয়ে |
| 6 | Resolve হলে | **[HTTP, static key]** | Admin → Notification API `POST /notification/request` (`IssueResolvedNotification`) |

**5. Components.** Admin portal (`issue.service.ts`, `chat.service.ts`, @microsoft/signalr); Admin service (proxy + নিজের `/admin/chathub` — legacy, note দ্রষ্টব্য); UserIssue service (মালিক); S3; Notification API (external); SignalR public ingress `chat.gobcbticket.com.bd`।

**6. API contracts.** মূল shape (UserIssue service): `ReportedUserIssue { id, user (CognitoUser), issueNumber, orderNumber, transactionId, orderStatus, orderDate, publicOrderId, description, feedback, status ("Open"/"Resolved"), createdAt/…, resolvedAt/… }`, `ReportedUserIssueDetails` যোগ করে `eventName, paymentInfo, tickets[]`; chat message: `ReportedUserIssueChatMessage { id, reportedIssueId, message, senderType ("USER"/"ADMIN"), senderId, senderName, isRead, attachmentFileName/Path/ContentType/Size, createdAt }`। Hub method: `SendMessage`, `JoinUserIssueChat`, `LeaveUserIssueChat`, `SendTypingIndicator`, `StopTyping`; client event: `NewMessage`, `MessagesRead`, `UserJoined`, `UserLeft`, `UserTyping`, `UserStoppedTyping`, `MessageError`। Error: standard envelope।

**7. Data and side effects.** `ReportedIssues` / `ReportedIssueChatMessages` row (মালিক UserIssue); S3 attachment; resolve-তে SMS।

**8. Code references.**

| কী | কোথায় |
|---|---|
| Portal service | `rvl-gobcb-admin-portal/src/app/features/issues/services/{issue,chat,reconciliation}.service.ts` |
| Admin proxy | `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/{UserIssueController,UserIssueChatController}.cs` |
| মালিক service | `rvl-gobcb-backend/Services/UserIssue/ETP.UserIssue.Service/Api/{ReportIssueController,ReportIssueChatController}.cs`, `Hubs/UserIssueChatHub.cs` |
| Notification | `rvl-gobcb-backend/Core/ETP.Core/ServiceClient/NotificationClient/NotificationClient.cs` |

**9. Handover notes.** ① Admin service-এর নিজের hub `/admin/chathub` (একই hub class) — portal UserIssue hub ব্যবহার করে, তাই Admin hub **legacy** মনে হয় `[UNCONFIRMED]`। ② UserIssue-এর **chat REST controller-এ `[Authorize]` নেই** (F6.18) — hub authorized, history/send endpoint network placement-এর উপর নির্ভরশীল। ③ Admin proxy-র `user-detail/{orderId}` `[AllowAnonymous]`।

### F1.25 Admin user

> **Bangla name:** অ্যাডমিন ইউজার ব্যবস্থাপনা

**1. Name and purpose.** Staff account তৈরি ও ব্যবস্থাপনা: নাম/ফোন/email, **role** (`admin`, `event_manager`, `ticket_manager`, `ticket_operator`, `customer_support`), program scope, enable/disable, set/force password, delete।

**2. Trigger and actor.** Admin portal → `/users`। Role: শুধু `admin` (`AdminUsersController`)।

**3. Business flow.**
1. Admin নাম, ফোন, email, role ও (ঐচ্ছিক) program id দিয়ে staff account বানান।
2. Account-এ অস্থায়ী Cognito password আসে — নতুন staff প্রথম লগইনে বদলান (F6.1) বা admin "set password" দেন।
3. Disable/enable account রেখে লগইন আটকায়; "forgot password" (`forget-password?phoneNo=` + `set-forget-password`) SMS দিয়ে reset করে।
4. Role ও program বদল cache refresh-এর পরে কার্যকর (client-এ ৫৫ মিনিট পর্যন্ত, F6.4)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/admin-users` | **[HTTP + user token]** | `AdminCreateUser { name, phone, email, role, programIds }` |
| 2 | Admin `Integration/Services/AdminUserProvider` | — | Cognito Admin-pool user তৈরি; `custom:role` ও `custom:program_ids` attribute লেখে |
| 3 | Portal → Admin `PUT {id}` / `disable/{id}` / `enable/{id}` / `set-password` | **[HTTP + user token]** | `AdminUpdateUser { userId, name, role, programIds }` প্রভৃতি — আবার Cognito |
| 4 | Forgot password | **[HTTP, no token]** (`[AllowAnonymous]`) | `GET forget-password?phoneNo=` (SMS OTP) → `POST set-forget-password { userId, password }` |

**5. Components.** Admin portal (`user.service.ts`); Admin service; Cognito Admin pool; Serverless API (SMS)।

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

আরও `GET {id}`, `DELETE {id}`, `POST disable/{id}`, `POST enable/{id}`, `POST set-password { userId }`, `GET forget-password?phoneNo=`, `POST set-forget-password { userId, password }`। Error: standard envelope।

**7. Data and side effects.** শুধু Cognito user record (staff-দের ETP টেবিল নেই)।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/users/services/user.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/AdminUsersController.cs`, `…/Integration/Services/AdminUserProvider.cs`।

**9. Handover notes.** ① Role-এর অর্থ F6.15-এ; program id F6.16-এ। ② Registration UI নেই — account তৈরি কেবল admin-এর হাতে, ইচ্ছাকৃত।

### F1.26 Agent (বিক্রেতা) user

> **Bangla name:** এজেন্ট (বিক্রেতা) ইউজার

**1. Name and purpose.** Offline বিক্রেতাদের **Agent-pool** account ব্যবস্থাপনা (নাম, ফোন, কোম্পানি/শাখা) — যারা offline-sold টিকিট রেকর্ড করে (F6.13)।

**2. Trigger and actor.** Admin portal → `/agent-user`। Role: **নেই** — `AgentController`-এ (`api/v1/agent-users`) **কোনো `[Authorize]` নেই** (F6.18)।

**3. Business flow.** Staff কোম্পানি তথ্যসহ agent বানান, password সেট করেন, disable/enable বা delete করেন; agent-রা তখন (Agent pool) লগইন করে টিকিট offline বিক্রি হিসেবে চিহ্নিত করেন।

**4. Technical flow.** Portal → Admin `POST /admin/api/v1/agent-users` **[HTTP — token যায় কিন্তু enforce হয় না]** → `AgentCreateUser { name, phone, email?, companyName, companyBranch, branchLocation }` → Cognito Agent pool। Response `AgentUserResponse`-এ `currentStatus/isActive/isPhoneNumberVerified` ও কোম্পানি field।

**5. Components.** Admin portal (`agent-user.service.ts`); Admin service; Cognito Agent pool।

**6. API contracts.** Base `/admin/api/v1/agent-users`: `GET ""`, `GET {id}`, `POST`, `PUT {id}` (`AgentUpdateUser { userId, name }`), `DELETE {id}`, `POST disable/{id}|enable/{id}`, `POST set-password` (`AgentUserSetPasswordRequest { password, userId }`)। Error: standard envelope।

**7. Data and side effects.** শুধু Cognito Agent-pool record।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/agent-user/services/agent-user.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/AgentUserController.cs`, `…/Integration/Services/AgentUserProvider.cs`।

**9. Handover notes.** এই controller-এ `[Authorize]`-এর অভাব handover-এর সবচেয়ে নিরাপত্তা-সংবেদনশীল আবিষ্কারগুলোর একটি — service-এ পৌঁছাতে পারলে যে কেউ Agent account বানিয়ে password সেট করতে পারে (F6.18, Open queries)।

### F1.27 Activity log viewer

> **Bangla name:** অ্যাক্টিভিটি লগ ভিউয়ার

**1. Name and purpose.** Service-গুলোর প্রতিটি entity পরিবর্তনের audit trail ব্রাউজ করা (কে কী বদলাল, পুরোনো বনাম নতুন মান) — service/entity/event অনুযায়ী, paged।

**2. Trigger and actor.** Admin portal → `/activity-log` (global) ও event details-এর Activity tab। Role: `admin`, `event_manager` (`ActivityLogController`)।

**3. Business flow.** Staff service নাম, entity নাম (বা বাদ দিয়ে), entity id দিয়ে ফিল্টার করেন; তালিকায় action (Added/Modified/Deleted), পুরোনো/নতুন JSON, user, IP ও সময় দেখেন।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `GET /admin/api/v1/activity-log` | **[HTTP + user token]** | Query: `serviceName, entityNames, entityNamesToExclude, entityId, pageOffset, pageSize` |
| 2 | Admin `ActivityLogsManager` | **[Shared table]** | **প্রতিটি** service-এর `ActivityLogInterceptor`-এর (F6.24) লেখা shared `ActivityLogs` টেবিল পড়ে |
| 3 | অন্য service-গুলো | — | নিজেদের অংশ `POST batch` (`ActivityLogsBatchRequest`) দিয়ে পড়ে, `ETP.Admin.Client` library ব্যবহার করে |
| 4 | Event tab | **[HTTP + user token]** | `GET event/{eventId}` |

**5. Components.** Admin portal (`activity-log.service.ts`); Admin service; shared `ActivityLogs` টেবিল (LoggingDbContext, schema `etp`)।

**6. API contracts.** Entry shape (`ActivityLog`): `{ serviceName, entityName, entityId, action ("Added"/"Modified"/"Deleted"), oldValues, newValues (বদলানো property-র JSON; file part "[Image File]" মাস্কড), entityContext, transactionId, timestamp, userId, userName, ipAddress }`; paged envelope `{ items, totalCount }`। Batch request: `{ requests: [ { serviceName, entityName, entityId?, pageOffset, pageSize } ] }`। Error: standard envelope।

**7. Data and side effects.** এখানে শুধু-পাঠ; লেখা হয় F6.24-এ।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/global-activity-log/services/activity-log.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/ActivityLogController.cs`; লেখক পক্ষ `rvl-gobcb-backend/Core/ETP.Core.EntityFramework/Interceptors/ActivityLogInterceptor.cs`।

**9. Handover notes.** ① Insert গুলো save-এর **পরে** log হয় (DB id পাওয়ার জন্য); update শুধু বদলানো property log করে। ② Actor চিনে `username` claim; background worker লেখে `System`।

### F1.28 Media configuration (banner, gallery, যোগাযোগ, রেজিস্ট্রেশন)

> **Bangla name:** মিডিয়া কনফিগারেশন (ব্যানার, গ্যালারি, যোগাযোগ, রেজিস্ট্রেশন)

**1. Name and purpose.** Public site-এর image ব্যবস্থাপনা: hero banner, sponsor strip, graffiti/advertisement banner, gallery page-এর দুই segment, contact-us ও registration page-এর ছবি — ক্রম, publish ও duplicate-সহ।

**2. Trigger and actor.** Admin portal → `/media-configuration` sub-page। Role: `admin`, `event_manager` (`LandingPageImageController`)।

**3. Business flow.** Staff **type**-প্রতি image upload করেন, title/bdescription/action URL ও display order দেন, publish/unpublish করেন; gallery-র দুই segment একাধিক image + segment title নেয়; দুটি image-এর ক্রম অদল-বদলের action আছে।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/landing-page-image` | **[HTTP + user token]** | multipart `CreateOrUpdateLandingPageImage` (image + ঐচ্ছিক thumbnail) |
| 2 | Admin manager | — | media bucket-এ upload; `LandingPageImage` row-তে `Type`, `DisplayOrder`, publish flag |
| 3 | Public read | **[HTTP, no token]** | Event service `GET /event/api/v1/landing-page-image/public` (Redis key `landing_page_image_published`) |
| 4 | Gallery segment | **[HTTP + user token]** | `POST add-gallery-image` — `GalleryPageSegmentImages { firstSegmentTitle, firstSegmentImageFiles[], secondSegmentTitle, secondSegmentImageFiles[] }` |

**5. Components.** Admin portal (`media-configuration.service.ts`); Admin service; Event service; S3 media bucket; `LandingPageImage` টেবিল।

**6. API contracts.** `LandingPageImageType` মান (wire string): `Hero, Sponsors, Graffiti, Advertisement, Gallery_Page_Segment_1, Gallery_Page_Segment_2, Contact_Us, Registration, Notice, Terms_Condition, Privacy_Policy, FAQ`। Public item (`LandingPageImagePublic`): `{ title?, description?, actionUrl?, imageUrl, thumbnailUrl?, type, displayOrder, startDateTime?, endDateTime? }`। Endpoint: `GET ""`, `GET {id}`, `POST`, `PUT {id}`, `DELETE {id}`, `PUT publish/{id}|unpublish/{id}|duplicate/{id}`, `PUT display-order/{type}/{displayOrder1}/{displayOrder2}`, `POST add-gallery-image`। Error: standard envelope।

**7. Data and side effects.** `LandingPageImage` row; S3-এ file; public cache TTL বিলম্ব।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/media-configuration/services/media-configuration.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/LandingPageImageController.cs`।

**9. Handover notes.** ① Admin service `GET /admin/api/v1/gallery`-ও দেয় (`GallerySettings` config section থেকে স্থির তালিকা) — কিছু screen ব্যবহার করে। ② Enum-এ `Terms_Condition/Privacy_Policy/FAQ/Notice` image type আছে — legal page CMS-নির্ভর হওয়ার পরিকল্পনার প্রমাণ; portal এখন সেগুলো static asset থেকে দেখায় (F2.3 note) `[UNCONFIRMED]`।

### F1.29 Content editor (শর্তাবলি, FAQ, প্রাইভেসি, নোটিশ)

> **Bangla name:** কনটেন্ট এডিটর (শর্তাবলি, FAQ, প্রাইভেসি, নোটিশ)

**1. Name and purpose.** Customer-মুখী content-এর admin screen: terms & conditions, FAQ, privacy policy, notice ও ticket-pricing page।

**2. Trigger and actor.** Admin portal → `/content-editor/*`। Role: portal menu অনুযায়ী screen পৌঁছানো যায়; backend হলো ticket-pricing controller (F1.14) ও general-notice controller (F1.31)।

**3. Business flow.** Staff ticket-pricing matrix (F1.14) সম্পাদনা করেন ও notice publish করেন (F1.31); T&C/FAQ/privacy screen UI-তে আছে।

**4. Technical flow.** Ticket pricing → F1.14; notice → F1.31। **T&C/FAQ/privacy editor screen-এর জন্য কোনো API call পাওয়া যায়নি** — কোনো service-এ এমন controller নেই।

**5. Components.** Admin portal (`content-editor/` component); Admin service (শুধু pricing + notice)।

**6. API contracts.** শুধু F1.14 ও F1.31-এর।

**7. Data and side effects.** F1.14/F1.31-এর মতো।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/content-editor/components/…`, `services/content-editor.service.ts`।

**9. Handover notes.** Customer-দের দেখা legal টেক্সট static client asset-এ (portal i18n; app string) — এদের admin screen কার্যকরহীন shell মনে হয় `[UNCONFIRMED]` — BS23 নিশ্চিত করুন CMS-নির্ভর legal page পরিকল্পিত ছিল কিনা (F1.28-এর image-type enum ইঙ্গিত দেয়)।

### F1.30 Header/footer ও social-media settings

> **Bangla name:** হেডার/ফুটার ও সোশ্যাল-মিডিয়া সেটিংস

**1. Name and purpose.** Public header/footer সম্পাদনা (brand logo, "powered by" logo, title, ফোন, email, ঠিকানা) ও social link; সাথে read-only system settings।

**2. Trigger and actor.** Admin portal → `/settings/footer-settings`। Role: `admin` (`SocialMediaSettingsController`); `HeaderFooterController`-এ **কোনো `[Authorize]` নেই** (F6.18)।

**3. Business flow.** Staff brand/powered-by image upload করেন, contact field ও social URL পূরণ করেন; save করলে public site-এর header/footer-এ যায়।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `PUT /admin/api/v1/header-footer` | **[HTTP + user token]** | multipart `UpdateHeaderFooter` (brand/powered-by file + JSON field) |
| 2 | Portal → Admin `GET /admin/api/v1/header-footer` | **[HTTP, no token]** (controller-এ auth নেই) | বর্তমান মান |
| 3 | Public read | **[HTTP, no token]** | Event service `GET /event/api/v1/header-footer` (তালিকা) |
| 4 | Social | **[HTTP + user token]** | `GET|PUT /admin/api/v1/social-media-settings` |

**5. Components.** Admin portal (`footer-settings.service.ts`); Admin service; Event service; S3 media bucket; `HeaderFooter`, `SocialMediaSettings` টেবিল।

**6. API contracts.** `HeaderFooter { brandImageUrl?, poweredByImageUrl?, facebookUrl?, instagramUrl?, linkedInUrl?, twitterUrl?, title, phoneNumber?, email?, officeAddress? }`; `SocialMediaSettings { facebookUrl?, instagramUrl?, linkedInUrl?, twitterUrl? }`; `SystemSettings { id, allowUserSignInWithUserPassword, seatLockTimeout }` (read-only `GET /admin/api/v1/system-settings`, role `admin`)। Error: standard envelope।

**7. Data and side effects.** Settings row; image upload; public cache refresh।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/program-settings/services/footer-settings.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/{HeaderFooterController,SocialMediaSettingsController,SystemSettingsController}.cs`।

**9. Handover notes.** `SystemSettings.SeatLockTimeout` setting হিসেবে আছে, অথচ Booking-এর lock মেয়াদ ১২ মিনিট hard-coded (F5.3) — setting আসলেই এটি চালায় কিনা `[UNCONFIRMED]`।

### F1.31 General notice

> **Bangla name:** সাধারণ নোটিশ

**1. Name and purpose.** Program-scoped notice (মেয়াদসহ) publish করা, যা public portal হোম page-এ দেখায়।

**2. Trigger and actor.** Admin portal → `/settings/notice`। Role: `admin`, `event_manager` (`GeneralNoticeController`)।

**3. Business flow.** Staff notice-র টেক্সট লেখেন, শুরু/শেষ date-time দেন ও publish করেন; portal home published notice আনে (`GeneralNoticePublic { description }`) — Redis-এ cached (`general_notice_published`)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/general-notice` | **[HTTP + user token]** | `CreateOrUpdateGeneralNotice { programId, description, startDateTime, endDateTime, isPublished }` → `GeneralNotices` row |
| 2 | Public read | **[HTTP, no token]** | `GET /admin/api/v1/general-notice/public` `[AllowAnonymous]`; Redis key family `general_notice_published` |

**5. Components.** Admin portal (`notice.service.ts`); Admin service; `GeneralNotices` টেবিল; Redis।

**6. API contracts.** `GeneralNotice { id, programId, description, startDateTime, endDateTime, isPublished, isDeleted, isActive, createdAt/By, updatedAt/By }`; endpoint `GET ""`, `GET public`, `GET {id}`, `POST`, `PUT {id}`, `DELETE {id}`। Error: standard envelope।

**7. Data and side effects.** `GeneralNotices` row; public cache TTL।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/features/program-settings/services/notice.service.ts`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/GeneralNoticeController.cs`; portal পাঠক `rvl-gobcb-user-portal/ETP-Web/src/app/modules/core/services/api/event-api.service.ts`।

**9. Handover notes.** Notice টেক্সট একটিমাত্র description field (rich text/বাংলা variant নেই) — portal যেমন আছে তেমনই দেখায়।

## 2. User Web Portal

Angular user portal-এ (`rvl-gobcb-user-portal/ETP-Web`) customer-দের শুরু করা feature, User Cognito pool (বা OneID SSO)। Portal দ্বিভাষিক (`/:lang/en|bn` route, F2.13) এবং auth/session (F6.10) ছাড়া stateless। Registration ও login cross-cutting (F6.6–F6.10)।

### F2.1 Home page-এর কনটেন্ট

> **Bangla name:** হোম পেজের কনটেন্ট

**1. Name and purpose.** Landing page: hero banner, আসন্ন event, notice, footer/social link ও program তালিকা — সব admin portal-এ পরিচালিত (F1.28, F1.30, F1.31)।

**2. Trigger and actor.** User portal `/:lang/` (`HomeEventsPageComponent`)। Actor: anonymous visitor (লগইন লাগে না)।

**3. Business flow.**
1. Visitor site খুললে published landing image (banner) দেখেন — page segment অনুযায়ী (home, gallery page, contact page…)।
2. আসন্ন event কার্ড হয়ে আসে (cover image, নাম, venue, শুরুর দাম, তারিখ)।
3. General notice থাকলে banner/section দেখায়।
4. Header/footer link (social media, যোগাযোগ) settings থেকে আসে।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Event `GET /event/api/v1/landing-page-image/public` | **[HTTP, no token]** | published landing image |
| 2 | Portal → Event `GET /event/api/v1/events/list?numberOfEvents=N` | **[HTTP, no token]** | আসন্ন event (Redis-cached) |
| 3 | Portal → Admin `GET /admin/api/v1/general-notice/public` | **[HTTP, no token]** | published notice |
| 4 | Portal → Event `GET /event/api/v1/header-footer` | **[HTTP, no token]** | footer/header কনটেন্ট |
| 5 | Portal → Event `GET /event/api/v1/events/programs` | **[HTTP, no token]** | menu-র জন্য active program |

**5. Components.** User portal (`event-api`, `common-api`, `footer-api`, `image-api` service); Event service (public mirror + Redis cache); Admin service (notice, gallery)।

**6. API contracts.** চারটিই anonymous GET; shape: `LandingPageImagePublic`, `EventDetails.Event` তালিকা (sample F2.2-এ), `GeneralNoticePublic`, `HeaderFooter`। Error: standard envelope।

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

**7. Data and side effects.** শুধু-পাঠ; Event service-এ Redis cache (ছোট TTL; নতুন banner cache শেষ হলে আসে)।

**8. Code references.** `rvl-gobcb-user-portal/ETP-Web/src/app/modules/featured/events/pages/home-events-page/home-events-page.component.ts`; `…/modules/core/services/api/{event-api,common-api,footer-api,image-api}.service.ts`; `rvl-gobcb-backend/Services/Event/ETP.Event.Service/Api/{LandingPageImageController,EventsController,HeaderFooterController}.cs`, `…/Admin.Service/Api/GeneralNoticeController.cs`।

**9. Handover notes.** Portal ইচ্ছাকৃতভাবে catalog data **Event** service থেকে (public, cacheable) পড়ে, Admin থেকে নয় — Admin staff-মুখী থাকে।

### F2.2 Event browse ও event details

> **Bangla name:** ইভেন্ট ব্রাউজ ও বিস্তারিত

**1. Name and purpose.** সব published event-এর তালিকা (program দিয়ে ছাঁকাইযোগ্য) ও এক event-এর বিস্তারিত page — venue, segment, দাম ও কেনার প্রবেশপথসহ।

**2. Trigger and actor.** Portal `/:lang/events` (`AllEventListPageComponent`) ও `/:lang/events/:id` (`EventDetailPageComponent`)। Actor: anonymous visitor; কিনতে লগইন লাগে।

**3. Business flow.**
1. Events page published event-এর তালিকা দেখায় (কার্ড), program filter-সহ।
2. Event খুললে cover image, নাম, সময়, venue, segment (টিম), selling window ও শুরুর দাম দেখায়।
3. Page event-এর **venue details গাছ** (gallery → block → level — দাম, color, gate-সহ) লোড করে, যা seat-selection dialog (F2.4) চালায়।
4. "Buy" এগিয়ে নেয় seat selection ও booking-এ (F2.4, F2.6)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Event `GET /event/api/v1/events/list` (ঐচ্ছিক `?programId=`) | **[HTTP, no token]** | published event (Redis-cached) |
| 2 | Portal → Event `GET /event/api/v1/events/{eventId}` | **[HTTP, no token]** | পূর্ণ `Event` model (নিচে) |
| 3 | Portal → Event `GET /event/api/v1/events/venue-details/{eventId}` | **[HTTP, no token]** | `EventVenueDetailsTree` (F2.4) |
| 4 | Event service DB | **[Shared table]** | Admin-এর `Events`/`EventSegments`/venue টেবিল ও Booking-এর `Capacities` mirror পড়ে; `AvailabilityStatus`, `MinimumPrice` হিসাব করে |

**5. Components.** User portal; Event service (Redis cache); shared table; Admin (data-র মালিক, F1.7-এর মাধ্যমে)।

**6. API contracts.** `GET /event/api/v1/events/{eventId}` — anonymous। Response = Event service-এর `Event` model (`Services/Event/ETP.Event.Domain/Models/Event.cs`):

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
  "segments": [ { "…": "টিম-সহ segment" } ]
}
```

অন্যান্য endpoint: `GET /event/api/v1/events/published/list`, `GET list?numberOfEvents&programId`, `GET client-filtered-list/{status}/{count}?programId=`, `GET events/programs`। Error: standard envelope; অজানা id → envelope-এ 404-স্টাইল।

**7. Data and side effects.** শুধু-পাঠ + Redis cache ভরাট।

**8. Code references.** `…/events/pages/all-event-list-page/…`, `…/event-detail-page/…`; `…/modules/core/services/api/event-api.service.ts`; `rvl-gobcb-backend/Services/Event/ETP.Event.Service/Api/EventsController.cs`; `…/ETP.Event.Domain/Managers/EventManager.cs`।

**9. Handover notes.** ① Event service-এ **class-level `[Authorize]` নেই** — published event data ইচ্ছাকৃতভাবে public; customer-ব্যক্তিগত কিছু এখানে নেই। ② একই controller-এর `for-ticketing` ও `EventLongId/{id}` internal helper — portal ব্যবহার করে না।

### F2.3 Information page (pricing, gallery, যোগাযোগ, নীতিমালা)

> **Bangla name:** তথ্য-পেজ (টিকিট মূল্য, গ্যালারি, যোগাযোগ, নীতিমালা)

**1. Name and purpose.** Static/আধা-static page: program/event-ভিত্তিক টিকিট pricing, ফটো gallery, যোগাযোগ page, শর্তাবলি, প্রাইভেসি policy, FAQ, ICC code page।

**2. Trigger and actor.** Portal route `/:lang/ticket-pricing`, `/:lang/gallery`, `/:lang/contact`, `/:lang/terms`, `/:lang/policy`, `/:lang/faq`, `/:lang/icc-anti-racism-code`, `/:lang/icc-anti-discrimination-code`, `/:lang/message-sent`। Actor: anonymous।

**3. Business flow.**
1. **Ticket pricing** program-ভিত্তিক gallery/level ও দামের ম্যাট্রিক্স দেখায় — admin portal-ে পরিচালিত (F1.14)।
2. **Gallery** Media Configuration-এর gallery-page image দেখায় (F1.28)।
3. **Contact** header/footer settings থেকে যোগাযোগের তথ্য (F1.30); contact form "message sent" নিশ্চিতকরণ দেখায়।
4. Terms/privacy/FAQ/ICC page-এ স্থির legal টেক্সট।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Event `GET /event/api/v1/ticket-pricing/list` | **[HTTP, no token]** | published pricing ম্যাট্রিক্স (Redis-cached) |
| 2 | Portal → Event `GET /event/api/v1/ticket-pricing/program-pricing?programId&eventId` | **[HTTP, no token]** | program/event ভাঙানো রূপ |
| 3 | Portal → Event `GET /event/api/v1/landing-page-image/public` | **[HTTP, no token]** | gallery-page image (segment type `Gallery_Page_Segment_*` দিয়ে ছাঁকাই) |
| 4 | Portal → Event `GET /event/api/v1/header-footer` | **[HTTP, no token]** | যোগাযোগের তথ্য |
| 5 | terms/policy/faq | — | portal bundle-এর static content (note দ্রষ্টব্য) |

**5. Components.** User portal; Event service; Admin service (মালিক — F1.14/F1.28/F1.30)।

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

`program-pricing` → `ProgramPricingResponse` (`{ programId, programName, programStartDate, events: [{ eventId, eventName, venueId, venueName, galleryName, ticketType, price }] }`)। সব anonymous GET; standard error।

**7. Data and side effects.** শুধু-পাঠ।

**8. Code references.** `…/events/pages/…` (ticket-pricing, gallery, contact, terms, policy, faq component); `…/modules/core/services/api/{event-api,common-api,footer-api}.service.ts`; `rvl-gobcb-backend/Services/Event/ETP.Event.Service/Api/{TicketPricingController,LandingPageImageController,HeaderFooterController}.cs`।

**9. Handover notes.** ① Admin portal-এর Content Editor-এ Terms/FAQ/Privacy page আছে, কিন্তু তার service শুধু ticket-pricing ও general-notice endpoint ডাকে — legal টেক্সট client-এ (portal i18n asset / app string) `[UNCONFIRMED: legal টেক্সটের প্রকৃত উৎস]`। ② User app একই pricing endpoint পড়ে (F3.3)।

### F2.4 Seat selection

> **Bangla name:** আসন নির্বাচন

**1. Name and purpose.** Gallery → block → level বেছে (seat-mapped level-এ নির্দিষ্ট আসন) লাইভ availability-সহ কেনা — per-order/per-user সীমার ভেতরে।

**2. Trigger and actor.** Portal event detail-এর buy dialog / `stadium-seat` map। Actor: customer (আসন-স্তরের availability call-এ User pool token লাগে)।

**3. Business flow.**
1. Customer venue গাছ খোলেন: gallery (যেমন Grandstand) → block → level — আসনপ্রতি দাম ও color-সহ।
2. Seat-mapped level-এ stadium map আলাদা আসন দেখায়; লাইভ availability backend থেকে (সবুজ/খালি, নেওয়া/লক)।
3. Customer `allowableMaximumSeatPerOrder` পর্যন্ত আসন (বা non-mapped level-এ সংখ্যা) বাছেন।
4. এগোলে booking dialog (F2.6) খোলে — দাম, VAT ও ছাড়ের হিসাবসহ।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Event `GET /event/api/v1/events/venue-details/{eventId}` | **[HTTP, no token]** | `EventVenueDetailsTree` (গঠন + দাম; Redis-cached ~১৫ দিন) |
| 2 | Portal → Admin `GET /admin/api/v1/eventsVenueDetails/get-level/{eventId}/{levelId}` | **[HTTP + user token]** | বাছাই করা level-এর `UserLevelWithGates` (দাম, gate নাম, sellable flag) |
| 3 | Portal → Booking `GET /booking/api/v1/capacity/level-user-portal-seats?…` | **[HTTP + user token]** | level-এর লাইভ আসন তালিকা/অবস্থা (Redis-backed) |
| 4 | Portal → Booking `GET /booking/api/v1/capacity/level-live-capacity?eventId&galleryId&blockId&levelId` | **[HTTP, no token]** (class-এ auth নেই) | বাকি সংখ্যা |
| 5 | Booking Redis | — | F2.6/F5.1/F5.3-এর রাখা লাইভ counter পড়ে (`level_live*`, §0.8) |

**5. Components.** User portal; Event + Admin + Booking service; Redis live counter; shared `Capacities`, `SeatReservations`, venue টেবিল।

**6. API contracts.** `UserLevelWithGates` (Event service; Admin-এর `get-level`-ও একই model):

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

Capacity endpoint সরল সংখ্যা/আসন তালিকা দেয়: `level-live-capacity` → `int`; `level-user-portal-seats` → `AvailableSeatsCapacity { total: string, available: string }` (কমা-দিয়ে-লেখা আসন তালিকা)। Error: standard envelope; token মেয়াদোত্তীর্ণ হলে 401 ও পুনরায় লগইন (F6.10)।

**7. Data and side effects.** এই ধাপে শুধু-পাঠ; আসন **lock** হয় শুধু F2.6-এ (Redis locked-capacity key)।

**8. Code references.** `…/events/pages/event-detail-page/…`, `…/tickets/pages/stadium-seat-page/…`, resolver `venue-details.resolver.service.ts`; `…/modules/core/services/api/{event-api,booking-api}.service.ts`; `…/Event.Service/Api/EventsController.cs` (`venue-details`, `get-level`), `…/Admin.Service/Api/EventsVenueDetailsController.cs`, `…/Booking.Service/Api/CapacityController.cs`।

**9. Handover notes.** ① এখানে দুই সত্যের মিলন: গাছ (গঠন, ১৫ দিন পর্যন্ত cached) ও লাইভ counter (সেকেন্ড) — দাম বদল (F1.9) cache TTL পর্যন্ত দেরিতে দেখাতে পারে। ② `CapacityController`-এ **`[Authorize]` নেই**; network placement-এ internal/public ধরা হয়েছে (F6.18)।

### F2.5 Promo code apply

> **Bangla name:** প্রোমো কোড প্রয়োগ

**1. Name and purpose.** Checkout-এর **আগে** বাছাই করা event/gallery-র সাথে promo code যাচাই করে ছাড় দেখানো, যাতে customer buy dialog-এ শুধরে যাওয়া মোট দেখেন।

**2. Trigger and actor.** Portal buy dialog-এর promo-code field। Actor: customer, User pool (policy `user`)।

**3. Business flow.** Customer কোড লিখে apply চাপেন; portal সফল/ব্যর্থতা ও ছাড়ের ধরন + মান দেখায়; booking (F2.6) পরে একই কোড পাঠায় ও Booking আবার server-side যাচাই করে।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Booking `POST /booking/api/v1/user-booking-order/apply-promo-code` | **[HTTP + user token]** | `ApplyPromoCodeRequest { promoCode, programId, eventId, galleryId }` |
| 2 | Booking manager | **[Shared table]** | `PromoCodes`/`PromoCodeAssigns` mirror-এ যাচাই: active window (F5.16), ব্যবহারের সীমা, assignment মিল → `ApplyPromoCodeResponse` |

**5. Components.** Portal (`booking-api.service.ts`); Booking service; promo টেবিল (মালিক Admin)।

**6. API contracts.**

```json
// POST /booking/api/v1/user-booking-order/apply-promo-code
{ "promoCode": "BCBWELCOME", "programId": 7,
  "eventId": "b8e6a9d2-3f1c-4e7a-9d5f-6c2b1a8e0d34", "galleryId": 12 }

// 200   (ApplyPromoCodeResponse)
{ "isSuccess": true, "discountType": "Percentage", "discountValue": 10.0, "discountAppliedTo": "BasePrice" }
```

মূল error: `400` envelope `"Invalid promo code. Please enter a valid code."` (`UserBookingOrderManager`-এ `ArgumentException`)।

**7. Data and side effects.** শুধু-পাঠ (ব্যবহারের হিসাব হয় F2.6-এ booking-এর সময়)।

**8. Code references.** `rvl-gobcb-user-portal/ETP-Web/src/app/modules/core/services/api/booking-api.service.ts`; `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/UserBookingOrderController.cs` (`apply-promo-code`), `…/Managers/UserBookingOrderManager.cs`।

**9. Handover notes.** System discount (কোড ছাড়া) আলাদাভাবে `GET /admin/api/v1/discount/program/{programId}/{eventId}/{galleryId}` (F1.16) থেকে আসে ও স্বয়ংক্রিয়ভাবে দেখায় — promo code ও system discount একসাথে থাকতে পারে; চূড়ান্ত হিসাব Booking-এর, F2.6-এ।

### F2.6 Booking order ও online payment (DgePay)

> **Bangla name:** বুকিং অর্ডার ও অনলাইন পেমেন্ট (DgePay)

**1. Name and purpose.** লগইন করা customer বাছাই করা আসন/সংখ্যাকে order বানান, DgePay-র hosted checkout-এ যান, পরিশোধ করে ফেরেন; backend স্বাধীনভাবে payment যাচাই করে টিকিট তৈরি শুরু করে।

**2. Trigger and actor.** Portal buy dialog → `complete-payment-modal.component.ts`। Actor: customer, User pool (policy `user`)।

**3. Business flow.**
1. Seat selection (F2.4) থেকে customer নিশ্চিত করেন: আসন বা সংখ্যা, টিকিট-প্রতি holder-এর তথ্য (নাম/ফোন), ঐচ্ছিক promo code (F2.5); dialog দাম, VAT, ছাড় ও মোট দেখায়।
2. নিশ্চিত করলে portal browser-কে backend-এর ফেরত দেওয়া DgePay checkout URL-এ নিয়ে যায়।
3. Customer DgePay-তে পরিশোধ করেন; DgePay browser-কে portal-এর payment-result page-এ ফেরায়।
4. Backend DgePay-র সাথে transaction পুনঃযাচাই করে (`check_transaction_status`) ও order **Paid** করে।
5. টিকিট PDF অ্যাসিনক্রোনাসভাবে তৈরি হয় (F5.7/F5.8); customer My Tickets-এ status দেখেন (F2.7)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal `booking-api.service.ts` → Booking `POST /booking/api/v1/user-booking-order` | **[HTTP + user token]** | JSON `UserBookingOrder`; Booking per-user RedLock-এ (`user_booking:{userId}`) লাইভ capacity যাচাই করে, promo/system discount প্রয়োগ করে, VAT হিসাব করে, `UserBookingOrders` row (Pending) তৈরি করে |
| 2 | Booking → DgePay `POST {BaseUrl}/payment_gateway/initiate_payment` | **[HTTP, static key]** (`PaymentSettings:DgePay`; AES/RSA-signed request, token Redis-cached) | gateway checkout URL ফেরায় |
| 3 | Booking → customer | — | `201` + `publicId` + `checkoutUrl`; portal `window.location.href = checkoutUrl` |
| 4 | Browser ← DgePay redirect → Booking `GET /booking/api/v1/user-booking-order/dgepay/payment-status?data=…` | **[HTTP, no token]** (ইচ্ছাকৃতভাবে anonymous) | Booking DgePay `check_transaction_status` ডাকে, status ম্যাপ করে ("3"/"Success" → **Paid**), order হালনাগাদ |
| 5 | সফল হলে Booking → SQS | **[SQS: OrderSuccess]** `LevelCapacityUpdate` (GroupId `{eventLongId}_{galleryId}_{blockId}_{levelId}`) ও **[SQS: VatChallanProcessing]** `VatChallanProcessing` | ভোক্তা: F5.1 (capacity) ও F5.10 (VAT challan) |
| 6 | Booking → Ticketing `GET /ticketing/api/v1/booking-order-ticket/initiate?orderId={publicId}` | **[HTTP, no token]** (internal endpoint) | blank PDF তৈরি → signing pipeline (F5.8) |
| 7 | Booking worker | **[Worker: 15 min]** | `InitiateUserTicketGenerationService` event-এর `TicketAvailabilityStartDateTime` পেরোনো paid order-ও ধরে (F5.7) — ধাপ ৬-এর safety net |

**5. Components.** User portal; Booking service; DgePay; SQS `OrderSuccess` + `VatChallanProcessing`; Redis (লাইভ capacity, lock, DgePay token cache); Aurora টেবিল `UserBookingOrders`, `Capacities`, `SeatReservations`, `BookedUserRecords`, `PromoCodes`/`Discounts` mirror; Ticketing (downstream)।

**6. API contracts.**

**`POST /booking/api/v1/user-booking-order`** — auth: User pool (policy `user`)। Request = `UserBookingOrder` (`Services/Booking/ETP.Booking.Domain/Models/UserBookingOrder.cs`):

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

**`GET /booking/api/v1/user-booking-order/dgepay/payment-status?data={encrypted}`** — anonymous; DgePay-র সাথে যাচাই করে, order হালনাগাদ করে, portal-এর payment-result page-এ `302` redirect দেয় (redirect টার্গেট backend-side secret-এ configured)।

মূল error: `401` (POST-এ User token নেই/মেয়াদোত্তীর্ণ), `400` envelope — আসন নেওয়া/capacity/promo-অবৈধ জাতীয় business ব্যর্থতা।

**7. Data and side effects.** `UserBookingOrders` insert + status হালনাগাদ (payment transaction id, `OneIdUserId`); Redis আসন lock; ধাপ ৫-এর SQS message; DgePay-পক্ষের payment; এখানে email/push নেই (তৈরি হওয়ার পরে — F5.12)।

**8. Code references.**

| কী | কোথায় |
|---|---|
| Portal caller | `rvl-gobcb-user-portal/ETP-Web/src/app/modules/core/services/api/booking-api.service.ts`; `complete-payment-modal.component.ts` |
| Controller | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/UserBookingOrderController.cs` |
| Manager | `…/ETP.Booking.Domain/Managers/UserBookingOrderManager.cs` (payment-success path-এ SQS publish) |
| DgePay client | `…/ETP.Booking.Domain/Managers/DgePayPaymentManager.cs` |
| Worker | `…/ETP.Booking.Service/Workers/BackgroundServices/{LevelCapacityUpdateService,VatChallanProcessingService,InitiateUserTicketGenerationService}.cs` |

**9. Handover notes.** ① Test endpoint `GET …/payment-status-bypass?rawData=` DgePay যাচাই এড়িয়ে সরাসরি টিকিট তৈরি শুরু করে — production-এ পৌঁছাচ্ছে না তা নিশ্চিত করুন `[UNCONFIRMED]`। ② DgePay-র পাশে পূর্ণ **SSLCommerz** endpoint (`payment-success|fail|cancel|ipn`, `payment-methods`) আছে; architecture doc শুধু DgePay-র নাম নেয় — কোন gateway live নিশ্চিত করুন `[UNCONFIRMED]` (program-প্রতি gateway নির্বাচন আছে, F1.3)। ③ Payment-এর সত্য হলো server-side status check, redirect নয়। ④ Per-user lock মানে customer-প্রতি একবারে একটি order-চেষ্টা; lock আটকে গেলে মেয়াদ শেষ না হওয়া পর্যন্ত পরের চেষ্টা দেরি করে।

### F2.7 আমার booking ও generation status

> **Bangla name:** আমার বুকিং ও জেনারেশন স্ট্যাটাস

**1. Name and purpose.** Customer-এর order তালিকা ("My Tickets") প্রতিটি order-এর status-সহ, আর PDF তৈরি হলে জানানোর polling।

**2. Trigger and actor.** Portal `/:lang/tickets` (`AllBookingsPageComponent`, AuthGuard)। Actor: customer, User pool।

**3. Business flow.**
1. Payment-এর পরে (এবং DgePay redirect ফেরার পরে) customer My Tickets-এ পড়েন ও order দেখেন (status `Paid`/`Pending`/…)।
2. টিকিট তৈরি হওয়া পর্যন্ত (F5.7/F5.8) page generation status poll করে; রেডি হলে টিকিট download-যোগ্য হয় (F2.9)।
3. Order খুললে বিস্তারিত দেখায়; seat-mapped order-এর আসনের ম্যাপ আলাদা screen-এ (`/tickets/:id/seats`)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Booking `GET /booking/api/v1/user-booking-order/list?page&pageSize&sortOrder` | **[HTTP + user token]** | paged `UserBooking` তালিকা |
| 2 | Portal → Booking `GET …/check-generated-status?id={publicId}` | **[HTTP + user token]** | খালি `true`/`false` — `true` হওয়া পর্যন্ত poll |
| 3 | Payment redirect | — | Backend browser-কে DgePay `RedirectUrl`-এ (একটি portal URL; `tickets` route `/{lang}/tickets`-এ redirect করে) নামায় — **query parse নেই**: ফলাফল order-এর status থেকেই বোঝা যায় |

**5. Components.** Portal (`booking-api.service.ts`, tickets feature); Booking service; `UserBookingOrders` টেবিল।

**6. API contracts.** `UserBooking` (`Services/Booking/ETP.Booking.Domain/Models/UserBooking.cs`) — item shape:

```json
{
  "id": 9001,
  "publicId": "7c9f2e64-51ab-4d3e-b1f0-9a8d6e5c4b21",
  "programId": 7, "eventId": "b8e6a9d2-…", "eventLongId": 1042,
  "galleryId": 12, "blockId": 7, "levelId": 45,
  "orderNumber": "ORD-000123",
  "numberOfSeats": 2, "hasSeats": true, "seats": "A1,A2",
  "pricePerSeat": 1500.0, "promoCode": "BCBWELCOME", "promoDiscount": 300.0,
  "totalCharge": 2700.0, "vat": 405.0, "vatIncludedBasePricePerSeat": 1500.0,
  "platformCharge": 0.0, "isVatInclusive": false, "discount": 0.0,
  "status": "Paid",
  "paymentTransactionId": "DPX88312",
  "eventName": "2nd ODI — Bangladesh vs Sri Lanka",
  "eventStartDateTime": "2026-07-08T14:00:00Z", "eventEndDateTime": "0001-01-01T00:00:00Z",
  "ticketAvaiableFrom": "2026-06-25T10:00:00Z",
  "vatInvoiceId": null, "vatInvoiceInfo": null, "vatInvoiceDownloadUrl": null,
  "smartChallanNumber": null, "oneIdUserId": null, "oneIdSync": false,
  "createdAt": "2026-07-01T09:12:33Z"
}
```

(status enum: `Pending|Failed|Paid|Cancelled|Requested|Generated`; `ticketAvaiableFrom`-এর বানানটি wire-এ এমনই)। `check-generated-status` খালি `true`/`false`; error `400` "Booking not found." / "Privacy error." (অন্যের order)।

**7. Data and side effects.** শুধু-পাঠ।

**8. Code references.** `…/tickets/pages/all-bookings-page/all-bookings-page.component.ts`; `…/core/services/api/booking-api.service.ts`; `…/Booking.Service/Api/UserBookingOrderController.cs` (`list`, `check-generated-status`)।

**9. Handover notes.** ① DgePay redirect টার্গেট secret config (`PaymentSettings:DgePay:RedirectUrl`) portal-কে নির্দেশ করে — handover-এর পর portal domain বদলালে ওটিও বদলাতে হবে। ② `eventEndDateTime`/`cancelledAt` ইত্যাদি unset হলে .NET-এর default তারিখ serialize হয় — আসল তারিখ ভেবে parse করবেন না।

### F2.8 Ticket generation request

> **Bangla name:** টিকিট জেনারেশন রিকোয়েস্ট

**1. Name and purpose.** Paid order-এর জন্য customer-এর স্পষ্ট "আমার টিকিট বানাও" action — availability window-এর ভেতরে; F5.7-এর user-চালিত যমজ।

**2. Trigger and actor.** Portal booking details-এর "request tickets" action (status `Paid` হলে দেখায়)। Actor: customer, User pool।

**3. Business flow.** Customer request চাপেন; order paid, আগে থেকে requested নয় এবং event-এর ticket-availability সময় এসে গেলে generation শুরু হয়; page আবার polling-এ ফেরে (F2.7)।

**4. Technical flow.** Portal → Ticketing `PATCH /ticketing/api/v1/booking-order-ticket/generate-request/{publicId}` **[HTTP + user token]** (খালি body) → `TicketManager.TicketGenerateRequest` (F5.7-এর মতোই: টিকিট + blank PDF তৈরি, **[SQS: TicketSigning]** publish, order → `Requested`)। ফেরে পূর্ণ `UserBookingResponse` (shape F2.9-এ)।

**5–7. Components / data.** Portal; Ticketing; SQS TicketSigning; S3; F5.7-এর মতো `Tickets`/`UserBookingOrders` লেখা।

**8. Code references.** `…/core/services/api/booking-api.service.ts` (`requestTicketsById`); `…/Ticketing.Service/Api/BookingOrderTicketController.cs` (`generate-request`), `…/Managers/TicketManager.cs` (`TicketGenerateRequest`)।

**9. Handover notes.** মূল error (400 envelope): `"Request to generate ticket is already taken."`, `"Only paid order requests can generate tickets"`, `"You can request after ticket availability date."`।

### F2.9 Ticket details, holder তথ্য, download, share, invoice

> **Bangla name:** টিকিট বিস্তারিত, হোল্ডার তথ্য, ডাউনলোড, শেয়ার, ইনভয়েস

**1. Name and purpose.** Customer তার টিকিট দিয়ে যা করেন: বিস্তারিত দেখা (নম্বর, আসন, holder, gate), holder-এর নাম/ID সম্পাদনা, একটি PDF বা পুরো order-এর zip নামানো, payment invoice নামানো, আর সময়সীমাসহ share link বানানো।

**2. Trigger and actor.** Portal `/:lang/tickets/ticket-details/:id` (`BookingDetailsComponent`)। Actor: customer, User pool।

**3. Business flow.**
1. Customer order খোলেন: event/venue তথ্য, দামের ভাগ (`SubTotal`, VAT, ছাড়) ও টিকিটের তালিকা — প্রতিটির status-সহ।
2. Generation-এর আগে প্রতিটি টিকিটের holder-এর নাম ও পরিচয় (NID/passport) সম্পাদনা করা যায়।
3. Generated হলে: একটি PDF, সব-এক-zip, invoice PDF নামানো বা "share" — সময়সীমাসহ public link।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Ticketing `GET /ticketing/api/v1/booking-order-ticket/details?publicId={guid}` | **[HTTP + user token]** | `UserBookingResponse` (নিচে) — Booking-এর `UserBooking` + `Tickets` + Event `EventDetails` + `VenueDetails` + `TicketAttributes` থেকে বানানো |
| 2 | Portal → Ticketing `PATCH /ticketing/api/v1/booking-order-ticket` | **[HTTP + user token]** | `TicketUpdateRequest { id, ticketHolderName, ticketHolderIdentification }` |
| 3 | Download | **[HTTP + user token]** | `GET download?ticketNumber=` → **PDF byte stream** (`{ticketNumber}.pdf`); `GET download-all/{orderPublicId}` → **ZIP byte stream** (`{eventName}.zip`); `GET download-invoice/{publicId}` → **PDF byte stream** (`TicketInvoice.pdf`) — portal `responseType: 'blob'` ব্যবহার করে |
| 4 | Share | **[HTTP + user token]** | `GET share?ticketNumber=` → JSON string URL `{ShareBase}?ticketNumber=…&signature=…` (presigned, Redis-এ `sharedTicket:{ticketNumber}_{signature}` key-তে `AWS:Ticket:ShareExpiryMinutes` মেয়াদে); যে কেউ `GET shared?ticketNumber&signature` **[AllowAnonymous]** দিয়ে PDF পায় |

**5. Components.** Portal; Ticketing service; Booking (order data); S3 ticket bucket + presigned URL; Redis shared-ticket cache।

**6. API contracts.** `UserBookingResponse` = F2.7-এর `UserBooking` field + এগুলো:

```json
{
  "transactionId": "DPX88312", "paymentMethod": "DgePay", "subTotal": 3000.0,
  "tickets": [
    { "id": 45001, "ticketNumber": "BCB-ODI2-A1B2C3", "seat": "A1",
      "ticketHolderName": "Rahim Uddin", "ticketHolderIdentification": "1990123456789",
      "entryGates": "Gate 3 — North", "miniGates": "M2",
      "status": "Generated", "oneIdSync": false, "blankTicketUrl": null, "signedTicketUrl": null }
  ],
  "eventDetails": { "…": "Event service-এর Event model (F2.2)" },
  "venueDetails": { "…": "UserLevelWithGates (F2.4)" },
  "ticketAttributes": {
    "programId": 7, "venueType": "Stadium", "showVenueName": true, "showSegmentDateTime": true,
    "dynamicAttributes": [ { "name": "Gallery", "value": "Grandstand", "isVisible": true, "priority": 1 } ]
  }
}
```

(টিকিটের ভেতরের URL server-side null করা; download streaming endpoint দিয়ে হয়।)

**7. Data and side effects.** `Tickets.TicketHolder*` হালনাগাদ; Redis share cache; S3 পাঠ।

**8. Code references.** `…/tickets/pages/booking-details/booking-details.component.ts`; `…/core/services/api/booking-api.service.ts`; `…/Ticketing.Service/Api/BookingOrderTicketController.cs` (`details`, `PATCH`, `download`, `download-all`, `download-invoice`, `share`, `shared`); `…/Managers/TicketManager.cs` (`GetTicketsInfo`, `ShareTicketAsync`)।

**9. Handover notes.** ① Holder-তথ্যের সম্পাদনা generation-এর আগেই অর্থবহ — sign হওয়ার পরে PDF স্থির। ② `share` object নয়, **JSON-quoted string** ফেরায় (portal-এ `responseType: 'text'`)। ③ `shared` endpoint ইচ্ছাকৃতভাবে anonymous (signature-ই রহস্য) — `ShareExpiryMinutes` ছোট রাখুন।

### F2.10 OneID wallet-এ টিকিট sync

> **Bangla name:** OneID ওয়ালেটে টিকিট সিঙ্ক

**1. Name and purpose.** Signed টিকিট PDF (বা পুরো order) customer-এর OneID wallet-এ পাঠানো — জাতীয় ডিজিটাল পরিচয়ের পাশে রাখার জন্য।

**2. Trigger and actor.** Portal booking details-এর "sync to OneID" action। Actor: customer, User pool। Auto-trigger: order-এ `OneIdUserId` থাকলে প্রতিটি user টিকিট sign হওয়ার পরে (F5.8)।

**3. Business flow.**
1. Customer sync চাপেন (টিকিট- বা order-প্রতি); প্ল্যাটফর্ম OneID-তে authenticate করে PDF upload করে।
2. সফল হলে টিকিট `OneIdSync = true` + timestamp; আগে-syncl হয়েছে এমন টিকিট skip হয়।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Ticketing `POST /ticketing/api/v1/booking-order-ticket/sync-to-oneid/{ticketNumber}` বা `…/sync-order-to-oneid/{orderPublicId}` | **[HTTP + user token]** | Body নেই |
| 2 | Ticketing `OneIdManager` | **[HTTP, static key]** | `POST {OneIdSettings:TokenUrl}` `grant_type=client_credentials` + Basic auth (`OneIdSettings:AuthorizationToken`) → token Redis `OneId:AuthToken` (`expires_in − 300 s`) |
| 3 | Upload | **[HTTP + bearer]** | `POST {OneIdSettings:DocumentSyncUrl}` multipart: `one_id`, `document_type=pdf`, `document_id` (টিকিট নম্বর), file part `file`; ঐচ্ছিক `vds_qr` (এখন `null`, TODO) |
| 4 | ফলাফল | — | `OneIdSyncResponse { success, message, ticketNumber, alreadySynced, syncedAt }`; order variant-এ সংখ্যা (`totalTickets, syncedTickets, failedTickets, alreadySyncedTickets, results[]`) |

**5. Components.** Portal; Ticketing service; OneID (external); Redis token cache; `Tickets.OneIdSync/OneIdSyncedAt`; `UserBookingOrders.OneIdUserId`।

**6. API contracts.** উপরের response; `404` body `{ "message": "Ticket not found" }` / `{ "message": "Order not found" }`; `SyncTicketToOneIdAsync`-এর নিয়ম (signed হতে হবে, আগে sync নয়, `OneIdUserId` থাকতে হবে)।

**7. Data and side effects.** `Tickets` sync flag; OneID-পক্ষের document।

**8. Code references.** `…/booking-api.service.ts` (`syncOrderToOneId`); `…/Ticketing.Service/Api/BookingOrderTicketController.cs`; `…/Managers/OneIdManager.cs`; model `…/Models/OneId/*`, `…/Models/OneIdSync/*`।

**9. Handover notes.** ① `OneIdUserId` কোথা থেকে আসে (SSO login-এ? booking-এ?) তা Ticketing কোডে দেখা যায় না `[UNCONFIRMED]`। ② OneID-র 401-এ token auto-refresh হয়ে একবার retry হয়; অন্য ব্যর্থতায় টিকিট unsynced থাকে পরে ম্যানুয়াল retry-র জন্য।

### F2.11 Profile

> **Bangla name:** প্রোফাইল

**1. Name and purpose.** External **identity API**-তে রাখা customer profile দেখা ও হালনাগাদ (নাম, জন্মতারিখ, ঠিকানা, verification id/ধরন); password বদল F6.10-এ।

**2. Trigger and actor.** Portal `/:lang/user-profile`। Actor: customer, User pool (+ identity API key header)।

**3. Business flow.** Customer নিজের profile দেখেন (verification অবস্থা, ekyc) ও ঠিকানা/জন্মতারিখ/verification field সম্পাদনা করেন; profile completeness কিছু flow নিয়ন্ত্রণ করে।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → identity `GET user/my-profile` | **[HTTP, static key]** (`environment.services.identity`, header `Authorization: environment.headerkey`) | Response `user_data` (নিচে) |
| 2 | Portal → identity `PUT user/my-profile` | **[HTTP, static key]** | `{ verification_type, verification_id, address, dob }` |

**5. Components.** Portal (`identity-api.service.ts`, profile feature); identity API (external, source repo-তে নেই `[UNCONFIRMED]`)।

**6. API contracts.**

```json
// GET user/my-profile   (user_data)
{
  "user_data": {
    "user_id": "a1b2c3d4-…", "name": "Rahim Uddin", "email": "rahim@example.com",
    "phone": "+8801712345678", "dob": "1990-05-12", "address": "House 12, Mirpur, Dhaka",
    "role": "user", "verified": true, "isProfileCompleted": "true",
    "registration_datetime": "2026-06-01T10:00:00Z", "sso_provider": null,
    "nonsensitive_data": { "verification": { "verification_type": "nid", "verification_id": "1990123456789" },
                            "ekyc": { "verified": true, "data": null } },
    "sensitive_data": { "verification": null, "payment": null, "ekyc": null }
  }
}
```

**7. Data and side effects.** সব লেখা external identity API-তে — ETP service-এ কিছু নয়।

**8. Code references.** `…/core/services/api/identity-api.service.ts`; `…/featured/profile/pages/user-profile-pages.component.ts`; app-পক্ষ `rvl-gobcb-user-app/data/lib/remote/api_service/profile_api_service_impl.dart`।

**9. Handover notes.** Identity API repo-বহির্ভূত সবচেয়ে বড় নির্ভরতা (registration F6.6, OTP F6.6/F6.9, profile, app version F3.1) — মালিকানা/SLA BS23-এর সাথে নিশ্চিত করতে হবে (Open queries)।

### F2.12 সমস্যা জানানো ও সাপোর্ট চ্যাট (ইউজার পাশ)

> **Bangla name:** সমস্যা জানানো ও সাপোর্ট চ্যাট (ইউজার পাশ)

**1. Name and purpose.** Customer কোনো order-এর ব্যাপারে issue খোলেন (order-প্রতি একটি) ও রিয়েল-টাইমে support-এর সাথে chat করেন, attachment-সহ — F1.24-এর আয়না।

**2. Trigger and actor.** Portal `/:lang/issues`, `/:lang/issues/issue/:id` (তৈরি), `/:lang/issues/issue-details/:id` (chat)। Actor: customer, User pool।

**3. Business flow.**
1. Customer order বেছে সমস্যার বর্ণনা (≤৬০০ অক্ষর) দিয়ে জমা দেন — issue number তৈরি হয়।
2. Chat screen thread দেখায়; typing indicator ও read receipt লাইভ; file (image/PDF/Office ≤ ১০ MB) যোগ করা যায়।
3. Support resolve করলে (F1.24) status বদলায় ও SMS নিশ্চিতকরণ যেতে পারে।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → UserIssue `POST /userissue/api/v1/user-issue` | **[HTTP + user token]** | `CreateUserIssue { publicOrderId, description, programId }` — order-প্রতি-এক-issue যাচাই (Booking-কে order-এর জন্য ডাকে), issue + প্রথম বার্তা ("USER") insert, Serverless থেকে user আনে |
| 2 | তালিকা/বিস্তারিত | **[HTTP + user token]** | `GET user-issue/user/{userId}`, `GET user-issue/user-detail/{orderId}` (order + টিকিট সমৃদ্ধ) |
| 3 | Chat history / send | **[HTTP + user token]** | `GET user-issue-chat/{id}/messages`, `POST user-issue-chat/send` (multipart `CreateChatMessage { userIssueId, message, senderType, senderId?, senderName?, attachmentFile? }`) — attachment → S3 `chat-attachments/{issueId}/{guid}{ext}` |
| 4 | রিয়েল-টাইম | **[SignalR]** | Hub `{userissuehub}/userissue/chathub` (token `accessTokenFactory` দিয়ে, auto-reconnect 0/2/10/30 s); method/event F1.24-এর মতোই |

**5. Components.** Portal (`booking-api.service.ts`-এর issue call, `signalr-chat.service.ts`, NgRx identity store); UserIssue service; Booking (order lookup); Serverless API (user); S3; SignalR public ingress `chat.gobcbticket.com.bd`।

**6. API contracts.** Shape F1.24 §6-তে (`ReportedUserIssue`, chat message)। Error: standard envelope; একই order-এ দ্বিতীয় issue → 400।

**7. Data and side effects.** `ReportedIssues`/`ReportedIssueChatMessages` insert; S3 attachment।

**8. Code references.** `…/Issues/pages/{report-issue,report-issue-list,report-issue-details}/…`; `…/core/services/signalr-chat.service.ts`; মালিক service `rvl-gobcb-backend/Services/UserIssue/ETP.UserIssue.Service/Api/{ReportIssueController,ReportIssueChatController}.cs`, `…/Managers/{ReportIssueManager,ReportIssueChatManager}.cs`।

**9. Handover notes.** ① Polling সরিয়ে SignalR আনা হয়েছে — chat "জমে" গেলে আগে hub ingress দেখুন। ② Chat REST endpoint anonymous (F6.18); বার্তা শুধু request-এর id দিয়ে user-scoped।

### F2.13 ভাষা পরিবর্তন (EN/BN)

> **Bangla name:** ভাষা পরিবর্তন (EN/BN)

**1. Name and purpose.** পুরো portal দ্বিভাষিক; `/:lang` route segment (`en` default, `bn`) অনুবাদ বেছে নেয় (`@ngx-translate`, `assets/i18n`), নির্বাচন navigation ও reload টিকে থাকে।

**2. Trigger and actor.** Portal-এর language switcher। Actor: যে কোনো visitor।

**3–4. Business/technical flow.** `LanguageGuard` জমা ভাষা পড়ে/লেখে; redirect route `tickets → /{lang}/tickets` (F2.7-এর payment callback) জমা ভাষা পুনরায় বসায়। Data API ভাষা-নিরপেক্ষ; শুধু UI string ও static content (শর্তাবলি, FAQ — F2.3) অনূদিত।

**5–8. Components / contracts / data / code.** `ETP-Web/src/app/app-routing.module.ts`, `modules/shared/services/custom-translate-loader.ts`, `assets/i18n/*`। Backend জড়িত নয়।

**9. Handover notes.** Backend-সরবরাহকৃত string (event-এর নাম, notice) **অনূদিত নয়** — staff যা লিখেছেন তাই; দ্বিভাষিক প্রদর্শনের সময় মনে রাখুন।

## 3. User App

Flutter user app-এ (`rvl-gobcb-user-app`, app id `gobcbticket`) customer-দের শুরু করা feature। App কেনার flow-গুলো **একই API**-তে web portal-এর আয়না, তাই নিচের প্রতিটি feature শুধু ভিন্ন জিনিস (native flow, WebView payment, download, push) নিয়ে আলোচনা করে ও portal-যমজের link দেয়। Auth flow F6.6–F6.11-তে। Clean architecture: `lib/presentation` (feature-first screen + view model), `domain/` (interface), `data/` (implementation); DI হাতে গড়া (`DataModule`)।

### F3.1 Splash, version gate ও onboarding

> **Bangla name:** স্প্ল্যাশ, ভার্সন গেট ও অনবোর্ডিং

**1. Name and purpose.** App চালু হওয়া: environment যাচাই, **সর্বনিম্ন app version** enforce (force-update), onboarding দেখানো, session ফিরিয়ে আনা।

**2. Trigger and actor.** App launch → `/splash`। Actor: app user।

**3. Business flow.** Splash env/config দেখে, identity API থেকে allowed version নিয়ে ইনস্টল করা build-এর সাথে তুলনে করে (`package_info_plus`); পুরোনো build-এ force-update screen দেখায় store link-সহ; নতুন ইনস্টলে onboarding page, তারপর login/home।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | App → identity `GET user/allowed-app-version` | **[HTTP, static key]** (`AUTH_API_BASE_URL` + `AUTH_API_TOKEN`) | `{ data: { up?: { android?, ios? }, tc?: { android?, ios? } } }` — প্রতিটি `{ version, build_number, app_link }` ("up" = user portal app, "tc" = ticket checker) |
| 2 | তুলনা | — | `package_info_plus` build number বনাম allowed; নিচে হলে force update |
| 3 | Session restore | — | `AMPLIFY_CONFIG` থেকে Amplify session; `custom:isprofilecomplete` profile completion নিয়ন্ত্রণ করে |

**5. Components.** App-এর splash/onboard feature; identity API (external); package_info_plus।

**6. API contracts.** Response sample:

```json
// GET {AUTH_API_BASE_URL}/user/allowed-app-version
{ "message": null, "status": "ok",
  "data": { "up": { "android": { "version": "2.3.0", "build_number": 120, "app_link": "https://play.google.com/…" },
                    "ios":     { "version": "2.3.0", "build_number": 120, "app_link": "https://apps.apple.com/…" } } } }
```

**7. Data and side effects.** onboarding flag ছাড়া স্থানীয় কিছু নয়।

**8. Code references.** `lib/presentation/feature/splash/…`; `data/lib/remote/api_service/app_version_api_service/app_version_api_service_impl.dart`; response model `data/lib/remote/response/app_version_response.dart`।

**9. Handover notes.** সর্বনিম্ন version বাড়ানো identity-API-র data পরিবর্তন, app release নয় — কিন্তু নামানো দিয়ে প্রকাশিত ভাঙা build ঠিক হয় না; identity API-র মালিক নিশ্চিত করতে হবে (Open queries)।

### F3.2 Home ও event browse (অ্যাপ)

> **Bangla name:** হোম ও ইভেন্ট ব্রাউজ (অ্যাপ)

**1. Name and purpose.** App home (banner, আসন্ন event), event তালিকা ও বিস্তারিত — মোবাইলে portal F2.1/F2.2।

**2. Trigger and actor.** App `/home`, `/eventList`, `/eventDetails`। Actor: app user (anonymous browsing চলে)।

**3–4. Business/technical flow.** Portal-ের মতোই endpoint (Event service — anonymous): `event/api/v1/events/list`, `events/{id}`, `events/programs`, `landing-page-image/public`, `header-footer`; details screen কেনার জন্য `events/venue-details/{eventId}`-ও আনে। লগইনে home screen push token রেজিস্টার করে (F3.9)। Analytics: screen `screen_view` ও network error Firebase Analytics-এ যায়।

**5–7. Components / contracts / data.** F2.1/F2.2-এর মতো (Event service, Redis cache)। লেখা নেই।

**8. Code references.** `lib/presentation/feature/{home,event_list,event_details}/…`; `data/lib/remote/api_service/event_api_service_impl.dart`, `venue_details_api_service_impl.dart`।

**9. Handover notes.** App সব service-এর জন্য **একটাই gateway host** (`API_BASE_URL`) ব্যবহার করে — service prefix client-এ যোগ হয়, portal-এর মতোই।

### F3.3 Information page (pricing, gallery, যোগাযোগ — অ্যাপ)

> **Bangla name:** তথ্য-পেজ (প্রাইসিং, গ্যালারি, যোগাযোগ — অ্যাপ)

**1. Name and purpose.** টিকিট pricing, ফটো gallery ও যোগাযোগ screen — মোবাইলে portal F2.3; legal page env config-এর URL হিসেবে বাইরে খোলে।

**2–4. Trigger/flow.** App `/ticketPricing`, `/gallery`, `/contact`। Pricing: `event/api/v1/ticket-pricing/program-pricing`; gallery: `landing-page-image/public` client-এ `Gallery_Page_Segment_*` ছেঁকে; contact: `header-footer`; terms/privacy/ICC: `TERMS_AND_CONDITIONS_URL`, `PRIVACY_AND_POLICY_URL`, `ICC_ANTI_*_POLICY_URL` env WebView/browser-এ।

**5–8. Components / contracts / code.** F2.3-এর মতো। App: `lib/presentation/feature/{ticket_pricing,gallery,contact}/…`, `data/lib/remote/api_service/gallery_api_service_impl.dart`।

**9. Handover notes.** Legal URL flavor-প্রতি (`env/.env.<flavor>`) বসানো — বদলাতে হলে build-সময়ের config বদলাতে হয়, portal-এর মতো নয়।

### F3.4 Seat selection ও promo code (অ্যাপ)

> **Bangla name:** আসন নির্বাচন ও প্রোমো কোড (অ্যাপ)

**1. Name and purpose.** লাইভ availability-সহ level/আসন বাছাই ও promo code apply — মোবাইলে portal F2.4/F2.5।

**2–4. Trigger/flow.** App `/seatSelection` → `/ticketBooking`। Availability: `booking/api/v1/capacity/level-user-portal-seats?…` → `{ total, available }` (কমা-দিয়ে আসন string, app কমা ধরে ভাঙে); promo: `POST booking/api/v1/user-booking-order/apply-promo-code`; system discount: `GET admin/api/v1/discount/program/…` (model পড়ে `name`, `discountType`, `discountValue`)।

**5–8. Components / contracts / code.** F2.4/F2.5-এর মতো। App: `lib/presentation/feature/seat_selection/…`, `ticket_booking/…`; `data/lib/remote/response/ticket_booking/seat_availability_response.dart`, `system_discount_response.dart`।

**9. Handover notes.** App আসনের string client-এ ভাঙে — আসনের নামে কমা থাকলে ভাঙা ভুল হবে (portal-এর মতোই wire format)।

### F3.5 Booking ও WebView payment

> **Bangla name:** বুকিং ও WebView পেমেন্ট

**1. Name and purpose.** App-এর ভেতরে order তৈরি করে in-app WebView-এ DgePay-র page-এ পরিশোধ; URL থেকে সফলতা বোঝা হয়।

**2. Trigger and actor.** App `/ticketBooking` → `/payment`। Actor: app user, User pool।

**3. Business flow.**
1. Customer আসন/holder নিশ্চিত করেন (promo আগেই প্রয়োগ) — app order POST করে `publicId` + `checkoutUrl` পায়।
2. App `/payment`-এ WebView খুলে checkout URL দেখায়।
3. WebView যখন `PAYMENT_SUCCESS_URL`-এর host-**ধারণকারী** URL-এ যায়, app payment সফল ধরে WebView বন্ধ করে booking success/details-এ যায়; backend যাচাই F2.6-এর মতোই (redirect callback চালায়)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | App → Booking `POST /booking/api/v1/user-booking-order` | **[HTTP + user token]** | F2.6-এর মতো body/response (`CheckoutResponse { publicId, checkoutUrl }`) |
| 2 | WebView | — | `webview_flutter`-এর `NavigationDelegate.onNavigationRequest`: `request.url.contains(targetUrlHostName)` হলে → `onPaymentSuccess(url)`, `NavigationDecision.prevent` |
| 3 | Backend | — | DgePay callback F2.6 ধাপ ৪–৬-এর মতোই Booking-এ পড়ে (WebView শুধু browser) |

**5–8. Components / contracts / code.** F2.6 + app: `lib/presentation/feature/{ticket_booking,payment}/…` (view model), `data/lib/remote/response/check_out_response.dart`।

**9. Handover notes.** ① সফলতা শনাক্তকরণ URL-এর host-এ **substring match** — ওই host-এর ভেতর দিয়ে যাওয়া যেকোনো DgePay redirect chain এটে ট্রিগার করতে পারে; নির্ভুলতা `[UNCONFIRMED]`। ② `PAYMENT_SUCCESS_URL`-এর কোডে fallback default `ticket-bangla.com/tickets` — আসল মান flavor-প্রতি সেট।

### F3.6 আমার booking ও টিকিট (অ্যাপ)

> **Bangla name:** আমার বুকিং ও টিকিট (অ্যাপ)

**1. Name and purpose.** Order তালিকা, booking বিস্তারিত ও সব টিকিট-action — একটি/সব/invoice নামানো, holder সম্পাদনা, share, OneID sync — মোবাইলে F2.7–F2.10, **native download ও share**-সহ।

**2. Trigger and actor.** App `/bookingList`, `/bookingDetails`। Actor: app user, User pool।

**3–4. Business/technical flow.** F2.7–F2.10-এর মতোই endpoint (`list`, `details?publicId=`, PATCH ticket, PATCH `generate-request`, `check-generated-status`, `download`, `download-all`, `download-invoice`, `sync-order-to-oneid`)। Native বৈশিষ্ট্য:

| # | ধাপ | কী ঘটে |
|---|---|---|
| 1 | Download | `{API_BASE_URL}/ticketing/api/v1/booking-order-ticket/…` URL-এ Bearer header-সহ; **flutter_downloader** enqueue (`{ticketId}.pdf`, `{publicId}.zip`, `{orderId}-invoice.pdf`; public storage) |
| 2 | Share | `share_plus`-এর `SharePlus.instance.share(ShareParams(files: [XFile(path)], subject: 'Ticket PDF'))` |
| 3 | Polling | booking বিস্তারিত `check-generated-status` poll করে টিকিট না হওয়া পর্যন্ত |

**5–8. Components / contracts / code.** F2.7–F2.10-এর মতো। App: `lib/presentation/feature/{booking_list,booking_details}/…`; `data/lib/service/download_service.dart`, `data/lib/repository/{booking_details,ticket_booking}_repository_impl.dart`।

**9. Handover notes.** Download endpoint-এ Authorization header লাগে — app নিজের HTTP client দিয়ে app storage-এ নামায়; CloudFront cookie ব্যবহার করে **না** (ওটা admin portal-এর পথ, F1.12)।

### F3.7 Profile ও settings (অ্যাপ)

> **Bangla name:** প্রোফাইল ও সেটিংস (অ্যাপ)

**1. Name and purpose.** Profile দেখা/হালনাগাদ, password বদল, ভাষা, logout ও delete-account প্রবেশ — portal F2.11 + app-এর নিজস্ব settings।

**2. Trigger and actor.** App `/profile`, `/setting`। Actor: app user।

**3–4. Business/technical flow.** Profile GET/PUT `user/my-profile` (identity API; shape F2.11-এর মতো) — profile client `AUTH_API_BASE_URL` **Cognito Bearer-সহ** ব্যবহার করে (portal-এর static key-এর বিপরীতে); SSO user `user/register-sso { name, cognito_sub }` দিয়ে auto-register; password বদল Amplify দিয়ে; logout session মুছে (ও push token মুছে উচিত — note দ্রষ্টব্য); delete account → F6.11।

**5–8. Components / code.** `lib/presentation/feature/{profile,settings}/…`; `data/lib/remote/api_service/profile_api_service_impl.dart`, client `profile_api_client.dart`।

**9. Handover notes.** ① Logout-এ FCM-token DELETE call আছে কিন্তু `profile_view_model.dart`-এ **comment out** — লগআউট করা device এখনো push পেতে পারে। ② Root pubspec-এ `dio` ও `amplify_authenticator` declared কিন্তু data layer plain `http`/`Amplify.Auth` ব্যবহার করে (dead dependency)।

### F3.8 সমস্যা জানানো ও সাপোর্ট চ্যাট (অ্যাপ)

> **Bangla name:** সমস্যা জানানো ও সাপোর্ট চ্যাট (অ্যাপ)

**1. Name and purpose.** Issue খোলা ও support-এর সাথে chat — মোবাইলে F2.12, একই UserIssue service ও hub-এ।

**2–4. Trigger/flow.** App `/issues`, `/reportIssue`, `/chatCommunication`। REST: `POST userissue/api/v1/user-issue`, `GET user-issue/user/{userId}`, `GET user-issue/user-detail/{orderId}`, `GET user-issue-chat/{id}/messages?pageOffset=0&pageSize=50`, multipart `POST user-issue-chat/send` (field `AttachmentFile`), `GET message/{id}/attachment/download`। রিয়েল-টাইম: SignalR (`signalr_netcore`, শুধু WebSocket) hub `env['CHAT_COMMUNICATION_HUB']/userissue/chathub` token factory-সহ; send প্রথমে SignalR `SendMessage`, HTTP multipart fallback।

**5–8. Components / code.** F2.12-এর মতো। App: `lib/presentation/feature/{issues,report_issue,chat_communication}/…`; `data/lib/service/signal_r_service.dart`, `data/lib/remote/api_service/{issue,chat}_api_service_impl.dart`।

**9. Handover notes.** F2.12-এর anonymous-REST সতর্কতা এখানেও; hub URL env (`CHAT_COMMUNICATION_HUB`) — production-এ `chat.gobcbticket.com.bd`।

### F3.9 Push device-token registration

> **Bangla name:** পুশ ডিভাইস-টোকন রেজিস্ট্রেশন

**1. Name and purpose.** Device-এর FCM token PushNotification service-এ রেজিস্টার করা যাতে user push পান; Firebase ঘুরিয়ে দিলে refresh; logout-এ delete।

**2. Trigger and actor.** App লগইন (home/event list view model), token refresh callback, logout। Actor: app user।

**3–4. Business/technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Firebase init | — | `Firebase.initializeApp` (option `data/lib/firebase_options.dart`, মান env থেকে `FIREBASE_ANDROID_*` / `FIREBASE_IOS_*`); permission; foreground বার্তা → `flutter_local_notifications` (channel `high_importance_channel`) |
| 2 | Register | **[HTTP + user token]** | `POST /pushnotification/api/v1/device-token` `{ userId (Cognito sub), fcmToken, osType }` |
| 3 | Refresh | **[HTTP + user token]** | `onTokenRefresh` → `PUT device-token` `{ userId, oldToken, newToken, osType }` |
| 4 | Delete | **[HTTP + user token]** | `DELETE device-token` `{ userId, fcmToken }` (call এখন comment out — note দ্রষ্টব্য) |

**5. Components.** App (`data/lib/service/firebase_service.dart`, `repository/firebase_repository_impl.dart`); PushNotification service; `UserDeviceTokens` টেবিল (`OsType` ∈ android/ios/web)।

**6. API contracts.** উপরের body; send-এ `202` (F6.23)। Error: standard envelope (কিন্তু service-এ **কোনো auth নেই**, F6.18)।

**7. Data and side effects.** `UserDeviceTokens` upsert/delete; token shared pref `firebase_token`-এ।

**8. Code references.** `rvl-gobcb-user-app/data/lib/remote/api_service/firebase_api_service_impl.dart`; backend `rvl-gobcb-backend/Services/PushNotification/ETP.PushNotification.Service/Api/DeviceTokenController.cs`।

**9. Handover notes.** এক user-এর অনেক device = অনেক row; `send-to-user/{userId}` সবগুলোতে পাঠায় (F6.23)।

### F3.10 Push notification গ্রহণ

> **Bangla name:** পুশ নোটিফিকেশন গ্রহণ

**1. Name and purpose.** Customer প্রকৃতপক্ষে যা পান: event ঘোষণা (F6.23-এর send-to-all/send-to-users) ও ticket-generated notice — foreground banner ও system notification।

**2. Trigger and actor.** Scheduler worker F5.11-এর FCM delivery। Actor: app user (প্রাপক)।

**3–4. Business/technical flow.** FCM device-এ ঠেলে দেয়: foreground → `FirebaseMessaging.onMessage` → title/body-সহ local notification; background → system tray। ট্যাপ করলে app-এর সংশ্লিষ্ট screen-এ যায় (যেমন ticket-generated-এ bookings)। Data payload-র key প্রেরকের `Data`-এর উপর নির্ভর করে (F6.23 request)।

**5–7. Components / contracts / data.** App-এর firebase_service + local notification; FCM; গ্রহণে backend call নেই।

**8. Code references.** `rvl-gobcb-user-app/data/lib/service/firebase_service.dart`; প্রেরক পক্ষ F6.23/F5.11।

**9. Handover notes.** "ticket generated" push-এ ঠিক কী আছে (title/body ভাষা, data key) তা **external Notification API** (F5.12) বা admin প্রেরকের হাতে — এই repo-গুলোতে দেখা যায় না `[UNCONFIRMED]`।

## 4. Checker App

Flutter checker app-এ (`rvl-gobcb-checker-app`) gate staff-দের feature, TicketChecker Cognito pool। App **offline-first**: gate-এর টিকিট ও scan counter স্থানীয় database-এ (drift/SQLite) রাখে ও timer-এ backend-এর সাথে sync করে। লগইন F6.12।

> 📦 **Explainer: স্থানীয় database-সহ offline-first**
> ম্যাচডেতে gate-এর নেটওয়ার্কে ভরসা করা যায় না। Checker app বৈধ টিকিট নম্বর একবার নামায় (F4.2), প্রতিটি scan **device-এই** যাচাই করে — স্থানীয় তালিকা ও app-এর ভেতরে থাকা certificate দিয়ে (F4.3), scan স্থানীয়ভাবে রেকর্ড করে, আর প্রতি ৯০ সেকেন্ডে counter backend-এ ঠেলে দেয়/টেনে আনে (F4.5)। Backend একই counter Redis-এ রাখে, তাই একই gate-এর অন্য device-গুলো মিলে যায়।

### F4.1 নির্ধারিত event ও gate

> **Bangla name:** নির্ধারিত ইভেন্ট ও গেট দেখা

**1. Name and purpose.** লগইনের পরে checker তাঁর প্রশাসক-নির্ধারিত event ও entry gate দেখেন ও কাজের জন্য বেছে নেন।

**2. Trigger and actor.** Checker app → `/eventPage` (event/gate picker)। Actor: gate checker, TicketChecker pool (policy `ticket-checker`)।

**3. Business flow.**
1. Checker সাইন-ইন করেন (F6.12) ও event page খোলেন।
2. App নির্ধারিত event (cover image, তারিখ, entry gate-এর নাম ও offline download চালু কিনা) দেখায়।
3. Event/gate বেছে নিলে scanner dashboard (`/qrPage`) খোলে।
4. তালিকা device-এ cached, তাই offline-এও খোলে।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | App → Admin `GET /admin/api/v1/ticket-checker-gate/event-info` | **[HTTP + user token]** | চেকারের `TicketCheckerEventInfo` (নির্ধারিত event + gate + `IsDownloadEnabled`) |
| 2 | Admin service | — | লগইন করা `sub`-এর জন্য `TicketCheckerGates` / `TicketCheckerGateUsers` পড়ে (মালিক Admin) |
| 3 | App storage | — | Response shared preference-এ (`event-list`) offline fallback হিসেবে; প্রতি sync cycle-এ আবার আনে (F4.5) |

**5. Components.** Checker app; Admin service; TicketChecker pool; `TicketCheckerGates`, `TicketCheckerGateUsers` টেবিল।

**6. API contracts.**

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

মূল error: standard envelope; assignment না থাকলে app `ticket_checker_event_not_found` দেখায়।

**7. Data and side effects.** Server-এ কিছু নয়; device-এ shared-preferences cache।

**8. Code references.** `rvl-gobcb-checker-app/lib/presentation/feature/event_page/…`; `data/lib/remote/api_service/ticket_api_service_impl.dart`; `rvl-gobcb-backend/Services/Admin/ETP.Admin.Service/Api/TicketCheckerGateController.cs` (`event-info`); assignment নিজে F1.18।

**9. Handover notes.** ① Assignment admin portal-এ (F1.18); assignment-হীন checker কোনো event দেখেন না। ② `EntryGateIds` তালিকা — এক assignment কয়েক gate ঢাকতে পারে; scan তালিকার সাথে যাচাই হয় (F4.3)।

### F4.2 Offline যাচাইয়ের টিকিট download

> **Bangla name:** অফলাইন টিকিট যাচাইয়ের জন্য টিকিট ডাউনলোড

**1. Name and purpose.** নির্ধারিত event/gate-এর বৈধ টিকিট নম্বর দিয়ে device-এর স্থানীয় database ভরাট — যাতে নেটওয়ার্ক ছাড়াই যাচাই চলে।

**2. Trigger and actor.** Checker app-এ event বেছে নেওয়ার পরে প্রথম sync (ও scanner dashboard-এর ম্যানুয়াল "sync" বোতাম)। Actor: gate checker।

**3. Business flow.**
1. Event/gate বেছে নেওয়ার পরে app একটি sync করে (F4.5)।
2. Backend-এর উত্তরে ওই event/gate-র **সম্পূর্ণ টিকিট-নম্বর map** থাকে — এটাই download।
3. App নম্বরগুলো স্থানীয় drift database-এ লিখে offline scan-এর জন্য প্রস্তুত হয়।
4. Checker offline copy রাখতে পারবে কিনা `IsDownloadEnabled` flag (F4.1) নিয়ন্ত্রণ করে, যা admin রিসেট করতে পারেন (F1.18; cleanup worker F5.15)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | App → TicketChecker `POST /ticketchecker/api/v1/tickets/sync-tickets` | **[HTTP + user token]** | খালি/ছোট scan map; response = প্রামাণিক পূর্ণ টিকিট map (নিচে) |
| 2 | TicketChecker `TicketsManager` | — | Event/gate-প্রতি প্রথম call-এ Ticketing service থেকে Redis hash `ticket_checker_tickets:event_{eventLongId}_gate_{gateId}` ভরে (`GET /ticketing/api/v1/booking-order-ticket/ticket-numbers?eventId=…&levelIds=…`), RedLock `ticket_checker_gate_{gateId}`-এর ভেতরে |
| 3 | TicketChecker DB | **[Shared table]** | Checker-এর gate বের করতে `Events`, `TicketCheckerGates`, `BlockLevelEntryGates` mirror পড়ে |
| 4 | App | — | টিকিট নম্বর স্থানীয় drift DB-তে (`QrDao`); পরের sync শুধু counter হালনাগাদ করে |

**5. Components.** Checker app (drift DB); TicketChecker service (Redis + lock); Ticketing service (টিকিট নম্বর); এই flow-এ লেখা টেবিল নেই।

**6. API contracts.** Endpoint F4.5-এর মতোই — `POST /ticketchecker/api/v1/tickets/sync-tickets`, body `{"<ticketNumber>": 0}` বা pending scan; response পূর্ণ map:

```json
// 200
{
  "BCB-ODI2-GL12-A1": 0,
  "BCB-ODI2-GL12-A2": 0,
  "BCB-ODI2-GL12-A3": 1
}
```

(সংখ্যা = ওই টিকিট এই gate-এ ইতিমধ্যে কতবার ব্যবহৃত হয়েছে — সব device মিলিয়ে।)

**7. Data and side effects.** প্রথম sync-এ Redis hash `ticket_checker_tickets:event_…_gate_…` তৈরি; device-এ স্থানীয় DB row; PostgreSQL-এ কিছু নয় (scan DB-তে পৌঁছায় F5.14-এর মাধ্যমে, এখানে নয়)।

**8. Code references.** `rvl-gobcb-checker-app/data/lib/repository/qr_repository_impl.dart`, `data/lib/local/drift_database/…`; `rvl-gobcb-backend/Services/TicketChecker/ETP.TicketChecker.Domain/Managers/TicketsManager.cs`; টিকিট উৎস `rvl-gobcb-backend/Core/ETP.Core/ServiceClient/TicketingClient/TicketingClient.cs`।

**9. Handover notes.** ① Redis flag `ticketCheckerDbSync` চালু থাকা অবস্থায় (F5.14 drain চলাকালে) sync endpoint refuse করে — app error পেয়ে retry করে। ② পুরো gate-এর টিকিট (হাজার হাজার হতে পারে) এক JSON map-এ যায় — বড় gallery-তে payload size খেয়াল রাখুন।

### F4.3 QR scan validation

> **Bangla name:** QR স্ক্যান করে টিকিট যাচাই

**1. Name and purpose.** Gate-এর মূল কাজ: টিকিটের QR স্ক্যান করে — offline-এ, device-এই — ঠিক করা যে প্রবেশকারী ঢুকতে পারবেন কিনা।

**2. Trigger and actor.** Checker app → `/qrPage` (scanner)। Actor: gate checker।

**3. Business flow.** প্রতিটি scan-এ app আলাদা শব্দসহ পাঁচরকম ফলাফল দেখায়:
1. **Valid** — টিকিট এই event ও gate-এর, signature ঠিক, আগে ব্যবহৃত নয় (প্রবেশ স্থানীয়ভাবে রেকর্ড)।
2. **Already checked** — টিকিট আগে ব্যবহৃত (এই বা অন্য device-এ)।
3. **Wrong event** — QR-এর event id নির্ধারিত event-এর সাথে মেলে না।
4. **Wrong gate** — টিকিটের entry gate নির্ধারিত gate-গুলোর ভেতরে নয়।
5. **Invalid** — signature যাচাই ব্যর্থ বা টিকিট স্থানীয় তালিকায় নেই (offline-sold টিকিট → app নিশ্চিতকরণ চায়, F6.13)।

**4. Technical flow.**

| # | ধাপ | কী ঘটে |
|---|---|---|
| 1 | Scan | fork করা `flutter_barcode_scanner` plugin QR string পড়ে |
| 2 | Decode | `vds_qr_decoder.dart` **VDS** (Visible Digital Seal) payload base64-decode করে (gzip-aware): `payload`, `signature`, `certSN`, `issuerDN` |
| 3 | Signature যাচাই | **Offline** — Kotlin `MethodChannel('certificate/methods').verifyCertificate` (android `MainActivity.kt`) `VDS_CERTIFICATE` env-এর PEM certificate দিয়ে |
| 4 | নিয়ম যাচাই | Event id ও entry gate `TicketCheckerEventInfo`-র (F4.1) সাথে; ব্যবহারের সংখ্যা স্থানীয় DB-র (F4.2) সাথে তুলনা |
| 5 | রেকর্ড | Valid scan স্থানীয়ভাবে `isSynced: false` হিসেবে জমা; F4.5 ঠেলে দেয় |

> 📦 **Explainer: VDS QR ও কেন যাচাই offline**
> প্রতিটি টিকিট PDF-এ EU VDS ফরম্যাটের QR থাকে, যা TSP PDF sign করার সময় তৈরি হয় (F5.8)। QR-তে টিকিটের data-র সাথে TSP-র certificate দিয়ে করা ক্রিপ্টোগ্রাফিক signature থাকে। App-এ **public** certificate (`VDS_CERTIFICATE`) থাকে; signature যাচাই শুধু গণিত — QR সত্য কিনা প্রমাণে নেটওয়ার্ক লাগে না। এরপর gate/event নিয়ম স্থানীয় data-র সাথে সরল তুলনা।

**5. Components.** Checker app (scanner plugin, VDS decoder, MethodChannel, drift DB, `assets/sounds/`); TSP certificate chain (F5.8-এ তৈরি)।

**6. API contracts.** নেই — এই feature সম্পূর্ণ offline।

**7. Data and side effects.** স্থানীয় drift DB row (scan + `isManual=false`); F4.5-এর আগে কিছু যায় না।

**8. Code references.** `rvl-gobcb-checker-app/lib/presentation/feature/qr_page/qr_page_view_model.dart`, `qr_page/state/qr_check_state.dart`; `data/lib/service/vds_qr_decoder.dart`; `android/app/src/main/kotlin/com/mahfuznow/hello_flutter/MainActivity.kt`।

**9. Handover notes.** ① `verifyCertificate`-র শুধু Android (Kotlin) দিক পাওয়া গেছে — iOS-এ আছে কিনা `[UNCONFIRMED]`। ② TSP signing certificate ঘুরিয়ে দিলে নতুন `VDS_CERTIFICATE`-সহ app update দিতে হবে (বহু-cert ব্যবস্থা নেই)। ③ MethodChannel-এর নাম `certificate/methods`।

### F4.4 Manual entry

> **Bangla name:** ম্যানুয়াল এন্ট্রি (টিকিট নম্বর টাইপ করে যাচাই)

**1. Name and purpose.** QR পড়া না গেলে প্রবেশকারীকে ঢাকানো: checker টিকিট নম্বর টাইপ করেন ও app একই স্থানীয় নিয়মে যাচাই করে।

**2. Trigger and actor.** Checker app → `/manualEntry` (এবং `/manualTicketValidation`, F4.6)। Actor: gate checker।

**3. Business flow.**
1. Scanner dashboard-এ Manual entry আছে।
2. Checker টিকিট নম্বর টাইপ করেন।
3. App QR scan-এর মতোই যাচাই করে (আগে-ব্যবহৃত / event / gate) ও ফলাফল দেখায়।
4. Manual প্রবেশ `isManual` চিহ্নিত হয় ও **−1** হিসেবে sync হয় (F4.5), যাতে backend আলাদা করে চিনতে পারে (manual-entry report, F1.19)।

**4. Technical flow.** F4.3-এর ৪–৫ নং ধাপের মতোই, decoded QR-এর বদলে টাইপ করা নম্বর; signature যাচাই নেই (QR ছাড়া যাচাইয়ের উপায় নেই)।

**5. Components.** Checker app (manual_entry feature, drift DB)।

**6. API contracts.** সরাসরি নেই; −1 চিহ্ন F4.5-এর map-এ যায়।

**7. Data and side effects.** স্থানীয় DB row `isManual = true`।

**8. Code references.** `rvl-gobcb-checker-app/lib/presentation/feature/manual_entry/…`, `…/manual_ticket_validation/…`।

**9. Handover notes.** ① Manual প্রবেশে সত্যতা প্রমাণিত হয় না — শুধু নামানো তালিকার সাথে নম্বর মেলায়; offline-sold টিকিট (F6.13) এখানে নিশ্চিতযোগ্য হয়ে আসে। ② Map-এর +1/−1-ই server-এ manual/QR পার্থক্যের একমাত্র চিহ্ন।

### F4.5 Scan sync (৯০ সেকেন্ডের হার্টবিট)

> **Bangla name:** স্ক্যান সিঙ্ক (৯০ সেকেন্ডের হার্টবিট)

**1. Name and purpose.** এই device-এর নতুন scan আপলোড, gate-এর সব device-এর প্রামাণিক ব্যবহার-সংখ্যা ডাউনলোড, আর event-এর বৈধতা refresh — প্রতি ৯০ সেকেন্ডে বা চাহিদামতো।

**2. Trigger and actor.** App-এর background timer (৯০ s) ও ম্যানুয়াল sync বোতাম। Actor: gate checker।

**3. Business flow.**
1. প্রতি ৯০ সেকেন্ডে app তার না-পাঠানো scan পাঠায় (টিকিট নম্বর → +1 QR, −1 manual)।
2. Backend সেগুলো gate-এর counter-এ যোগ করে ও **সম্পূর্ণ** counter map ফেরায়।
3. App স্থানীয় counter প্রতিস্থাপন করে — অন্য device-এর scan এখানে "already checked" হয়ে দেখা যায়।
4. প্রতি cycle-এ app event info-ও (F4.1) আবার আনে; offline হলে cached copy।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | App → TicketChecker `POST /ticketchecker/api/v1/tickets/sync-tickets` | **[HTTP + user token]** | Body: pending scan map; policy `ticket-checker` |
| 2 | `TicketsManager.UpdateAndSyncTickets` | — | Redis flag `ticketCheckerDbSync` চালু থাকলে refuse (F5.14); RedLock `ticket_checker_gate_{gateId}` (expiry ২ s, wait ৫ s) নেয় |
| 3 | Redis | — | টিকিট-প্রতি `HashIncrementAsync` (+1/−1) hash `ticket_checker_tickets:event_…_gate_…`-এ; চেকার-প্রতি cache `ticket_checker_checked_tickets:{eventLongId}_{gateId}_{userSubId}` (`ConcurrentDictionary<string, TicketInfo>`) রাখে |
| 4 | Response | — | পূর্ণ hash ফেরে (`HashGetAllAsync<int>`); app স্থানীয় scan `isSynced` করে ও counter হালনাগাদ করে |

**5. Components.** Checker app; TicketChecker service; Redis (counter, flag, lock); Ticketing service (শুধু প্রথম ভরাটে, F4.2)।

**6. API contracts.** `POST /ticketchecker/api/v1/tickets/sync-tickets` — auth: TicketChecker pool (policy `ticket-checker`)। Body `Dictionary<string,int>`:

```json
{ "BCB-ODI2-GL12-A7": 1, "BCB-ODI2-GL12-A9": -1 }
```

Response: পূর্ণ counter map (sample F4.2-এ)। মূল error: standard envelope; app-নিয়ন্ত্রিত বার্তা `user_disabled_for_this_gate` (শিফটের মধ্যে checker disable) ও `ticket_checker_event_not_found`।

**7. Data and side effects.** Redis hash হালনাগাদ; scan PostgreSQL-এ পৌঁছায় শুধু Admin drain worker-এ (F5.14) যা `CheckedTickets`-এ লেখে।

**8. Code references.** `rvl-gobcb-checker-app/lib/presentation/feature/qr_page/qr_page_view_model.dart`; `data/lib/remote/api_service/ticket_api_service_impl.dart`; `rvl-gobcb-backend/Services/TicketChecker/ETP.TicketChecker.Service/Api/TicketController.cs`; `…/Managers/TicketsManager.cs`।

**9. Handover notes.** ① Counter শুধু Redis-ে F5.14 drain না হওয়া পর্যন্ত — admin report (F1.19) DB টেবিল পড়ে, তাই scan report-এ ~৩০ মিনিট পর্যন্ত দেরি। ② App দীর্ঘ offline থাকলেও scan হারায় না: স্থানীয়ভাবে জমা হয়ে পরে sync হয়; শুধু "অন্য device-এ already checked" সতেজতা কমে।

### F4.6 শুধু signature যাচাই (ম্যানুয়াল টিকিট ভ্যালিডেশন)

> **Bangla name:** শুধু সিগনেচার যাচাই (ম্যানুয়াল টিকিট ভ্যালিডেশন)

**1. Name and purpose.** QR-এর signature **ছাড়া** gate/event নিয়ম প্রয়োগ এবং প্রবেশ রেকর্ড না করে শুধু সত্য-নকল যাচাই — সন্দেহজনক QR পরীক্ষার জন্য।

**2. Trigger and actor.** Checker app → `/manualTicketValidation`। Actor: gate checker।

**3. Business flow.** Checker scan (বা টাইপ) করেন; app VDS QR decode করে F4.3-এর মতোই offline signature যাচাই করে, কিন্তু শুধু সত্য/নকল জানায় — event/gate তুলনা করে না, counter বাড়ায় না।

**4. Technical flow.** F4.3-এর ১–৩ ধাপ শুধু; স্থানীয় counter লেখা নেই, sync হয় না।

**5–7. Components / contracts / side effects.** F4.3-এর মতো নিয়ম ও counter বাদে; API call নেই, data লেখা নেই।

**8. Code references.** `rvl-gobcb-checker-app/lib/presentation/feature/manual_ticket_validation/…`।

**9. Handover notes.** এই screen আর F4.4-এর পার্থক্য চোখে পড়ে না: F4.4 প্রবেশকারীকে ঢাকায় (প্রবেশ রেকর্ড করে), এই screen শুধু সত্যতা যাচাই করে।

## 5. System-initiated (worker ও queue)

কাউকে সরাসরি শুরু করতে হয় না এমন কাজ: SQS queue consumer ও timer-চালিত background worker। আগে §0.8-এর explainer পড়ুন। এই worker-দের ডাকা endpoint-গুলোতে **`[Authorize]` নেই** — নিরাপত্তা শুধু network placement (F6.18)।

### F5.1 Level capacity update (OrderSuccess queue)

> **Bangla name:** লেভেল ক্যাপাসিটি আপডেট (OrderSuccess কিউ)

**1. Name and purpose.** প্রতিটি order event-এর পরে (payment সফল, cancel, admin capacity বদল) আসনের পরিবর্তন level-এর durable capacity ও Redis লাইভ counter-এ প্রয়োগ করা ও আসনের lock ছাড়া।

**2. Trigger and actor.** SQS queue `AWS:Queue:OrderSuccess`; publisher: Booking (`UserBookingOrderManager` payment সফল/cancel-এ; `CapacityManager` admin বদলে)। মানুষ জড়িত নয়।

**3. Business flow.** প্রতিটি booked/released আসন-দলের জন্য database capacity ও লাইভ আসন-ম্যাপ মিলে যায়, পরের customer সঠিক availability দেখেন।

**4. Technical flow.**

| # | ধাপ | কী ঘটে |
|---|---|---|
| 1 | Message | `LevelCapacityUpdate { orderType, amount, hasSeats, seats, isIncrease, capacityAction, groupId, orderId }` (`Core/ETP.Core/Queue/Messages/LevelCapacityUpdate.cs`); `GroupId = {eventLongId}_{galleryId}_{blockId}_{levelId}`, `OrderId` = booking `PublicId` |
| 2 | Consumer | Booking `LevelCapacityUpdateService` → `LevelCapacityUpdateTaskManager` (SQS receive; সফল হলে delete) |
| 3 | DB | `ICapacityManager.UpdateLevelCapacityAsync` — durable `Capacities` row |
| 4 | Redis | `capacity` hash: `level_live:{groupId}` কমায়, `HDEL level_locked:{groupId}/{orderId}`, `level_live_seats:{groupId}` পুনঃগণনা (সব আসন − কেনা − ১২ মিনিটের কম lock) |

**5–6. Components / contracts.** Booking service; SQS OrderSuccess; Redis `capacity` hash; `Capacities` টেবিল। HTTP API নেই।

**7. Data and side effects.** `Capacities` হালনাগাদ; উপরের Redis field; সফল হলে message delete।

**8. Code references.** `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Workers/{BackgroundServices/LevelCapacityUpdateService.cs,TaskManagers/LevelCapacityUpdateTaskManager.cs}`; publisher `…/Domain/Managers/{UserBookingOrderManager,CapacityManager}.cs`।

**9. Handover notes.** GroupId parse-এ `_` ধরে ভাঙা হয় — id-তে সংখ্যাই থাকতে হবে (`_` থাকলে ভাঙা ভুল হয়)।

### F5.2 Event live capacity (EventCapacity queue)

> **Bangla name:** ইভেন্ট লাইভ ক্যাপাসিটি (EventCapacity কিউ)

**1. Name and purpose.** Redis-এর event-স্তরের লাইভ counter (`event_live:{eventId}`) capacity বদলের সাথে মিলিয়ে রাখা, যাতে "এই event-এ N টিকিট বাকি" সঠিক থাকে।

**2. Trigger and actor.** SQS `AWS:Queue:EventCapacity`; publisher: Booking `CapacityManager` (admin capacity adjustment)।

**3–4. Business/technical flow.** Message `EventLiveCapacityUpdate { eventId, amount, isIncrease, groupId, orderId }` → Booking `EventLiveCapacityUpdateService` → task manager ধারাবাহিকভাবে (একবারে এক message, ক্রম ঠিক রেখে) Redis STRING `event_live:{groupId}` বাড়ায়/কমায়।

**5–7. Components / data.** Booking service; SQS; Redis STRING `event_live:{eventId}`; DB লেখা নেই।

**8. Code references.** `…/Workers/BackgroundServices/EventLiveCapacityUpdateService.cs`, `…/TaskManagers/EventLiveCapacityUpdateTaskManager.cs`।

**9. Handover notes.** এই key পড়ে `GET /booking/api/v1/capacity/event-live-capacity?eventId=` (F2.4); Scheduler *ভিন্ন* key লেখে (`event_{eventId}`, F5.4) — গুলিয়ে ফেলবেন না।

### F5.3 Locked-capacity refresh

> **Bangla name:** লক করা ক্যাপাসিটি রিফ্রেশ

**1. Name and purpose.** যারা পরিশোধ করেননি তাদের লক করা আসন ছাড়া, যাতে পরিত্যক্ত checkout আসন আটকে না রাখে।

**2. Trigger and actor.** Booking timer worker `RefreshLockedCapacityService` — প্রতি **৩০ মিনিটে** (error-এর পরে ৫ মিনিট)।

**3–4. Business/technical flow.** Order আসন lock করলে তার key Redis SET `refresh`-এও যোগ হয়। Worker (RedLock `locked_order_refresher_{0..4}`, ১৫ মিনিট) `SMEMBERS refresh` করে; key-প্রতি `refresh_level_locks_{key}` (৩০ s) নিয়ে `level_locked:{groupId}` থেকে **১২ মিনিটের** বেশি পুরোনো entry `HDEL` করে, `level_live_seats` পুনঃগণনা করে ও key `SREM` করে। আটকে যাওয়া checkout তাই ≈ ১২ + ৩০ মিনিটে আসন ছাড়ে।

**5–7. Components / data.** Booking service; Redis SET `refresh`, hash `level_locked:*`; DB capacity পুনঃগণনা।

**8. Code references.** `…/Workers/{BackgroundServices/RefreshLockedCapacityService.cs,TaskManagers/RefreshLockedCapacityTaskManager.cs}`, `…/Managers/CapacityManager.cs`।

**9. Handover notes.** ১২ মিনিটের মেয়াদ hard-coded (`SystemSettings.SeatLockTimeout`-এর সাথে তুলনা করুন, F1.30 `[UNCONFIRMED]`)।

### F5.4 Scheduler capacity reconcile

> **Bangla name:** শিডিউলার ক্যাপাসিটি রিকনসাইল

**1. Name and purpose.** মাঝেমধ্যে level-প্রতি লাইভ counter গুটিয়ে event-মোট বানানো — Redis ও বাস্তবের বিচ্যুতি মেরামত।

**2. Trigger and actor.** Scheduler timer worker `CapacityUpdateService` — প্রতি **১৫ মিনিটে** (RedLock `event_live_capacity_refresher`, ১৫ মিনিট)।

**3–4. Business/technical flow.** পুরো Redis hash `capacity` পড়ে; ৫-অংশের `_`-বিভাজিত প্রতিটি field-এর (`level_live:{eventId}_…`) জন্য `parts[1]` (event id) ধরে গুছিয়ে লাইভ মান যোগ করে STRING `event_{eventId}` লেখে — কিন্তু key আগে থেকে থাকলেই (নতুন বানায় না, শুধু self-heal করে)।

**5–7. Components / data.** Scheduler service; Redis hash `capacity` + STRING `event_{eventId}`; HTTP নেই, DB নেই।

**8. Code references.** `rvl-gobcb-backend/Services/Scheduler/ETP.Scheduler.Service/Workers/{BackgroundServices/CapacityUpdateService.cs,TaskManagers/CapacityUpdateTaskManager.cs}`।

**9. Handover notes.** F5.1-এর মতোই `_`-ভাঙার ভঙ্গুরতা; আর লেখা key family (`event_…`) F5.2-এর (`event_live:…`) থেকে আলাদা — দুটোর পাঠক আলাদা।

### F5.5 Pending/failed payment পুনঃযাচাই

> **Bangla name:** পেন্ডিং/ফেইল্ড পেমেন্ট পুনঃযাচাই

**1. Name and purpose.** Payment-এর মাঝে browser বন্ধ করা customer-দের order `Pending`/`Failed` থেকে যায়। এই job সাম্প্রতিকগুলো DgePay-র সাথে পুনঃযাচাই করে (আসলে পরিশোধ হয়ে থাকতে পারে) ও বাকিগুলো cancel করে।

**2. Trigger and actor.** Scheduler timer worker `PendingOrFailedBookingStatusUpdateService` — প্রতি **২ মিনিটে** (RedLock `pending_cancel_booking_status_updater`, ২ মিনিট)।

**3–4. Business/technical flow.**

| # | ধাপ | কী ঘটে |
|---|---|---|
| 1 | Scheduler → Booking `PUT /booking/api/v1/user-booking-order/update-status` | **[HTTP, no token]** (internal endpoint) — body `UpdateBookingStatusRequest { limit, cutoffTime }` (cutoff = এখন − ১২ মিনিট; `limit` অব্যবহৃত) |
| 2 | Booking controller | **দুটি সমান্তরাল background task** চালায়: `CancelBookingAsync(cutoff)` — পুরোনো Pending/Failed order cancel; এবং `RevaildateRecentPendingBookingsAsync(cutoff)` (কোডেই বানান-ভুল) — সাম্প্রতিক pending order DgePay `check_transaction_status` দিয়ে পুনঃযাচাই করে সত্যিই পরিশোধিতগুলো সম্পূর্ণ করে; `true` ফেরায় |

**5–7. Components / data.** Scheduler; Booking; DgePay; `UserBookingOrders` status হালনাগাদ; মুক্ত capacity manager-এর F5.1 message দিয়ে যায়।

**8. Code references.** `…/Scheduler.Service/Workers/BackgroundServices/PendingOrFailedBookingStatusUpdateService.cs`; `…/Booking.Service/Api/UserBookingOrderController.cs` (`update-status`), `…/Managers/UserBookingOrderManager.cs` (`CancelBookingAsync`, `RevaildateRecentPendingBookingsAsync`)।

**9. Handover notes.** DgePay পৌঁছানো না গেলেও cancel task চলে — পরিশোধিত-কিন্তু-অনিশ্চিত order cancel হয়ে পরে discrepancy report-এ (F1.22) উঠতে পারে। পুনঃযাচাই window = ১২ মিনিটের cutoff।

### F5.6 Booking status → Generated

> **Bangla name:** বুকিং স্ট্যাটাস → Generated

**1. Name and purpose.** Order-এর (ও reservation-এর) প্রতিটি টিকিট সত্যিই তৈরি (signed) হয়ে গেলে `Requested` থেকে `Generated`-এ ওল্টানো — F2.6/F2.8-এ শুরু হওয়া চক্র পূর্ণ করে।

**2. Trigger and actor.** Booking timer worker `BookingStatusUpdateService` — প্রতি **২ মিনিটে** (RedLock `booking_status_updater`); ভাই `ReservationStatusUpdateService` — প্রতি **৩০ মিনিটে** (RedLock `reservation_status_updater`) reservation-এর জন্য।

**3–4. Business/technical flow.** ≤৫০০টি `Requested` booking নিয়ে → **[HTTP, no token]** `POST /ticketing/api/v1/booking-order-ticket/ticket-counts` (body: order id, `onlyGenerated=true`, `createdBy="user"`) → যেখানে `GeneratedCount == NumberOfSeats` সেগুলো `UpdateRequestedBookingToGeneratedAsync(ids)` (status `Requested → Generated`)। Reservation worker একই কাজ reservation-এ করে।

**5–7. Components / data.** Booking + Ticketing service; `UserBookingOrders`/`SeatReservations` status লেখা।

**8. Code references.** `…/Workers/BackgroundServices/{BookingStatusUpdateService,ReservationStatusUpdateService}.cs` + task manager।

**9. Handover notes.** `Requested` মানে "তৈরির অনুরোধ হয়েছে"; এই worker নিশ্চিত করার আগে My Tickets poll করে (F2.7-এর `check-generated-status`)।

### F5.7 User ticket generation শুরু (সেফটি-নেট)

> **Bangla name:** ইউজার টিকিট জেনারেশন শুরু (সেফটি-নেট)

**1. Name and purpose.** Event-এর ticket-availability সময় এসে যাওয়া **paid** order-দের তৈরি শুরু করার safety net — window খোলার আগে পরিশোধিত বা inline শুরু (F2.6 ধাপ ৬) ব্যর্থ হওয়া order ধরে।

**2. Trigger and actor.** Booking timer worker `InitiateUserTicketGenerationService` — প্রতি **১৫ মিনিটে** (১০ মিনিট start delay); event-প্রতি RedLock `user_ticket_generator_{eventId}` (১২ মিনিট)।

**3–4. Business/technical flow.** `TicketAvailabilityStartDateTime <= UtcNow` এমন প্রতিটি active+published event-এর জন্য: ≤২০০টি `Paid` booking নিয়ে প্রতিটির জন্য **[HTTP, no token]** `GET /ticketing/api/v1/booking-order-ticket/initiate-user-ticket?orderId={publicId}` → Ticketing `InitiateUserTicket`: status `Paid`/`Requested` চায়, RedLock `create_user_ticket_{orderId}` (৩০ s) নেয়, Ticket row বানায় (`TicketNumber = {TicketNumberPrefix}{unique code}`), blank PDF `{BlankBase}/user/{userId}/{publicId}/{TicketNumber}.pdf`-তে তোলে, `Requested` চিহ্নিত করে, প্রতি টিকিটে **[SQS: TicketSigning]** publish করে ও order `Requested` করে।

**5–7. Components / data.** Booking + Ticketing; SQS TicketSigning; S3 ticket bucket; `Tickets` (insert), `UserBookingOrders` (→ Requested)।

**8. Code references.** `…/Workers/BackgroundServices/InitiateUserTicketGenerationService.cs`; `…/Ticketing.Domain/Managers/TicketManager.cs` (`InitiateUserTicket`, `InitiateBulkTicketForNewlyPaidOrder`, `TicketGenerateRequest`)।

**9. Handover notes.** `TicketGenerateRequest` portal-এর PATCH `generate-request` (F2.8) থেকেও প্রতি-request চলে — একই lock + idempotency দ্বৈত তৈরি আটকায়।

### F5.8 TSP-তে টিকিট signing (TicketSigning queue)

> **Bangla name:** TSP-এর মাধ্যমে টিকিট সাইনিং (TicketSigning কিউ)

**1. Name and purpose.** টিকিটের সত্যতার হৃদয়: প্রতিটি blank টিকিট PDF সরকারি TSP gateway-তে পাঠিয়ে ডিজিটালি sign (PAdES) করানো VDS QR-সহ, signed PDF সংরক্ষণ, আর customer ও gate cache-তে দৃশ্যমান করা।

**2. Trigger and actor.** SQS `AWS:Queue:TicketSigning`; publisher: Ticketing `TicketManager` (F5.7/F2.8-এর পরে user টিকিট; F1.12-এর পরে reserved টিকিট)।

**3. Business flow.** টিকিট প্রমাণিতভাবে সত্য হয়: signed PDF-এর QR checker app offline-এ যাচাই করতে পারে (F4.3), আর My Tickets download দিতে শুরু করে (F2.9)।

**4. Technical flow.**

| # | ধাপ | কী ঘটে |
|---|---|---|
| 1 | Message | `SignedTicketGeneration { fileName, unsignedTicketUrl, gateId, data (Dictionary<string, QRCodeField>), qrPosition [x,y,size], orderId (= ticket id) }`। User টিকিটের QR `data`: `Platform (online/user-ticket), Name, Phone, Date (BST +6), Time, Ticket ID, Event ID, Gallery, Block, Level, Entry Gate, Mini Gate [, Seat]`; reserved টিকিটে Name/Phone-এর বদলে `Platform (offline/…)` + `Complimentary`। `qrPosition` layout-এর `TicketSize` অনুযায়ী: Default/Vertical `[900,650,650]`, A4 `[1650,915,650]`, Horizontal `[2494,1055,650]` |
| 2 | Consumer | Ticketing `TicketGenerationService` → `TicketGenerationTaskManager` (SQS ৫ message / ১০ s wait / ৬০ s visibility); **idempotent**: `IsTicketSigned(orderId)` হলে কাজ ছাড়াই message delete |
| 3 | TSP auth | `TspAuthProvider` **[HTTP, mTLS + static identity]**: `GET {TSP:AuthUrl}` client cert `Cert/tspgw_client.pfx`-সহ; token Redis `tsp_token`-এ ১ মিনিট (server cert validation disabled — note দ্রষ্টব্য) |
| 4 | Sign | `TspSignedTicketProvider` **[HTTP + mTLS + bearer]**: `POST {TSP:SignUrl}` `TicketSigningPayload` (নিচে) → `TspResponse.data.signedData[0]` (base64 PDF) |
| 5 | সংরক্ষণ | `GenerateSignedTicketAsync`: reserved type-এ টিকিটের তথ্য PDF-এ **আঁকা** হয় (`DrawTicketInfo`, PdfSharpCore); upload `{SignedBase}/user/{CreatedBy}/{orderPublicId}/{TicketNumber}.pdf` (বা `…/reserved/{CreatedBy}/…/{TicketNumber}-{type}.pdf`); `Status=Generated`, `SignedTicketUrl` সংরক্ষণ |
| 6 | OneID tail | `bookingOrder.OneIdUserId` থাকা user টিকিটে: signed PDF OneID-তে auto-sync (flow F2.10); error গিলে ফেলা হয় |
| 7 | Gate cache tail | Redis hash `TicketCheckerLevelGateMap`-এর field `{eventLongId}_{gateId}` → gate-এর `ticket_checker_tickets:event_…_gate_…` key থাকলে `{TicketNumber}: 0` যোগ, পরের sync-এ gate device নতুন টিকিট পায় (F4.5) |

`TicketSigningPayload` (`Domain/TspClient/Models/TicketSigningPayload.cs`, snake_case): `{ blevel, customNotification, digitalIdentityId (TSP:DigitalIdentityId), documents: [ { data (base64 PDF), fileName, vdsData: { qrCodeData, qrCodePage: 1, qrCodeSize, qrCodeXPosition, qrCodeYPosition }, vsigEnabled: false, … } ], packaging: "ENVELOPED", sealDocument: false, signAlgorithm: "SHA256WithRSA", signatureSubType: "PAdES_BASELINE_B", signatureType: "PADES", userId (TSP:UserId) }`।

**5–6. Components / contracts.** Ticketing service; SQS TicketSigning; TSP gateway (mTLS); Redis (`tsp_token`, gate map); S3 ticket bucket; `Tickets` টেবিল।

**7. Data and side effects.** `Tickets.Status`/`SignedTicketUrl` হালনাগাদ; S3-এ signed PDF; ঐচ্ছিক OneID sync (`OneIdSync`/`OneIdSyncedAt`); gate-cache Redis সংযোজন; message শুধু সফলতায় delete।

**8. Code references.** `rvl-gobcb-backend/Services/Ticketing/ETP.Ticketing.Service/Workers/{BackgroundServices/TicketGenerationService.cs,TaskManagers/TicketGenerationTaskManager.cs}`; `…/Managers/TicketManager.cs` (`GenerateSignedTicketAsync`, `GetBlankPdf`); `…/TspClient/{TspAuthProvider,TspSignedTicketProvider}.cs`; blank PDF আঁকা `…/Domain/BlankPdf.cs` (PdfSharpCore, font Inter/Oswald)।

**9. Handover notes.** ① TSP client cert (`Cert/tspgw_client.pfx`) container-এর সাথে যায় — মেয়াদ operationally গুরুত্বপূর্ণ `[UNCONFIRMED: বর্তমান মেয়াদ]`। ② TSP call-এ server-certificate validation বন্ধ। ③ QR-এর "Date" hard-coded +৬ ঘণ্টা BST offset-এ। ④ OneID sync-এর `vdsQrData` একটি `TODO` stub (`null`)।

### F5.9 Reserved টিকিট merge/zip (TicketProcessing queue)

> **Bangla name:** রিজার্ভড টিকিট মার্জ/জিপ (TicketProcessing কিউ)

**1. Name and purpose.** Reservation-এর signed টিকিট PDF একত্রিত করা (ছাপার জন্য) বা আলাদাভাবে zip করা (বিতরণের জন্য) — F1.12-এর merge/zip বোতামের ভারী কাজ।

**2. Trigger and actor.** SQS `AWS:Queue:TicketProcessing`; publisher: Ticketing `TicketManager.RequestMergeTicketsAsync`/`RequestZipTicketsAsync` (reservation-এ `MergeStatus.Requested`/`ZipStatus.Requested` সেট করে)।

**3–4. Business/technical flow.**

| # | ধাপ | কী ঘটে |
|---|---|---|
| 1 | Message | `TicketProcessingRequest { reservationId, groupId, orderId, processingType: "Merge"|"Zip" }` |
| 2 | Consumer | **Utility** service-এর `TicketProcessingService` (১-মিনিট cycle, একবারে ১ message); RedLock `ticket_processing_service_{reservationId}` (১ ঘণ্টা) |
| 3 | Skip-if-done | **[HTTP, no token]** Booking `GET merge-status/{publicId}` / `zip-status/{publicId}` — হয়ে গেলে delete করে থামে |
| 4 | Merge | **[HTTP, no token]** `PATCH update-merge-status/{publicId}?status=Merging` → `TicketingClient.GetTicketUrlsAsync(reservationId)` → `AWS:Ticket:MergeSize`-এর চাঙ্কে PdfSharpCore merge → `{MergeBase}/{reservationId}/{ReservationNumber}_Merged_PDF_{i}.pdf` upload → status `Merged` |
| 5 | Zip | একইভাবে: `{ReservationNumber}_Individual_Zipped_{i}.zip` (temp dir + `ZipFile.CreateFromDirectory`, `CompressionLevel.Optimal`); status `Zipping`→`Zipped` |
| 6 | ব্যর্থতা | status `Failed`, message queue-তে **থেকে যায়** (retry; শেষে dead-letter `[UNCONFIRMED: DLQ config]`) |

**5–7. Components / data.** Utility + Booking + Ticketing; SQS; S3 ticket bucket; `SeatReservations.MergeStatus/ZipStatus`; S3 `IsObjectExistAsync` দিয়ে idempotent।

**8. Code references.** `rvl-gobcb-backend/Services/Utility/ETP.Utility.Service/Workers/…/TicketProcessingTaskManager.cs`; `…/Utility.Domain/Managers/UtilityService.cs`; publisher `…/Ticketing.Domain/Managers/TicketManager.cs`।

**9. Handover notes.** ① `AWS:Ticket:MergeBuffer` option-এ আছে কিন্তু কোথাও ব্যবহৃত নয় (dead config)। ② Worker প্রতি ~৫০ item-এ `GC.Collect` করে — বড় PDF batch-এ memory pressure-এর দুশ্চিন্তা স্পষ্ট।

### F5.10 NBR-এ VAT challan (VatChallanProcessing queue)

> **Bangla name:** NBR-এর সাথে VAT চালান (VatChallanProcessing কিউ)

**1. Name and purpose.** Paid order-এর পরে বাংলাদেশের NBR e-challan সিস্টেমে VAT record করা ও challan download করে booking-এর সাথে জোড়া (`VatInvoiceId/Info/DownloadUrl`, `SmartChallanNumber` field)।

**2. Trigger and actor.** SQS `AWS:Queue:VatChallanProcessing`; publisher: Booking `UserBookingOrderManager` (payment সফল হলে)।

**3–4. Business/technical flow.**

| # | ধাপ | কী ঘটে |
|---|---|---|
| 1 | Message | `VatChallanProcessing { groupId, orderId, bookingPublicId, userId, eventLongId, eventId, eventName?, orderNumber, paymentTransactionId, totalCharge, pricePerSeat, numberOfSeats, vat, discount, promoDiscount, isVatInclusive, createdAt, retryCount, lastErrorMessage? }` |
| 2 | Consumer | Booking `VatChallanProcessingService` — প্রতি **৪৫ সেকেন্ডে**; RedLock `vat_challan_processor_{0..9}` (৫ মিনিট, wait ১০ s); SQS ৫ message / ৩০০ s visibility; **সর্বোচ্চ ৩ retry** (exponential backoff, message-এ `retryCount`) |
| 3 | NBR call | `NBROpenApiManager` **[HTTP, static key]** (`PaymentSettings:NBROpenApi:BaseUrl`): `POST /vschallan/v3/integration/vendor_authenticate` → `POST …/record_vat` → `GET/POST …/download_schallan`; NBR token মেয়াদ শেষে `UnauthorizedAccessException` (403 path) |
| 4 | সংরক্ষণ | challan নম্বর + invoice id/info/download URL `UserBookingOrders` row-তে |
| 5 | ব্যর্থতা | message-এ `lastErrorMessage` রেখে ৩ বার পর্যন্ত retry; তারপর DLQ-র জন্য থেকে যায় `[UNCONFIRMED]` |

**5–7. Components / data.** Booking service; SQS; NBR OpenAPI (external); `UserBookingOrders`-এর VAT field।

**8. Code references.** `…/Workers/{BackgroundServices/VatChallanProcessingService.cs,TaskManagers/VatChallanProcessingTaskManager.cs}`; `…/Managers/NBROpenApiManager.cs`; model `…/Domain/Models/NBR/NBR*.cs`।

**9. Handover notes.** NBR vendor credential secret config (`PaymentSettings:NBROpenApi:*`); retry সীমা মানে ব্যর্থ NBR ~৩ চেষ্টার পরে হাল ছাড়ে — সেগুলো discrepancy report-এ (F1.22) খুঁজুন।

### F5.11 FCM-এ push delivery (FirebaseNotification queue)

> **Bangla name:** FCM-এ পুশ ডেলিভারি (FirebaseNotification কিউ)

**1. Name and purpose.** Push notification ফোনে পৌঁছানো: PushNotification service queue-তে দেয় (F6.23), এই worker প্রতিটি batch Firebase Cloud Messaging দিয়ে পাঠায়।

**2. Trigger and actor.** SQS `AWS:Queue:FirebaseNotification`; publisher: PushNotification `NotificationManager` (২০০ token-এর batch, `GroupId=requestId`, `OrderId="{requestId}-batch-N"`)।

**3–4. Business/technical flow.**

| # | ধাপ | কী ঘটে |
|---|---|---|
| 1 | Message | `FirebaseNotificationRequest { title, body, data, deviceTokens[], createdAt, groupId, orderId }` |
| 2 | Consumer | Scheduler `FirebaseNotificationService` — ১-মিনিট outer cycle; SQS ৫ message / ১০ s wait / ৬০ s visibility |
| 3 | Send | `FirebasePushNotificationService.SendNotificationToMultipleAsync` — FirebaseAdmin `SendEachForMulticastAsync`; credential = config section `FirebasePushNotificationConfig` থেকে গড়া service-account JSON (key `Type, ProjectId, PrivateKeyId, PrivateKey, ClientEmail, ClientId, ClientX509CertUrl, AuthUri, TokenUri, AuthProviderX509CertUrl, UniverseDomain`) |
| 4 | Delete | Message **সবসময় `finally`-তে delete** — সফল বা ব্যর্থ (retry নেই!) |

**5–7. Components / data.** Scheduler; SQS; Firebase FCM (external); DB নেই।

**8. Code references.** `rvl-gobcb-backend/Core/ETP.Core/PushNotification/FirebasePushNotificationService.cs`; `…/Scheduler.Service/Workers/{BackgroundServices/FirebaseNotificationService.cs,TaskManagers/FirebaseNotificationTaskManager.cs}`; `Core/ETP.Core/Options/FirebaseOptions.cs`।

**9. Handover notes.** ① ব্যর্থতা delete হয়ে যায় বলে খারাপ token বা FCM outage-এ batch নীরবে হারায় — `bulk-status/{requestId}` endpoint (F6.23) stub, delivery tracking নেই। ② `FirebaseBulkNotificationRequest` (`BatchNumber/TotalBatches`-সহ) আছে কিন্তু কেউ পূরণ/ব্যবহার করে না (dead code)।

### F5.12 Ticket-generated notification

> **Bangla name:** টিকিট-জেনারেটেড নোটিফিকেশন

**1. Name and purpose.** Customer-দের জানানো টিকিট প্রস্তুত (external Notification API দিয়ে SMS) — কেনার অভিজ্ঞতার সমাপ্তি।

**2. Trigger and actor.** Scheduler timer worker `SendNotificationAfterGeneratedTicketService` — প্রতি **৩ মিনিটে** (RedLock `notification_for_ticket_generated`, ৩ মিনিট)।

**3–4. Business/technical flow.**

| # | ধাপ | কী ঘটে |
|---|---|---|
| 1 | Batch আনা | **[HTTP, no token]** Booking `GET /booking/api/v1/user-booking-order/not-notified-list?limit=100` |
| 2 | সমৃদ্ধকরণ | booking-প্রতি: **[HTTP, no token]** Event `GET /event/api/v1/events/{id}` (`IEventClient`), Ticketing `GetGeneratedTicketByOrderId`, Admin `GetEventLevelInfoAsync` |
| 3 | পাঠানো | **[HTTP, static key]** Notification API `POST {Notification:Endpoint}/notification/request` — body `TicketGeneratedNotification` (snake_case): `{ notification_type: "ticket_generated", user_id, notification_data: { order_id, ticket_id, program_event, event_venue, seating_gallery, seating_block, seating_level, entry_gate, mini_gate } }` |
| 4 | চিহ্নিতকরণ | **[HTTP, no token]** Booking `PUT …/update-notification-status` (body: order id-র তালিকা) |

**5–7. Components / data.** Scheduler; Booking, Event, Admin, Ticketing service; Notification API (external — SMS fan-out `[UNCONFIRMED: push-ও পাঠায় কিনা?]`); `UserBookingOrders`-এ notified চিহ্ন।

**8. Code references.** `…/Scheduler.Service/Workers/BackgroundServices/SendNotificationAfterGeneratedTicketService.cs`; client `Core/ETP.Core/ServiceClient/NotificationClient/NotificationClient.cs`; model `Core/ETP.Core/Models/Notification.cs`।

**9. Handover notes.** Message-গুলো SMS বর্ণনা করে; user app-এর "ticket generated" push (F3.10) সম্ভবত এখানে বা Notification API-তে উৎপন্ন — FCM send-এর পথ repo-তে দেখা যায় না `[UNCONFIRMED]`।

### F5.13 Device-token cleanup

> **Bangla name:** ডিভাইস-টোকেন ক্লিনআপ

**1. Name and purpose.** পুরোনো FCM device token (uninstall হওয়া app) দৈনিক অপসারণ, যাতে push মৃত token-এ না যায়।

**2. Trigger and actor.** Scheduler timer worker `DeviceTokenCleanupService` — প্রতিদিন **02:00 UTC**-তে (RedLock `device_token_cleanup`, ২ ঘণ্টা)।

**3–4. Business/technical flow.** Worker → `EventClient.CleanupOldDeviceTokensAsync(30)` — `DELETE api/v1/device-token/cleanup?retentionDays=30` (Polly ৫ retry)। ওই route-এর একমাত্র implementation **PushNotification** service-এ (`{ message, deletedCount, cutoffDate, retentionDays }`, cutoff-এর আগের `UserDeviceTokens` মুছে) — **কিন্তু** Scheduler-এর `IEventClient` base address `Services:Admin`। `Services:Admin` যদি `/api/v1/device-token/*`-কে PushNotification-এ route করা কোনো gateway না হয়, call কাজ করবে না — repo থেকে যাচাইযোগ্য নয় `[UNCONFIRMED]` (Open queries)।

**5–7. Components / data.** Scheduler; PushNotification service (implementation); `UserDeviceTokens` delete।

**8. Code references.** `…/Scheduler.Service/Workers/BackgroundServices/DeviceTokenCleanupService.cs`; `Core/ETP.Core/ServiceClient/EventClient/EventClient.cs`; implementation `…/PushNotification.Service/Api/DeviceTokenController.cs`।

**9. Handover notes.** এটি সবচেয়ে স্পষ্ট "BS23-কে জিজ্ঞাসা করুন" item-এর একটি: হয় `Services:Admin` routing gateway, নয়তো এই cleanup production-এ আসলে চলেই না।

### F5.14 Checked-ticket sync (Redis → database)

> **Bangla name:** চেক করা টিকিট সিঙ্ক (Redis → ডেটাবেস)

**1. Name and purpose.** Redis-এ জমা gate scan (F4.5) `CheckedTickets` টেবিলে লেখা — admin report-এর (F1.19) data।

**2. Trigger and actor.** Admin timer worker `CheckedTicketService` — প্রতি **৩০ মিনিটে** (RedLock `checked_ticket`, ২০ মিনিট)।

**3–4. Business/technical flow.**

| # | ধাপ | কী ঘটে |
|---|---|---|
| 1 | Flag | Redis bool `ticketCheckerDbSync = true` সেট করে — drain চলাকালে checker-এর `sync-tickets` refuse করে (F4.5) |
| 2 | Drain | প্রতিটি (event, gate, checker)-এর জন্য: STRING `ticket_checker_checked_tickets:{eventLongId}_{gateId}_{userId}` পড়ে (serialized `ConcurrentDictionary<string, TicketInfo { value, isManual, entryTime }>`) |
| 3 | লেখা | `CheckedTicket { eventLongId, eventId, ticketCheckerGateId, gateName, checkerId, checkerName, ticketNumber, entryCount, isManualEntry, entryTime }` row-তে রূপান্তর করে bulk insert |
| 4 | পরিষ্কার | drain হওয়া Redis key মুছে; `ticketCheckerDbSync = false` |

**5–7. Components / data.** Admin service; Redis; `CheckedTickets` টেবিল।

**8. Code references.** `…/Admin.Service/Workers/{BackgroundServices/CheckedTicketService.cs,TaskManagers/CheckedTicketServiceTaskManager.cs}`।

**9. Handover notes.** Drain window-এ (কয়েক সেকেন্ড–মিনিট) gate device sync error পেয়ে retry করে — স্বাভাবিক, কিন্তু ম্যাচডেতে জেনে রাখা ভালো।

### F5.15 Gate download-status cleanup

> **Bangla name:** গেট ডাউনলোড-স্ট্যাটাস ক্লিনআপ

**1. Name and purpose.** Event শেষ হলে checker-দের offline-download অনুমতি স্বয়ংক্রিয়ভাবে বন্ধ (`IsDownloadEnable`-এর data hygiene)।

**2. Trigger and actor.** Admin timer worker `GateCheckerDownloadStatusCleanupService` — প্রতি **১৫ মিনিটে** (কোডের মন্তব্য "2 mins" বলে; কোড বলে ১৫) — RedLock `ticket_checker_status_reset` (৫ মিনিট)।

**3–4. Business/technical flow.** `DisableDownloadAccessForPastEventsAsync()`: `EndDateTime < UtcNow − ৩০ মিনিট` এমন event খুঁজে তাদের `TicketCheckerGateUsers`-এ `IsDownloadEnable = false` লেখে।

**5–8. Components / data / code.** Admin service; `TicketCheckerGateUsers` হালনাগাদ। `…/Workers/BackgroundServices/GateCheckerDownloadStatusCleanupService.cs`, `…/Managers/TicketCheckerGateManager.cs`।

**9. Handover notes.** মন্তব্য/কোডের schedule-মিল নেই — কোডেই বিশ্বাস করুন (১৫ মিনিট)।

### F5.16 Promo-code status update

> **Bangla name:** প্রোমো-কোড স্ট্যাটাস আপডেট

**1. Name and purpose.** তারিখ ও ব্যবহারের সীমা অনুযায়ী promo code স্বয়ংক্রিয় activate/expire/limit-এ-পৌঁছানো — মানুষের ছোঁয়া ছাড়াই।

**2. Trigger and actor.** Admin timer worker `PromoCodeStatusUpdateService` — প্রতি **২ মিনিটে** (RedLock `promo_code_status_updater`, ২ মিনিট)।

**3–4. Business/technical flow.** `PromoCodeManager.UpdatePromoCodeStatusesAsync`: প্রতিটি code-এর status `StartDateTime/EndDateTime/TotalUsageLimit` থেকে পুনঃগণনা — `Active(1)`, `Expired(2)`, `Upcoming(3)`, `LimitReached(4)` — বদলালে `Status`, `IsActive = (status == Active)`, `IsPublished = (status == Active)`, `UpdatedAt` সেট করে bulk update।

**5–8. Components / data / code.** Admin service; `PromoCodes` হালনাগাদ। `…/Workers/BackgroundServices/PromoCodeStatusUpdateService.cs`, `…/Managers/PromoCodeManager.cs`।

**9. Handover notes.** `IsPublished`-ও ওল্টায় বলে expire হওয়া code public picker থেকে নিজেই সরে যায়।

### F5.17 System-discount status update

> **Bangla name:** সিস্টেম-ডিসকাউন্ট স্ট্যাটাস আপডেট

**1. Name and purpose.** F5.16-এর মতোই system discount-এর (early-bird window ইত্যাদি) স্বয়ংক্রিয় status যন্ত্র।

**2. Trigger and actor.** Admin timer worker `SystemDiscountStatusUpdateService` — প্রতি **২ মিনিটে** (RedLock `system_discount_status_updater`, ২ মিনিট)।

**3–4. Business/technical flow.** `DiscountManager.UpdateSystemDiscountStatusesAsync`: `StartDateTime/EndDateTime` থেকে status `Active/Expired/Upcoming/LimitReached`; একই `IsActive/IsPublished/UpdatedAt` লেখা।

**5–8. Components / data / code.** Admin service; `Discounts` হালনাগাদ। `…/Workers/BackgroundServices/SystemDiscountStatusUpdateService.cs`, `…/Managers/DiscountManager.cs`।

**9. Handover notes.** Active window-ই public discount endpoint (F1.16) দেয়; ওই cache-এর TTL ও এই worker-এর ২-মিনিট cycle-র কারণে discount expire হতে ~২ মিনিট দেরি হতে পারে।

## 6. Cross-cutting (authentication, authorization, platform service)

অনেক feature-এর সাথে সম্পর্কিত বিষয়: প্রতিটি client-এর sign-in, authorization-এর চার স্তর, service-to-service call, storage, messaging, logging, cache ও configuration। Cognito pool: **Admin, User, TicketChecker, Agent** — পঞ্চম `service` scheme (shared-key JWT) আছে কিন্তু অব্যবহৃত (F6.19 note)।

### F6.1 Admin login (ফোন OTP + পাসওয়ার্ড)

> **Bangla name:** অ্যাডমিন লগইন (ফোন OTP + পাসওয়ার্ড)

**1. Name and purpose.** তিন-ধাপে staff sign-in: ১০-অঙ্কের ফোন → ৬-অঙ্কের SMS code → Cognito password। সফল হলে browser Admin-pool token পায় যা প্রতিটি admin API call বহন করে; তিনটি role CloudFront download cookie-ও পায়।

**2. Trigger and actor.** Admin portal `/auth/login` (`LoginComponent`)। Actor: staff (role `admin`, `event_manager`, `ticket_manager`, `ticket_operator`, `customer_support`)।

**3. Business flow.**
1. Staff `+880` ছাড়া ফোন লেখেন।
2. Portal Serverless API-কে SMS code পাঠাতে বলে (অজানা নম্বরে "User not found.")।
3. Staff code লেখেন (২ মিনিট পরে resend)।
4. বৈধ code-এর পরে password field আসে; portal `+880<phone>` + password দিয়ে Cognito-তে sign-in করে।
5. Portal `custom:role` পড়ে role-এর default page-এ নামে (`/program-management` — admin/event_manager(+ticket_manager); বাকিরা `/home`)।
6. `admin`, `ticket_manager`, `ticket_operator` role-দের জন্য CloudFront signed cookie-ও আনে (F1.12-এর download)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Serverless `POST {serverless.baseUrl}/admin/login-2fa-send-otp` | **[HTTP, static key]** | `{ otp_type: "sms", destination: "+880…" }`; সফলতা `status_message == "otp_generated_and_enqueued_successfully"` |
| 2 | Portal → Serverless `POST …/admin/login-2fa-verify-otp` | **[HTTP, static key]** | `otp` যোগ; সফলতা `sms_otp_verified_successfully`, নয়তো `invalid_otp` |
| 3 | Portal → Cognito | Amplify `Auth.signIn(phone, password)` | Token বা challenge: `NEW_PASSWORD_REQUIRED` (portal একই password দিয়ে `completeNewPassword`), `SMS_MFA` (ফেরত আসে, handle হয় না — note) |
| 4 | Portal → Cognito | `currentSession()/currentUserInfo()` | Access token ৫৫ মিনিট cache; `custom:role` ৫৫ মিনিট cache |
| 5 | Portal → Ticketing `GET /ticketing/api/v1/booking-order-ticket/signed-cookie` | **[HTTP + user token]** | Role admin/ticket_manager/ticket_operator; response string থেকে তিনটি `CloudFront-*` cookie `document.cookie` দিয়ে (domain = `environment.cloudFront.mainDomain`) |

ধাপ ১–৪-এ কোনো GoBCB service জড়িত নয়; service-রা user-কে দেখে পরের API call-এ (F6.14)।

**5. Components.** Portal (`LoginComponent`, `CognitoService`, `EventService.setSignedCookie()`); Serverless API (external, source repo-তে নেই `[UNCONFIRMED]`); Cognito Admin pool; Ticketing (cookie); browser storage (Amplify token, `sessionStorage.lastKnownUserRole`, `localStorage.globalProgramId`, cookie)।

**6. API contracts.**

```json
// POST {serverless}/admin/login-2fa-send-otp          // static Authorization header
{ "otp_type": "sms", "destination": "+8801700000001" }
// 200 → { "status_message": "otp_generated_and_enqueued_successfully" }

// POST {serverless}/admin/login-2fa-verify-otp
{ "otp_type": "sms", "destination": "+8801700000001", "otp": "123456" }
// 200 → { "status_message": "sms_otp_verified_successfully" }   // ভুল → "invalid_otp"
```

Cognito call (Amplify, public client): `InitiateAuth`/`RespondToAuthChallenge` — error `NotAuthorizedException`, `UserNotFoundException`… `getCognitoErrorMessage`-এ টেক্সট ম্যাপ হয়। `signed-cookie` auth: policy `admin`, নয়তো 401।

**7. Data and side effects.** লগইনে GoBCB backend কিছু লেখে না; Serverless API SMS পাঠায়; browser-এ token/role/cookie।

**8. Code references.** `rvl-gobcb-admin-portal/src/app/modules/auth/login/login.component.ts:124-249`; `…/core/services/cognito.service.ts:213-246` (sign-in), `:261-302` (cache), `:444-472` (OTP call); `…/core/config/aws-exports.ts`; signed cookie `…/features/events/services/event.service.ts:234`; skip list `…/core/interceptors/auth.interceptor.ts:19-29`, `…/interceptors/program-id.interceptor.ts:15`।

**9. Handover notes.** ① **SMS code শুধু browser যাচাই করে** — OTP ফলাফল Cognito বা service-এ পৌঁছায় না; staff password জানলে কেউ Cognito সরাসরি ডেকে ঢুকতে পারে। Admin pool নিজে MFA enforce করে কিনা repo-তে দেখা যায় না `[UNCONFIRMED]`। ② Serverless static key browser bundle-এ (সবাই পড়তে পারে)। ③ `SMS_MFA` pseudo-সফল হয়ে পরে role আনতে ব্যর্থ হয় — `confirmMFA()` helper আছে, কোনো screen ডাকে না। ④ Signed-cookie role exact-string match — দুই-role ব্যবহারকারী (`event_manager,ticket_manager`) লগইনে cookie পান না (top bar-এ refresh action)। ⑤ Local: OTP stub যেকোনো ফোনে code `123456` (`scripts/Setup-AdminPortal.ps1` proxy); test user `floci/seed-users.ps1`-এ, password `docs/local-dev.md`-এ।

### F6.2 Admin forgot password

> **Bangla name:** অ্যাডমিন পাসওয়ার্ড ভুলে যাওয়া

**1. Name and purpose.** ফোনের নিয়ন্ত্রণ SMS code দিয়ে প্রমাণ করে নতুন admin password সেট করা; Admin service তা Cognito-তে লেখে, সব session বাতিল করে ও নতুন password SMS করে।

**2. Trigger and actor.** Admin portal `/auth/forgot-password`। Actor: staff, anonymous।

**3. Business flow.** ফোন → SMS code (F6.1-এর মতো Serverless call; verify `user_id` ফেরায়) → নতুন password (নীতি: ≥৮ অক্ষর, বড়/ছোট/সংখ্যা/চিহ্ন) → `set-forget-password` → session বাতিল, নতুন password SMS, লগইনে ফেরা। Screen-এর "Resend" বরং Cognito-র email flow চালু করে যার code এই screen জমা দেয় না (অসঙ্গতিপূর্ণ)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1–2 | Serverless send/verify OTP | **[HTTP, static key]** | F6.1-এর মতো; portal `response.user_id` রাখে |
| 3 | Portal → Admin `POST /admin/api/v1/admin-users/set-forget-password` | **[HTTP, no token]** (`[AllowAnonymous]`) | `{ userId, password }` |
| 4 | Admin → Cognito | AWS SDK | `AdminGetUser` (ফোন পড়ে), `AdminUserGlobalSignOut`, `AdminSetUserPassword(Permanent=true)` |
| 5 | Admin → Notification API `POST {Notification:Endpoint}/notification/send-message` | **[HTTP, static key]** | SMS "Your password has been changed successfully. New Password is …" (স্পষ্ট টেক্সটে) |
| 6 | Activity log | — | `AdminUser / PasswordResetCompleted` |

UI-বিহীন কিন্তু পৌঁছানো-যায়: `GET /admin/api/v1/admin-users/forget-password?phoneNo=` → Cognito `AdminResetUserPassword` (`RESET_REQUIRED` করে), `true/false` ফেরায়।

**5. Components.** Portal (`ForgotPasswordComponent`, `CognitoService.submitPassword()`); Admin service (`AdminUsersController` → `AdminUserManager` → `AdminUserProvider`); Cognito; Notification API (external); activity log।

**6. API contracts.** `set-forget-password`: `200` + literal body `200`; 400 envelope-এ `ArgumentException` হয়ে Cognito-র নীতি-বার্তা। Sample:

```json
// POST /admin/api/v1/admin-users/set-forget-password
{ "userId": "3f6c2a8e-0000-4000-8000-000000000001", "password": "N3w!Passw0rd" }
// 400 → { "status": 400, "title": "Password did not conform with policy: …" }
```

**7. Data and side effects.** Cognito password প্রতিস্থাপন + সব session বাতিল; স্পষ্ট টেক্সট SMS; activity-log row।

**8. Code references.** `…/modules/auth/forgot-password/forgot-password.component.ts:123-263`; `…/core/services/cognito.service.ts:432-434`; `…/Admin.Service/Api/AdminUsersController.cs:28-39,185-196`; `…/Admin.Domain/Managers/AdminUserManager.cs:197-231`; `…/Admin.Integration/Services/AdminUserProvider.cs:508-586`।

**9. Handover notes.** ① **Backend OTP যাচাই করে না**: `set-forget-password` anonymous এবং body-র `userId`-তে (Cognito `sub` বা ফোন-username) বিশ্বাস করে — API Gateway route না আটকালে service-এ পৌঁছানো যে কেউ যেকোনো admin-এর password রিসেট করতে পারে `[UNCONFIRMED]` (Open queries)। ② Password SMS-এ স্পষ্ট টেক্সটে যায় (provisioning-ও একই, F6.5)। ③ অব্যবহৃত-কিন্তু-খোলা `GET forget-password` শুধু ফোন দিয়ে যেকোনো account-কে `RESET_REQUIRED` করতে পারে — মুছে ফেলার প্রার্থী।

### F6.3 Admin change password ও logout

> **Bangla name:** অ্যাডমিন পাসওয়ার্ড পরিবর্তন ও লগআউট

**1. Name and purpose.** Sign-in করা admin নিজের password বদলান (তারপর sign out); logout browser session শেষ করে ও program নির্বাচন ও cookie মুছে। দুটোই browser↔Cognito-তে সীমিত।

**2. Trigger and actor.** Admin portal top bar-এর profile menu (`/change-password`, logout)। Actor: যে কোনো sign-in করা staff।

**3. Business flow.** Change: পুরোনো + নতুন password ×২ (≥৮ অক্ষর, ভিন্ন হতে হবে) → সফল বার্তা → এক সেকেন্ডে auto sign-out ও লগইন; ভুল পুরোনো password-এ "Current password is wrong."। Logout: নিশ্চিত → sign out, program id 0, `CloudFront-*` cookie মেয়াদোত্তীর্ণ, লগইন page।

**4. Technical flow.** Change: Amplify `Auth.changePassword(user, old, new)` (Cognito `ChangePassword`)। Logout: `Auth.signOut()` (শুধু local), `ProgramService.setProgramId(0)`, `clearSignedCookie()`।

**5–6. Components / contracts.** Portal component + Cognito — **কোনো GoBCB endpoint নেই**। (Server-side `AdminUserManager.ChangePasswordAsync` আছে controller ছাড়া; portal-এর `ChangePasswordService` অস্তিত্বহীন `PUT /admin/api/v1/Users/change-password` ডাকে ও অব্যবহৃত — দুটোই dead code।)

**7. Data and side effects.** Cognito password বদল; logout-এ browser storage/cookie মুছে।

**8. Code references.** `…/modules/auth/change-password/change-password.component.ts:50-85`; `…/core/services/cognito.service.ts:303-352`; `…/layout/app.topbar.component.ts:80-120`; dead: `…/Admin.Domain/Managers/AdminUserManager.cs:181-195`, `…/change-password/change-password.service.ts:20-22`।

**9. Handover notes.** ① Sign-out **local** (`{global:true}` নয়) — অন্য session তাদের refresh token শেষ না হওয়া পর্যন্ত বেঁচে; global বাতিল হয় কেবল disable/password reset-এ (F6.5)। ② Cookie পরিষ্কারকরণ `domain` attribute ছাড়া করে, তাই browser আসল CloudFront cookie মেয়াদ শেষ পর্যন্ত রাখতে পারে — deployed environment-এ যাচাই করুন।

### F6.4 Admin session (টোকেন সংযুক্তি ও রিফ্রেশ)

> **Bangla name:** অ্যাডমিন সেশন (টোকেন সংযুক্তি ও রিফ্রেশ)

**1. Name and purpose.** Admin portal-এর প্রতিটি API call কীভাবে `Authorization` ও `X-Program-Id` header পায়, token মেয়াদের আগে কীভাবে refresh হয়, আর কখন হাল ছেড়ে লগইনে ফেরে।

**2. Trigger and actor.** Portal-এর প্রতিটি HTTP call; সুস্থ থাকলে user কিছু দেখেন না।

**3. Business flow.** Cognito refresh token বৈধ থাকা পর্যন্ত session reload ও idle টিকে থাকে; refresh ব্যর্থ হলে (মেয়াদ/বাতিল) পরের call sign-out + লগইন page ঘটায়।

**4. Technical flow.**

| # | ধাপ | কী ঘটে |
|---|---|---|
| 1 | Skip list | `/admin-users/forget-password`, `admin/login-2fa-*`, `/admin-users/set-forget-password`-এ token যায় না |
| 2 | Token | `CognitoService.getAccessToken()`: ৫৫ মিনিট cache, `exp`-এর ২ মিনিট আগে proactive refresh |
| 3 | সংযুক্তি | `Authorization: Bearer …` (AuthInterceptor) |
| 4 | Program | `/admin/login-2fa*` ছাড়া প্রতিটি request-এ `X-Program-Id: <globalProgramId>` (0 = global) |
| 5 | 401-এ | Single-flight refresh (`isRefreshing` + `BehaviorSubject`): `Auth.currentSession()`, ব্যর্থ request নতুন token-এ একবার retry; মাঝের request অপেক্ষা করে |
| 6 | Refresh ব্যর্থ | cache + `lastKnownUserRole` মুছে, `Auth.signOut()`, `/auth/login`-এ navigate |

Interceptor ক্রম (app.module.ts): `AuthInterceptor`, `LoaderInterceptor`, `ProgramIdInterceptor`।

**5–6. Components / contracts.** Portal interceptor + `CognitoService`; header ভোক্তা F6.14 (`Authorization`) ও F6.16 (`X-Program-Id` — শুধু Admin service; বাকিরা উপেক্ষা করে)।

**7. Data and side effects.** শুধু browser cache (token ৫৫ মিনিট, user info ৫৫ মিনিট)।

**8. Code references.** `…/core/interceptors/auth.interceptor.ts:14-102`; `…/interceptors/program-id.interceptor.ts:14-29`; `…/core/services/cognito.service.ts:88-211,261-302`; `…/app.module.ts:22-33`।

**9. Handover notes.** ① দুটি স্বাধীন refresh guard (interceptor + service) — একসাথে বদলান। ② SignalR chat connection interceptor-এর বাইরে (token query string-এ, F1.24)। ③ **Idle timeout নেই** — session-এর দৈর্ঘ্য Cognito-র refresh-token আয়ু (pool setting, repo-তে নেই)। ④ Role বদল দেখতে ৫৫ মিনিট পর্যন্ত লাগতে পারে (role cache; backend-এর নিজস্ব claim cache — F6.15)।

### F6.5 Staff account provisioning (shared mechanics)

> **Bangla name:** স্টাফ অ্যাকাউন্ট তৈরি (shared mechanics)

**1. Name and purpose.** Staff নিজেরা sign up করেন না: administrator প্রতিটি admin/checker/agent account বানান; Admin service সংশ্লিষ্ট Cognito pool-এ ব্যবহারকারী বানায় generated **permanent** password-সহ এবং username+password ফোনে SMS করে। Screen: F1.25, F1.17, F1.26; এই feature-এ shared Cognito mechanics।

**2. Trigger and actor.** Admin portal-এর user screen (global menu)। Role: admin account-এ `admin`; checker account-এ চারটি staff role; **agent account: server-side কোনো বাধা নেই** (F6.18)।

**3. Business flow.** তৈরি (নাম, ফোন, email, role(s), program) → credential-সহ SMS → পরে edit / disable / enable / delete / set-password (নতুন generated password SMS-এ)। Disable, enable ও set-password user-কে সর্বত্র sign out করায়।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Portal → Admin `POST /admin/api/v1/admin-users` (বা `/ticket-checker`, `/agent-users`) | **[HTTP + user token]** (agent-এ token enforce হয় না) | Body F1.25/F1.17/F1.26-এ |
| 2 | Admin → Cognito | AWS SDK (static IAM key) | Admin: `ListUsers(email)` duplicate যাচাই → `AdminCreateUser(Username=phone)` temp password → `AdminSetUserPassword(Permanent=true)`। Attribute: `phone_number, name, email, custom:role (কমা-সহ), custom:program_ids, *_verified=true`। Checker: email `<phone>@gobcbticket.com`, `custom:role="TicketChecker"`। Agent: `custom:branch_location/company_name/company_branch` |
| 3 | Admin → Notification API `POST {Notification:Endpoint}/notification/send-message` | **[HTTP, static key]** | SMS "Your account has been created successfully. Your user name is <phone> and password is <password>" |
| 4 | অন্যান্য | — | Update: `AdminUpdateUserAttributes` + cached `user_{id}` মুছে; Disable/Enable: `AdminDisable/EnableUser` + `AdminUserGlobalSignOut` (নিজের account নিয়ে 400 "Invalid permission"); Set password: global sign-out + নতুন generated password + SMS; Delete: `AdminDeleteUser` |

Generated password: ৮ অক্ষর, বড়/ছোট/সংখ্যা/`!@#$`, `System.Random` দিয়ে (`AdminUserProvider.GeneratePassword`)।

**5. Components.** Portal user service; Admin service (`AdminUserProvider`, `TicketCheckerUserProvider`, `AgentUserProvider`); Cognito pool ×৩; Notification API; Redis `user_{id}` attribute cache; activity log (admin account)।

**6. API contracts.** Endpoint টেবিল F1.25/F1.17/F1.26-এ। Create response (`AdminUserResponse`) sample F1.25-এ।

**7. Data and side effects.** Cognito user; SMS; global sign-out; activity-log row (`Created/Updated/Deleted/Disabled/Enabled/PasswordReset`); cache invalidation।

**8. Code references.** `…/Admin.Integration/Services/{AdminUserProvider,TicketCheckerUserProvider,AgentUserProvider}.cs` (password generator `AdminUserProvider.cs:588-608`); `…/Admin.Domain/Managers/AdminUserManager.cs:39-179`; Cognito client `…/Admin.Service/Configurations/DependencyConfig.cs:197-207`।

**9. Handover notes.** ① Agent endpoint কোডে anonymous (F6.18)। ② Password `System.Random`-এ তৈরি ও স্পষ্ট SMS-এ, permanent সেট (প্রথম লগইনে বদলানোর বাধ্যবাধকতা নেই)। ③ Email uniqueness শুধু admin-এ; ফোন username, pool-প্রতি একবার। ④ Role/program বদল ধীরে ছড়ায় (Admin cache সাথে সাথে, UserIssue-এর নিজস্ব copy, portal-এ ৫৫ মিনিট, ইস্যু হওয়া token মেয়াদ পর্যন্ত)। ⑤ SMS ব্যর্থ হলে Cognito account তৈরি হয়েও API 400 ফেরায় (অর্ধসম্পন্ন)।

### F6.6 গ্রাহক registration

> **Bangla name:** গ্রাহক নিবন্ধন

**1. Name and purpose.** নতুন customer GoBCB account বানান (User Cognito pool) — email **ও** ফোন one-time code দিয়ে প্রমাণের পরে, সবই external **identity API** দিয়ে; অথবা OneID দিয়ে (প্রথম OneID লগইনে account তৈরি, F6.8)।

**2. Trigger and actor.** Portal `/:lang/auth/register` → verify-email → verify-phone → set-password; app `/signup → /confirmationCode → /phoneNumberOtp → /setPassword`। Actor: anonymous visitor।

**3. Business flow.** ১) নাম, email, ১০-অঙ্কের ফোন (+ শর্ত) → ২) email code → ৩) SMS code → ৪) password নির্বাচন → account তৈরি, লগইনে যান। OneID বিকল্প: "Register with OneID" popup-এ OneID-র page (`environment.aws.oneIdRegisterUrl`) খোলে।

**4. Technical flow.** সব call identity API-তে static key header নিয়ে (`environment.headerkey` / `AUTH_API_TOKEN`); **কোনো GoBCB service জড়িত নয়**:

| # | Call | Body (client যেমন পাঠায়) |
|---|---|---|
| 1 | `POST user/register-cached` | portal `{ name, email (ছোট হাতে), phone, dob: "1900-01-01", address: "n/a", verification_type: "mobile", verification_id: "0123456789" }` (placeholder!); app `{ name, email, phone, address, verification_type, verification_id, dob }` |
| 2/4 | `POST otp/send-otp` | `{ type: "email"|"sms", destination }` |
| 3/5 | `POST otp/verify-otp` | `{ type, destination, otp }` — ফোন ধাপ `user_id` ফেরায়, provisional id হিসেবে থাকে |
| 6 | `POST user/register` | portal `{ user_id, password }`; app `{ user_id, ekyc, address, password }` |
| 7 | identity API → Cognito User pool | user তৈরি — repo-র বাইরে `[UNCONFIRMED]` |

Client-চেনা error: `user_already_exists`, `passport_or_nid_required`, `user_not_found`, `user_data_incomplete`, `error_getting_verification_information`, `error_creating_user`, `error_saving_data_to_db`, `server_error`।

**5. Components.** Portal registration component + NgRx `IdentityEffects`; app auth feature + `AuthApiServiceImpl`; identity API (external); OneID registration page; Cognito User pool।

**6. API contracts.**

```json
// POST {identity}/user/register-cached   (portal)
{ "name": "Rahim Uddin", "phone": "+8801711111111", "email": "rahim@example.com",
  "dob": "1900-01-01", "address": "n/a", "verification_type": "mobile", "verification_id": "0123456789" }

// POST {identity}/otp/verify-otp   (ফোন ধাপ)   →   200
{ "user_id": "<identity API-র দেওয়া id>" }
```

**7. Data and side effects.** সব identity API-তে (provisional data, OTP, Cognito user) — দেখা যায় না `[UNCONFIRMED]`; portal `localStorage`-এ `rvl_init_register`, `rvl_init_id`, resend timestamp (সফলে মুছে)। GoBCB টেবিলে কিছু নয়।

**8. Code references.** Portal: `…/featured/auth/components/user-registration/user-registration.component.ts:172-266`, `…/core/modules/identity/store/identity.effects.ts:38-212`, `…/core/services/api/identity-api.service.ts:30-64`। App: `data/lib/remote/api_service/auth_api_service/auth_api_service_impl.dart:34-240`, client `auth_api_client.dart`।

**9. Handover notes.** ① Identity API **black box** — repository/hosting/mালিক BS23-এর কাছে নিন (Open queries)। ② Static key দুই client-এই যায় (app শুরুতে log-ও করে `lib/main/main.dart:55`)। ③ Portal placeholder তথ্য পাঠায়, app আসল মান + `ekyc` — অসঙ্গত; identity API আসল NID/passport চায় কিনা `[UNCONFIRMED]`। ④ App-এর `register` অজানা error গিলে ফেলে সফল ভেবে চলতে থাকে। ⑤ OTP response-এর `user_id`-তে client বিশ্বাস করে — server-side binding দেখা যায় না।

### F6.7 ফোন ও পাসওয়ার্ড দিয়ে গ্রাহক লগইন

> **Bangla name:** ফোন ও পাসওয়ার্ড দিয়ে গ্রাহক লগইন

**1. Name and purpose.** Portal/app-এ নিবন্ধিত customer-এর sign-in — সরাসরি User Cognito pool-এর সাথে, তারপর identity API থেকে profile লোড।

**2. Trigger and actor.** Portal `/:lang/auth/login`; app `/login`। Actor: customer।

**3. Business flow.** ফোন (১০ অঙ্ক) + password → token → profile লোড → যেখান থেকে এসেছেন সেখানে ফেরা (portal `sessionStorage.returnUrl`) বা Home; ব্যর্থতায় Cognito-র বার্তা (app-এ "Incorrect phone number or password")। Profile না পাওয়া password-user (`user_not_found`) আবার sign out হন (portal)।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Client → Cognito (User pool) | Amplify SRP `signIn("+880…", password)` | Amplify token রাখে; challenge: `NEW_PASSWORD_REQUIRED` (portal একই password-এ সম্পূর্ণ), `SMS_MFA` (**দুই client-এই ভাঙা** — note) |
| 2 | Client → identity `GET user/my-profile` | **[HTTP + user token]** (portal: token interceptor static header-এর বদলে `Bearer`; app: `ProfileApiClient`, `?user_id=<sub>`) | Profile → NgRx store / app cache |
| 3 | `user_not_found` | — | Portal: sign out (password user) / register (SSO user, F6.8)। App: **যেকোনো** profile error-এ → `POST user/register-sso` তারপর retry |
| 4 | Analytics | — | Firebase `logLogin(user_id)` |

App sign-in-এর আগে থাকা session সরাসরি sign out করে।

**5–6. Components / contracts.** Cognito `InitiateAuth` (public client); `GET {identity}/user/my-profile` (Bearer) → `UserProfile` (shape F2.11-এ); error `NotAuthorizedException` ইত্যাদি।

**7. Data and side effects.** Client token storage; portal flag `rvl_cognito_auth = true`; analytics event। GoBCB টেবিলে লেখা নেই।

**8. Code references.** Portal `…/user-login/user-login.component.ts:182-224`, `…/shared/services/cognito.service.ts:49-72`, `…/identity/store/identity.effects.ts:291-343`। App `lib/presentation/feature/auth/login/login_view_model.dart`, `data/lib/repository/auth_repository_impl.dart:26-62`, `data/lib/service/aws_amplify_service.dart:38-66`, `data/lib/repository/profile_repository_impl.dart:55-86`।

**9. Handover notes.** ① User-pool MFA চালু করলে দুই client-ই ভাঙে (portal MFA state-এ আটকায়; app ভুল password বলে) — MFA config repo-তে নেই `[UNCONFIRMED]`। ② App-এর register-sso fallback শুধু `user_not_found` নয়, **যেকোনো** error-এ চলে। ③ Local: portal Floci-তে চলে; app-এর Amplify local-এ আসল AWS-কে ডাকে (known gap, `docs/mobile-local.md`); তৈরি user `+8801700000011` / `Passw0rd!23`।

### F6.8 OneID single sign-on

> **Bangla name:** OneID সিঙ্গেল সাইন-অন

**1. Name and purpose.** Password ছাড়া OneID Wallet দিয়ে sign-in: OneID **User** pool-এ `oneid` নামে external identity provider; client Cognito-র hosted sign-in খোলে ও সাধারণ User-pool token পায়। প্রথম OneID লগইনে GoBCB profile স্বয়ংক্রিয় তৈরি হয়।

**2. Trigger and actor.** Portal লগইনের "Login with OneID Wallet" (popup); app-এর OneID বোতাম। Actor: OneID account-ধারী customer।

**3. Business flow.** OneID চাপেন → popup/browser-এ OneID-র page (সবসময় credential চায় — portal-এ `prompt=login`) → অনুমোদন → sign-in; profile না থাকলে তৈরি; আগের page/Home-এ পড়েন।

**4. Technical flow.**

**Portal (popup-এ ম্যানুয়াল PKCE):**

| # | ধাপ | কী ঘটে |
|---|---|---|
| 1 | Popup | মূল window `/:lang/auth/login?sso_init=oneid`-কে 500×700 popup (`OneID Login` নামে) খোলে; `sso_login = true` |
| 2 | PKCE | Popup ৩২-বাইট verifier বানায় (`localStorage.pkce_key`) + S256 challenge |
| 3 | Redirect | `https://<oauth.domain>/oauth2/authorize?identity_provider=oneid&redirect_uri={redirectSignIn}&response_type=code&client_id=…&scope=…&prompt=login&code_challenge=…&code_challenge_method=S256` → OneID |
| 4 | Callback | popup-এ `redirectSignIn?code=…` |
| 5 | Token exchange | `fetch`-এ `POST https://<oauth.domain>/oauth2/token` form-encoded (`grant_type=authorization_code`, `code_verifier`) |
| 6 | সংরক্ষণ | Popup Amplify-format `localStorage` key লেখে (`CognitoIdentityServiceProvider.<clientId>.<username>.*`, `amplify-signin-with-hostedUI`), flag `sso_auth_complete`, `postMessage`, বন্ধ হয় |
| 7 | মূল window | ৩০০ ms পোল; `Auth.currentAuthenticatedUser({bypassCache:true})` |
| 8 | Profile | `GET user/my-profile` **[HTTP + user token]**; `user_not_found` + `sso_login` হলে → `POST user/register-sso` (body = পুরো Amplify user object!) → আবার |

**App (Amplify hosted UI):** `Amplify.Auth.signInWithWebUI(provider: AuthProvider.custom('oneid'), isPreferPrivateSession: true)` → system browser; profile `?user_id=<sub>`-সহ; **যেকোনো** error-এ → `POST user/register-sso` `{"name":"","cognito_sub":<sub>}` → retry।

**5. Components.** Portal popup/PKCE কোড; app `loginWithOneID`; Cognito hosted UI (User pool, provider `oneid`); OneID Wallet (external — IdP config repo-তে নেই, architecture doc Q5); identity API।

**6. API contracts.**

```http
POST https://<oauth.domain>/oauth2/token
Content-Type: application/x-www-form-urlencoded
grant_type=authorization_code&client_id=<userPoolWebClientId>&code=<code>&redirect_uri=<redirectSignIn>&code_verifier=<verifier>
```

`register-sso` (app): `{ "name": "", "cognito_sub": "8c1d2f7e-0000-4000-8000-000000000011" }`; portal কাঁচা Amplify user object পাঠায় (নির্দিষ্ট DTO নয়)।

**7. Data and side effects.** Cognito federated user (provider-এর স্বাভাবিক আচরণ; mapping repo-তে নেই); identity-API profile; portal `localStorage` key (`pkce_key` exchange-এর পরে মুছে, `was_sso_login`, `sso_auth_complete/error`)।

**8. Code references.** Portal `…/user-login/user-login.component.ts:46-73,226-419`, `…/shared/services/cognito.service.ts:23-45,302-372`, `…/identity/store/identity.effects.ts:303-320,374-427`, `…/core/config/awsConfig.ts`। App `data/lib/service/aws_amplify_service.dart:68-98`, `data/lib/repository/profile_repository_impl.dart:55-86`।

**9. Handover notes.** ① **Logout OneID session শেষ করে না** — portal শুধু Cognito থেকে local sign-out (`skipFederatedLogout`); `federatedSignOut()` আছে, কেউ ডাকে না; পুনরায় লগইনের নিরাপত্তা `prompt=login`-এর উপর। ② Portal-এর `register-sso` body স্থিতিশীল DTO নয় (DevTools-এ দেখে নিন)। ③ App-এ `loginWithOneID`-এর error গিলে ফেলা — সফল কিনা নির্বিশেষে Home-এ যায়। ④ Local: `/p/oneid`-তে **fake OneID** auto-approve করে Floci token দেয় (`docs/user-portal-local.md`); app flow local সম্ভব নয়।

### F6.9 গ্রাহকের পাসওয়ার্ড ভুলে যাওয়া/রিসেট

> **Bangla name:** গ্রাহকের পাসওয়ার্ড ভুলে যাওয়া/রিসেট

**1. Name and purpose.** ফোন + SMS code + নতুন password — পুরোটাই external identity API; কোনো GoBCB service জড়িত নয় `[UNCONFIRMED]`।

**2. Trigger and actor.** Portal `/:lang/auth/phone-reset-password` → `reset-password-code` → `reset-password-verified`; app `/forgetPassword` → `/confirmNewPassword` → `/forgetPasswordSuccess`। Actor: sign-in-হীন customer।

**3. Business flow.** ফোন লিখুন → SMS code → code + নতুন password → সফল page → লগইন।

**4. Technical flow.** দুটি call, দুটোই **[HTTP, static key]**: `POST {identity}/otp/password-reset-request` `{ phone }`; তারপর `POST {identity}/otp/password-reset` `{ phone, otp, password }`। Portal ফোনটি ধাপের মাঝে `localStorage.rvl_reset_pass`-এ রাখে (সফলে মুছে)।

**5–7. Components / contracts / data.** Identity API (external); client screen। চেনা `status_message` error: `phone_number_not_found`, `user_not_found`, `invalid_otp`, `exceeded_maximum_otp_generation_limit`। Cognito-তে password বদল assumed (repo-র বাইরে)।

```json
// POST {identity}/otp/password-reset
{ "phone": "+8801711111111", "otp": "482913", "password": "N3w!Passw0rd" }
```

**8. Code references.** Portal `…/identity/store/identity.effects.ts:214-289`, `…/identity-api.service.ts:73-89`; app `data/lib/remote/api_service/auth_api_service/auth_api_service_impl.dart:243-292`, `lib/presentation/feature/auth/confirm_new_password/confirm_new_password_view_model.dart:110-155`।

**9. Handover notes.** ① OTP ও password একসাথে যায় — identity API জোড়া হিসেবে যাচাই করে কিনা `[UNCONFIRMED]`। ② Reset-এ অন্য session বাতিলের কিছু দেখা যায় না। ③ Portal-এর অব্যবহৃত helper `CognitoService.forgotPassword` ভুল আর্গুমেন্টে `Auth.changePassword` ডাকে (dead code)।

### F6.10 গ্রাহক session (টোকেন সংযুক্তি, পাসওয়ার্ড পরিবর্তন, লগআউট)

> **Bangla name:** গ্রাহক session (টোকেন সংযুক্তি, পাসওয়ার্ড পরিবর্তন, লগআউট)

**1. Name and purpose.** Portal/app কীভাবে User-pool token API call-এ জোড়ে, মেয়াদ শেষে কী হয়, আর password বদল ও logout। লগইন-লাগা প্রতিটি customer feature এর উপর নির্ভর করে।

**2. Trigger and actor.** প্রতিটি HTTP call (portal `TokenInterceptor`; app API client); password/logout-এর profile screen। Actor: sign-in করা customer।

**3. Business flow.** Password বদল (পুরোনো + নতুন ×২; sign-in থাকে); logout → লগইন page/screen; মেয়াদোত্তীর্ণ session → ব্যর্থ call-এর আগেই sign out।

**4. Technical flow.**

**Portal token সংযুক্তি — URL fragment-এর allow-list** (শুধু এগুলোতে `Authorization: Bearer` যায়): `…/booking` path (booking/capacity/order + `admin/api/v1/discount`), `userissue` API + chathub, `ticketing` path, identity-র `user/my-profile` + `user/register-sso`, `event/…/venue-details`। বাকি সব (public Event read) token ছাড়া যায়। ধাপ: `Auth.currentSession()` (Amplify প্রয়োজনে refresh করে) → তবুও `exp` পেরোলে: `rvl_cognito_auth`/profile মুছে, sign out, synthetic 401 → নয়তো header যোগ। সার্ভার-থেকে-আসা 401-এ **retry নেই**।

**App token সংযুক্তি:** `TicketBanglaApiClient` (`API_BASE_URL`) ও `ProfileApiClient` (`AUTH_API_BASE_URL`) প্রতি request-এ `Amplify.Auth.fetchAuthSession()` ডেকে `Bearer` জোড়ে; `AuthApiClient` static `AUTH_API_TOKEN` ব্যবহার করে।

Password বদল: portal `Auth.changePassword`, app `Amplify.Auth.updatePassword`। Logout: portal `Auth.signOut({global:false})` (SSO user `skipFederatedLogout`); app `signOut()` — FCM-token delete **comment out**।

**5–7. Components / contracts / data.** Cognito User pool; নিজস্ব GoBCB endpoint নেই। App logout-এর পরেও push token নিবন্ধিত থাকে (F3.9 note)।

**8. Code references.** Portal `…/core/interceptors/token.interceptor.ts:133-193` (উপরে পুরোনো সংস্করণ comment), `…/user-profile-pages.component.ts:299-340`, `…/layout/components/default/default.component.ts:128-142`; app `data/lib/remote/api_client/*.dart`, `data/lib/service/aws_amplify_service.dart:157-189`, `lib/presentation/feature/profile/profile_view_model.dart:343,370-382`।

**9. Handover notes.** ① Token লাগবে এমন নতুন backend path allow-list-এ **যোগ করতেই হবে**, নইলে call token ছাড়া গিয়ে 401 খাবে। ② সবখানে logout local; OneID session থেকে যায় (F6.8)। ③ App logout-এর পরেও push আসে (F3.9)।

### F6.11 অ্যাকাউন্ট মুছে ফেলা ও অ্যাপ force-update

> **Bangla name:** অ্যাকাউন্ট মুছে ফেলা ও অ্যাপ force-update

**1. Name and purpose.** Identity API-নির্ভর দুটি app নিয়ন্ত্রণ: customer profile মুছে ফেলা (শুধু user app) ও চালুর সময়ের সর্বনিম্ন-version gate (user app + checker app)।

**2. Trigger and actor.** App Profile → Delete account; splash screen। Actor: customer / gate staff।

**3. Business flow.** Delete: নিশ্চিত → profile মুছে, sign out, স্থানীয় data পরিষ্কার। Force update: প্রকাশিত সর্বনিম্ন version নতুন হলে অপসরণ-অযোগ্য "Update required" sheet store link খোলে এবং app splash পেরোয় না। Version যাচাই ব্যর্থ হলে **উপেক্ষা** হয় (app চলতে থাকে)।

**4. Technical flow.** Delete: **[HTTP + user token]** `DELETE {identity}/user/delete-my-profile` (app `ProfileApiClient`) → `signOut()`, analytics `delete_user`। (Amplify-এর `deleteUser()` আছে অব্যবহৃত — app Cognito user *মুছে না*।) Version: **[HTTP, static key]** `GET user/allowed-app-version` → dotted version তুলনা (অংশ-সংখ্যা ভিন্ন হলে update দরকার); user app `data.up.<platform>` পড়ে, checker app `data.tc.<platform>`।

**5–8. Components / contracts / code.** Identity API (external)। Response shape: sample F3.1-এ (পূর্ণ `up` + `tc`)। App: `profile_view_model.dart:385-393`, `auth_repository_impl.dart:247-252`; version `splash_view_model.dart`, `data/lib/repository/app_repository_impl.dart:88-115`, `data/lib/mapper/app_version_mapper.dart`; checker variant `rvl-gobcb-checker-app/data/lib/mapper/app_version_mapper.dart:9-11`।

**9. Handover notes.** ① Profile-এর সাথে GoBCB-পক্ষের data (order, টিকিট, issue) মুছে কিনা এই repo-গুলোতে কোথাও নেই `[UNCONFIRMED]`। ② Portal-এ `deleteUserProfile()` আছে কিন্তু কোনো screen ডাকে না — deletion শুধু app-এ। ③ `AUTH_API_BASE_URL` checker app-এর required-env তালিকায় নেই; না থাকলে version gate নীরবে বন্ধ।

### F6.12 Checker login

> **Bangla name:** চেকার লগইন

**1. Name and purpose.** Gate staff checker app-এ admin-তৈরি credential দিয়ে (F1.17/F6.5) **TicketChecker** Cognito pool-এ sign-in করেন — version gate পেরোনোর পরে।

**2. Trigger and actor.** Checker app `/splash` → `/signIn` → `/eventPage`। Actor: gate checker (role claim `ticket-checker` scheme যোগ করে, F6.14)।

**3. Business flow.** Splash version দেখে ও থাকা session খুঁজে (থাকলে সরাসরি event); নয়তো ফোন + password → event page assignment লোড করে (F4.1); event page-তেই sign-out।

**4. Technical flow.** Version **[HTTP, static key]** `GET user/allowed-app-version` (`tc` entry পড়ে); sign-in Amplify Flutter `Auth.signIn("+880…", password)` (unresolved challenge-এ session `null`); প্রথম backend call **[HTTP + user token]** `GET /admin/api/v1/ticket-checker-gate/event-info`; sign-out local।

**5–8. Components / contracts / code.** Cognito TicketChecker pool (`AMPLIFY_CONFIG`); identity API (version)। Checker app `sign_in_view_model.dart`, `data/lib/service/aws_amplify_service.dart:35-62`, client `auth_api_client.dart` / `ticket_api_client.dart`; required env `VDS_CERTIFICATE`, `AMPLIFY_CONFIG`, `API_BASE_URL` (`lib/main/main.dart:14-18`)।

**9. Handover notes.** ① Debug build **password log করে** (`Logger.debug`, শুধু `kDebugMode`) — debug log শেয়ার করবেন না। ② App-এ password বদল/reset নেই (admin করেন; backend-এর `PUT ticket-checker/change-password`-এর কোনো client নেই)। ③ Checker disable করলে session বাতিল হয় কিন্তু app পরের server call পর্যন্ত downloaded টিকিটসহ offline চলে। ④ Local: Amplify Flutter Floci-কে নির্দেশ করতে পারে না — local sign-in অসম্ভব; তৈরি checker `+8801700000021` / `Passw0rd!23`।

### F6.13 Agent pool ও offline-sold টিকিট

> **Bangla name:** এজেন্ট pool ও অফলাইনে বিক্রি টিকিট

**1. Name and purpose.** চতুর্থ Cognito pool (**Agent**) offline বিক্রেতাদের জন্য। তাদের একমাত্র API পূর্ব-ছাপা **Partner Sale** টিকিট বিক্রি হিসেবে রেকর্ড করে, ক্রেতার ফোন/ID-সহ। **পাঁচ repo-র কোনো client এই pool দিয়ে sign-in করে না বা API ডাকে না** `[UNCONFIRMED]` (Open queries)।

**2. Trigger and actor.** অজানা external client; actor: seller agent (account F1.26/F6.5, role `agent`)।

**3. Business flow.** Partner reservation-এর টিকিট তৈরি হয় (F1.11/F1.12); agent কিছু offline বিক্রি করে টিকিট নম্বর + holder পরিচয় রেকর্ড করেন; প্ল্যাটফর্ম non-partner, duplicate ও selling-stop পেরোনো টিকিট নিষেধ করে।

**4. Technical flow.**

| # | From → To | Hop | কী ঘটে |
|---|---|---|---|
| 1 | Agent client → Ticketing `POST /ticketing/api/v1/offline-sold-ticket` | **[HTTP + user token]** (Agent pool, policy `agent`) | `OfflineSoldTicketCreateRequest { ticketNumbers[], ticketHolderIdentification? }` |
| 2 | Ticketing | **[Shared table]** | `TicketType == "Partner Sale"` টিকিট লোড; নেই/duplicate হলে 400 |
| 3 | Ticketing → Event `GET /event/api/v1/events/{eventId}` | **[HTTP + user token]** (forwarded) | `TicketSellingStopDateTime` পেরোলে নিষেধ |
| 4 | Ticketing | — | `OfflineSoldTickets` row insert (`UserId` = agent sub) |

**5–6. Components / contracts.** Ticketing (`OfflineTicketSoldController` → `OfflineSoldTicketManager`), Event service, Cognito Agent pool, `Tickets` (পাঠ) / `OfflineSoldTickets` (লেখা)। সফল: `{ "message": "Offline sold tickets created successfully." }`; 400 error: "The following ticket is already sold: …", "Invalid QR || This ticket can not be sold: …", "Phone no must not exceed 20 characters.", "Ticket requests are no longer available as the ticket selling period of … has ended."

**7. Data and side effects.** শুধু `OfflineSoldTickets` row — টিকিট বা reservation নিজে **হালনাগাদ হয় না**।

**8. Code references.** `…/Ticketing.Service/Api/OfflineTicketSoldController.cs:30-41`; `…/Managers/OfflineSoldTicketManager.cs:21-132`; partner filter `…/Storage/Repositories/TicketRepository.cs:36-40`; pool scheme `Core/ETP.Core/Configuration/DefaultAuthenticationConfig.cs:173-214`।

**9. Handover notes.** ① কোনো পরিচিত client নেই; architecture doc-ও পায়নি `[UNCONFIRMED]`। ② **`OfflineSoldTickets` পিছনে কেউ পড়ে না** (report/screen নেই) — অন্য কোনো সিস্টেম খায় কিনা BS23-কে জিজ্ঞাসা করুন। ③ Agent account ব্যবস্থাপনা anonymous (F6.18)। ④ Local agent `+8801700000031` / `Passw0rd!23`।

### F6.14 Authorization স্তর ১: pool স্কিম ও পলিসি

> **Bangla name:** অথরাইজেশন স্তর ১: pool স্কিম ও পলিসি

**1. Name and purpose.** প্রতিটি service bearer token নিজেই যাচাই করে। Cognito pool-প্রতি একটি JWT authentication scheme (`user`, `admin`, `ticket-checker`, `agent`) + পঞ্চম (`service`, shared-key, অব্যবহৃত)। Endpoint `[Authorize(Policy = …)]` দিয়ে বলে কোন pool গ্রহণ করবে — নাম না থাকলে implicit-ভাবে **Admin pool** (default scheme `admin`)।

**2. Trigger and actor.** `Authorization: Bearer …`-সহ প্রতিটি request, যেসব service `AddJwtBearerAuthentication` + `UseAuthentication` করে (Platform, PushNotification, UserAuth ছাড়া — ওখানে pipeline লাইন comment)।

**3–4. Business/technical flow.**

| # | ধাপ | বিস্তারিত |
|---|---|---|
| 1 | Scheme | endpoint-এর নাম-দেওয়া scheme; default = `admin` (`DefaultAuthenticateScheme`) |
| 2 | যাচাই | Issuer `AWS:CognitoPool:<Pool>:Authority`; key `<Pool>:Metadata` (OIDC/JWKS); lifetime; **audience `client_id` claim-এ যাচাই** (Cognito access token-এ `client_id` থাকে, `aud` নয় — ID token প্রত্যাখ্যাত) |
| 3 | সমৃদ্ধকরণ | `OnTokenValidated` কাঁচা token `AppClaimTypes.AccessToken` claim-এ রাখে (token forwarding-এর জন্য, F6.19) ও pool-প্রতি নির্দিষ্ট role claim যোগ করে (`user`, `ticket-checker`, `agent`); `admin` scheme role যোগ করে না (আসে F6.15 থেকে) |
| 4 | Chat hub | `user`/`admin` scheme query string-এর `?access_token=` নেয় — শুধু `/userissue/chathub` ও `/admin/chathub` path-এ (WebSocket header পাঠাতে পারে না) |
| 5 | Policy | `AuthorizationConfig`: `admin` = admin scheme-এ authenticated; `user`/`ticket-checker`/`agent` = সেই scheme **ও** একই নামের role claim; `service` = service scheme + role |
| 6 | ব্যর্থতা | token নেই/invalid → 401 (খালি body); ভিন্ন pool → 401 (issuer অমিল) বা 403 (role নেই) |

Service-প্রতি pool গ্রহণ (attribute থেকে): Admin — role-ভিত্তিক Admin + `ticket-checker-gate`-এ TicketChecker + legacy user-issue action-এ User, অনেক endpoint খোলা (F6.18); Booking — customer order-এ `user`, admin lookup-এ `admin` (role ছাড়া); Ticketing — `user` + `admin` + `agent`; UserIssue — `user`/`admin` + authorized hub; TicketChecker — `ticket-checker`; Event/PushNotification/Scheduler/Utility/Platform — নেই।

**5–7. Components / contracts / data.** কোড `Core/ETP.Core/Configuration/{DefaultAuthenticationConfig,AuthorizationConfig}.cs`, `Core/ETP.Core/Constant/AppConstant.cs`; config `AWS:CognitoPool:{User,Admin,TicketChecker,Agent}:{PoolId,ClientId,Authority,Metadata}`, `Authentication:Jwt:*`; data লেখা নেই।

**8. Code references.** `DefaultAuthenticationConfig.cs:16-246`; `AuthorizationConfig.cs:13-38`; registration উদাহরণ `Services/Admin/ETP.Admin.Service/Program.cs:38-39,86-87,109-110`।

**9. Handover notes.** ① `Policy = admin` মানে "যে কোনো Admin-pool ব্যবহারকারী" — যেমন `customer_support` token Ticketing-এর reserved-ticket endpoint ডাকতে পারে (architecture §2.5)। ② Default scheme `admin`: শুধু `[Authorize(Roles=…)]`-এর endpoint Admin pool-এ authenticate হয়; User token পেলে 401, 403 নয়। ③ `service` scheme অব্যবহৃত (F6.19 note)। ④ API Gateway আগে থেকে token যাচাই করে কিনা unverified (architecture Q1/Q1b)। ⑤ Local-এ Floci চার pool-ই দেয়; `postman/etp-cognito-auth.postman_collection.json`-এর "04" folder সব ব্যর্থতার ধরন দেখায়।

### F6.15 Authorization স্তর ২–৩: স্টাফ রোল

> **Bangla name:** অথরাইজেশন স্তর ২–৩: স্টাফ রোল

**1. Name and purpose.** Admin-pool ব্যবহারকারীর role Cognito attribute `custom:role`-এ (কমা-সহ)। Admin ও UserIssue service প্রতি request-এ তা role claim বানায় (স্তর ২); controller `[Authorize(Roles = …)]` দিয়ে দেয়/নেয় (স্তর ৩)।

**2. Trigger and actor.** Admin বা UserIssue-তে প্রতিটি Admin-pool request। Role: `admin`, `event_manager`, `ticket_manager`, `ticket_operator` (BCB personnel), `customer_support`।

**3–4. Business/technical flow.** ① `admin` scheme token যাচাই → ② `CognitoUserAttributesMiddleware` (শুধু Admin + UserIssue): `sub` পড়ে, token-এর `scope` claim থেকে pool বাছে (`aws.cognito.signin.user.admin` → Admin pool), Redis cache `User` key `user_{sub}` দিয়ে Cognito `AdminGetUser` ডাকে (**২ মিনিটের** absolute expiry, `Core/ETP.Core/Configuration/CacheConfig.cs`), `custom:role` থেকে role claim ও `custom:program_ids` থেকে `program_id` claim যোগ করে → ③ `[Authorize(Roles="a,b")]` (class ও method দুটোই প্রযোজ্য — AND) → ④ role নেই → 403 (সমৃদ্ধকরণ error গিলে যায় → role ছাড়া 403)।

**Role × controller ম্যাট্রিক্স (Admin service; ✔ অনুমোদিত, — নিষেধ, "open" = auth নেই):**

| Controller | admin | event_mgr | ticket_mgr | ticket_op | cust_support |
|---|---|---|---|---|---|
| activity-log | ✔ | ✔ | — | — | — |
| admin-users (+২টি open endpoint) | ✔ | — | — | — | — |
| agent-users | open | open | open | open | open |
| dashboard (+[AuthorizeProgram]) | ✔ | — | — | ✔ | — |
| discount (public read open) | ✔ | — | — | — | — |
| events, eventsVenueDetails, ticket-attributes, ticket-layout, ticket-checker | ✔ | ✔ | ✔ | ✔ | — |
| program | ✔ | ✔ | ✔ | ✔ | ✔ |
| program-settings, programVenue(+Details), teams, venues | ✔ | ✔ | — | — | — |
| promo-codes | ✔ | — | — | — | — |
| raffle-draw, general-notice, landing-page-image | ✔ | ✔ | — | — | — |
| social-media-settings, system-settings, gallery, block-level-entry-gate | ✔ | — | — | — | — |
| ticket-checker-gate (scheme admin+ticket-checker) | ✔ | ✔ ( subset) | — | ✔ | — |
| event-settings, header-footer, ticket-pricing, currency, token, portal-users, user-issue-chat | open | | | | |

Admin-এর বাইরে role **যাচাই হয় না** (Booking/Ticketing/UserIssue pool-only `Policy = admin` ব্যবহার করে)।

**5–7. Components / data.** `Core/ETP.Core/Middleware/CognitoUserAttributesMiddleware.cs:34-140`; registration `Admin.Program.cs:90`, `UserIssue.Program.cs:75`; Cognito `AdminGetUser`; Redis `user_{sub}` (২ মিনিট)।

**8. Code references.** উপরের সাথে `Services/Admin/ETP.Admin.Service/Api/`-র controller attribute (যেমন `TicketCheckerGateController.cs:23-24,72`)।

**9. Handover notes.** ① `scope` দিয়ে pool-নির্বাচন "দুর্ঘটনাক্রমে কাজ করে" — scope প্রতিটি SDK-token-এ স্বাভাবিক, তাই middleware সবসময় Admin pool দেখে; আজ ক্ষতিকর নয়, নকশায় ভঙ্গুর (architecture §2.5)। ② **Checker token** কঠোরতর method attribute ছাড়া `ticket-checker-gate`-এর প্রতিটি method ডাকতে পারে — `force-assign`, `remove-user`, `report`, `duplicate-tickets`-সহ (ইচ্ছাকৃত কিনা BS23 জানাক)। ③ Role বদল server-এ ≤২ মিনিট, portal UI-তে ≤৫৫ মিনিট (F6.4)। ④ Cache miss-প্রতি প্রতি user-এ ২ মিনিটে একবার `AdminGetUser` — burst load-এ Cognito rate-এর বিষয়।

### F6.16 Authorization স্তর ৪: প্রোগ্রাম স্কোপ

> **Bangla name:** অথরাইজেশন স্তর ৪: প্রোগ্রাম স্কোপ

**1. Name and purpose.** `admin` ছাড়া অন্য staff তাদের নির্ধারিত program-এ (`custom:program_ids`) কাজ করবেন। `X-Program-Id` header দিয়ে দুটি আলাদা ব্যবস্থা: **data filter** (Admin-এর EF global query filter) ও **access check** (`[AuthorizeProgram]`, শুধু dashboard-এ active)।

**2. Trigger and actor.** Program নির্বাচনের পরের admin-portal request (F1.1)। শুধু Admin service।

**3–4. Business/technical flow.** ① `ProgramIdMiddleware` header পার্স করে `HttpContext.Items["ProgramId"]`-এ (নেই/invalid হলে 0) → ② `ProgramIdAccessor` → ③ `AdminDbContext`-এর global filter প্রতিটি `IHasProgramId` entity-তে (`ProgramId <= 0 OR entity.ProgramId == header`); ফিল্টার হওয়া entity: Event, EventVenueDetails, ProgramTeam, ProgramVenue, ProgramVenueDetails, ProgramSettings, PromoCode, PromoCodeAssign, Discount, DiscountAssign, GeneralNotice, TicketCheckerGate, TicketAttributes, TicketLayoutConfig, UserIssue, UserIssueChatMessage → ④ `[AuthorizeProgram]` (dashboard): role `admin` বা `user` pass; নয়তো header নেই/invalid → **400** "Missing or invalid X-Program-Id header."; header claim-এ নেই → **403** "User does not have permission for program with Id {id}." (সাদা-টেক্সট body)।

**5–8. Components / contracts / code.** `Services/Admin/ETP.Admin.Service/Middleware/ProgramIdMiddleware.cs`; `ETP.Admin.Storage/Repositories/ProgramIdAccessor.cs`; global filter `AdminDbContext.cs:595-617`; `Attributes/AuthorizeProgramAttribute.cs`; ব্যবহার `DashboardController.cs:18` (`EventsController.cs:19`-এ comment)।

**9. Handover notes.** ① **Data filter access control নয়** — header-এর উপর ভরসা; `0`/না-পাঠালে ফিল্টার সরে যায়; মালিকানা আসলে যাচাই করে শুধু dashboard। ② `AuthorizeProgramAttribute`-এর 403 branch response লেখে কিন্তু `context.Result` সেট করে না, তাই MVC action-এ ঢুকে পড়ে — read-only dashboard-তে সমস্যা নেই, write endpoint-এ পুনর্ব্যবহার করবেন না। ③ অন্য service header উপেক্ষা করে (তারা স্পষ্ট `programId` param নেয়)।

### F6.17 Client-side authorization (মেনু ও গার্ড)

> **Bangla name:** ক্লায়েন্ট-সাইড অথরাইজেশন (মেনু ও গার্ড)

**1. Name and purpose.** Portal-গুলো role/program অনুযায়ী menu লুকায় ও route আটকায় — **সুবিধা, নিরাপত্তা নয়**; আসল সীমানা server-side স্তর (F6.14–F6.16)।

**2. Trigger and actor.** Admin portal-এর menu/route guard; user portal-এর auth guard।

**3–4. Business/technical flow.** Admin portal: দুটি menu — global (program 0) ও program menu। Role-প্রতি: `admin` সব; `customer_support` → Issues; `event_manager` (+`ticket_manager`) → program/venue/event/settings; `ticket_manager` → Generate Ticket; `ticket_operator` → dashboard/generate/reports। Guard: `ProgramMenuGuard` (dashboard/events/promo/ticket-layout/issues/report-এ program > 0), `LimitedMenuGuard` (users/settings/venues/program-management-এ program == 0), `AuthGuard` + `RoleChangeService.isRouteAllowedForRole` (role-প্রতি URL-prefix allow-list; role বদল `sessionStorage.lastKnownUserRole` দিয়ে ধরা পড়ে → program reset + toast)। User portal: `AuthGuard` (শুধু `localStorage.rvl_cognito_auth == "true"` দেখে), `UnAuthGuard` (OneID popup ঢুকতে দেয়), `LanguageGuard`।

**5–8. Components / code.** `rvl-gobcb-admin-portal/src/app/layout/app.menu.component.ts:39-262`; `src/app/core/guard/{auth,program-menu,limited-menu}.guard.ts`; `src/app/core/services/role-change.service.ts:31-201`; portal guard `ETP-Web/src/app/modules/core/guards/*.guard.ts`।

**9. Handover notes.** ① মেনু ও সার্ভার নিয়মে কিছু জায়গায় অমিল — যেমন `customer_support` সরাসরি reserved-ticket endpoint ডাকতে পারে (F6.14 note ①) যদিও UI লুকায়; `media-configuration`/`content-editor` route-এ **কোনো guard নেই**। ② `/settings` module route-এ আছে কিন্তু কোনো menu-তে নেই (notice/landing/team/footer screen ধারণ করে)। ③ Menu role match করে substring-এ (`roles.includes('admin')`) — ভবিষ্যতে "admin"-ধারী role-ও মিলে যাবে; route allow-list সঠিকভাবে ভাঙে। ④ User-portal `AuthGuard` local flag-এ ভরসা করে; আসল প্রত্যাখ্যান হয় API-তে।

### F6.18 Authorization ছাড়া endpoint-এর তালিকা

> **Bangla name:** অথরাইজেশন ছাড়া endpoint-এর তালিকা

**1. Name and purpose.** `BaseController`-এর `[Authorize]` comment out, তাই controller/action না বললে action anonymous। Backend-এর **৩৫৪টির মধ্যে ১৩৭টি** endpoint-এ authorization নেই। API Gateway/NLB/ingress এগুলোকে internet থেকে আটকায় কিনা repo-তে দেখা যায় না `[UNCONFIRMED]` (architecture Q1b; Open queries)।

**2. Trigger and actor.** Service-এ পৌঁছাতে পারা যে কোনো HTTP client।

**3–4. শ্রেণিবিভাগ** (controller audit অনুযায়ী):

- **A — ইচ্ছাকৃতভাবে public:** সব `GET /event/api/v1/*`; Admin-এর `landing-page-image/public`, `general-notice/public`, `header-footer` (GET), `discount/program/...`; Admin `ticket-pricing` GET; Booking `capacity/level-user-portal-seats`; Ticketing `shared` (signature-সুরক্ষিত)।
- **B — payment callback:** Booking `dgepay/payment-status`; `sslcommerz/payment-*`; **`payment-status-bypass`** (test hook — পৌঁছালে উচ্চ ঝুঁকি)।
- **C — internal call (worker/অন্য service, নকশা-অনুযায়ী tokenless):** Booking `capacity/*` (GET + POST), বেশিরভাগ `seat-reservation` update (`update-reservation-status`, `update-merge-status`, `merge-status`, `update-zip-status`, `zip-status`, `update-reservation-ticket-preview`, `event-id/{publicId}`), `user-booking-order`-এর internal (`public-id`, PATCH `generate-ticket-request/{publicId}`, `update-status`, `not-notified-list`, `update-notification-status`, `promo-code/{code}`, `booked-user-record/{id}`); Ticketing `initiate`, `initiate-user-ticket`, PATCH `generate-request`, `ticket-counts`, `by-gallery-block-level`, `ticket-numbers`, `GET ?id=`, `booking-order-id`, `reserved-urls`; Admin `portal-users/{phoneNo}`; **PushNotification — সব endpoint** (device token + send)।
- **D — authorization-ছাড়া admin operation (পর্যালোচনা দরকার):** Admin `agent-users/*` (৮), `admin-users/forget-password` + `set-forget-password`, `ticket-pricing`-র লেখা, `header-footer` PUT, `event-settings` GET/PUT; Booking `dashboard/*` (৪), `report/admin/*` (৮), `POST seat-reservation`, `GET seat-reservation/by-event-level`, `POST event-capacity-adjustment`, `GET by-event-level`; UserIssue `user-issue-chat/*` (৮)।
- **E — legacy/test:** Admin `currency`, `token` (service-token issuer), Admin-এর নিজের `user-issue-chat/*` copy, `user-issue/user-detail/{orderId}`; TicketChecker `testing/*`; root `GET /event|/platform|/ticketChecker|/ticketing`; PushNotification `bulk-status` stub।

**5–8. Components / code.** Comment-করা base attribute `Core/ETP.Core.Web/BaseController.cs:14-15`; Platform/PushNotification/UserAuth-এর `Program.cs`-এ pipeline comment; internal caller `Core/ETP.Core/ServiceClient/{BookingClient,TicketingClient,AdminClient,PushNotificationClient}/`।

**9. Handover notes.** প্রস্তাবিত নিষ্পত্তি: A রাখুন; B রাখুন তবে `payment-status-bypass` production থেকে সরান; C-তে `[Authorize]` যোগ করার **আগে** service credential বা network policy আনুন (এখন যোগ করলে worker ভাঙবে — অব্যবহৃত `service` scheme, F6.19, শুরুর পথ); D-তে menu-এর ইঙ্গিত-অনুযায়ী `[Authorize]` দিন; E মুছুন। যেকোনো controller বদলের পরে আবার audit করুন।

### F6.19 Service-to-service communication

> **Bangla name:** সার্ভিস-থেকে-সার্ভিস যোগাযোগ

**1. Name and purpose.** কে কাকে কোন credential নিয়ে ডাকে তার রেফারেন্স: token forwarding-সহ typed HTTP client, tokenless worker call, static-key external call ও SQS queue (ধারণা §0.8-এ)।

**2–4. Mechanism ও registry।**

| Tag | Mechanism | Credential |
|---|---|---|
| **[HTTP + user token]** | request-এর ভেতরের typed `HttpClient` + `DelegatedBearerAuthenticationHandler` | caller-এর Cognito access token |
| **[HTTP, no token]** | worker থেকে একই client (`HttpContext` নেই) | নেই — F6.18-এর C-শ্রেণির endpoint-ই লক্ষ্য |
| **[HTTP, static key]** | config থেকে স্থির header-এর client | `Notification:Authorization`, `Serverless:Authorization`, DgePay/SSLCommerz/NBR/TSP/OneID credential |
| **[SQS: Key]** | `SqsPublisher` → queue → polling worker | static `AWS:AccessKey/SecretAccessKey` (SigV4); message-এ token নেই |

Client registry (base URL key → forwarding): Admin → Event/Booking/Ticketing/UserIssue/PushNotification (forwarded) + Notification + Serverless (static)। Booking → Event/Ticketing (forwarded) + User (`Services:AppBase` → identity API, forwarded) + Serverless/Notification (static) + DgePay/SSLCommerz/NBR। Event → Booking (forwarded)। Scheduler → Booking / `IEventClient`→**`Services:Admin`** / Ticketing / Admin (worker: tokenless) + Notification (static)। TicketChecker → Ticketing (forwarded)। Ticketing → Event ×২ / Booking / User (forwarded) + Serverless (static) + TSP (mTLS) + OneID (Basic)। UserIssue → Booking/Ticketing (forwarded) + Serverless (static)। Utility → Admin/Booking/Ticketing (worker: tokenless)। বেশিরভাগ client Polly দিয়ে ৩-বার exponential backoff retry করে। Queue catalog: §0.8।

**5–8. Components / code.** `Core/ETP.Core.Web/Security/DelegatedBearerAuthenticationHandler.cs`; token-as-claim `DefaultAuthenticationConfig.cs:52-53`; প্রতিটি service-এর `DependencyConfig.cs`-এ registration (Admin `:123-195`, Booking `:83-200`, Scheduler `:71-110`, Ticketing `:151-255`, UserIssue `:55-80`, Utility `:51-75`, Event `:66`, TicketChecker `:49`); shared client `Core/ETP.Core/ServiceClient/*`; publisher `Core/ETP.Core/Queue/Services/SqsPublisher.cs`।

**9. Handover notes.** ① Forwarding caller-এর pool-কে callee-এর policy-র সাথে বাঁধে — এ কারণেই internal endpoint anonymous। ② Scheduler-এর `IEventClient` base `Services:Admin` (path ঠিক করে কে উত্তর দেয়) — device-token cleanup-এর বিভ্রান্তি (F5.13) এখান থেকে। ③ `Services:AppBase` = identity API-র base (`IUserClient` forwarded token নিয়ে `user/my-profile` ডাকে) `[UNCONFIRMED]`; local-এ সেটা admin portal-কে নির্দেশ করে (তাই local-এ call ব্যর্থ)। ④ Service-পক্ষে token refresh নেই — request-এর মাঝে token মেয়াদ শেষ হলে চেইন 401-এ ব্যর্থ। ⑤ MassTransit registered, অব্যবহৃত (dead)। ⑥ অব্যবহৃত `service` scheme: `GET /admin/api/v1/token` (header `ServiceApiKey`) ১-দিনের HS256 JWT দেয়; কোনো endpoint চায় না — পৌঁছানো-যায়-কিন্তু-অব্যবহৃত (F6.18-E-ও)।

### F6.20 File storage (S3, CloudFront)

> **Bangla name:** ফাইল স্টোরেজ (S3, CloudFront)

**1. Name and purpose.** দুটি S3 bucket: **media bucket** (`AWS:Bucket:Name`) — CMS image/SVG map/chat attachment; আর **ticket bucket** (`AWS:Ticket:Bucket:Name`) — টিকিট PDF; দুটোই CloudFront-এর পেছনে, টিকিট file-এ signed URL/cookie।

**2. Trigger and actor.** প্রতিটি upload/download feature (F1.2, F1.5, F1.12, F1.13, F1.28, F1.30, F2.9, F2.12, F5.7–F5.9)।

**3–4. Layout ও mechanics।**

| বিষয় | কোড যা করে |
|---|---|
| Media upload | `AwsSimpleStorageMediaManager` (`ICloudFrontMediaManager`) — event cover, logo, banner, SVG map, chat attachment (`chat-attachments/{issueId}/{guid}{ext}`, সর্বোচ্চ ১০ MB) |
| টিকিট PDF | `AwsSimpleStorageTicketMediaManager` (`ITicketMediaManager`) — key নির্মাণ: template `{TemplateBase}/ticket-back{programId}{eventId}.pdf`; blank `{BlankBase}/user/{userId}/{publicId}/{TicketNumber}.pdf` বা `{BlankBase}/reserved/{publicId}/…`; signed `{SignedBase}/user/{CreatedBy}/{publicId}/{TicketNumber}.pdf` বা `{SignedBase}/reserved/{CreatedBy}/{publicId}/{TicketNumber}-{type}.pdf`; merged/zip `{MergeBase}/{reservationId}/{ReservationNumber}_Merged_PDF_{i}.pdf` / `_Individual_Zipped_{i}.zip` |
| সরবরাহ | media: row-তে রাখা public CloudFront URL; টিকিট: **Ticketing API মাধ্যমে stream** (`download*`, F2.9) — সরাসরি CloudFront শুধু admin reserved download-এ signed URL/cookie দিয়ে |
| Signed URL | `S3CloudFrontStroge.GeneratePresignedUrlAsync` (share link, F2.9) |
| Signed cookie | `TicketingCookieManager.GetCloudFrontSignedCookie()` — RSA-SHA1-signed policy; key-pair id + private key appsettings-এ **নেই**: runtime-এ S3 JSON object থেকে পড়ে `{CloudfrontTicketValidator:BucketName}/{ObjectKey}` (`CloudfrontTicketConfig { KeyPairId, ResourceUrl, Expiration, PrivateKey }`)। `GET /ticketing/api/v1/booking-order-ticket/signed-cookie` cookie string ফেরায়; caller নিজে `CloudFront-Policy`, `CloudFront-Signature`, `CloudFront-Key-Pair-Id` cookie বসায় |

**5–8. Components / code.** `Core/ETP.Core.BlobStorage/AWSS3/{AwsSimpleStorageMediaManager,AwsSimpleStorageTicketMediaManager,S3CloudFrontStroge,TicketingCookieManager}.cs`; config key + `AWS:Bucket:BaseUrl`, `AWS:Ticket:{TemplateBase,BlankBase,SignedBase,ShareBase,MergeBase,ShareExpiryMinutes}`।

**9. Handover notes.** ① CloudFront signing key S3 object-এ থাকা অস্বাভাবিক — AWS-এ object-টি খুঁজে (নাম secret-এ) key rotation-এ আনুন। ② টিকিট download API দিয়ে মানে customer-দের জন্য API bandwidth, CDN নয় — সরাসরি CloudFront শুধু admin reserved download-এ। ③ Core-এ Imgix cache-purge helper আছে `[UNCONFIRMED: production-এ Imgix ব্যবহৃত কিনা]`।

### F6.21 Email (SES)

> **Bangla name:** ইমেইল (SES)

**1. Name and purpose.** Transactional email আজ সীমিত: admin console থেকে পাঠানো reserved-ticket zip-ই একমাত্র পাঠানো।

**2–4. Trigger/flow.** `EmailService` (`Core/ETP.Core.Email/Services/EmailService.cs`, `IAmazonSimpleEmailService`): সাধারণ send + template + `SendEmailWithZipAttachmentAsync` (হাতে-গড়া MIME `multipart/alternative`, base64 zip attachment, `SendRawEmailAsync`)। Sender = `AWS:Ticket:EmailSender` (`TicketOptions.EmailSender`)। `TicketManager.SendReservedTicketsAsync` ব্যবহার করে (default subject "Get your tickets", তারপর টিকিটের `Action = "emailed: {recipient}"`)। SES credential = shared AWS key।

**5–8. Components / code / config.** উপরের মতো; identity-verification helper (`VerifyEmailIdentityAsync`, quota, template) feature-এ অব্যবহৃত।

**9. Handover notes.** Customer-মুখী transactional email (order confirmation, receipt) কোডে নেই — invoice download (F2.9)। RVL email confirmation চাইলে এই service-ই extension point।

### F6.22 SMS ও external notification service

> **Bangla name:** এসএমএস ও বাহ্যিক নোটিফিকেশন সার্ভিস

**1. Name and purpose.** সব SMS external **Notification API** দিয়ে (`Notification:Endpoint` + static `Notification:Authorization` header) — এর source কোনো repo-তে নেই `[UNCONFIRMED]`।

**2–4. ব্যবহারকারী:** staff credential SMS (F6.2, F6.5), ticket-generated notification (F5.12), issue-resolved notification (F1.24)। Client `Core/ETP.Core/ServiceClient/NotificationClient/NotificationClient.cs` — `POST /notification/request` (`TicketGeneratedNotification` / `IssueResolvedNotification`, snake_case model `Core/ETP.Core/Models/Notification.cs`-এ) ও `POST /notification/send-message` (`SMSNotification { message_destination, message_type, the_message }`), ৩-বার exponential backoff retry। Admin, Booking, Scheduler-এ registered।

**5–8. Components / code.** উপরের মতো; config `Notification:Endpoint`, `Notification:Authorization` (local-এ `https://notification.invalid/`)।

**9. Handover notes.** ① API-র মালিক/hosting/capacity BS23-এর কাছে নিশ্চিত করুন (Open queries)। ② Architecture diagram-এর Lambda-র সম্ভাব্য ঠিকানাও এটি (architecture §2.6 Q1) `[UNCONFIRMED]`। ③ SMS ব্যর্থতায় admin operation অর্ধসম্পন্ন থাকে (F6.5 note ⑤)।

### F6.23 Push notification (PushNotification service + Firebase)

> **Bangla name:** পুশ নোটিফিকেশন (PushNotification service + Firebase)

**1. Name and purpose.** Push pipeline: client FCM device token **PushNotification** service-এ রেজিস্টার করে (F3.9); প্রেরকরা (admin portal → Admin service, Scheduler) পাঠাতে বলে; সে ২০০-token batch-এ `FirebaseNotification` queue-তে দেয়; Scheduler worker FCM দিয়ে পৌঁছায় (F5.11)।

**2–4. Trigger/flow।**

| # | Call | Hop | নোট |
|---|---|---|---|
| 1 | `POST /pushnotification/api/v1/device-token` (register), `PUT` (refresh), `DELETE` (remove), `GET {userId}` | **[HTTP + user token]** (কিন্তু service-এ **কোনো auth নেই** — F6.18) | `UserDeviceTokens` row |
| 2 | `POST …/push-notification/send-to-all` / `send-to-users` (UserIds আবশ্যক) / `send-to-user/{userId}` body `PushNotificationRequest { title, body, data?, userIds?, sendToAll }` | **[HTTP]** → `202 { message, requestId }` | `NotificationManager` token মেলায়, ২০০-প্রতি `FirebaseNotificationRequest` batch, **[SQS: FirebaseNotification]** publish (`GroupId=requestId`, `OrderId="{requestId}-batch-N"`) |
| 3 | `GET …/push-notification/bulk-status/{requestId}` | — | stub: সবসময় `{ requestId, status: "processing", message }` — tracking নেই |

Delivery পথ ও ব্যর্থতার অর্থ: F5.11। Admin service `send-to-users|send-to-all` (token-forwarded) ডাকে — যেমন support console থেকে issue-resolution push `[UNCONFIRMED: কোন screen আসলে পাঠায়]`।

**5–8. Components / code.** `Services/PushNotification/` (controller + `NotificationManager.cs`); `Core/ETP.Core/Models/{PushNotificationRequest,DeviceTokenRequest}.cs`; queue message `Core/ETP.Core/Queue/Messages/Firebase*.cs`; FCM `Core/ETP.Core/PushNotification/FirebasePushNotificationService.cs` (config `FirebasePushNotificationConfig:*` থেকে গড়া service-account JSON)।

**9. Handover notes.** ① পুরো service anonymous (F6.18) — পৌঁছানো মাত্র যে কেউ token row নাড়াতে পারে। ② ব্যর্থতা নীরবে হারায় (F5.11 note ①)। ③ `FirebaseBulkNotificationRequest` dead code। ④ FCM credential config key থেকে গড়া সম্পূর্ণ service-account JSON — উচ্চ-মূল্যের secret।

### F6.24 Activity logging (অডিট ট্রেইল)

> **Bangla name:** অ্যাক্টিভিটি লগ (অডিট ট্রেইল)

**1. Name and purpose.** ছয়টি service-এর প্রতিটি entity পরিবর্তন এক `SaveChangesInterceptor` দিয়ে একটাই shared `ActivityLogs` টেবিলে (schema `etp`) রেকর্ড হয় — F1.27-এর data।

**2. Trigger and actor.** Admin, Booking, Event, Ticketing, TicketChecker, UserIssue-এর যেকোনো EF `SaveChanges`।

**3–4. Technical flow.** Service-প্রতি `ActivityLogInterceptor` (`Core/ETP.Core.EntityFramework/Interceptors/ActivityLogInterceptor.cs`) — service নাম, `username` claim থেকে user id (fallback `System`), `IHttpContextAccessor` থেকে IP, shared `TransactionId` (`AsyncLocal`): `Modified` → শুধু বদলানো property-র diff; `Deleted` → সম্পূর্ণ পুরোনো মান; `Added` → buffer করে `SavedChangesAsync`-এ লেখা (DB id পাওয়ার জন্য)। Audit housekeeping field (`CreatedAt/By`, `UpdatedAt/By`) বাদ; enum নামে serialize; `IFormFile` "[Image File]" মাস্ক; খালি diff skip। Row সাথে সাথে আলাদা `LoggingDbContext` দিয়ে যায়। কলাম: `Id, ServiceName, EntityName, EntityId, Action, OldValues, NewValues, EntityContext, TransactionId, Timestamp, UserId, UserName, IpAddress` (+ ServiceName/TransactionId/EntityName/EntityId/Timestamp/IpAddress index)।

**5–8. Components / code.** `Core/ETP.Core.EntityFramework/{LoggingDbContext.cs,Interceptors/ActivityLogInterceptor.cs,Configuration/ActivityLogConfiguration.cs}`; service-প্রতি `*DbContext.cs` (যেমন `AdminDbContext.cs:79`); পাঠক F1.27।

**9. Handover notes.** ① PushNotification ও Utility log করে **না** (interceptor নেই)। ② Insert save-এর পরে লেখা হয় — ব্যর্থ transaction-এর চেষ্টার চিহ্ন থাকে না। ③ `OldValues/NewValues` JSON diff; বড় entity মানে বড় row।

### F6.25 Redis: cache, live capacity ও lock

> **Bangla name:** Redis: ক্যাশ, লাইভ ক্যাপাসিটি ও লক

**1. Name and purpose.** ElastiCache Redis একসাথে তিন কাজ: ছোট-TTL read cache, **লাইভ আসন/scan counter-এর ভাণ্ডার**, আর RedLock coordination।

**2–4. Key family** (constant `Core/ETP.Core/Constant/AppConstant.cs`-এর `CachePrefix` + Booking/Ticketing/Admin manager-এর সংযোজন):

| Family | Key | কাজ |
|---|---|---|
| Catalog cache | `program_details`, `program_settings_details`, `event_details`, `event_venue_details`, `event_settings_details`, `ticket_attributes_details`, `admin_event_details`, `admin_level_info`, `general_notice_published`, `landing_page_image_published`, `ticket_pricing_all` | ছোট TTL (attribute cache `User` = ২ মিনিট; venue details ১৫ দিন পর্যন্ত) |
| Live capacity | hash `capacity` ও তার field `level_live:{eventId}_{galleryId}_{blockId}_{levelId}`, `level_live_seats:…`, `level_database:…`, `level_database_seats:…`, `level_database_purchased_seats:…`; STRING `event_live:{eventId}` (F5.2) ও `event_{eventId}` (F5.4); SET `refresh` (F5.3); hash `level_locked:{groupId}` field = orderId (১২-মিনিট মেয়াদ) | §0.8 explainer |
| Ticketing | `event_ticket_counter:{eventId}` (ক্রমিক নম্বর), `tsp_token` (১ মিনিট), `OneId:AuthToken`, `sharedTicket:{ticketNumber}_{signature}`, `signedToken` (৬০ s), `mergeTicket`/`zipTicket` | F5.8/F5.9/F2.9 |
| Checker | `ticket_checker_tickets:event_{eventLongId}_gate_{gateId}`, `ticket_checker_checked_tickets:{eventLongId}_{gateId}_{userId}`, hash `TicketCheckerLevelGateMap` field `{eventId}_{gateId}`, flag `ticketCheckerDbSync` | F4.x/F5.14 |
| Lock (RedLock) | `checked_ticket` (২০ মি), `promo_code_status_updater` / `system_discount_status_updater` / `booking_status_updater` / `reservation_status_updater` / `pending_cancel_booking_status_updater` (২ মি), `notification_for_ticket_generated` (৩ মি), `event_live_capacity_refresher` (১৫ মি), `device_token_cleanup` (২ ঘ), `locked_order_refresher_{0..4}` (১৫ মি), `refresh_level_locks_{key}` (৩০ s), `user_ticket_generator_{eventId}` (১২ মি), `vat_challan_processor_{0..9}` (৫ মি), `ticket_processing_service_{reservationId}` (১ ঘ), `ticket_checker_gate_{gateId}` (২ s), `create_user_ticket_{orderId}` (৩০ s), `user_booking:{userId}`, `ticket_checker_status_reset` (৫ মি) | worker + business op |

**5–8. Components / code.** `Core/ETP.Core/Configuration/{RedisConfig,DistributedLockConfig,CacheConfig}.cs`; `Core/ETP.Core/Caching/RedisService.cs`; `Core/ETP.Core.Web/ConcurrencyLock/RedisLockManager.cs`; ব্যবহার feature-প্রতি।

**9. Handover notes.** ① বিক্রির মধ্যে Redis flush হলে লাইভ counter পরের worker cycle-এ DB থেকে গড়ে — ফাঁকের সময়ে অতি-বিক্রির ঝুঁকি। ② Lock-এর মেয়াদ hard-coded; tune করতে কোড বদলাতে হবে। ③ `ticketCheckerDbSync` flag ৩০-মিনিট drain cycle-এ sync fail-closed করে — ওই window-এ gate device error দেখে (নকশা-অনুযায়ী, F5.14)।

### F6.26 Configuration ও secret

> **Bangla name:** কনফিগারেশন ও সিক্রেট

**1. Name and purpose.** প্রতিটি setting-এর উৎস: service-প্রতি `appsettings.json` (শুধু গঠন — মান `[see User Secrets]`), local-এ user-secrets, AWS-এ SSM Parameter Store (`/rvl/<env>/<service>-appsettings` → CodeBuild buildspec-এ k8s secret — architecture doc §6)।

**2–4. Key reference (গুছিয়ে)।**

| গ্রুপ | Key |
|---|---|
| Service-এর পরিচয় | `Application:ServiceName` (route prefix) |
| Database | `ConnectionStrings:{Admin,Booking,Event,TicketChecker,UserIssue,PushNotification}` (+ অব্যবহৃত `:Ticketing`, `:Platform`, `:Scheduler`, `:UserAuth`) |
| Peer service | `Services:{Admin,Booking,Event,Ticketing,TicketChecker,UserIssue,PushNotification,Scheduler,Platform,UserAuth}` + `Services:AppBase` (identity API) |
| Auth | `AWS:CognitoPool:{Admin,User,TicketChecker,Agent}:{PoolId,ClientId,Authority,Metadata}`; `Authentication:Jwt:{Key,Issuer,Audience}`; `Authentication:ServiceApiKey` |
| AWS | `AWS:{Region,AccessKey,SecretAccessKey}`; `AWS:Bucket:{Name,BaseUrl}`; `AWS:Ticket:*` (F6.20); `AWS:Queue:{OrderSuccess,EventCapacity,TicketSigning,TicketProcessing,VatChallanProcessing,FirebaseNotification}`; `CloudfrontTicketValidator:{BucketName,ObjectKey}` |
| Cache/lock | `Cache:Redis:{InstanceName,ConnectionString,DefaultDatabase}`; `DistributedLock:Redis:{EndPoint,Port,AccessKey}` |
| Payment/VAT | `PaymentSettings:{DgePay,SSLCommerz,NBROpenApi}:*` (merchant id/secret, base URL, DgePay `RedirectUrl`) |
| External | `TSP:{AuthUrl,SignUrl,UserId,DigitalIdentityId}` (+ `Cert/tspgw_client.pfx`); `OneIdSettings:{TokenUrl,DocumentSyncUrl,AuthorizationToken}`; `Notification:{Endpoint,Authorization}`; `Serverless:{BaseUrl,Authorization}`; `FirebasePushNotificationConfig:*` |
| Client | Angular `environment*.ts` (generated); Flutter `env/.env.<flavor>`: `API_BASE_URL`, `AUTH_API_BASE_URL`, `AUTH_API_TOKEN`, `AMPLIFY_CONFIG`, `CHAT_COMMUNICATION_HUB`, `PAYMENT_SUCCESS_URL`, `VDS_CERTIFICATE`, `FIREBASE_ANDROID_*`, `FIREBASE_IOS_*`, policy URL |

**5–8. Components / code.** Service host-প্রতি appsettings; local `scripts/user-secrets.example.json`; client env template README-তে; SSM path pattern `buildspec-*.yaml` (architecture §6)।

**9. Handover notes.** ① Service-প্রতি একটি static IAM key pair (`AWS:AccessKey/SecretAccessKey`) SQS/S3/SES/Cognito/DynamoDB-র জন্য — rotation-এর পরিধি ও per-service বিভাজন অজানা `[UNCONFIRMED]` (architecture §2.3)। ② `ConnectionStrings:Ticketing` অব্যবহৃত (Ticketing `:Booking` চড়ে) — Ticketing pod-এর DB grant দেখে Booking-এর সাথে মিলিয়ে রাখুন। ③ Ticketing-এর DynamoDB registration-এ hard-coded `http://localhost:8000` ServiceURL branch আছে — production-এ আসল endpoint ওভাররাইড করছে না তা দেখুন `[UNCONFIRMED]`। ④ Client static key (`headerkey`, `AUTH_API_TOKEN`, `serverless.authorization`) browser/app bundle-এ — জনসাধারণ্যে প্রকাশিত ধরুন।

## 7. Open queries — BS23-এর জন্য খোলা প্রশ্ন

এই ডকুমেন্টের সব `[UNCONFIRMED]` item এখানে একত্রিত। প্রতিটি প্রশ্ন BS23-কে as-is পাঠানোর উপযোগী (architecture doc-এর Open questions §9-এর একই ধাঁচে)। Architecture doc-এর প্রশ্নের (Q1–Q6) সাথে ওভারল্যাপ হলে তা বলা আছে। উত্তরের ধরন: প্রশ্ন-নম্বর + সংক্ষিপ্ত উত্তর।

### OQ1. Identity API-র source কোনো repository-তে নেই
- **কোথায়:** প্রতিটি customer-facing auth flow (F6.6 registration, F6.9 password reset, F2.11/F6.7 profile, F3.1/F6.11 app version + delete account)। Client-রা `user/register-cached`, `otp/send-otp`, `otp/verify-otp`, `user/register`, `user/register-sso`, `user/my-profile`, `user/delete-my-profile`, `user/allowed-app-version` ডাকে `environment.services.identity` (portal) / `AUTH_API_BASE_URL` (app)-তে; backend service-গুলোও একই API ডাকে `Services:AppBase` (`IUserClient`) দিয়ে।
- **যা দেখা যায়:** backend-এর `Services/UserAuth` খালি stub। Identity API Cognito User-pool user বানায়, OTP পাঠায়, profile ও সর্বনিম্ন app version রাখে — সবই পাঁচ repo-র বাইরে। এর static key (`environment.headerkey` / `AUTH_API_TOKEN`) দুই client-এর bundle-এ।
- **প্রশ্ন:** এই API কোথায় আছে (repository, hosting, মালিক, SLA)? `user/register` ও `otp/password-reset`-এ OTP server-side যাচাই হয় কি? Account deletion-এ Cognito user ও GoBCB-পক্ষের data মুছে কি? Source/config হস্তান্তর করুন ও static key ঘুরিয়ে দিন।

### OQ2. Database topology: একটাই shared schema, "one schema per service" নয়
- **কোথায়:** প্রতিটি `*DbContext.cs` (`DefaultSchema = "etp"`); Ticketing `ConnectionStrings:Booking` ব্যবহার করে (`TicketingDbContext`), `ConnectionStrings:Ticketing` আছে কিন্তু অব্যবহৃত; Event/TicketChecker/Ticketing/UserIssue অন্যের টেবিল `ExcludeFromMigrations` দিয়ে mirror করে।
- **যা দেখা যায়:** একটাই Aurora database, একটাই schema `etp`, read-only mirror-সহ shared table — handover brief-এর "one schema per service" কোডের সাথে মেলে না।
- **প্রশ্ন:** (a) shared-schema layout কোডের মতোই কি (নিশ্চিত করুন); (b) Ticketing-এর Booking connection string ব্যবহার ইচ্ছাকৃত কি; (c) আলাদা DB instance/grant পরিকল্পিত আছে কি? না হলে আমরা প্রতিটি টেবিল-পরিবর্তনকে cross-service ধরে নেব।

### OQ3. "Serverless" API (admin 2FA OTP + Cognito lookup) — source ও architecture-এর Lambda
- **কোথায়:** admin login 2FA (F6.1), staff "user not found" যাচাই, Admin/Booking/Ticketing/UserIssue-এর `user/get-bulk-users` call — `Serverless:BaseUrl` + static `Serverless:Authorization` header।
- **প্রশ্ন:** এই API কি architecture diagram-এ API Gateway ও Cognito-র মাঝের Lambda (overlap: architecture Q1)? Source কোথায়? নোট: admin 2FA OTP ফলাফল শুধু browser যাচাই করে (OQ4) — Lambda কি server-side কিছু enforce করে?

### OQ4. Anonymous admin endpoint — gateway কি আটকায়?
- **কোথায় (কোডে `[Authorize]` নেই):** `POST/PUT/DELETE /admin/api/v1/agent-users/*` (Agent account তৈরি + password সেট); `POST /admin/api/v1/admin-users/set-forget-password` (শুধু `userId` দিয়ে যেকোনো admin-এর password সেট — OTP server-side যাচাই হয় না); `GET /admin/api/v1/admin-users/forget-password?phoneNo=` (যেকোনো account-কে RESET_REQUIRED করে); `GET /booking/api/v1/user-booking-order/payment-status-bypass` (DgePay যাচাই ছাড়াই "payment" প্রক্রিয়া করে); Ticketing `initiate`/`initiate-user-ticket`; Booking `not-notified-list`/`update-status`; সম্পূর্ণ PushNotification service; Booking `dashboard/*` + `report/admin/*`; Admin `event-settings`, `header-footer` PUT, `ticket-pricing`-র লেখা; UserIssue `user-issue-chat/*` (F6.18-এ সব ১৩৭টির তালিকা)।
- **প্রশ্ন:** API Gateway/NLB/ingress routing কি এগুলোকে internet থেকে আটকায় (overlap: architecture Q1b)? F6.18-এর প্রতিটি শ্রেণির জন্য: রাখব, রক্ষা করব, নাকি সরাব? অগ্রাধিকার: `set-forget-password`, `agent-users/*`, `payment-status-bypass`।

### OQ5. Notification API (SMS) — source ও মালিকানা
- **কোথায়:** `Notification:Endpoint` + `Notification:Authorization`; staff credential SMS (F6.2/F6.5), ticket-generated notice (F5.12), issue-resolved notice (F1.24) পাঠায়। Source কোনো repo-তে নেই।
- **প্রশ্ন:** এই API কোথায়, কে মালিক? নোট: SMS ব্যর্থ হলে admin operation অর্ধসম্পন্ন থাকে (account তৈরি কিন্তু API 400) — retry/queue পরিকল্পনা আছে কি? সম্পর্কিত: "ticket generated"-এ ঠিক কী পাঠায় — শুধু SMS, নাকি push-ও (OQ13)?

### OQ6. SQS queue: physical নাম, FIFO, dead-letter queue
- **কোথায়:** `AWS:Queue:{OrderSuccess, EventCapacity, TicketSigning, TicketProcessing, VatChallanProcessing, FirebaseNotification}` — সব মান secret।
- **প্রশ্ন:** প্রতি environment-এর physical queue নাম/URL দিন; কোনগুলো FIFO (publisher `.fifo` suffix অনুমান করে — F5.1/F5.2-এর ক্রম-নির্ভরতা এর উপর); কোডের মন্তব্যের অনুমিত DLQ configuration ও redrive policy কী?

### OQ7. কোন payment gateway live?
- **কোথায়:** Booking-এ DgePay ও SSLCommerz উভয়ের পূর্ণ flow আছে; `ProgramSettings.PaymentGateway` program-প্রতি বাছে (DgePay=1, SSLCommerz=2)।
- **প্রশ্ন:** production-এর কোন program কোন gateway ব্যবহার করে? SSLCommerz কোথাও live কি? `payment-status-bypass` কি production routing-এ বন্ধ (OQ4)?

### OQ8. Cognito pool-গুলোতে MFA configuration
- **কোথায়:** admin login `SMS_MFA` ভুলভাবে handle করে (F6.1 note ③); user login User-pool MFA চালু থাকলে ভাঙে (F6.7 note ①); admin 2FA OTP browser-only (F6.1 note ①)।
- **প্রশ্ন:** কোনো pool-এ (Admin/User) MFA চালু আছে কি? থাকলে client ঠিক করা দরকার; browser-only admin 2FA-ই যদি নিয়ন্ত্রণ, তাহলে API-Gateway-স্তরের সুরক্ষা আছে কি (OQ4) — কোড তা enforce করে না।

### OQ9. Scheduler device-token cleanup routing
- **কোথায়:** Scheduler-এর `DeviceTokenCleanupService` `DELETE api/v1/device-token/cleanup` ডাকে `IEventClient` দিয়ে যার base URL `Services:Admin`; ওই route-এর একমাত্র implementation **PushNotification** service-এ (F5.13)।
- **প্রশ্ন:** `Services:Admin` কি `/api/v1/device-token/*`-কে PushNotification-এ পাঠানো কোনো gateway, নাকি এই cleanup production-এ নীরবে ভাঙা?

### OQ10. TSP signing: certificate lifecycle ও TLS validation
- **কোথায়:** Ticketing `TSP:AuthUrl`/`TSP:SignUrl` client cert `Cert/tspgw_client.pfx`-সহ sign করে; দুই client-এই `ServerCertificateCustomValidationCallback => true` (F5.8); checker app QR offline যাচাই করে `VDS_CERTIFICATE` দিয়ে (শুধু Android Kotlin implementation — F4.3)।
- **প্রশ্ন:** (a) বর্তমান client certificate-এর মেয়াদ কবে শেষ, rotation প্রক্রিয়া কী (`VDS_CERTIFICATE`-এর জন্য app update লাগবে)? (b) server-certificate validation বন্ধ করা কি ইচ্ছাকৃত (network constraint)? (c) checker app-এর iOS build কি signature verify করে (আমরা শুধু Kotlin পেয়েছি)?

### OQ11. OneID integration-এর বিস্তারিত
- **কোথায়:** SSO federation `oneid` (F6.8), wallet sync (F2.10)। Overlap: architecture Q5।
- **প্রশ্ন:** (a) `UserBookingOrders.OneIdUserId` কোথায় সেট হয় (SSO login flow? booking?); (b) Cognito-তে OneID identity-provider config ও attribute mapping (repo-তে নেই); (c) document sync-এর `vds_qr` field `TODO` stub হিসেবে `null` পাঠায় — এই feature কাজ করার কথা ছিল কি?

### OQ12. Production-এ DynamoDB ব্যবহার
- **কোথায়:** Ticketing DynamoDB register করে hard-coded `ServiceURL http://localhost:8000` branch-সহ (`DependencyConfig.cs`); একমাত্র ব্যবহার test hook `TestTicketGeneratorController` (`TicketGeneratorQueue`)।
- **প্রশ্ন:** Production-এ DynamoDB আসলে ব্যবহৃত হয় কি? না হলে registration ও test controller সরানো যাবে? হ্যাঁ হলে আসল endpoint configuration কী?

### OQ13. "Ticket generated" push — কে পাঠায় ও কী থাকে?
- **কোথায়:** F5.12 Notification API-তে `TicketGeneratedNotification` পাঠায়; user app push পায় (F3.10) যার title/body/data key এই repo-তে দেখা যায় না; `bulk-status/{requestId}` stub।
- **প্রশ্ন:** Notification API (বা অন্য সিস্টেম) কি ticket generation-এর FCM push পাঠায়? তার template (title/body ভাষা, deep-link data key) জানান এবং push delivery tracking কোথাও আছে কি।

### OQ14. Agent pool / offline-sold ticket — client ও ভোক্তা
- **কোথায়:** F6.13 — পাঁচ repo-র কোনো client Agent pool দিয়ে sign-in করে না বা `POST /ticketing/api/v1/offline-sold-ticket` ডাকে না; `OfflineSoldTickets` পিছনে কেউ পড়ে না (report/screen নেই)।
- **প্রশ্ন:** agent-রা কোন system/app ব্যবহার করে? `OfflineSoldTickets` কে খায় (reconciliation? ছাপা?)? Handover-এর পরে feature রাখা হবে কি?

### OQ15. মুছে ফেলার আগে নিশ্চিত করতে হবে এমন dead/legacy code
- **কোথায়:** MassTransit event bus registered, consumer নেই (সব service); Event service-এর অব্যবহৃত `AWS:Queue:FirebaseNotification` registration; `AWS:Ticket:MergeBuffer` config key অপ্রয়োজিত; `ConnectionStrings:{Ticketing,Platform,Scheduler,UserAuth}` অব্যবহৃত; Admin `/api/v1/token` service-scheme issuer (পৌঁছানো-যায়, অব্যবহৃত); Admin-এর নিজের `/admin/chathub` + Admin `user-issue-chat` copy (portal UserIssue hub ব্যবহার করে); Admin `currency` controller অপ্রয়োজিত; admin portal-এর `ChangePasswordService` অস্তিত্বহীন endpoint ডাকে; user portal-এর legacy identity endpoint (`/token`, `/refreshToken`, …); user portal-এর Innovatrics DOT auto-capture package declared কিন্তু অব্যবহৃত; checker app-এর demo `movie*` screen; `FirebaseBulkNotificationRequest` অব্যবহৃত; checker app-এ `go_router` declared কিন্তু অব্যবহৃত।
- **প্রশ্ন:** প্রতিটির জন্য: handover-এর পরে মুছে ফেলা নিরাপদ, নাকি ভবিষ্যৎ ব্যবহারের জন্য রাখা?

### OQ16. Production-এ Swagger exposure
- **কোথায়:** প্রতিটি service `app.UseSwagger` + UI শর্তহীনভাবে register করে (`/<prefix>/swagger`)।
- **প্রশ্ন:** Production-এ Swagger পৌঁছানো কি ইচ্ছাকৃত (takeover team-এর জন্য দরকারি), নাকি environment-gate করা উচিত?

### OQ17. IAM key: ভাগাভাগি ও rotation
- **কোথায়:** প্রতিটি service SQS/S3/SES/Cognito/DynamoDB-তে একটি static pair `AWS:AccessKey/SecretAccessKey` দিয়েauthenticate করে (SSM → k8s secret; architecture §2.3)। IRSA/role-ভিত্তিক ব্যবস্থা নেই; queue message unsigned।
- **প্রশ্ন:** একটি key pair কি সব service-এ ভাগ হয়? তার IAM policy কী অনুমতি দেয়? Rotation প্রক্রিয়া কী (এবং কি per-service policy ভাগ করা যায়)? Overlap: architecture §2.5 item 7।

### OQ18. CloudFront ticket signing key S3-এ সংরক্ষিত
- **কোথায়:** `TicketingCookieManager` `CloudfrontTicketConfig` (KeyPairId, PrivateKey, ResourceUrl, Expiration) S3 object থেকে পড়ে — নাম `CloudfrontTicketValidator:{BucketName,ObjectKey}` (F6.20)।
- **প্রশ্ন:** bucket/object-এর অবস্থান জানান ও এই key pair-কে handover + rotation পরিকল্পনায় আনুন। সাথে Imgix (Core-এ cache-purge helper আছে) production-এ ব্যবহৃত কিনা জানান।

### OQ19. Gate controller-এ checker token
- **কোথায়:** `TicketCheckerGateController` class স্তরে `ticket-checker` scheme নেয়, ফলে checker token `force-assign`, `force-unassign`, `update-download-status`, `remove-user`, `report`, `export`, `duplicate-tickets`, `manual-entry-tickets` — সব ডাকতে পারে (F6.15 note ②)।
- **প্রশ্ন:** ইচ্ছাকৃত (checker-রা বিশ্বস্ত staff), নাকি এগুলো শুধু admin-scheme হওয়া উচিত?

### OQ20. Program scoping data filter, access check নয়
- **কোথায়:** `X-Program-Id` EF query filter চালায় যা header-এর উপর ভরসা করে; মালিকানা যাচাই করে শুধু dashboard (`[AuthorizeProgram]`); `EventsController`-এ attribute comment out (F1.1/F6.16)।
- **প্রশ্ন:** Non-admin staff-দের জন্য program-ভিত্তিক বিচ্ছিন্নতা অন্য কোথাও (gateway?) enforce হয়, নাকি তা গ্রহণকৃত ঝুঁকি — নয়তো handover-এর পরে `[AuthorizeProgram]` event/তালিকায় বাড়ানো হবে?

### OQ21. `SystemSettings.SeatLockTimeout` — কোথাও ব্যবহৃত হয়?
- **কোথায়:** setting আছে (F1.30), অথচ Booking lock-এর ১২-মিনিট মেয়াদ hard-coded (F5.3)।
- **প্রশ্ন:** `SeatLockTimeout` কি কিছু পড়ে (অন্য সিস্টেম?), নাকি ১২-মিনিট ধ্রুবকই আসল configuration?

### OQ22. কোড থেকে পড়া যায়নি এমন ops রীতি
- (a) venue-details cache TTL ১৫ দিন পর্যন্ত (F1.9/F2.4) — BS23 জরুরি দাম বদল কীভাবে প্রকাশ করে (manual cache clear?) (b) payment-discrepancy report-এর matching নিয়ম (F1.22) (c) কোন screen আসলে `push-notification/send-to-users` দিয়ে push পাঠায় (F6.23) (d) client env key-এর production মান (`PAYMENT_SUCCESS_URL` host, OneID URL, `CHAT_COMMUNICATION_HUB`) — সব secret-পক্ষে `[UNCONFIRMED]`।

---

*বাংলা সংস্করণের সমাপ্তি। ইংরেজি সংস্করণ (`gobcb-feature-documentation-en.md`) অভিন্ন কনটেন্ট ও কাঠামো বহন করে।*

