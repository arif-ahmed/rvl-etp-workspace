# RVL-ETP লোকাল ডেভেলপমেন্ট সেটআপ গাইড (বাংলা)

> **এই ডকুমেন্ট কার জন্য**: নতুন যোগ দেওয়া .NET ডেভেলপার, যিনি Windows মেশিনে একদম শূন্য থেকে RVL-ETP ব্যাকএন্ডটা সেটআপ করে চালাবেন, ডিবাগ করবেন, আর ফিচার টেস্ট করবেন।
>
> **তথ্যের উৎস**: এই গাইডের প্রতিটা দাবি সাবমডিউলগুলোর সোর্স কোড, কনফিগ ও স্ক্রিপ্ট থেকে যাচাই করা (মূলত `rvl-gobcb-backend`; ক্লায়েন্ট-সাবমডিউলের কনফিগ যেখানে প্রাসঙ্গিক) — ওয়ার্কস্পেস রিপোর নিজের কোনো doc ব্যবহার করা হয়নি। যেসব বিষয় রিপো থেকে নিশ্চিত করা যায়নি, সেগুলো শেষের [অযাচাইকৃত বিষয়](#১৩-অযাচাইকৃত-বিষয়-এবং-টিমকে-করার-প্রশ্নের-লিস্ট) সেকশনে আলাদা করে চিহ্নিত।
>
> **শেষ যাচাই**: ২০২৬-১০-২১

---

## ১. ভূমিকা: প্ল্যাটফর্ম এক নজরে

RVL-ETP (আগের নাম GoBCB, BS23-এর তৈরি) একটা **ইভেন্ট টিকিটিং প্ল্যাটফর্ম**। ইউজার ওয়েব/মোবাইল থেকে টিকিট কেনে, পেমেন্ট করে (SSLCommerz/DgePay), সাইনড PDF টিকিট পায়, আর ইভেন্টের গেটে টিকচেকার অ্যাপ দিয়ে QR স্ক্যান হয়। ব্যাকএন্ড **.NET 8 মাইক্রোসার্ভিসেস**, AWS-তে হোস্টেড (EKS + ALB + Cognito + S3 + SQS)।

ওয়ার্কস্পেসে ৫টা সাবমডিউল:

| সাবমডিউল | কী |
|---|---|
| `rvl-gobcb-backend` | **.NET 8 ব্যাকএন্ড** — এই গাইডের মূল বিষয় (49 প্রজেক্ট, ১১ সার্ভিস) |
| `rvl-gobcb-admin-portal` | Angular 18 অ্যাডমিন ওয়েব (Cognito `custom:role` দিয়ে রোল) |
| `rvl-gobcb-user-portal/ETP-Web` | Angular 19 ইউজার ওয়েব (OneID OAuth সহ) |
| `rvl-gobcb-checker-app` | Flutter গেট-স্ক্যানার অ্যাপ (অফলাইন VDS QR ভেরিফাই) |
| `rvl-gobcb-user-app` | Flutter ইউজার অ্যাপ |

**প্রতিটা সার্ভিসের ভেতরের লেয়ারিং** (সব সার্ভিসে একই প্যাটার্ন):

```
Services/<X>/
 ├─ ETP.<X>.Domain      → Managers (বিজনেস লজিক), Models, Interfaces
 ├─ ETP.<X>.Storage     → DbContext, Repositories, EF Migrations
 ├─ ETP.<X>.Service     → Controllers (Api/), Workers (BackgroundServices), Program.cs
 └─ ETP.<X>.Client      → অন্য সার্ভিস থেকে কল করার টাইপড HttpClient
```

শেয়ার্ড লাইব্রেরি `Core/`-এ: `ETP.Core` (constants, SQS publisher, টাইপড service clients, Firebase — ৩১ প্রজেক্ট ব্যবহার করে), `ETP.Core.Web` (auth handlers, CORS, filters), `ETP.Core.EntityFramework` (repository/UoW + ActivityLog interceptor), `ETP.Core.BlobStorage` (S3/CloudFront/Imgix), `ETP.Core.Email` (SES)।

## ২. প্রয়োজনীয় টুল

| টুল | কেন | নোট |
|---|---|---|
| **.NET 8 SDK** | সব ৪৯ প্রজেক্ট `net8.0` | রিপোতে `global.json` নেই, তাই ইনস্টল করা SDK-ই 8.0 হতে হবে |
| **Visual Studio 2022** | সলিউশন VS2022 ফরম্যাটের; "ASP.NET and web development" workload লাগবে | |
| **Docker Desktop** | PostgreSQL + Redis লোকালে চালাতে | রিপোর compose ফাইল এ দেয় না, নিজে চালাতে হবে |
| **git** | | |
| `dotnet ef` tool | ম্যানুয়ালি মাইগ্রেশন চালাতে চাইলে | `dotnet tool install --global dotnet-ef` |
| dev certificate | https প্রোফাইলে চালালে | `dotnet dev-certs https --trust` |

সুবিধার জিনিস: **pgAdmin** বা **Azure Data Studio** (PostgreSQL দেখার জন্য), **Postman**।

## ৩. আর্কিটেকচার পরিচিতি

### ৩.১ ১১টা সার্ভিস

| সার্ভিস | রুট প্রিফিক্স | http পোর্ট (launchSettings) | দায়িত্ব | DB |
|---|---|---|---|---|
| Admin | `/admin` | 5099 | সবচেয়ে বড়; admin portal-এর কার্যত BFF — প্রোগ্রাম, ইভেন্ট, ইউজার, প্রাইসিং, প্রোমো, Cognito ইউজার ম্যানেজমেন্ট (34 controllers) | নিজের |
| Booking | `/booking` | 5086 | সিট রিজার্ভেশন, ক্যাপাসিটি, পেমেন্ট, NBR VAT | নিজের |
| Event | `/event` | 5001 | পাবলিক read-side API — ইভেন্ট লিস্ট, প্রাইসিং, ল্যান্ডিং | নিজের (⚠️ মাইগ্রেশন নেই) |
| Ticketing | `/ticketing` | 5112 | টিকিট PDF, TSP ডিজিটাল সাইনিং, OneID | **Booking-এর DB শেয়ার করে** |
| TicketChecker | `/ticketchecker` | 5274 | গেট-স্ক্যানার অ্যাপের সিঙ্ক API | নিজের (⚠️ মাইগ্রেশন নেই) |
| Scheduler | `/scheduler` | 5033 | worker-only: FCM পুশ, স্ট্যাটাস আপডেট | নেই |
| Utility | `/utility` | 5014 (ফিক্সের পর; আসল ফাইলে ভুল আছে — দেখুন §৬.৩) | worker-only: টিকিট PDF merge/zip | নেই |
| PushNotification | `/pushnotification` | 5007 | ডিভাইস টোকেন + FCM কিউইং | নিজের |
| UserIssue | `/userissue` | 56775 | ইউজার সমস্যা রিপোর্ট + SignalR চ্যাট | নিজের |
| UserAuth | `/user-auth` | 5126 | **স্কেলিটন** (খালি TestController) | নেই |
| Platform | `/platform` | 5021 | **স্কেলিটন** (আনটাচড টেমপ্লেট) | নেই |

⚠️ README-তে UserAuth/Platform-কে আসল সার্ভিস বলা হলেও কোডে এরা খালি খোল; docker-compose-এর পোর্ট-লিস্ট (5001–5011) launchSettings-এর পোর্ট থেকে আলাদা — লোকাল ডিবাগে launchSettings-এর পোর্টই ব্যবহৃত হবে।

### ৩.২ সার্ভিস-টু-সার্ভিস কমিউনিকেশন

**সিঙ্ক্রোনাস REST**: `Core\ETP.Core\ServiceClient\*`-এ টাইপড HttpClient (Polly retry সহ), base URL আসে `Services:{Name}` কনফিগ থেকে, আর `DelegatedBearerAuthenticationHandler` ইউজারের JWT পরের সার্ভিসে ফরওয়ার্ড করে। কল-গ্রাফ: Admin→(Event, Booking, Ticketing, UserIssue, PushNotification, Serverless, Notification); Booking→(Event, Ticketing); Event→Booking; Ticketing→(Event, Booking); TicketChecker→Ticketing; Scheduler→(Booking, Admin, Ticketing); UserIssue→(Booking, Ticketing); Utility→(Admin, Booking, Ticketing)।

**অ্যাসিঙ্ক্রোনাস**: MassTransit-এর SQS bus সত্যিই চালু আছে (`Core\ETP.Core.EventBus` — স্টার্টআপ লগের "Bus started: amazonsqs://..." ওটাই), কিন্তু কোনো সার্ভিসে `IConsumer` নেই — তাই গ্রহণ করে নিচের কিউগুলোতে **raw `ReceiveMessage` polling** (`Services/*/ETP.*.Service/Workers/TaskManagers/`):

| কিউ | Publisher → Consumer | কাজ |
|---|---|---|
| `OrderSuccess` | Booking → Booking worker | Level capacity আপডেট |
| `EventCapacity` | Booking → Booking | Live capacity |
| `VatChallanProcessing` | Booking → Booking | NBR VAT চালান |
| `TicketSigning` | Ticketing → Ticketing worker | TSP সাইন + S3 আপলোড |
| `TicketProcessing` | Ticketing → Utility worker | PDF merge/zip |
| `FirebaseNotification` | PushNotification/Event → Scheduler | FCM পুশ |

### ৩.৩ অথেন্টিকেশন

AWS **Cognito-র ৪টা ইউজার পুল** (Admin/User/TicketChecker/Agent) + ১টা symmetric-key `Service` স্কিম — মোট ৫টা JWT স্কিম (`Core\ETP.Core\Configuration\DefaultAuthenticationConfig.cs`, সব সার্ভিস এটাই ব্যবহার করে)। Cognito স্কিমগুলো pool-এর `MetadataAddress` (JWKS) দিয়ে ভ্যালিডেট হয়, `client_id` ক্লেইম দিয়ে audience চেক হয়। Controller-এ `[Authorize(Policy = AuthScheme.X)]`, পলিসি ৫টা `Core\ETP.Core\Configuration\AuthorizationConfig.cs`-এ। রোল: `admin`, `user`, `ticket-checker`, `agent`, `ticket_operator`, `event_manager`, `customer_support`, `ticket_manager`।

সার্ভিস-টু-সার্ভিস টোকেন: Admin-এর `TokenIssuerController` (`GET api/v1/token`, `ServiceApiKey` হেডার) ১ দিনের JWT দেয় — **কোডে TODO আছে যে client-id ভ্যালিডেশন এখনো ইমপ্লিমেন্ট হয়নি**।

⚠️ বিভ্রান্তির ফাঁদ: `Core\ETP.Core.Web\Security\DefaultAuthenticationConfig.cs`-এ **একই নামের আরেকটা** লিগ্যাসি single-scheme এক্সটেনশন আছে — ব্যবহৃত হয় না।

## ৪. ডাটাবেস টোপোলজি: AWS-এ ৬টা আলাদা DB, লোকালে একটাই (`etp_local`)

**৭টা DB-ব্যবহারকারী সার্ভিস → ৬টা আলাদা DB** — প্রতিটা সার্ভিস নিজের connection key টানে:

| সার্ভিস | Connection key | প্রমাণ (ফাইল:লাইন) |
|---|---|---|
| Admin | `ConnectionStrings:Admin` | `ETP.Admin.Service\Configurations\DependencyConfig.cs:47` |
| Booking | `ConnectionStrings:Booking` | `ETP.Booking.Service\Configuration\DependencyConfig.cs:207` |
| **Ticketing** | **`ConnectionStrings:Booking`** ← একই key | `ETP.Ticketing.Service\Configurations\DependencyConfig.cs:78` |
| Event | `ConnectionStrings:Event` | `ETP.Event.Service\Configurations\DependencyConfig.cs:77` |
| TicketChecker | `ConnectionStrings:TicketChecker` | `ETP.TicketChecker.Service\Configurations\DependencyConfig.cs:61` |
| PushNotification | `ConnectionStrings:PushNotification` | `ETP.PushNotification.Service\Configurations\DependencyConfig.cs:27` |
| UserIssue | `ConnectionStrings:UserIssue` | `ETP.UserIssue.Service\Configurations\DependencyConfig.cs:35` |

**AWS-টোপোলজিতে ৬টা আলাদা DB** — উপরের connection-key বিভাজনের স্বাভাবিক ফল (৭টা DbContext-ই একই স্কিমা `etp` আর একই `__EFMigrationsHistory` টেবিল ব্যবহার করে; Admin আর Booking-এর মডেলে একই নামের টেবিলও আছে — `Events` AdminDbContext.cs:51, BookingDbContext.cs:32)। তবে **এক DB-তে সব কনটেক্সট একসাথেও চলে** — Aspire লোকাল স্ট্যাকে লাইভ যাচাই হয়েছে: এক শেয়ার্ড DB-তে ১২৯টা মাইগ্রেশন একই স্কিমায় মিলেমিশে apply হয়, শেয়ার্ড টেবিলগুলো দুই মডেলই ম্যাপ করে, সার্ভিসগুলো বুট করে। মানে টেবিল-ওভারল্যাপ ভাঙার কারণ নয়; ৬-DB ভাগ আসলে ডিপ্লয়মেন্ট-টোপোলজির সিদ্ধান্ত (নিচের floci/Aspire অংশ দেখুন)।

**লোকালে ডিফল্ট এখন একটাই শেয়ার্ড DB — `etp_local`** (workspace-এর compose স্ট্যাক এটাই বানায়; secrets টেমপ্লেটেও সব সার্ভিসের `ConnectionStrings:*` এক মানে এখানেই পয়েন্ট করে — লাইভ-যাচাইকৃত ২০২৬-১০-২১: কোনো সেটিং ছোঁয়া ছাড়াই ৭টা কনটেক্সটের ১২৯টা মাইগ্রেশন এক DB-তে apply হয়, ৫৩টা টেবিল তৈরি হয়)। কেউ AWS-এর মতো পার-সার্ভিস DB লেআউট লোকালে চাইলে ধাপ ২-এর ঐচ্ছিক কমান্ডগুলো দেখুন।

**সব DB-তে স্কিমা `etp`-তেই তৈরি হবে** — মাইগ্রেশন নিজে বানাবে, আপনাকে স্কিমা বানাতে হবে না।

## ৫. ধাপে ধাপে সেটআপ

> **ডিরেক্টরি কনভেনশন**: নিচের বেশিরভাগ `dotnet` কমান্ড **backend root থেকে** চলবে:
> ```
> cd D:\Workspace\Sources\RVL\rvl-etp\rvl-etp-workspace\rvl-gobcb-backend
> ```
> (Git Bash ব্যবহার করলে: `cd /d/Workspace/Sources/RVL/rvl-etp/rvl-etp-workspace/rvl-gobcb-backend`)
> Docker কমান্ডগুলো যেকোনো ডিরেক্টরি থেকে চলবে।
>
> টিম আসলে **Aspire + floci স্ট্যাকেও** চালায় (নিচের "বিকল্প পথ" অংশ) — ওটা নিলে ধাপ ১–৩-এর বেশিরভাগ কাজ কমে যায়।

### ধাপ ১: PostgreSQL + Redis চালানো (docker compose — workspace root থেকে)

ওয়ার্কস্পেস রুটের `docker-compose.yml`-এ dev-ডিপেন্ডেন্সি দুটো (PostgreSQL 16 + Redis 7) তৈরি করাই আছে — ব্যাকএন্ড রিপোর নিজের `docker-compose.yaml` শুধু CI-র ৯টা অ্যাপ-ইমেজের (UserAuth/Platform ওখানে নেই), ওখানে PostgreSQL/Redis নেই। **পোর্ট-ইউজার-ডাটাবেস সবই secrets টেমপ্লেটের সাথে হুবহু মেলানো**: postgres হোস্ট-পোর্ট **5433**-এ (ইউজার `etp`, পাসওয়ার্ড `etp_local_pw`, `etp_local` ডাটাবেস অটো-তৈরি), Redis হোস্ট-পোর্ট **6380**-এ — মানে টেমপ্লেটের connection string/Redis মান কোনোটাই বদলাতে হয় না, আর native PostgreSQL (5432) / Redis (6379) ব্যস্ত থাকলেও সংঘর্ষ হয় না।

> শুরুর আগে দেখে নিন Docker Desktop চালু আছে (`docker ps` কাজ করছে কি না) — বন্ধ থাকলে আগে অ্যাপটা খুলে engine ready হতে দিন।

```bash
cd D:\Workspace\Sources\RVL\rvl-etp\rvl-etp-workspace
docker compose up -d
```

- কন্টেইনার নাম ফিক্সড — `etp-postgres`, `etp-redis` — তাই এই গাইডের বাকি সব কমান্ড (`docker exec`, `docker stop/start`) আগের মতোই চলবে।
- **প্রথমবার চালালেই `etp_local` ডাটাবেস অটো তৈরি হয়ে যায়** (`POSTGRES_DB` দিয়ে — আলাদা initdb স্ক্রিপ্টের দরকার নেই)।
- ডেটা named volume-এ (`etp-pgdata`, `etp-redis-data`) — কন্টেইনার মুছলেও ডেটা বাঁচে।
- পোর্ট/পাসওয়ার্ড বদলাতে env দিন: `ETP_PG_PORT`, `ETP_REDIS_PORT`, `ETP_PG_PASSWORD` — তবে তখন secrets-এর connection string/Redis মানও সেই সাথে বদলাতে হবে।
- মেশিন রিস্টার্টের পর Docker উঠলে দুটো নিজেই ফিরে আসে (`restart: unless-stopped`)।

চালু আছে কি না চেক: `docker ps` (দুটোই `Up (healthy)` দেখাতে হবে)।

**ম্যানুয়াল বিকল্প (reference — compose ছাড়া সরাসরি চালাতে চাইলে):**

```bash
docker run -d --name etp-postgres -e POSTGRES_USER=etp -e POSTGRES_PASSWORD=etp_local_pw -e POSTGRES_DB=etp_local -p 5433:5432 postgres:16
docker run -d --name etp-redis -p 6380:6379 redis:7
# পরে বন্ধ/চালু: docker stop etp-postgres etp-redis  /  docker start etp-postgres etp-redis
```

এ পথেও `etp_local` অটো তৈরি হয় (`POSTGRES_DB`); পার্থক্য শুধু — ডেটা anonymous volume-এ থাকে (`docker rm -v`-এ চলে যায়, নতুন কন্টেইনারে ফেরে না)।

### ধাপ ২: ডাটাবেস যাচাই — একটাই শেয়ার্ড `etp_local` (ধাপ ১-এই অটো তৈরি হয়ে যায়)

⚠️ **কেন এই বিষয়টা জানা দরকার**: পুরো রিপোতে কোথাও `EnsureCreated`/`CREATE DATABASE` নেই — মাইগ্রেশন শুধু **স্কিমা** বানায়, ডাটাবেস **নিজে বানায় না** (যাচাইকৃত: `MigratePendingDatabase` শুধু `Database.Migrate()` কল করে)। compose-এর `POSTGRES_DB` প্রথম রানেই ডাটাবেসটা বানিয়ে দেয়। যাচাই করুন:

```bash
docker exec etp-postgres psql -U etp -d etp_local -c "\l"
```

লিস্টে `etp_local` দেখলেই তৈরি (স্কিমা তৈরি হবে পরের ধাপে — সার্ভিস চালু করলে বা ম্যানুয়াল মাইগ্রেশনে)।

**Ticketing-এর আলাদা DB লাগে না** — কোডেই সে Booking-এর key টানে (§৪ দেখুন); এক-DB লেআউটে এটা স্বাভাবিকভাবেই মিটে যায়।

DB না দেখলে (পুরনো volume-এ init স্কিপ হয়েছে) — হাতে বানান:

```bash
docker exec etp-postgres psql -U etp -c "CREATE DATABASE etp_local;"
```

**ঐচ্ছিক**: কেউ AWS-টোপোলজির মতো পার-সার্ভিস DB লোকালে চাইলে নিজে বানিয়ে নিতে পারেন, তারপর প্রতিটা সার্ভিসের `ConnectionStrings:<নিজেরটা>`-য় `Database=...` অংশটা বদলে দিতে হবে:

```bash
docker exec etp-postgres psql -U etp -c "CREATE DATABASE etp_admin;" -c "CREATE DATABASE etp_booking;" -c "CREATE DATABASE etp_event;" -c "CREATE DATABASE etp_ticketchecker;" -c "CREATE DATABASE etp_pushnotification;" -c "CREATE DATABASE etp_userissue;"
```

### ধাপ ৩: User Secrets ভরা (backend root থেকে)

রিপোর প্রতিটা `appsettings.json`-এ প্রতিটা মান লেখা `"[see User Secrets]"` — bin ফোল্ডারের কপিও তাই। **আসল মানের উৎস**: (ক) টিমমেটের মেশিনের user-secrets (`%APPDATA%\Microsoft\UserSecrets\`), অথবা (খ) AWS SSM:

```bash
aws ssm get-parameter --name /rvl/dev/admin-service-appsettings --with-decryption --query Parameter.Value --output text
aws ssm get-parameter --name /rvl/dev/booking-service-appsettings --with-decryption --query Parameter.Value --output text
# ... বাকিগুলো: /rvl/dev/event-, ticketchecker-, ticketing-, scheduler-, platform-,
#     userauth-, utility-, pushnotification-, userissue-service-appsettings  (buildspec-dev.yml:10-20)
```

SSM থেকে পাওয়া JSON-টা প্রতিটা সার্ভিসের user-secrets হিসেবে বসান। **ভালো খবর**: টিমের লোকাল-টেমপ্লেট (টিমমেটের মেশিনের user-secrets) নিলে DB/Redis-এর মানগুলো এমনিই ধাপ ১-এর স্ট্যাকের দিকে পয়েন্ট করা থাকে — `Port=5433;Database=etp_local` আর Redis `localhost:6380` — কিছুই বদলাতে হয় না। ভরার উপায় — VS-এ প্রজেক্টে রাইট-ক্লিক → **Manage User Secrets**, বা CLI (মানগুলো টেমপ্লেটেরটাই):

```bash
# backend root থেকে
dotnet user-secrets set "ConnectionStrings:Booking" "Host=localhost;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true" --project Services/Booking/ETP.Booking.Service
dotnet user-secrets set "Cache:Redis:ConnectionString" "localhost:6380" --project Services/Booking/ETP.Booking.Service
dotnet user-secrets set "Cache:Redis:InstanceName" "etp-local:" --project Services/Booking/ETP.Booking.Service
dotnet user-secrets set "DistributedLock:Redis:EndPoint" "localhost" --project Services/Booking/ETP.Booking.Service
dotnet user-secrets set "DistributedLock:Redis:Port" "6380" --project Services/Booking/ETP.Booking.Service
dotnet user-secrets set "DistributedLock:Redis:Database" "0" --project Services/Booking/ETP.Booking.Service
```

**Key চিটশিট** (কোন key কার, কতটা জরুরি):

| Key | কোথায় লাগে | জরুরিতা |
|---|---|---|
| `ConnectionStrings:<নিজেরটা>` | DB-ওয়ালা প্রতিটা সার্ভিস | 🔴 না দিলে startup-এই মরবে/মাইগ্রেশন হবে না |
| `Cache:Redis:ConnectionString`, `InstanceName`, `DefaultDatabase` | সব সার্ভিস | 🔴 Redis-এ eager connect হয় — না দিলেই crash |
| `DistributedLock:Redis:EndPoint/Port/Database` | Event/PushNotification/UserAuth/Platform ছাড়া সবাই | 🔴 না দিলে `ConfigurationErrorsException` |
| `AWS:{Region, AccessKey, SecretAccessKey}` | SQS/S3/SES/Cognito-নির্ভর সার্ভিসগুলো | 🟠 dev AWS creds দিন |
| `AWS:CognitoPool:{Admin/User/TicketChecker/Agent}:*` | `[Authorize]` endpoint টেস্টে | 🟡 Swagger/`/health` anonymous — না দিলেও সার্ভিস উঠবে |
| `AWS:Queue:*` | worker-ওয়ালা সার্ভিস | 🟡 না দিলে ব্যাকগ্রাউন্ডে error লগ, হোস্ট ক্র্যাশ করে না |
| `Services:<Name>` | অন্য সার্ভিস কল করলে | 🟠 **প্রিফিক্সসহ** দিন: `http://localhost:5099/admin` |
| `Authentication:Jwt:{Issuer,Audience,Key}`, `Authentication:ServiceApiKey` | Service-to-service auth | 🟡 টিমমেটের কাছ থেকে |
| `PaymentSettings`, `TSP`, `OneIdSettings`, `FirebasePushNotificationConfig` | শুধু সংশ্লিষ্ট ফিচার ডিবাগে | ⚪ প্রথমে বাদ দিতে পারেন |

লোকালে যা বদলাবেন: **DB আর Redis কিছুই না** (টেমপ্লেটের মানই ধাপ ১-এর স্ট্যাকে খাটে); `Services:*` চাইলে নিজের F5 পোর্ট (প্রিফিক্সসহ)। CORS-এ `http://localhost:4200/4201` আগেই যোগ করা আছে।

⚠️ **UserAuth-এ `UserSecretsId` নেই** — আগে চালান: `dotnet user-secrets init --project Services/UserAuth/ETP.UserAuth.Service`

### ধাপ ৪: বিল্ড (backend root থেকে)

```bash
dotnet build RVL-ETP.BackEnd.sln
```

কোনো `global.json`/`Directory.Build.props` নেই; NuGet restore ডিফল্ট nuget.org থেকে হবে।

### বিকল্প পথ: floci + Aspire — টিমের ফুল লোকাল স্ট্যাক (লাইভ-যাচাইকৃত ২০২৬-১০-২১)

ওয়ার্কস্পেসে টিমের বানানো দুটো জিনিস এটা: `floci/` (Floci — এক কন্টেইনারে local AWS emulator: S3, SQS, SES, Cognito; পোর্ট 4566, ওয়েব UI 4500) আর `aspire/Etp.AppHost` (postgres + redis + DynamoDB Local কন্টেইনার + ১১টা সার্ভিস একসাথে, ফিক্সড পোর্ট **5101–5111**, Aspire dashboard)। নিচে প্রতিটা কমান্ড কোন ফোল্ডার থেকে দেবেন সেটাসহ পুরো ফ্লো:

#### ক০. একবারের প্রস্তুতি (নতুন মেশিনে)

টুল চেক: Docker Desktop চালু, **.NET 10 SDK** (AppHost নিজে net10.0-এর), `pwsh` + AWS CLI v2 (seed-এর জন্য)। তারপর floci চালু করে seed:

```bash
cd D:\Workspace\Sources\RVL\rvl-etp\rvl-etp-workspace
pwsh ./scripts/Setup-EtpHttps.ps1  # একবার: HTTPS proxy-র সার্টিফিকেট
docker compose up -d        # Postgres + Redis + DynamoDB + floci + UI কন্টেইনার (floci-র ডেটা etp-floci-data volume-এ থাকে)
pwsh ./scripts/Seed-EtpFloci.ps1       # S3 bucket etp-local + ৬টা SQS queue + SES identity
pwsh ./scripts/Seed-EtpCognitoUsers.ps1 # ৪টা Cognito pool + client + টেস্ট ইউজার — আউটপুটের PoolId/ClientId কপি করুন
```

টেস্ট ইউজার (password `Passw0rd!23`, username = ফোন): Admin `+8801700000001`, User `+8801700000011`, TicketChecker `+8801700000021`, Agent `+8801700000031`।

এরপর নিচের **Secrets-টেবিলের** মানগুলো প্রতিটা AWS-ব্যবহারকারী সার্ভিসের user-secrets-এ বসান (এই মেশিনে ১০ সার্ভিসে বসানোই আছে)।

#### ক১. প্রতিদিন স্ট্যাক চালু (aspire ফোল্ডার থেকে)

```bash
cd D:\Workspace\Sources\RVL\rvl-etp\rvl-etp-workspace\aspire
dotnet run --project Etp.AppHost
```

- প্রথমবার ~৪–৬ মিনিট (docker ইমেজ-ডাউনলোড + বিল্ড); পরের বার অনেক দ্রুত।
- কনসোলে **dashboard login URL** ছাপা হবে (`http://localhost:15888/login?t=...`) — ব্রাউজারে খুলুন; সব রিসোর্সের স্ট্যাটাস, log, trace, console এক জায়গায়।
- সার্ভিসগুলো 5101–5111-এ (Admin 5101, Booking 5102, Event 5103 … UserIssue 5110, Utility 5111); ইনফ্রা: postgres (একক `etp` DB, volume `etp-postgres-data`, password `etp-local-pg`), Redis, DynamoDB Local :8000, pgAdmin, RedisInsight।
- এ পথে সার্ভিসের নিজের connection-string secret **লাগে না** — AppHost env var দিয়ে সব বসিয়ে দেয় (নিচের "AppHost নিজে যা দেয়")।
- দ্রুত যাচাই: dashboard-এ সবাই `Running`, বা `curl http://localhost:5101/health`।

> ⚠️ **আজকের বাস্তব সীমা**: secrets-এ floci-মান বসানো থাকলে **প্রতিটা HTTP রিকোয়েস্ট 500** হবে — কারণ নিচের "ফাঁক ১" (RequireHttpsMetadata)। স্ট্যাক উঠবে, মাইগ্রেশন আর worker চলবে, কিন্তু API কল করার আগে ওই ফিক্সটা সাবমডিউল-PR-এ আসতে হবে। floci-মান না বসালে endpoint স্বাভাবিক চলে, কিন্তু তখন AWS-জাতীয় ফিচার কাজ করবে না।

#### ক২. Visual Studio দিয়ে ডিবাগ (backend sln + Attach to Process)

1. VS-এ খুলুন `rvl-gobcb-backend\RVL-ETP.BackEnd.sln` — যেখানে দরকার breakpoint বসান।
2. টার্মিনালে ক১-এর কমান্ড দিয়ে স্ট্যাক চালু করুন।
3. VS-এ **Debug → Attach to Process…** → লিস্টে `ETP.Booking.Service`-জাতীয় প্রসেস খুঁজে (Ctrl+click-এ একসাথে একাধিক) **Attach** করুন।
4. Breakpoint বাঁধবে — source আর PDB ওই খোলা sln-এই আছে, প্রসেস শুধু টার্মিনালের।

- VS Code-এ: Run and Debug → "Attach to .NET Process" — একই কাজ।
- ⚠️ সার্ভিস চালু অবস্থায় VS থেকে Build/F5 করবেন না — bin ফাইল-লক হয়ে build error (একবার ঘটেছে)।
- রোজ পুরো-স্ট্যাক ডিবাগ করতে হলে `aspire/`-এ একটা wrapper sln বানানো যায় (AppHost + ৪৯ প্রজেক্ট; সাবমডিউল অপরিবর্তিত) — তখন AppHost-এ F5 দিলেই সব সার্ভিস ডিবাগারে ওঠে।

#### ক৩. বন্ধ করা

- AppHost-এর টার্মিনালে **Ctrl+C** — সার্ভিস-প্রসেসগুলো বন্ধ হবে।
- `docker ps` দেখুন: এলোমেলো সাফিক্স-নামের ইনফ্রা-কন্টেইনার (যেমন `postgres-xxxxx`) থেকে গেলে `docker rm -f <নাম>` — কিন্তু `etp-postgres-data` / `etp-redis-data` **volume রাখুন**, পরের রানে ডেটা ফিরে আসবে।
- floci-জোড়া আলাদা — বন্ধ না করলেও চলবে (`restart: unless-stopped`)।

**Secrets-এ যা বসবে** (প্রতিটা AWS-ব্যবহারকারী সার্ভিসের user-secrets-এ; এই মেশিনে ১০ সার্ভিসে বসানোই আছে):

| Key | মান |
|---|---|
| `AWS:Region` / `AWS:AccessKey` / `AWS:SecretAccessKey` | `ap-southeast-1` / `test` / `test` |
| `AWS:Bucket:Name` / `AWS:Bucket:BaseUrl` | `etp-local` / `http://localhost:4566` (কোড এটাকেই S3 ServiceURL ধরে) |
| `AWS:Queue:OrderSuccess` … (৬টা) | queue-এর **নাম** — URL নয় (কোড `GetQueueUrl` করে) |
| `AWS:CognitoPool:{Admin,User,TicketChecker,Agent}:PoolId` / `:ClientId` | `Seed-EtpCognitoUsers.ps1`-এর আউটপুট থেকে |
| `AWS:CognitoPool:X:Authority` / `:Metadata` | `http://localhost:4566/<PoolId>` / `http://localhost:4566/<PoolId>/.well-known/openid-configuration` |

এই মেশিনের বর্তমান মান (উদাহরণ): Admin pool `ap-southeast-1_2a67fbbf0` / client `f965366831814296abb70a9b65`; User pool `ap-southeast-1_656aa721c` / client `27c371e0e0544671a0e1736e88`। ⚠️ `docker compose down -v` করলে আইডি বদলে যায় — আবার seed করে নতুন মান বসাতে হবে।

**AppHost নিজে যা দেয়** (env var — user-secrets-কে override করে): `ConnectionStrings:*` → নিজের postgres-এর **একক `etp` DB** (password `etp-local-pg`, volume `etp-postgres-data` — তাই সার্ভিসগুলোর নিজের connection-secret এ পথে অগ্রাহ্য), password-হীন Redis, `Services:*` → `http://localhost:5101–5111`, DynamoDB Local :8000 (Ticketing-এর জন্য), `ASPNETCORE_ENVIRONMENT=Development`, আর `AWS_ENDPOINT_URL=http://localhost:4566` — শেষোক্তটা এ টেস্টে AppHost-এ যোগ করা হয়েছে, যাতে SQS/SES/Cognito কল ফ্লোসিতে যায়। AppHost ছাড়া একক সার্ভিস চালালে শেলে নিজে দিন: `$env:AWS_ENDPOINT_URL="http://localhost:4566"`।

**লাইভ-যাচাইয়ের ফল (২০২৬-১০-২১)**: ১১ সার্ভিসের পোর্টই উঠেছিল, শেয়ার্ড `etp` DB-তে ১২৯টা মাইগ্রেশন apply হয়েছিল, dashboard কাজ করেছিল। সাথে দুটো ব্লকার ধরা পড়েছে — নিচের ১ নম্বরটা না মেটালে floci-পথে authenticated কল হয় না:

1. **http metadata ব্লকড (কোড-চেঞ্জ লাগবে)**: floci-র Cognito URL http বলে JwtBearer-এর `RequireHttpsMetadata` (ডিফল্ট true) প্রতিটা রিকোয়েস্ট 500 করে দেয়। ফিক্স: `Core\ETP.Core\Configuration\DefaultAuthenticationConfig.cs`-এর ৪টা Cognito স্কিমে `options.RequireHttpsMetadata = false;` (dev-only)। টেম্পরারি প্যাচে পরীক্ষিত — health/swagger 500 → 200। ⚠️ এই ফিক্স **সাবমডিউলের নিজের repo-তে PR করে আসতে হবে** — ওয়ার্কস্পেস থেকে সাবমডিউল এডিট করা কড়া নিয়মে নিষিদ্ধ (AGENTS.md দেখুন)।
2. **floci-টোকেনে `client_id` claim নেই**: ইউজার লগইনে সঠিক টোকেন ইস্যু হয় (issuer/JWKS/RS256 ঠিক), কিন্তু floci সব টোকেন ID-token আকারে দেয় — `AudienceValidator`-এর চাওয়া `client_id` claim নেই → 401। Emulator-এর fidelity gap; ফিক্স করতে হলে emulator/ভ্যালিডেটর দুই-এর একটা বদলাতে হবে।

## ৬. রান ও ডিবাগ

### ৬.১ CLI দিয়ে একটা সার্ভিস (backend root থেকে)

```bash
dotnet run --project Services/Admin/ETP.Admin.Service/ETP.Admin.Service.csproj
```

বাকিদের path একই প্যাটার্নে: `Services/Booking/ETP.Booking.Service/ETP.Booking.Service.csproj`, `Services/Event/...`, `Services/Ticketing/...`, `Services/TicketChecker/...`, `Services/Scheduler/...`, `Services/Utility/...`, `Services/PushNotification/...`, `Services/UserIssue/...`

### ৬.২ Visual Studio দিয়ে (ডিবাগের মূল পথ)

1. `rvl-gobcb-backend\RVL-ETP.BackEnd.sln` খুলুন।
2. **একটা সার্ভিস**: Solution Explorer-এ `ETP.<X>.Service` → রাইট-ক্লিক → *Set as Startup Project* → **F5**। `launchSettings.json`-এর `launchUrl` ঠিক থাকায় ব্রাউজারে সরাসরি Swagger খুলবে।
3. **একাধিক সার্ভিস**: solution-এর নামায় রাইট-ক্লিক → *Properties* → *Startup Project* → **Multiple startup projects** → যেগুলো লাগবে সেগুলোতে **Start** → OK → F5। (এই সেটিং `.vs` ফোল্ডারে রাখা হয়, একবার সেট করলেই থাকে।)
4. **Aspire-স্ট্যাক ডিবাগ করতে চাইলে**: এই F5-পথ নয় — §৫-এর "বিকল্প পথ" → ক২ অনুসরণ করুন (backend sln খোলা রাখুন, স্ট্যাক টার্মিনালে চালু, তারপর **Attach to Process**)।

### ৬.৩ প্রথম রানের আগে একটা ফিক্স + পোর্ট-সতর্কতা

- `Services/Utility/ETP.Utility.Service/Properties/launchSettings.json` **Scheduler থেকে কপি-পেস্ট করা** — পোর্ট 5033/7005 আর launchUrl `scheduler/swagger`, সব ভুল। ইউনিক পোর্ট (যেমন 5014) আর `utility/swagger` দিন।
- **https প্রোফাইলে ক্ল্যাশ**: Ticketing ও PushNotification দুজনেরই 7007; Scheduler ও Utility দুজনেরই 7005। একসাথে https-এ চালালে একজন উঠবে না — **http প্রোফাইলেই কাজ চালান** (প্রোডাকশনে TLS ALB দেয়)।

### ৬.৪ Swagger URL টেবিল (http প্রোফাইল)

| সার্ভিস | URL |
|---|---|
| Admin | `http://localhost:5099/admin/swagger` |
| Booking | `http://localhost:5086/booking/swagger` |
| Event | `http://localhost:5001/event/swagger` |
| Ticketing | `http://localhost:5112/ticketing/swagger` |
| TicketChecker | `http://localhost:5274/ticketchecker/swagger` |
| PushNotification | `http://localhost:5007/swagger` |
| UserIssue | `http://localhost:56775/userissue/swagger` |
| Scheduler / Utility | controller নেই — শুধু `/health` |

**রাউট সবসময় প্রিফিক্সসহ** (`/booking/api/v1/...`) — `GlobalRoutePrefixConvention` `Application:ServiceName` থেকে প্রিফিক্স বসায়।

### ৬.৫ স্টার্টআপ আচরণ (যাচাইকৃত বুট-চেইন)

Booking-এর `Program.cs`: JWT auth → Serilog (console) → Redis cache + DataProtection (**eager connect**, `Core\ETP.Core\Configuration\RedisConfig.cs:31`) → RedLock → SQS publisher → `AddDependencies` (typed HttpClients + DbContext + workers) → শেষে `app.MigratePendingDatabase(...)` → middleware। অর্থাৎ:

- **সার্ভিস উঠছে না মানে এই ক্রমে চেক**: Redis চালু? → `Cache:Redis:*`/`DistributedLock:Redis:*` দেওয়া? → DB reachable?
- **Cognito স্টার্টআপে লাগে না** — JWKS প্রথম `[Authorize]` রিকোয়েস্টে fetch হয়। Swagger/`/health` anonymous।
- **SQS worker-রা** ভ্যালিড কিউ না পেলে ব্যাকগ্রাউন্ডে error লগ করে, API ডিবাগ চলতে থাকে।
- **অটো-মাইগ্রেশন**: Admin, Booking, Event, PushNotification, Ticketing, UserIssue স্টার্টআপেই pending মাইগ্রেশন apply করে (`<Storage>/Extensions|Extentions/*StorageExtensions.cs`)।

## ৭. মাইগ্রেশন ও স্কিমা

**সাধারণত কিছু করতে হয় না** — উপরের ৬টা সার্ভিস F5 করলেই স্কিমা নিজে থেকে তৈরি হয়। সার্ভিস না চালিয়ে আগেই স্কিমা নামাতে চাইলে (backend root থেকে) — **`--context` লাগবেই**: প্রতিটা সার্ভিসের DI-তে নিজের context-এর পাশে Core-এর `LoggingDbContext`-ও রেজিস্টারড (`dotnet ef dbcontext list -p ... -s ...`-এ দুটোই দেখা যায় — যাচাইকৃত ২০২৬-১০-২১), `--context` ছাড়া EF "More than one DbContext was found" বলে আটকাবে:

```bash
dotnet ef database update -p Services/Admin/ETP.Admin.Storage -s Services/Admin/ETP.Admin.Service --context AdminDbContext
dotnet ef database update -p Services/Admin/ETP.Admin.Storage -s Services/Admin/ETP.Admin.Service --context LoggingDbContext   # Core-এর ActivityLogs (৩টা মাইগ্রেশন) — Admin-এর connection-এই বসে (কোডও তাই করে)
dotnet ef database update -p Services/Booking/ETP.Booking.Storage -s Services/Booking/ETP.Booking.Service --context BookingDbContext
dotnet ef database update -p Services/Ticketing/ETP.Ticketing.Storage -s Services/Ticketing/ETP.Ticketing.Service --context TicketingDbContext
dotnet ef database update -p Services/PushNotification/ETP.PushNotification.Storage -s Services/PushNotification/ETP.PushNotification.Service --context PushNotificationDbContext
dotnet ef database update -p Services/UserIssue/ETP.UserIssue.Storage -s Services/UserIssue/ETP.UserIssue.Service --context UserIssueDbContext
```

লাইভ-যাচাইকৃত ২০২৬-১০-২১: ধাপ ১-এর স্ট্যাক + secrets টেমপ্লেট অপরিবর্তিত রেখে এই ছয় কমান্ডেই এক `etp_local`-এ ৭ কনটেক্সটের ১২৯টা মাইগ্রেশন apply হয় (৫৩টা টেবিল)।

README-র সাথে দুটো পার্থক্য (রিপো ঘেঁটে প্রমাণিত):
- README Event ও TicketChecker-এর জন্যও এই কমান্ড দেখায়, কিন্তু **এই দুই Storage প্রজেক্টে কোনো Migrations ফোল্ডার নেই** — কমান্ড no-op। তাদের স্কিমা কোথা থেকে আসে রিপো থেকে বলা সম্ভব নয় ([§১৩](#১৩-অযাচাইকৃত-বিষয়-এবং-টিমকে-করার-প্রশ্নের-লিস্ট) দেখুন)।
- README PushNotification/UserIssue-এর কমান্ড দেয়নি — উপরে যোগ করা আছে।

নতুন মাইগ্রেশন বানাতে (উদাহরণ, Booking — এখানেও `--context` লাগবে): `dotnet ef migrations add <Name> -p Services/Booking/ETP.Booking.Storage -s Services/Booking/ETP.Booking.Service --context BookingDbContext` — একই প্যাটার্ন অন্যদের।

## ৮. কোন ফিচার টেস্টে কোন সার্ভিস চালাবেন

| সিনারিও | চালাতে হবে | অতিরিক্ত দরকার |
|---|---|---|
| পাবলিক ইভেন্ট/লিস্টিং API | Event | তার DB-তে ডেটা (স্কিমা-উৎস প্রশ্নটা দেখুন) |
| বুকিং ফ্লো (সিট, প্রোমো, পেমেন্ট) | Booking + Event + Ticketing | Redis (সিট লক), পেমেন্ট কনফিগ |
| অ্যাডমিন-পোর্টাল ফিচার | Admin + ফিচার অনুযায়ী Event/Booking/Ticketing | Cognito Admin pool |
| পুশ নোটিফিকেশন | PushNotification + Scheduler | Scheduler-এ Firebase service-account JSON |
| টিকিট PDF/মার্জ/জিপ | Ticketing + Utility | S3 + TSP কনফিগ |
| ইস্যু/চ্যাট | UserIssue (+Admin) | SignalR `/userissue/chathub` |
| গেট-স্ক্যান সিঙ্ক | TicketChecker (+Ticketing) | TicketChecker DB |

Frontend-ও চালাতে চাইলে: admin-portal `ng serve` (localhost:4200); তার `environment.ts` লোকাল পোর্ট 5101/5102/5108/5110 ধরে রাখছে — ম্যানুয়াল F5 পোর্ট ব্যবহার করলে `src/environments/environment.ts` বদলান বা পোর্ট মিলিয়ে নিন।

## ৯. ডিবাগিং গাইড

### ৯.১ `[Authorize]` endpoint টেস্ট (রেসিপি লাইভ-যাচাইকৃত ২০২৬-১০-২১)

1. **Service টোকেন — পুরোপুরি কাজ করে**: `GET http://localhost:5099/admin/api/v1/token` + হেডার `ServiceApiKey: <Authentication:ServiceApiKey-এর মান>` → `{ "access_token": "..." }` — ১ দিনের HS256 JWT (যাচাইকৃত: সঠিক key-এ 200, ভুল/শূন্য key-এ 401 "Invalid Service API Key", signature/issuer/audience কনফিগের সাথে মিলেছে)। তবে জেনে রাখুন: **এখনো কোনো endpoint-এ Service-policy নেই** আর `ServiceApiKeyTokenProvider`-ও কোথাও ব্যবহৃত নয় — পুরো ফ্লোটা ভবিষ্যতের জন্য বানানো।
2. **Cognito টোকেন (ইউজার-কনটেক্সট)**: dev portal-এ লগইন করে ব্রাউজার storage থেকে access token নিন, অথবা floci থেকে CLI দিয়ে — `aws cognito-idp admin-initiate-auth --user-pool-id <UserPoolId> --client-id <ClientId> --auth-flow ADMIN_USER_PASSWORD_AUTH --auth-parameters USERNAME='+8801700000011',PASSWORD='Passw0rd!23'` (endpoint 4566) → `Authorization: Bearer <token>`। ⚠️ §৫-এর দুটো ব্লকার (RequireHttpsMetadata + floci-র `client_id` gap) মেটানো না হলে floci-টোকেনে 401 আসবে।
3. **নেগেটিভ টেস্ট প্যাটার্ন**: টোকেন-ছাড়া → 401; ভুল টোকেন → 401। `WWW-Authenticate: Bearer error="invalid_token"`-এর `error_description` দেখুন — যেমন "The audience 'x' is invalid" মানে ভ্যালিডেশন audience-চেক পর্যন্ত পৌঁছেছে (signature/issuer পার হয়েছে)। ডিবাগের সময় মনে রাখুন: `DefaultAuthenticateScheme=Admin` প্রতি রিকোয়েস্টে চলে বলে এরর-বার্তা অন্য স্কিমেরটাও দেখাতে পারে।

### ৯.২ Worker-only সার্ভিস (Scheduler/Utility) ডিবাগ

এদের controller নেই। `Workers/BackgroundServices/*.cs` আর `Workers/TaskManagers/*.cs`-এ **breakpoint** বসান — SQS-এ মেসেজ এলে হিট করবে। লাইভ চেক: `http://localhost:<পোর্ট>/health`।

### ৯.৩ কাজে লাগার ট্রিক

- **সার্ভিস-চেইন ডিবাগ**: এক সার্ভিস থেকে আরেক সার্ভিসে কলে `DelegatedBearerAuthenticationHandler` ইউজারের টোকেন ফরওয়ার্ড করে — `Services:*` base URL ঠিক (প্রিফিক্সসহ) থাকলে চেইনজুড়ে ইউজার-কনটেক্সট পাবেন।
- **ActivityLog**: প্রতিটা DbContext-এ `ActivityLogInterceptor` বসানো — কে/কী/IP লগ হয়, ডিবাগে কাজে লাগে।
- ম্যাপিং লাইব্রেরি **Mapster** (README-তে AutoMapper লেখা — ভুল)।
- Booking-এ `ReservationStatusUpdateService` কোডে আছে কিন্তু DI-তে রেজিস্টার করা নেই (ডেড কোড) — ওটা নিয়ে বিভ্রান্ত হবেন না।

## ১০. ট্রাবলশুটিং

| উপসর্গ | কারণ → সমাধান |
|---|---|
| Startup-এই crash, Redis socket error | `etp-redis` বন্ধ → `docker start etp-redis`; বা `Cache:Redis:ConnectionString` মিসিং (NullReferenceException আসে) |
| `ConfigurationErrorsException` | `DistributedLock:Redis:{EndPoint,Port,Database}` দিন |
| মাইগ্রেশন/DB error বুটে | DB বানানো কি না (`CREATE DATABASE`), পোর্ট 5432 ফ্রি কি না, connection string ঠিক কি না |
| Event/TicketChecker-এ টেবিল নেই | এদের মাইগ্রেশন নেই — স্কিমার উৎস §১৩-এর প্রশ্ন |
| 401 / IDX এরর | Cognito config (`Authority/Metadata/ClientId`) + ইন্টারনেট; টোকেন সেই pool থেকেই এসেছে কি না |
| সার্ভিস-কলে connection refused | `Services:<Name>` প্রিফিক্সসহ ঠিক আছে কি না (যেমন `http://localhost:5086/booking`) |
| পোর্ট ব্যস্ত | launchSettings ক্ল্যাশ (Utility↔Scheduler 5033; Ticketing↔PushNotification 7007 https) |
| 6379-এ আগে থেকেই native Redis চলছে | সংঘর্ষ নেই — compose-এর Redis হোস্ট-পোর্ট 6380-এ। নিজে পোর্ট বদলালে (`ETP_REDIS_PORT=...`) সেটা `Cache:Redis:ConnectionString` ও `DistributedLock:Redis:Port`-এও দিন |
| ব্যাকগ্রাউন্ডে SQS error স্প্যাম | `AWS:Queue:*`/creds নেই — API ডিবাগ চলবে; দরকার না হলে ওই workerের `AddHostedService` সাময়িক কমেন্ট করুন |
| `docker-compose up` fail | স্বাভাবিক — compose ফাইলটা CI-র (ECR ভ্যারিয়েবল লাগে), লোকালে `dotnet run`/F5 ব্যবহার করুন |

## ১১. Teardown: কাজ শেষে সব বন্ধ ও রিসোর্স ক্লিনআপ

কতটা পরিষ্কার করতে চান তার ওপর নির্ভর করে লেভেল — যতটা দরকার ততটা নিন।

### লেভেল ১: শুধু বন্ধ (ডেটা থাকবে) — দিন শেষে সাধারণত এটাই যথেষ্ট

- **সার্ভিস**: VS-এ **Shift+F5** (Stop Debugging); CLI-তে চালালে প্রতিটা টার্মিনালে `Ctrl+C`।
- **ডিপেন্ডেন্সি** (workspace root থেকে):

```bash
docker compose stop        # বা আগের মতোই: docker stop etp-postgres etp-redis
```

ডেটা volume-এ সেভ থাকে — পরে `docker compose start` (বা `docker start etp-postgres etp-redis`) করলেই আগের অবস্থায় ফিরবে, DB আর মাইগ্রেশন নতুন করতে হবে না।

### লেভেল ২: ডাটাবেস রিসেট (স্কিমা+ডেটা মুছে ফ্রেশ শুরু)

> আগে সব সার্ভিস বন্ধ করুন — কেউ কানেক্টেড থাকলে `DROP` হবে না।

```bash
docker exec -it etp-postgres psql -U etp -c "DROP DATABASE etp_local WITH (FORCE);"
docker exec -it etp-postgres psql -U etp -c "CREATE DATABASE etp_local;"
```

এরপর সার্ভিস F5 করলেই (বা §৭-এর ম্যানুয়াল মাইগ্রেশন চালালেই) অটো-মাইগ্রেশন নতুন স্কিমা বানাবে। Redis-ও ফ্লাশ করতে চাইলে (সিট-লক, ক্যাশ — সব ক্লিয়ার):

```bash
docker exec -it etp-redis redis-cli FLUSHALL
```

### লেভেল ৩: পুরো লোকাল স্ট্যাক মুছে ফেলা

```bash
docker compose down        # workspace root থেকে — কন্টেইনার+নেটওয়ার্ক যাবে, ডেটা volume থাকবে
docker compose down -v     # সাথে etp-pgdata / etp-redis-data-ও — সব ডেটা মুছে যাবে
```

⚠️ `down -v`-এর পর নতুন `docker compose up -d` করলে সব খালি থেকে শুরু — `etp_local` অটো-তৈরি হবে ঠিকই, কিন্তু স্কিমা/ডেটা আবার গড়তে হবে (§৫-এর ধাপ ১ আর ৩–৪ আবার)। ম্যানুয়াল `docker run` পথে চালালে সমতুল্য: `docker rm -f etp-postgres etp-redis` (ও পথে ডেটাও কার্যত হারায়)।

### লেভেল ৪: মেশিন থেকে ETP-এর সব স্পেসিফিক জিনিস সরানো

- **user-secrets** (backend root থেকে, যে প্রজেক্টে দিয়েছেন): `dotnet user-secrets clear --project Services/Booking/ETP.Booking.Service` — বা `%APPDATA%\Microsoft\UserSecrets\`-এর সংশ্লিষ্ট GUID ফোল্ডারগুলো একসাথে মুছুন। ⚠️ টিমমেটের দেওয়া আসল মান মুছে গেলে আবার SSM/টিমমেটের কাছ থেকে আনতে হবে — দরকার হলে আগে ব্যাকআপ নিন।
- **বিল্ড আর্টিফ্যাক্ট** (backend root): `dotnet clean RVL-ETP.BackEnd.sln`; পুরোপুরি ফ্রেশ চাইলে প্রজেক্টগুলোর `bin`/`obj` মুছে আবার build।
- **VS লোকাল স্টেট**: `.vs` ফোল্ডার মুছলে multiple-startup কনফিগসহ VS-এর সেটিং রিসেট হবে।
- **dev certificate** (https trust করিয়ে থাকলে): `dotnet dev-certs https --clean`।

> ⚠️ `docker system prune` মেশিনের *সব* আনইউজড ইমেজ/কন্টেইনার/নেটওয়ার্ক মুছে দেয় — অন্য প্রজেক্টের জিনিসও যেতে পারে। নিজেরটা নাম ধরে `docker stop/rm etp-postgres etp-redis` করাই নিরাপদ।

## ১২. CI/CD সংক্ষেপ (লোকালের সাথে সম্পর্ক)

- AWS CodeBuild (`buildspec-dev/test/stage/prod.yml`): SSM থেকে appsettings নেয় → Docker ইমেজ → ECR → `envsubst`+`kubectl apply` (k8s manifests `deployment/k8s/<env>/`)।
- **dev/test-এ সিক্রেট ইমেজের ভেতরেই বেক হয়**; staging/prod-এ k8s Secret volume।
- CI-তে কোনো `dotnet build`/টেস্ট ধাপ নেই — কম্পাইল হয় Dockerfile-এর ভেতরে। **সলিউশনে কোনো টেস্ট প্রজেক্টই নেই।**

## ১৩. অযাচাইকৃত বিষয় এবং টিমকে করার প্রশ্নের লিস্ট

রিপো ঘেঁটে নিশ্চিত করা যায়নি — হ্যান্ডওভার কলে এগুলো জিজ্ঞেস করুন:

1. **আসল সিক্রেট/কনফিগ মান** — connection string-এর DB নাম, Cognito pool ID, SQS, পেমেন্ট/TSP/Firebase মান (SSM `/rvl/dev/*` বা টিমমেটের user-secrets)।
2. **Event ও TicketChecker-এর DB স্কিমা কে বানায়?** — এদের মাইগ্রেশন নেই; Event-এর মডেল Admin-ওয়ালা + Booking-ওয়ালা দুই ধরনের টেবিলই পড়ে। dev-এর DB dump নেওয়া লাগতে পারে।
3. **Event আর TicketChecker একই DB শেয়ার করে কি না** — মান দেখেই বলা যাবে (`Database=` অংশ মিলিয়ে)।
4. ~~লোকাল রানের পোর্ট-কনভেনশন~~ **নিষ্পন্ন (২০২৬-১০-২১)** — টিম Aspire স্ট্যাক ব্যবহার করে (`aspire/Etp.AppHost`: সার্ভিসগুলো 5101–5111-এ, floci AWS emulator 4566-এ); §৫-এর "বিকল্প পথ" অংশে বর্ণিত ও লাইভ-যাচাইকৃত।
5. **`Authentication:Jwt:Key` / `ServiceApiKey` / `SystemAccounts:Admin:Password`** কোথা থেকে পাবেন।
6. **floci-র দুটো ব্লকার** (§৫ দেখুন): `RequireHttpsMetadata=false` কোডে যোগ করা লাগবে (dev-only PR), আর floci-টোকেনে `client_id` claim নেই — টিম কোনটা বদলাবে (emulator vs validator) ঠিক করবে।
7. **User-পুল টোকেনে 200** এ টেস্টে পাওয়া যায়নি — স্কিম-চ্যালেঞ্জের জটিলতায় (নেগেটিভ/audience পরীক্ষা সত্য প্রমাণিত)। টিমের কারো সাথে ৫ মিনিট জয়েন্ট-ডিবাগে স্পট হয়ে যেতে পারে।

## ১৪. রেফারেন্স (মূল ফাইল)

| কী | ফাইল |
|---|---|
| সলিউশন | `rvl-gobcb-backend/RVL-ETP.BackEnd.sln` |
| Auth (5 scheme) | `Core/ETP.Core/Configuration/DefaultAuthenticationConfig.cs` |
| Authorization policies | `Core/ETP.Core/Configuration/AuthorizationConfig.cs` |
| রোল কনস্ট্যান্ট | `Core/ETP.Core/Constant/AppConstant.cs` |
| Redis eager connect | `Core/ETP.Core/Configuration/RedisConfig.cs:31` |
| রুট প্রিফিক্স কনভেনশন | `Core/ETP.Core/Conventions/GlobalRoutePrefixConvention.cs` |
| Connection key ম্যাপিং | প্রতিটা সার্ভিসের `Configurations/DependencyConfig.cs` (লাইন §৪-এর টেবিলে) |
| অটো-মাইগ্রেশন | `<Storage>/Extensions/*StorageExtensions.cs` + প্রতিটা `Program.cs` |
| SQS কিউ মেসেজ | `Core/ETP.Core/Queue/Messages/` |
| টাইপড service clients | `Core/ETP.Core/ServiceClient/` |
| Service টোকেন issuer | `Services/Admin/ETP.Admin.Service/Api/TokenIssuerController.cs` |
| k8s manifests | `deployment/k8s/{development,testing,staging,production}/` |
| CI buildspec + SSM নাম | `buildspec-dev.yml:10-20` |
| ব্যাকএন্ড README (সাবধান: SQL Server/AutoMapper প্রসঙ্গে ভুল আছে) | `rvl-gobcb-backend/README.md` |
| আর্কিটেকচার ডক | `rvl-gobcb-backend/ETP-Architecture-Diagram.md` |
| কোড রিভিউ প্রসেস | `rvl-gobcb-backend/CODE_REVIEW_PROCESS.md` |
