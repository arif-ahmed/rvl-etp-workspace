# RVL-ETP লোকাল ডেভেলপমেন্ট সেটআপ গাইড (বাংলা)

> **এই ডকুমেন্ট কার জন্য**: নতুন যোগ দেওয়া .NET ডেভেলপার, যিনি Windows মেশিনে একদম শূন্য থেকে RVL-ETP ব্যাকএন্ডটা সেটআপ করে চালাবেন, ডিবাগ করবেন, আর ফিচার টেস্ট করবেন।
>
> **তথ্যের উৎস**: এই গাইডের প্রতিটা দাবি `rvl-gobcb-backend` সাবমডিউলের সোর্স কোড, কনফিগ ও স্ক্রিপ্ট থেকে যাচাই করা। যেসব বিষয় রিপো থেকে নিশ্চিত করা যায়নি, সেগুলো শেষের [অযাচাইকৃত বিষয়](#১২-অযাচাইকৃত-বিষয়-এবং-টিমকে-করার-প্রশ্নের-লিস্ট) সেকশনে আলাদা করে চিহ্নিত।
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
| **Visual Studio 2022** (v17.10+) | সলিউশন VS2022 ফরম্যাটের; "ASP.NET and web development" workload লাগবে | |
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

**অ্যাসিঙ্ক্রোনাস = raw AWS SQS** (`ISqsPublisher` + polling `BackgroundService`):

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

## ৪. ডাটাবেস টোপোলজি: ৬টা আলাদা DB

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

**কেন এক DB-তে সব মিলিয়ে দেওয়া যায় না** (রিপো থেকে প্রমাণিত): ৭টা DbContext-ই একই স্কিমা `etp` (`DefaultSchema = "etp"` সবার কনস্ট্যান্টে) আর একই migrations history টেবিল `__EFMigrationsHistory` ব্যবহার করে। Admin আর Booking দুই মডেলেই একই নামের টেবিল আছে (`Events` — AdminDbContext.cs:51, BookingDbContext.cs:32; সাথে `Currencies`, `Discounts`, `PromoCodes` ইত্যাদি ~১০টা)। একই physical DB হলে দুই সার্ভিসের মাইগ্রেশন একই টেবিল আর history নিয়ে সংঘর্ষ করত — সিস্টেম চলতই না। Booking আর Ticketing শেয়ার করা **পারে** কারণ Ticketing-এর টেবিল (`Tickets`, `OfflineSoldTickets`, `TicketLayoutConfigs`) Booking-এর কোনো টেবিলের সাথে নামে সংঘর্ষ করে না।

**সব DB-তে স্কিমা `etp`-তেই তৈরি হবে** — মাইগ্রেশন নিজে বানাবে, আপনাকে স্কিমা বানাতে হবে না।

## ৫. ধাপে ধাপে সেটআপ

> **ডিরেক্টরি কনভেনশন**: নিচের বেশিরভাগ `dotnet` কমান্ড **backend root থেকে** চলবে:
> ```
> cd D:\Workspace\Sources\RVL\rvl-etp\rvl-etp-workspace\rvl-gobcb-backend
> ```
> (Git Bash ব্যবহার করলে: `cd /d/Workspace/Sources/RVL/rvl-etp/rvl-etp-workspace/rvl-gobcb-backend`)
> Docker কমান্ডগুলো যেকোনো ডিরেক্টরি থেকে চলবে।

### ধাপ ১: PostgreSQL + Redis চালানো (Docker — যেকোনো ডিরেক্টরি)

রিপোর `docker-compose.yaml`-এ শুধু ১১টা অ্যাপ-ইমেজ ডেফাইন করা (CI-তে ECR-এ push করার জন্য) — PostgreSQL/Redis **নেই**। নিজে দুটো কন্টেইনার চালান:

```bash
docker run -d --name etp-postgres -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:16
docker run -d --name etp-redis -p 6379:6379 redis:7
```

মেশিন রিস্টার্টের পর শুধু: `docker start etp-postgres etp-redis`

চালু আছে কি না চেক: `docker ps` (দুটোই `Up` দেখাতে হবে)।

### ধাপ ২: ৬টা খালি ডাটাবেস তৈরি (যেকোনো ডিরেক্টরি)

⚠️ **গুরুত্বপূর্ণ**: পুরো রিপোতে কোথাও `EnsureCreated`/`CREATE DATABASE` নেই — মাইগ্রেশন শুধু **স্কিমা** বানায়, ডাটাবেস **নিজে বানায় না** (যাচাইকৃত: `MigratePendingDatabase` শুধু `Database.Migrate()` কল করে)। তাই আগে খালি DB বানাতে হবে:

```bash
docker exec -it etp-postgres psql -U postgres -c "CREATE DATABASE etp_admin;"
docker exec -it etp-postgres psql -U postgres -c "CREATE DATABASE etp_booking;"
docker exec -it etp-postgres psql -U postgres -c "CREATE DATABASE etp_event;"
docker exec -it etp-postgres psql -U postgres -c "CREATE DATABASE etp_ticketchecker;"
docker exec -it etp-postgres psql -U postgres -c "CREATE DATABASE etp_pushnotification;"
docker exec -it etp-postgres psql -U postgres -c "CREATE DATABASE etp_userissue;"
```

দুটো কথা:
- **নামগুলো রিপোতে নেই** — আসল নাম থাকবে আপনার পাওয়া connection string-এ (`Database=...` অংশ)। উপরের নাম আপনার connection string-এর সাথে মিলিয়ে নিন।
- **Ticketing-এর আলাদা DB লাগবে না** — সে Booking-এর DB-ই ব্যবহার করে।

### ধাপ ৩: User Secrets ভরা (backend root থেকে)

রিপোর প্রতিটা `appsettings.json`-এ প্রতিটা মান লেখা `"[see User Secrets]"` — bin ফোল্ডারের কপিও তাই। **আসল মানের উৎস**: (ক) টিমমেটের মেশিনের user-secrets (`%APPDATA%\Microsoft\UserSecrets\`), অথবা (খ) AWS SSM:

```bash
aws ssm get-parameter --name /rvl/dev/admin-service-appsettings --with-decryption --query Parameter.Value --output text
aws ssm get-parameter --name /rvl/dev/booking-service-appsettings --with-decryption --query Parameter.Value --output text
# ... বাকিগুলো: /rvl/dev/event-, ticketchecker-, ticketing-, scheduler-, platform-,
#     userauth-, utility-, pushnotification-, userissue-service-appsettings  (buildspec-dev.yml:10-20)
```

SSM থেকে পাওয়া JSON-টা প্রতিটা সার্ভিসের user-secrets হিসেবে বসান (পোর্ট/হোস্ট লোকালের জন্য বদলে)। ভরার উপায় — VS-এ প্রজেক্টে রাইট-ক্লিক → **Manage User Secrets**, বা CLI:

```bash
# backend root থেকে
dotnet user-secrets set "ConnectionStrings:Booking" "Host=localhost;Port=5432;Database=etp_booking;Username=postgres;Password=postgres" --project Services/Booking/ETP.Booking.Service
dotnet user-secrets set "Cache:Redis:ConnectionString" "localhost:6379" --project Services/Booking/ETP.Booking.Service
dotnet user-secrets set "Cache:Redis:InstanceName" "ETP:" --project Services/Booking/ETP.Booking.Service
dotnet user-secrets set "DistributedLock:Redis:EndPoint" "localhost" --project Services/Booking/ETP.Booking.Service
dotnet user-secrets set "DistributedLock:Redis:Port" "6379" --project Services/Booking/ETP.Booking.Service
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

লোকালে যা বদলাবেন: connection string → `Host=localhost;Port=5432;...`, Redis → `localhost:6379`, `Services:*` → নিজের F5 পোর্ট (প্রিফিক্সসহ)। CORS-এ `http://localhost:4200/4201` আগেই যোগ করা আছে।

⚠️ **UserAuth-এ `UserSecretsId` নেই** — আগে চালান: `dotnet user-secrets init --project Services/UserAuth/ETP.UserAuth.Service`

### ধাপ ৪: বিল্ড (backend root থেকে)

```bash
dotnet build RVL-ETP.BackEnd.sln
```

কোনো `global.json`/`Directory.Build.props` নেই; NuGet restore ডিফল্ট nuget.org থেকে হবে।

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

**সাধারণত কিছু করতে হয় না** — উপরের ৬টা সার্ভিস F5 করলেই স্কিমা নিজে থেকে তৈরি হয়। সার্ভিস না চালিয়ে আগেই স্কিমা নামাতে চাইলে (backend root থেকে):

```bash
dotnet ef database update -p Services/Admin/ETP.Admin.Storage -s Services/Admin/ETP.Admin.Service
dotnet ef database update -p Services/Booking/ETP.Booking.Storage -s Services/Booking/ETP.Booking.Service
dotnet ef database update -p Services/Ticketing/ETP.Ticketing.Storage -s Services/Ticketing/ETP.Ticketing.Service
dotnet ef database update -p Services/PushNotification/ETP.PushNotification.Storage -s Services/PushNotification/ETP.PushNotification.Service
dotnet ef database update -p Services/UserIssue/ETP.UserIssue.Storage -s Services/UserIssue/ETP.UserIssue.Service
```

README-র সাথে দুটো পার্থক্য (রিপো ঘেঁটে প্রমাণিত):
- README Event ও TicketChecker-এর জন্যও এই কমান্ড দেখায়, কিন্তু **এই দুই Storage প্রজেক্টে কোনো Migrations ফোল্ডার নেই** — কমান্ড no-op। তাদের স্কিমা কোথা থেকে আসে রিপো থেকে বলা সম্ভব নয় ([§১২](#১২-অযাচাইকৃত-বিষয়-এবং-টিমকে-করার-প্রশ্নের-লিস্ট) দেখুন)।
- README PushNotification/UserIssue-এর কমান্ড দেয়নি — উপরে যোগ করা আছে।

নতুন মাইগ্রেশন বানাতে (উদাহরণ, Booking): `dotnet ef migrations add <Name> -p Services/Booking/ETP.Booking.Storage -s Services/Booking/ETP.Booking.Service` — একই প্যাটার্ন অন্যদের।

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

### ৯.১ `[Authorize]` endpoint টেস্ট

1. **Cognito টোকেন (ইউজার-কনটেক্সট)**: dev-এর portal-এ লগইন করে ব্রাউজার storage থেকে access token নিয়ে Swagger-এ Authorize করুন।
2. **Service টোকেন**: `GET http://localhost:5099/admin/api/v1/token`, হেডার `ServiceApiKey: <মান>` → ১ দিনের JWT → `[Authorize(Policy=AuthScheme.Service)]` endpoint-এ।

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
| Event/TicketChecker-এ টেবিল নেই | এদের মাইগ্রেশন নেই — স্কিমার উৎস §১২-এর প্রশ্ন |
| 401 / IDX এরর | Cognito config (`Authority/Metadata/ClientId`) + ইন্টারনেট; টোকেন সেই pool থেকেই এসেছে কি না |
| সার্ভিস-কলে connection refused | `Services:<Name>` প্রিফিক্সসহ ঠিক আছে কি না (যেমন `http://localhost:5086/booking`) |
| পোর্ট ব্যস্ত | launchSettings ক্ল্যাশ (Utility↔Scheduler 5033; Ticketing↔PushNotification 7007 https) |
| ব্যাকগ্রাউন্ডে SQS error স্প্যাম | `AWS:Queue:*`/creds নেই — API ডিবাগ চলবে; দরকার না হলে ওই workerের `AddHostedService` সাময়িক কমেন্ট করুন |
| `docker-compose up` fail | স্বাভাবিক — compose ফাইলটা CI-র (ECR ভ্যারিয়েবল লাগে), লোকালে `dotnet run`/F5 ব্যবহার করুন |

## ১১. CI/CD সংক্ষেপ (লোকালের সাথে সম্পর্ক)

- AWS CodeBuild (`buildspec-dev/test/stage/prod.yml`): SSM থেকে appsettings নেয় → Docker ইমেজ → ECR → `envsubst`+`kubectl apply` (k8s manifests `deployment/k8s/<env>/`)।
- **dev/test-এ সিক্রেট ইমেজের ভেতরেই বেক হয়**; staging/prod-এ k8s Secret volume।
- CI-তে কোনো `dotnet build`/টেস্ট ধাপ নেই — কম্পাইল হয় Dockerfile-এর ভেতরে। **সলিউশনে কোনো টেস্ট প্রজেক্টই নেই।**

## ১২. অযাচাইকৃত বিষয় এবং টিমকে করার প্রশ্নের লিস্ট

রিপো ঘেঁটে নিশ্চিত করা যায়নি — হ্যান্ডওভার কলে এগুলো জিজ্ঞেস করুন:

1. **আসল সিক্রেট/কনফিগ মান** — connection string-এর DB নাম, Cognito pool ID, SQS, পেমেন্ট/TSP/Firebase মান (SSM `/rvl/dev/*` বা টিমমেটের user-secrets)।
2. **Event ও TicketChecker-এর DB স্কিমা কে বানায়?** — এদের মাইগ্রেশন নেই; Event-এর মডেল Admin-ওয়ালা + Booking-ওয়ালা দুই ধরনের টেবিলই পড়ে। dev-এর DB dump নেওয়া লাগতে পারে।
3. **Event আর TicketChecker একই DB শেয়ার করে কি না** — মান দেখেই বলা যাবে (`Database=` অংশ মিলিয়ে)।
4. **লোকাল রানের পোর্ট-কনভেনশন** — admin-portal-এর `environment.ts` ".NET Aspire local stack (`aspire/Etp.AppHost`)" দেখায় (পোর্ট 5101/5102/5108/5110)। ওয়ার্কস্পেসের `aspire/` ও `floci/` (local AWS emulation) ফোল্ডার দুটি এই গাইডের স্কোপের বাইরে ছিল; টিম আসলে কোন পথে লোকাল ডেভ করে জেনে নিন।
5. **`Authentication:Jwt:Key` / `ServiceApiKey` / `SystemAccounts:Admin:Password`** কোথা থেকে পাবেন।

## ১৩. রেফারেন্স (মূল ফাইল)

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
