# RVL ETP (GoBCB) — Knowledge Transfer (KT) রোডম্যাপ

**তৈরি:** 2026-10-23
**কার জন্য:** নতুন যোগ দেওয়া .NET সফটওয়্যার ইঞ্জিনিয়ার, যিনি এই ইভেন্ট টিকিটিং প্ল্যাটফর্মের (GoBCB) মালিকাভার নেবেন
**মোট সময়:** আনুমানিক ১২ সপ্তাহ — ৩৬টি সেশন (প্রতিটি সেশন ≈ আধা দিনের ব্লক)
**সত্যের উৎস:** এই workspace-এর docs ও ৫টি submodule-এর কোড; প্রতিটি সেশনে নির্দিষ্ট ডকুমেন্ট ও কোড-এরিয়ার রেফারেন্স দেওয়া আছে

---

## ১. লক্ষ্য (Goal)

১২ সপ্তাহ শেষে আপনি হবেন একজন **কনফিডেন্ট .NET ইঞ্জিনিয়ার**, যিনি:

1. প্ল্যাটফর্মের **প্রায় সব বিজনেস লজিক জানেন** — ১০৩টি ফিচার-ডক কভার করা (ক্যাটালগ, ক্যাপাসিটি, বুকিং, পেমেন্ট, টিকিট জেনারেশন, গেট ভ্যালিডেশন, রিপোর্টিং, অথ/অথরাইজেশন, নোটিফিকেশন)।
2. **সবকিছু নিজ হাতে ডিবাগ ও টেস্ট করেছেন** — ১১টি ব্যাকএন্ড সার্ভিস লোকালি চালিয়ে, ব্রেকপয়েন্ট বসিয়ে, ৫টি ক্লায়েন্ট অ্যাপ (২টি Angular পোর্টাল + ২টি Flutter অ্যাপ) ম্যানুয়ালি চালিয়ে।
3. **প্রতিটি if-and-but জানেন** — edge case, race condition, failure path, বিকল্প ফ্লো (অফলাইন চ্যানেল, পেমেন্ট revalidation), ৭৫টি open query, legacy কোড।
4. **ইনসিডেন্ট হ্যান্ডেল করতে পারেন** — BPL 2025-এর ৯টি রিয়েল ইনসিডেন্টের কারণ জানেন, লোকালি সিমুলেট করেছেন, ট্রায়েজ ও ফিক্স করতে পারেন।
5. **নতুন ফিচার বা ইমপ্রুভমেন্ট কনফিডেন্টলি করতে পারেন** — কোন সার্ভিসে কী বদলাতে হবে, কোন টেবিলের write-owner কে, কোন ক্লায়েন্ট আপডেট লাগবে — সব ম্যাপ মাথায়।

## ২. সফলতার মাপকাঠি (Definition of Done)

রোডম্যাপ শেষ হলে নিচের চেকলিস্টের প্রতিটি আইটেমে সৎভাবে "হ্যাঁ" বলতে পারাই সাফল্য:

- [ ] কোনো সাহায্য ছাড়া সম্পূর্ণ প্ল্যাটফর্ম লোকালি চালাতে পারি (Floci + Docker + Aspire AppHost, ১১ সার্ভিস healthy)।
- [ ] এক পাতায় সিস্টেমের আর্কিটেকচার ও একটি টিকিটের পূর্ণ জীবনচক্র মুখস্থভাবে এঁকে দেখাতে পারি।
- [ ] শূন্য থেকে একটি ইভেন্ট তৈরি করে টিকিট বিক্রি → জেনারেশন → ডাউনলোড → গেট-এ scan পর্যন্ত পুরো চেইন একা চালাতে পারি।
- [ ] একটি বুকিং-সংক্রান্ত bug দিলে Controller → Manager → Repository ধরে কোড ট্রেস করে কারণ বের করতে পারি।
- [ ] পেমেন্ট fail, ticket generation stuck, checker false-rejection, capacity race — এই ইনসিডেন্টগুলোর ট্রায়েজ করতে পারি।
- [ ] প্রতিটি টেবিলের write-owner সার্ভিস বলতে পারি (schema change workflow সহ)।
- [ ] র‍্যান্ডম যেকোনো ফিচার-ডক ধরে দিলে ব্যাখ্যা + কোড trace + লোকাল টেস্ট দেখাতে পারি।
- [ ] একটি ছোট ফিক্স/ইমপ্রুভমেন্ট PR সাবমডিউলের নিজ রিপোতে দিতে পারি।

## ৩. এই রোডম্যাপ যেভাবে ব্যবহার করবেন

### সেশনের ফরম্যাট (প্রতিটি সেশনে একই ছন্দ)

1. **পড়া** — সেশনে উল্লেখিত ফিচার-ডক/ডকুমেন্ট পড়ুন।
2. **কোড trace** — প্রতিটি ফিচার-ডকের **সেকশন 8 (Code references)**-এ file:line রেফারেন্স দেওয়া থাকে; সেগুলো ধরে submodule-এর কোড খুলে ফ্লো অনুসরণ করুন।
3. **হাতে-কলমে টেস্ট** — ফিচার-ডকের **সেকশন 11 (Developer test guide)** বলে দেয় লোকালি কীভাবে পরীক্ষা করবেন; প্রতিটি ফিচার **অবশ্যই নিজে চালিয়ে** দেখুন — শুধু পড়ে গেলে কাজ হবে না।
4. **নোট** — নিজের শেখার নোটে প্রতি সেশনের ৩-৫ লাইন লিখুন (কী শিখলাম, কোথায় অবাক হলাম, কোন প্রশ্ন জমল)।

### ডক-রেফারেন্স কনভেনশন

`A-07`, `P-06`, `U-04`, `C-03`, `S-08`, `X-25` — এগুলো ফিচার-ডকের ID, ফাইলগুলো এখানে:
`docs/handover/feature-docs/bn/<গ্রুপ-ফোল্ডার>/<ID>-<নাম>.md`
যেমন `A-07` মানে `docs/handover/feature-docs/bn/10-admin-portal/A-07-events.md`। বাংলা ট্রি-ই পড়ুন — কোড identifier, endpoint, টেবিল-নাম ইংরেজিতে রাখা আছে।

| গ্রুপ | অর্থ | সংখ্যা |
|---|---|---|
| `A-xx` | Admin portal (স্টাফ) ফিচার | 31 |
| `P-xx` | User portal (ওয়েব ক্রেতা) ফিচার | 13 |
| `U-xx` | User mobile app (Flutter) ফিচার | 10 |
| `C-xx` | Checker app (গেট স্টাফ, Flutter) ফিচার | 6 |
| `S-xx` | System-initiated (SQS worker/টাইমার) ফিচার | 17 |
| `X-xx` | Cross-cutting (অথ, রেডিস, নোটিফিকেশন...) ফিচার | 26 |

### সময়সূচি স্কেল করা

- **ডিফল্ট (১২ সপ্তাহ):** সপ্তাহে ৩টি সেশন, দিনে ৩-৪ ঘণ্টা — নিয়মিত কাজের পাশাপাশি।
- **ইনটেনসিভ (৬ সপ্তাহ):** দিনে ১-২টি সেশন, ফুল-টাইম।
- **ধীরগতি (১৬-১৮ সপ্তাহ):** সপ্তাহে ২ সেশন।
- সেশনের ক্রম **বদলাবেন না** — প্রতিটি ফেজ পরেরটির ভিত্তি। শুধু ফেজ ৩-এর ভেতরের সেশনগুলো (১১-২১) প্রয়োজনে পুনর্বিন্যাস করা যায়।
- সব সেশন সপ্তাহ-ভাগ সহ **এক টেবিলে** দেখতে সেকশন ১৩-এর মাস্টার টাইমলাইন দেখুন।

### মেন্টর চেকপয়েন্ট (ঐচ্ছিক কিন্তু দৃঢ়ভাবে প্রস্তাবিত)

প্রতিটি ফেজের শেষে "চেকপয়েন্ট" প্রশ্ন দেওয়া আছে। টিমের কোনো অভিজ্ঞ সদস্যের সাথে বসে এই প্রশ্নগুলোর উত্তর দিন — যা ব্যাখ্যা করতে না পারেন, সেটাই পরের ফেজের আগে পরিষ্কার করার তালিকা।

### সর্বদা মনে রাখুন (AGENTS.md নিয়ম)

- **সাবমডিউলের ভেতরে কোনো পরিবর্তন নয়** — পড়া, ডিবাগ, টেস্ট চলবে, কিন্তু edit/commit নয়। ফিক্স/ফিচার সাবমডিউলের **নিজস্ব রিপোতে PR**-এ যাবে।
- লোকাল এক্সপেরিমেন্ট থাকবে user-secrets, environment variable বা workspace-ফাইলে (`aspire/`, `floci/`, `docs/`, `scripts/`)।

## ৪. প্রস্তুতি-সামগ্রীর ম্যাপ

| কী | কোথায় |
|---|---|
| Workspace পরিচিতি ও সেটআপ | `README.md`, `docs/local-dev.md`, `docs/local-dev-setup.bn.md` |
| ফিচার ডকুমেন্টেশন (বাংলা) | `docs/handover/feature-docs/bn/` (১০৩টি ফিচার + primer/appendix) |
| ওভারভিউ ডক | `00-platform-primer.md`, `01-system-map.md`, `02-traceability-matrix.md`, `03-component-reverse-index.md` |
| AWS আর্কিটেকচার | `docs/architecture/gobcb-aws-architecture.md` |
| ডেটা/স্কিমা রেফারেন্স | `docs/knowledge_transfer_context.md` |
| রিয়েল ইনসিডেন্ট (BPL 2025) | `docs/live-experiences-and-uat-focus.md` |
| AWS অ্যাক্সেস/এনভায়রনমেন্ট | `docs/rvl-handover-AWS-access-summary.md` |
| কনফিগ রেফারেন্স | `docs/config-reference.md` |
| ক্লায়েন্ট লোকাল-রান গাইড | `docs/admin-portal-local.md`, `docs/user-portal-local.md`, `docs/mobile-local.md` |
| অথ-ফ্লো বিশ্লেষণ | `docs/admin-portal-auth-flow.md` |
| স্ক্রিপ্ট | `scripts/` — `Set-EtpSecrets.ps1`, `Seed-EtpData.ps1`, `Setup-*.ps1`, `Test-EtpLocal.ps1` |
| Postman কালেকশন | `postman/etp-cognito-auth.postman_collection.json`, `etp-login-all-pools.postman_collection.json` |
| ফিচার-ম্যাট্রিক্স (BS23 রিভিউ) | `docs/handover/feature-matrix/GoBCB-Feature-Matrix.xlsx` |

**ব্যাকএন্ড সার্ভিস ও লোকাল পোর্ট** (Aspire AppHost, সবাই একই `etp_local` PostgreSQL ডেটাবেস শেয়ার করে):

| সার্ভিস | পোর্ট | সার্ভিস | পোর্ট |
|---|---|---|---|
| Admin | 5101 | TicketChecker | 5107 |
| Booking | 5102 | Ticketing | 5108 |
| Event | 5103 | UserAuth | 5109 |
| Platform | 5104 | UserIssue | 5110 |
| PushNotification | 5105 | Utility | 5111 |
| Scheduler | 5106 | | |

প্রতিটি সার্ভিসের Swagger: `http://localhost:<পোর্ট>/swagger`, হেলথ: `http://localhost:<পোর্ট>/health`।

---

## ৫. ফেজ ০ — পরিবেশ ও ওরিয়েন্টেশন (সপ্তাহ ১)

> লক্ষ্য: পুরো প্ল্যাটফর্ম নিজের মেশিনে চালু। এই ফেজ ছাড়া পরের কিছুই হবে না।

### সেশন ১ — ওরিয়েন্টেশন: প্ল্যাটফর্ম ও workspace-মডেল

- **বিষয়:** GoBCB ইভেন্ট টিকিটিং প্ল্যাটফর্ম কী; ৫টি submodule (backend, admin portal, user portal, user app, checker app) ও orchestrator workspace-মডেল; Aspire + Floci + docker-compose — তিনটি লোকাল উপাদান; সাবমডিউল read-only নিয়ম।
- **পড়া:** `README.md` (§1-2), `AGENTS.md`, `docs/local-dev.md`।
- **হাতে-কলমে:** `git submodule status` ও `status.ps1` চালিয়ে ৫টি submodule-এর অবস্থা দেখুন; `docs/` ফোল্ডারটি একবার উপরে-নিচে স্ক্যান করুন — কোন ডক কোথায় আছে তার ধারণা নিন।
- **সেলফ-চেক:** ৫টি submodule কী কী, কে কী পড়ে? সাবমডিউলে কমিট করা যাবে না কেন? লোকালে কোন AWS-সার্ভিসগুলো Floci প্রতিস্থাপন করে?

### সেশন ২ — লোকাল এনভায়রনমেন্ট সেটআপ ও ১১টি সার্ভিস চালানো

- **পড়া:** `README.md` (§First-time setup / §4), `docs/local-dev-setup.bn.md` (বাংলা গাইড), `floci/QUICKSTART.md`, `scripts/user-secrets.example.json`।
- **হাতে-কলমে (ঠিক এই ক্রমে):**
  1. `docker compose up -d` — Postgres 16 + Redis 7 + DynamoDB Local।
  2. Floci চালু (`floci/`), তারপর `seed.ps1` ও `seed-users.ps1` — ৪টি Cognito pool + ৫টি স্টাফ ইউজার seeded হবে।
  3. `%USERPROFILE%\.etp-local\user-secrets.json` তৈরি ও `scripts/Set-EtpSecrets.ps1` দিয়ে সব সার্ভিসে প্রয়োগ।
  4. `AWS_ENDPOINT_URL=http://localhost:4566` সেট করে `dotnet run --project aspire/Etp.AppHost`।
  5. সব সার্ভিস Running হলে `pwsh ./scripts/Test-EtpLocal.ps1` (~২০ সেকেন্ড)।
  6. ডেটাবেসে যান: `select count(*) from etp."__EFMigrationsHistory";` — **129** হলে সব migration লেগেছে (Admin-ই আগে core টেবিল বানায়)।
- **সেলফ-চেক:** কোন সার্ভিস কোন পোর্টে (উপরের টেবিল মুখস্থ)? `ETP_SKIP=Booking` দিলে কী হয় (উত্তর: AppHost ওটা চালাবে না, আপনি IDE থেকে একই পোর্টে ব্রেকপয়েন্ট সহ চালাবেন)? সার্ভিস-টু-সার্ভিস কল `Services__*` env-var দিয়ে কীভাবে ঠিকানা পায়?

### সেশন ৩ — ক্লায়েন্ট অ্যাপ ও লগইন চালানো

- **পড়া:** `docs/admin-portal-local.md`, `docs/user-portal-local.md`, `docs/admin-portal-auth-flow.md`।
- **হাতে-কলমে:** `scripts/Setup-AdminPortal.ps1` ও `Setup-UserPortal.ps1` দিয়ে পোর্টাল দুটো চালান; seeded স্টাফ ইউজার দিয়ে admin portal-এ লগইন (OTP + পাসওয়ার্ড); user portal-এ একটি একাউন্ট খুলে লগইন; Postman-এ `etp-cognito-auth` ও `etp-login-all-pools` কালেকশন চালিয়ে ৪টি pool-এর টোকেন নিন; `scripts/Seed-EtpData.ps1` দিয়ে BCB ক্রিকেট টেস্ট-ডেটা seed করুন।
- **সেলফ-চেক:** ৪টি Cognito pool কী কী (User, Admin, TicketChecker, Agent)? অ্যাডমিন লগইনে OTP কোথা থেকে আসে (Floci SES)? JWT টোকেন jwt.io-তে খুলে `custom:role`, `custom:program_ids` claim দেখেছেন?

**চেকপয়েন্ট ০:** পুরো সিস্টেম আপনার মেশিনে চলছে — ১১ সার্ভিস healthy, দুই পোর্টালে লগইন করা, টেস্ট-ডেটা seeded। **যদি না হয়, পরের ফেজে যাবেন না** — পরের সব সেশন এই সেটআপের উপর দাঁড়িয়ে।

---

## ৬. ফেজ ১ — বড় ছবি: বিজনেস ডোমেইন ও আর্কিটেকচার (সপ্তাহ ১-২)

> লক্ষ্য: কোডে ডোবার আগে মানসিক মানচিত্র — বিজনেস কী, কীভাবে সাজানো, কোথায় চলে।

### সেশন ৪ — বিজনেস ডোমেইন ও শব্দকোষ

- **পড়া:** `docs/handover/feature-docs/bn/README.md`, `01-system-map.md`।
- **বিষয়:** Program (আয়োজক-সীমানা) → Team/Venue (Venue → VenueGallery → GalleryBlock → BlockLevel) → Event → ticket pricing/layout → booking → payment → ticket generation → download → gate validation; অ্যাক্টর: অ্যাডমিন স্টাফ, ওয়েব ইউজার, অ্যাপ ইউজার, গেট চেকার, এজেন্ট; অর্ডারের অবস্থা: Pending → Paid/Failed/Cancelled/Requested/Generated।
- **হাতে-কলমে:** `01-system-map.md` পড়ে **নিজে হাতে** এক পাতার টিকিট-জীবনচক্র ডায়াগ্রাম আঁকুন (ক্যাটালগ তৈরি → বিক্রি → জেনারেশন → গেট)। এই ডায়াগ্রামটা সেশন ২৭-এ আবার কাজে লাগবে।
- **সেলফ-চেক:** Program আর Event-এর পার্থক্য কী? Venue hierarchy-র স্তরগুলো বলুন। একটি টিকিট জন্ম থেকে গেট পর্যন্ত কোন কোন অবস্থার মধ্য দিয়ে যায়?

### সেশন ৫ — AWS আর্কিটেকচার

- **পড়া:** `docs/architecture/gobcb-aws-architecture.md` (পুরোটা)।
- **বিষয়:** ap-southeast-1, VPC 2 AZ; Route 53 → CloudFront (স্ট্যাটিক) / API Gateway → NLB → EKS (৯ সার্ভিস per AZ, nginx ingress, আলাদা chat ingress); Cognito ৪ pool + OneID external IdP; Aurora PostgreSQL, ElastiCache Redis, SQS, SES, S3, DynamoDB; সার্ভিস-টু-সার্ভিস HTTP (টোকেন forward, ৩ রিট্রাই); CI/CD: GitHub → CodeBuild → ECR → kubectl; SSM `/rvl/<env>/<service>-appsettings`।
- **সতর্কতা:** এই ডকে `[UNCONFIRMED]` চিহ্নিত ৬টি ওপেন প্রশ্ন আছে (API Gateway-Cognito মাঝে Lambda? Aurora multi-AZ? ইত্যাদি) — এগুলো **সত্য ধরে নেবেন না**, BS23-এর কাছে নিশ্চিত করা বাকি।
- **হাতে-কলমে:** একটি টেবিল বানান — প্রোডাকশনের প্রতিটি AWS সার্ভিসের বিপরীতে আপনার লোকাল বিকল্প কী (Cognito→Floci:4566, Aurora→Docker Postgres, ElastiCache→Docker Redis:6379, SQS→Floci, S3→Floci, DynamoDB→DynamoDB Local:8000)।
- **সেলফ-চেক:** ব্রাউজারের একটি API রিকোয়েস্ট EKS-এর পড পর্যন্ত কী কী স্তর পার করে? ব্যাকগ্রাউন্ড worker গুলো SQS থেকে কীভাবে কাজ পায় (static IAM key, unsigned message — security দৃষ্টিতে নোট রাখুন)?

### সেশন ৬ — মাইক্রোসার্ভিস ম্যাপ ও কোড-স্ট্রাকচার

- **পড়া:** `00-platform-primer.md` (মাইক্রোসার্ভিস নতুন হলে এটা আগে), `02-traceability-matrix.md`, `03-component-reverse-index.md`।
- **কোড এরিয়া:** `rvl-gobcb-backend/` — `Core/` (ETP.Core, ETP.Core.Web, ETP.Core.EntityFramework, ETP.Core.EventBus, ETP.Core.Storage, ETP.Core.BlobStorage, ETP.Core.SMS, ETP.Core.Email) এবং `Services/`-এর একটি সার্ভিস গভীরভাবে (সুপারিশ: Admin) — `Api/`, `Workers/`, `Resolver/`, `Resource/`, `Hubs/`; সাথে `*.Domain` (Managers — বিজনেস লজিক), `*.Storage` (DbContext, Migrations, Repositories)।
- **হাতে-কলমে:** ১১টি সার্ভিসের Swagger (`localhost:5101-5111/swagger`) ঘুরে প্রতিটির controller-সূচি দেখুন; `02-traceability-matrix.md` থেকে ৩টি ফিচার বেছে তাদের component-table-queue-Redis ম্যাপ কোডে মিলিয়ে দেখুন।
- **সেলফ-চেক:** একটি রিকোয়েস্টের পথ Controller → Domain Manager → Repository → DbContext ব্যাখ্যা করুন। Core লাইব্রেরিগুলো কী দেয়? `03-component-reverse-index.md` কী কাজে লাগে (উত্তর: কোনো component বদলানো/বাদ দেওয়ার আগে কোন কোন ফিচার প্রভাবিত হবে জানা)?

**চেকপয়েন্ট ১:** কাগজে-কলমে না দেখে সিস্টেমের এক-পাতার মানচিত্র + টিকিট-জীবনচক্র এঁকে মেন্টরকে বোঝান।

---

## ৭. ফেজ ২ — ক্রস-কাটিং ভিত্তি: অথ, অথরাইজেশন, ইনফ্রা (সপ্তাহ ৩-৪)

> লক্ষ্য: প্রতিটি ফিচারের নিচে যে অভিন্ন ভিত্তি (auth, Redis, notification, storage) — সেটা একবারে শেখা, যাতে ফেজ ৩-এ বারবার আটকে না লাগেন।

### সেশন ৭ — অথেনটিকেশন: সব পক্ষের লগইন

- **পড়া:** `X-01` (admin login: phone OTP + password), `X-02` (admin forgot password), `X-03` (change password/logout), `X-04` (admin session), `X-05` (admin provisioning), `X-06` (user registration), `X-07` (user password login), `X-08` (OneID SSO), `X-09` (user forgot password), `X-10` (user session), `X-11` (delete account/force update), `X-12` (checker login) — সব `60-cross-cutting/` ফোল্ডারে।
- **কোড এরিয়া:** `Services/UserAuth` (Cognito integration), প্রতিটি ফিচার-ডকের সেকশন 8 রেফারেন্স ধরে।
- **হাতে-কলমে:** প্রতিটি লগইন-ফ্লো ডকের সেকশন 11 অনুযায়ী লোকালি চালান — admin OTP, user registration+login, checker login; Floci-তে SES-এ OTP ইমেইল দেখুন; `X-08` OneID SSO ফ্লো কোডে trace করুন (external IdP federation)।
- **সেলফ-চেক:** OTP যাচাই হয় কোথায় (Cognito)? সেশন/টোকেন refresh কীভাবে কাজ করে? OneID-এর সাথে Cognito-র সম্পর্ক? force update কখন ট্রিগার হয়?

### সেশন ৮ — অথরাইজেশনের ৪ স্তর

- **পড়া:** `X-13` (agent pool), `X-14` (authz pool policies), `X-15` (authz roles), `X-16` (authz program scope), `X-17` (authz client-side), `X-18` (endpoints without auth), `X-19` (service-to-service)।
- **বিষয়:** ৪ স্তর — pool policy → `custom:role` claim → route roles → program scope (`X-Program-Id` হেডার / `custom:program_ids`)।
- **হাতে-কলমে:** ভুল role-এর টোকেন দিয়ে protected endpoint হিট করে 403 দেখুন; `X-Program-Id` ছাড়া কল করে কী হয় দেখুন; `X-18`-এর তালিকা ধরে কয়েকটি unauthenticated endpoint যাচাই করুন (নিরাপত্তা-দৃষ্টিতে নোট করুন কেন এগুলো খোলা)।
- **সেলফ-চেক:** একটি admin API রিকোয়েস্টের অথরাইজেশন ৪ স্তরই উদাহরণসহ ব্যাখ্যা করুন। সার্ভিস-টু-সার্ভিস কলে টোকেন কীভাবে forward হয়?

### সেশন ৯ — ফাইল স্টোরেজ, ইমেইল, SMS, পুশ, অ্যাক্টিভিটি লগ

- **পড়া:** `X-20` (file storage/S3), `X-21` (email/SES), `X-22` (SMS), `X-23` (push/Firebase), `X-24` (activity logging)।
- **হাতে-কলমে:** Floci S3-তে আপলোড হওয়া ফাইল খুঁজুন; SES-এ পাঠানো ইমেইল দেখুন; DynamoDB-তে activity log রেকর্ড ইন্সপেক্ট করুন (`docs/knowledge_transfer_context.md`-এর DynamoDB অংশ সহায়ক); Firebase push লোকালে কীভাবে সামলানো হয় তা `X-23`-এর test guide থেকে দেখুন।
- **সেলফ-চেক:** টিকিট PDF কোথায় থাকে, কে আপলোড করে? অ্যাক্টিভিটি লগ কোন DB-তে, কে লেখে, admin কোথায় দেখে?

### সেশন ১০ — Redis ও কনফিগারেশন

- **পড়া:** `X-25` (Redis), `X-26` (configuration), `docs/config-reference.md`।
- **বিষয়:** Redis-এর ৩টি ভূমিকা — ক্যাশ, live/locked capacity, distributed lock; কনফিগের উৎস-ক্রম (env-var → user-secrets → appsettings), Aspire কী কী env-var ইনজেক্ট করে (`ConnectionStrings__*`, `Services__*`, `Cache__Redis__*`, `DistributedLock__Redis__*`, `AWS_ENDPOINT_URL`)।
- **হাতে-কলমে:** Redis-এ কানেক্ট করে (`redis-cli` বা RedisInsight) কী-প্যাটার্ন দেখুন; একটি সিট-লক করার সময় live capacity কী-র মান বদলানো লাইভ পর্যবেক্ষণ করুন।
- **সেলফ-চেক:** live capacity আর locked capacity-র পার্থক্য? Redis নেমে গেলে বুকিং কী হবে? কোন কনফিগ-কী কোন সার্ভিস পড়ে (`config-reference.md` থেকে ৫টি উদাহরণ)?

**চেকপয়েন্ট ২:** একটি admin API কলের সাথে জড়িত অথ-থেকে-অথরাইজেশন-পর্যন্ত পুরো চেইন টোকেন-সহ ব্যাখ্যা করুন; Redis-এ এই মুহূর্তে কী কী কী আছে বলুন।

---

## ৮. ফেজ ৩ — ব্যাকএন্ড ডিপ-ডাইভ: বিজনেস লজিকের মূল খনি (সপ্তাহ ৩-৭) ⭐

> লক্ষ্য: এই ফেজই রোডম্যাপের হৃদয় — ১১টি সার্ভিস ধারাবাহিকভাবে, প্রতিটি ফিচার কোডে trace + লোকালি টেস্ট। এখানে সবচেয়ে বেশি সময় দিন।
> প্রতিটি সেশনে মনে রাখুন: ফিচার-ডক সেকশন 8 = কোড রেফারেন্স, সেকশন 11 = টেস্ট গাইড।

### সেশন ১১ — Admin + Event: ক্যাটালগের ভিত্তি (Program, Team, Venue, Event)

- **পড়া:** `A-01` (program selection), `A-02` (programs), `A-03` (program settings), `A-04` (teams), `A-05` (venues), `A-06` (program-venue mapping), `A-07` (events), `A-08` (event settings)।
- **কোড এরিয়া:** `Services/Admin` (Domain Managers, Storage repositories), `Services/Event` (EventDetails/EventInfo — খেয়াল করুন Event নিজে কোনো migration own করে না, consumer context)।
- **হাতে-কলমে:** শূন্য ডেটাবেসে (বা নতুন program-এ) পুরো ক্যাটালগ তৈরি করুন: program → team → venue → program-venue mapping → event → event settings। প্রতিটি ধাপের পর ডেটাবেস টেবিল দেখুন। অ্যাডমিন পোর্টাল UI ও Swagger দুইভাবেই করে দেখুন।
- **সেলফ-চেক:** ক্যাটালগ তৈরির সঠিক ক্রম কী এবং কেন (নির্ভরতা)? Event সার্ভিসের আসল ভূমিকা কী?

### সেশন ১২ — Booking I: আসন নির্বাচন ও ক্যাপাসিটি (race condition সহ)

- **পড়া:** `P-04` (seat selection), `A-10` (capacity adjustment), `A-11` (seat reservation), `A-12` (reserved tickets), `S-01` (level capacity update), `S-02` (event live capacity), `S-03` (locked capacity refresh), `S-04` (scheduler capacity update)।
- **কোড এরিয়া:** `Services/Booking` — `UserBookingOrderManager`, `CapacityManager` (Domain), Storage repositories।
- **হাতে-কলমে:** দুইটি ব্রাউজার (বা দুইজন টেস্ট ইউজার) থেকে **একই সিট একই মুহূর্তে** নেওয়ার চেষ্টা করুন — Redis distributed lock ও DB capacity কীভাবে দ্বিতীয়টাকে আটকায়; সিট লক হলে Redis-এ locked-capacity কী দেখুন; admin থেকে মাঝ-সেলে capacity adjustment করে দেখুন।
- **সেলফ-চেক:** same-seat-sold-twice race কোন কোন প্রতিরক্ষায় আটকানো (BPL-এ এটা ঘটেছিল — Incident 4)? capacity-র উৎস DB না Redis — কে কাকে sync করে (S-01..S-04 এর ভূমিকা)? লক করা সিট আবার ছাড়ে কে?

### সেশন ১৩ — Booking II: পেমেন্ট

- **পড়া:** `P-06` (booking & payment), `S-05` (pending/failed payment revalidation), `S-06` (booking-status → generated), `S-10` (VAT challan processing)।
- **কোড এরিয়া:** `DgePayPaymentManager` (সক্রিয় গেটওয়ে), `SSLCommerzPaymentManager` (কোডে আছে কিন্তু **disabled** — কারণ open query Q-19), payment callback handler, NBR/VAT অংশ।
- **হাতে-কলমে:** user portal দিয়ে একটি বুকিং করে পেমেন্ট সম্পন্ন করুন (sandbox/user-secrets-এর DgePay config); পেমেন্ট callback-এ অর্ডার স্টেটাস বদল ডিবি + Serilog লগে দেখুন; ইচ্ছা করে callback "না এসে" পেন্ডিং রেখে `S-05` revalidation worker-এর আচরণ পর্যবেক্ষণ করুন; VAT challan রেকর্ড ডিবিতে খুঁজুন।
- **সেলফ-চেক:** পেমেন্ট fail/cancel হলে locked capacity কীভাবে ছাড়ে? অর্ডার-স্টেটাস লাইফসাইকেল আঁকুন। BPL UAT-এ ২০-৩০% পেমেন্ট ফেইলুর (Incident 3) — আমাদের কোডে এর কোন কোন জায়গা সংশ্লিষ্ট?

### সেশন ১৪ — Booking III: প্রাইসিং, প্রোমো ও ডিসকাউন্ট

- **পড়া:** `A-09` (event-level pricing), `A-14` (ticket pricing/content), `A-15` (promo codes), `A-16` (discounts), `S-16` (promo code status), `S-17` (discount status), `P-05` (apply promo), `U-04` (app-এ promo)।
- **হাতে-কলমে:** admin-এ promo code তৈরি করুন (ব্যবহার-সীমা, মেয়াদসহ) → user portal-এ বুকিংয়ের সময় apply করুন; discount নিয়ম তৈরি করে দাম বদল যাচাই; promo মেয়াদ পেরোলে `S-16`/`S-17` status worker কী করে দেখুন।
- **সেলফ-চেক:** promo আর discount একসাথে প্রযোজ্য হয় কি (কোডে যাচাই)? প্রাইসিং-এর স্তরগুলো (event-level vs ticket pricing) কীভাবে একত্রিত হয়?

### সেশন ১৫ — Ticketing I: টিকিট জেনারেশন পাইপলাইন

- **পড়া:** `S-07` (initiate user ticket generation), `S-08` (ticket signing — VDS/TSP), `S-09` (ticket merge/zip), `P-08` (ticket generation request), `A-13` (ticket layouts), `A-14` (ticket pricing/content)।
- **কোড এরিয়া:** `Services/Ticketing` — `TicketManager`, `TicketBatchManager`, `TspClient`, OneId; `Services/Utility` (merge/zip, PDF)।
- **হাতে-কলমে:** paid বুকিং থেকে পুরো পাইপলাইন পর্যবেক্ষণ করুন: SQS মেসেজ (Floci কনসোল) → signing request → PDF → S3 আপলোড → merge/zip → নোটিফিকেশন। `ETP_SKIP=Ticketing` দিয়ে Ticketing সার্ভিসটি IDE থেকে চালিয়ে `TicketManager`-এ ব্রেকপয়েন্ট বসান — এটি পুরো রোডম্যাপের সবচেয়ে গুরুত্বপূর্ণ debug-হার্নেস অনুশীলনগুলোর একটি।
- **সেলফ-চেক:** QR signing কেন দরকার (জাল টিকিট ঠেকানো — কোন TSP)? পাইপলাইনের কোন ধাপ কোন সার্ভিস/queue-তে? টিকিট "generated" হয় না বসে থাকলে কোন কোন জায়গায় তাকাবেন (checklist লিখুন)?

### সেশন ১৬ — Ticketing II: ডাউনলোড, OneID সিঙ্ক, অফলাইন চ্যানেল

- **পড়া:** `P-09` (ticket details/downloads), `P-10` (OneID ticket sync); `OfflineSoldTickets` সংক্রান্ত অংশ `92-appendix-c-coverage.md` থেকে (offline channel-এর ডকুমেন্টেশন তুলনামূলক পাতলা — কোডেই দেখতে হবে)।
- **কোড এরিয়া:** `Services/Ticketing/ETP.Ticketing.*` — `OfflineSoldTickets`, `OneIdSync` এরিয়া।
- **হাতে-কলমে:** জেনারেট হওয়া টিকিট user portal/app থেকে ডাউনলোড করে PDF খুলে QR পরীক্ষা করুন; OneID sync flow কোড trace (কখন ট্রিগার হয়, কী পাঠায়); offline sold ticket ingestion কোড পড়ুন — BPL-এ শেষ মুহূর্তে অফলাইন চ্যানেল যোগ হয়েছিল (Incident 8)।
- **সেলফ-চেক:** অফলাইন চ্যানেলের টিকিট মূল সিস্টেমে কীভাবে ঢোকে? OneID sync ব্যর্থ হলে কী হয়?

### সেশন ১৭ — TicketChecker: গেট ভ্যালিডেশন ও অফলাইন স্ক্যান

- **পড়া:** `C-01` (assigned event/gate), `C-02` (offline ticket download), `C-03` (QR scan validation), `C-04` (manual entry), `C-05` (ticket sync), `C-06` (manual ticket validation), `A-17` (ticket checker users), `A-18` (gate assignment), `A-19` (gate reports), `S-14` (checked ticket sync), `S-15` (gate download status cleanup)।
- **কোড এরিয়া:** `Services/TicketChecker` — `TicketsManager`, `PassCheckerScanInfoManager`।
- **হাতে-কলমে:** checker ইউজার তৈরি + gate assignment করুন; checker app-এ (সেশন ২৬-এ বিস্তারিত, এখানে API দিয়ে) বৈধ টিকিট scan → success; একই QR দ্বিতীয়বার → duplicate rejection; ভুল গেট → rejection; manual entry; Redis-এ checked-ticket জমা হয় → `S-14` এর DB flush পর্যবেক্ষণ; gate report-এ ফলাফল দেখুন।
- **সেলফ-চেক:** একই টিকিট দুই গেটে ব্যবহার কীভাবে ধরা পড়ে (Incident 1)? sync delay-তে false rejection কেন হয় (Incident 2 — আমাদের sync interval 90 সেকেন্ড, ওই আর্টিকেলের fix ছিল 30s — পার্থক্যটা নোট করুন)? গেট-ভ্যালিডেশনের সব নিয়ম (expiry, gate permission, duplicate, limit) তালিকা করুন।

### সেশন ১৮ — Scheduler, PushNotification ও বাকি সিস্টেম-worker

- **পড়া:** `S-11` (Firebase notification), `S-12` (ticket-generated notification), `S-13` (device token cleanup), `S-14`/`S-15` (আগের সেশনে পড়া), `S-16`/`S-17` (আগে পড়া) — এবং `50-system-initiated/README.md` সূচি।
- **কোড এরিয়া:** `Services/Scheduler` (টাইমার), `Services/PushNotification`, বিভিন্ন সার্ভিসের `Workers/` (BackgroundServices, TaskManagers)।
- **হাতে-কলমে:** একটি "worker → লক্ষণ" ম্যাপ-টেবিল তৈরি করুন: ১৭টি S-ফিচারের প্রতিটির জন্য — এটা বন্ধ থাকলে বাইরে কী দেখাবে (যেমন `S-05` বন্ধ = পেন্ডিং পেমেন্ট চিরকাল ঝুলে থাকবে)। এই টেবিল ইনসিডেন্ট-ট্রায়েজের সবচেয়ে বড় হাতিয়ার হবে।
- **সেলফ-চেক:** টিকিট জেনারেট হলে ইউজার কীভাবে জানেন (push-email chain)? device token কেন cleanup হয়?

### সেশন ১৯ — Admin সার্ভিস: SignalR, ড্যাশবোর্ড, রিপোর্ট, রিকনসিলিয়েশন, রাফল

- **পড়া:** `A-20` (raffle draw), `A-21` (dashboard), `A-22` (reports), `A-23` (reconciliation), `A-27` (activity log)।
- **কোড এরিয়া:** `Services/Admin` — `Hubs/` (SignalR), report/reconciliation managers, raw SQL report repository।
- **হাতে-কলমে:** ড্যাশবোর্ড খুলে প্রতিটি সংখ্যা কোন কোয়েরি থেকে আসে trace করুন (network tab + report manager); রিকনসিলিয়েশন রিপোর্ট জেনারেট করে ম্যানুয়ালি ডিবির সাথে মিলিয়ে দেখুন; raffle draw চালিয়ে দেখুন; অ্যাক্টিভিটি লগ পেজে আগের সেশনগুলোর কাজ পড়ে উঠতে দেখুন।
- **সেলফ-চেক:** SignalR কোথায় ব্যবহৃত (admin লাইভ-আপডেট + user chat — আলাদা ingress `chat.gobcbticket.com.bd`)? রিপোর্টগুলো raw SQL — কোথায় আছে?

### সেশন ২০ — UserAuth, UserIssue, Platform ও কনটেন্ট-ম্যানেজমেন্ট ফিচার

- **পড়া:** `A-24` (user issues admin side), `P-12`/`U-08` (issues chat), `A-25` (admin users), `A-26` (agent users), `A-28` (media configuration), `A-29` (content editor), `A-30` (header/footer/social), `A-31` (general notices), `P-01` (home content), `P-03`/`U-03` (info pages)।
- **কোড এরিয়া:** `Services/UserAuth`, `Services/UserIssue`, `Services/Platform` (খেয়াল: UserAuth ও Platform প্রায়-খালি stub — README §15 known issue 6), Admin-এর content/media অংশ।
- **হাতে-কলমে:** user portal থেকে issue রিপোর্ট → admin portal-এ reply → chat চলতে দেখুন (SignalR); নতুন admin user ও agent user তৈরি করুন; content editor দিয়ে হোম-পেজ কনটেন্ট বদলে user portal-এ দেখুন; মিডিয়া আপলোড → S3।
- **সেলফ-চেক:** issue-চ্যাটের মেসেজ কোন টেবিলে, কোন সার্ভিস লেখে? এজেন্ট-ইউজার আর অ্যাডমিন-ইউজারের পার্থক্য? হোম-কনটেন্ট ইউজার অ্যাপ/পোর্টালে কোথা থেকে আসে?

### সেশন ২১ — ডেটাবেস ডিপ-ডাইভ: স্কিমা, মালিকানা, মাইগ্রেশন

- **পড়া:** `docs/knowledge_transfer_context.md` (পুরোটা — per-service schema, migration, backup/recovery, cross-service dependency), README-এর EF migration সেকশন।
- **হাতে-কলমে:** প্রতিটি সার্ভিসের `*.Storage/DbContexts` ও `Migrations` ঘুরে **write-ownership ম্যাট্রিক্স** নিজে যাচাই করুন (Admin: catalog/gates/CheckedTickets, Booking: capacity/orders/reservations, Ticketing: tickets/batches, TicketChecker: pass-check info, UserIssue: issues/chat...); `ExcludeFromMigrations` প্যাটার্ন (এক সার্ভিস অন্যের টেবিল পড়ে, migration করে না) কোডে খুঁজুন; লোকালে একটি মনিং-মাইগ্রেশন add করে rollback প্র্যাকটিস (সাবমডিউলে কমিট নয়, শুধু বোঝা)।
- **সেলফ-চেক:** schema change workflow বলুন — owner সার্ভিসে migration → consumer mapping আপডেট → owner আগে deploy → পরে consumer। Admin catalog change করলে কোন কোন সার্ভিস প্রভাবিত (উচ্চ-ঝুঁকি চেইন)?

**চেকপয়েন্ট ৩ (সবচেয়ে গুরুত্বপূর্ণ):** বুকিং-থেকে-গেট পুরো চেইন (সেশন ১২-১৭) মুখস্থভাবে এঁকে দেখান; worker→লক্ষণ টেবিল ও write-ownership ম্যাট্রিক্স মেন্টরকে দেখান।

---

## ৯. ফেজ ৪ — ক্লায়েন্ট অ্যাপ: ফ্লো-লেভেল বোঝা + হাতে-কলমে টেস্ট (সপ্তাহ ৭-৯)

> লক্ষ্য: .NET-ইঞ্জিনিয়ার হিসেবে Angular/Flutter কোড গভীরভাবে ডিবাগ করা লক্ষ্য নয়; লক্ষ্য হলো — প্রতিটি স্ক্রিন ব্যবহার করতে পারা, কোন UI কোন API কল করে জানা, আর ক্লায়েন্ট-সাইডের ফিচারগুলো (অফলাইন স্ক্যান, webview পেমেন্ট) ব্যবহার-স্তরে আয়ত্ত করা।

### সেশন ২২ — Admin portal I (Angular 18): ক্যাটালগ ও কনফিগারেশন স্ক্রিন

- **পড়া:** `A-01` থেকে `A-14` (ফেজ ৩-এ পড়া ডকগুলোই, এবার UI-লেন্সে), `docs/admin-portal-local.md`।
- **হাতে-কলমে:** অ্যাডমিন পোর্টালের প্রতিটি মেনু একবার করে খুলুন; browser DevTools-এর Network ট্যাব খোলা রেখে প্রতিটি স্ক্রিনের API কল চিহ্নিত করুন (কোন সার্ভিস, কোন endpoint); প্রোগ্রাম-সুইচার (`A-01`) বদলালে কী বদলায় দেখুন।
- **সেলফ-চেক:** "Events" স্ক্রিনের প্রতিটি অ্যাকশন (তৈরি/এডিট/সেটিংস/প্রাইসিং) কোন controller-এ পৌঁছায়?

### সেশন ২৩ — Admin portal II: অপারেশন স্ক্রিন

- **পড়া:** `A-15` থেকে `A-31`।
- **হাতে-কলমে:** promo/discount স্ক্রিন, ticket-checker ইউজার ও gate assignment, gate report, raffle draw, সব রিপোর্ট, reconciliation, activity log, media/content/header-footer/notice স্ক্রিন — সব হাতে-কলমে; ফেজ ৩-এ করা backend-কাজের সাথে UI মিলিয়ে মানসিক ম্যাপ পূর্ণ করুন।
- **সেলফ-চেক:** একজন স্টাফ-অপারেটরের ইভেন্ট-দিবসের রুটিন (গেট রিপোর্ট মনিটরিং, issue হ্যান্ডলিং, reconciliation) ধাপে ধাপে বর্ণনা করুন।

### সেশন ২৪ — User portal (Angular 19): ক্রেতার পূর্ণ যাত্রা

- **পড়া:** `P-01` থেকে `P-13`, `docs/user-portal-local.md`।
- **হাতে-কলমে:** রেজিস্ট্রেশন → লগইন → হোম → ইভেন্ট ব্রাউজ → info পেজ → সিট নির্বাচন → প্রোমো → পেমেন্ট → my bookings → জেনারেশন রিকোয়েস্ট → টিকিট ডাউনলোড → issue chat → প্রোফাইল → ভাষা বদল — পুরো যাত্রা নিজে করে Network ট্যাবে API চিহ্নিত করুন; NgRx state-এর ধারণা নিন (store/effects — ফ্লো-লেভেলে যথেষ্ট)।
- **সেলফ-চেক:** সিট-ম্যাপের লাইভ আপডেট কোথা থেকে আসে? KYC/Innovatrics ক্যাপচার কোথায় ব্যবহৃত?

### সেশন ২৫ — User app (Flutter): একই যাত্রা মোবাইলে

- **পড়া:** `U-01` থেকে `U-10`, `docs/mobile-local.md`।
- **হাতে-কলমে:** `scripts/Setup-MobileApps.ps1` / `scripts/mobile-gateway.js` অনুযায়ী অ্যাপটি রান করুন (device/emulator); splash/onboarding থেকে বুকিং-webview-পেমেন্ট (U-05) পর্যন্ত ফ্লো চালান; push receipt (U-10) ও device token (U-09) ফ্লো ডক ধরে যাচাই।
- **সেলফ-চেক:** পেমেন্ট অ্যাপে webview-এ হয়, পোর্টালে সরাসরি — পার্থক্য ও ফলাফল একই কেন? অ্যাপ আর পোর্টালে ফিচার-পার্থক্য তালিকা করুন।

### সেশন ২৬ — Checker app (Flutter): অফলাইন-ফার্স্ট গেট অপারেশন

- **পড়া:** `C-01` থেকে `C-06`, `docs/mobile-local.md`।
- **হাতে-কলমে:** checker লগইন → assigned event/gate → **offline ticket download** (C-02) → নেটওয়ার্ক বন্ধ করুন → QR স্ক্যান (বৈধ, duplicate, ভুল গেট) → manual entry → নেটওয়ার্ক চালু করে sync (C-05) → admin গেট-রিপোর্টে ফলাফল মিলিয়ে দেখুন। এই অ্যাপই BPL-এর বেশিরভাগ ইনসিডেন্টের কেন্দ্রে ছিল — বারবার খেলুন।
- **সেলফ-চেক:** অফলাইনে কোন যাচাইগুলো লোকালি হয়, কোনগুলো অসম্ভব? sync conflict (দুই ডিভাইসে একই টিকিট) কীভাবে হ্যান্ডেল হয়?

**চেকপয়েন্ট ৪:** ৫টি অ্যাপের প্রতিটি থেকে একটি করে ফ্লো মেন্টরের সামনে চালিয়ে দেখান এবং পর্দার আড়ালে কোন API-গুলো ছুটছে বলুন।

---

## ১০. ফেজ ৫ — এন্ড-টু-এন্ড মাস্টারি ও ডিবাগিং (সপ্তাহ ৯-১০)

> লক্ষ্য: আলাদা আলাদা টুকরো জ্ঞানকে একটানা ফ্লোতে জোড়া দেওয়া, আর জেনে-বুঝে ভাঙা-গড়ার হাত পাকানো।

### সেশন ২৭ — ফুল লাইফসাইকেল E2E: এক টিকিটের পূর্ণ যাত্রা

- **হাতে-কলমে:** সম্পূর্ণ শূন্য থেকে, কোনো ডক খুলে না দেখে: program তৈরি → team/venue → event → settings → pricing → ticket layout → capacity → (user portal) অ্যাকাউন্ট → সিট → প্রোমো → পেমেন্ট → অর্ডার Paid → টিকিট জেনারেশন → ডাউনলোড → (checker app) offline download → scan → admin গেট-রিপোর্ট + reconciliation। **প্রতিটি ধাপে** ডিবি-টেবিল, Redis কী, S3 অবজেক্ট, SQS মেসেজ — চার জায়গাতেই স্টেট নোট করুন।
- **ডেলিভারেবল:** এক পাতার **"টিকিটের জীবন" টাইমলাইন** — প্রতিটি মুহূর্তে কোন সার্ভিস কী করল, কোথায় কী লেখা হলো। এটি আপনার ব্যক্তিগত রেফারেন্স-ডক।
- **সেলফ-চেক:** যেকোনো ধাপে আটকে গেলে নিজে নিজে কোথায় তাকালেন — সেটাই আপনার আসল অগ্রগতির মাপকাঠি।

### সেশন ২৮ — Edge case ও failure ড্রিল

- **হাতে-কলমে (প্রতিটির পূর্বাভাস আগে লিখুন, তারপর পরীক্ষা করুন):**
  1. পেমেন্ট শুরু করে callback আসার আগে ব্রাউজার বন্ধ → অর্ডার কী অবস্থায়, `S-05` কখন কী করে?
  2. সেল চলাকালীন admin capacity adjustment → চলমান বুকিংয়ে প্রভাব?
  3. দুই ইউজার একই সিট (আবার, এবার জেনেবুঝে) → কে জিতল কোন লক-এ?
  4. টিকিট জেনারেশন চলাকালীন Ticketing সার্ভিস বন্ধ → পুনরায় চালু হলে কী হয়?
  5. checker sync-এর মাঝে নেটওয়ার্ক বিচ্ছিন্ন → conflict কীভাবে মেটানো হয়?
  6. মেয়াদোত্তীর্ণ promo apply করার চেষ্টা।
- **সেলফ-চেক:** প্রতিটি ফেইলিওরে সিস্টেম কোন অবস্থায় "আটকে থাকে", কোন worker/ম্যানুয়াল পদক্ষেপ এটা পরিষ্কার করে — তালিকা করুন।

### সেশন ২৯ — ডিবাগিং ড্রিল ও known issues

- **পড়া:** `README.md` §15 Known backend issues (৭টি — TicketGenerationService-এর error-spin, launchSettings পোর্ট-সংঘর্ষ, TSP certificate validation bypass, UserAuth/Platform stub ইত্যাদি), README-এর debugging সেকশন।
- **হাতে-কলমে:** `ETP_SKIP=<সার্ভিস>` দিয়ে একটি সার্ভিস IDE থেকে (ব্রেকপয়েন্ট সহ) চালান, বাকিগুলো AppHost-এ; Booking-এর একটি manager-এ ব্রেকপয়েন্ট বসিয়ে একটি বুকিং করুন; Serilog স্ট্রাকচার্ড লগ থেকে request-id/order-id ধরে correlation অনুশীলন করুন; TicketGenerationService-এর error-spin issue-টি ইচ্ছা করে ঘটিয়ে (exception path) লগ-বিস্ফোরণ নিজে চোখে দেখুন।
- **সেলফ-চেক:** "bug report" পাওয়ার পর আপনার নিজস্ব ৮-ধাপের রেসিপি লিখুন (রিপ্রোডিউস → লগ → ব্রেকপয়েন্ট → টেবিল → Redis → worker → ফিক্স → ভেরিফাই)।

**চেকপয়েন্ট ৫:** মেন্টর একটি "রহস্য" তৈরি করে দেবেন (যেমন একটি অর্ডার পেন্ডিং-এ আটকে আছে) — আপনি ট্রায়েজ করে কারণ বের করবেন।

---

## ১১. ফেজ ৬ — অপারেশনস ও ইনসিডেন্ট রেডিনেস (সপ্তাহ ১০-১১)

> লক্ষ্য: প্রোডাকশনের মালিক হওয়ার শেষ ধাপ — জানা কীভাবে চলে, কোথায় দেখবেন, কীভাবে সামলাবেন।

### সেশন ৩০ — AWS এনভায়রনমেন্ট, অ্যাক্সেস ও ডিপ্লয়-ফ্লো

- **পড়া:** `docs/rvl-handover-AWS-access-summary.md`, `docs/architecture/gobcb-aws-architecture.md`-এর CI/CD-সেকশন, সাবমডিউলগুলোর `buildspec-{dev,test,stage,prod}.yml` (শুধু পড়া)।
- **বিষয়:** ৪টি এনভায়রনমেন্ট (dev/test/stage/prod); stage DB public + IP-allowlist, prod DB VPC-only + bastion; SSM `/rvl/<env>/<service>-appsettings` (সতর্কতা: সেখান থেকে মান কপি করলে শুধু Cognito/S3-ধরনের নিন, connection string/Redis/queue কখনোই নয়); CodeBuild → ECR → kubectl; CloudWatch logs।
- **হাতে-কলমে:** অ্যাক্সেস থাকলে stage-এর একটি সার্ভিসের CloudWatch লগ খুলে লোকাল লগের সাথে ফরম্যাট মিলিয়ে দেখুন; না থাকলে ডক ধরে deploy-pipeline-এর ধাপগুলো কাগজে রিহার্স করুন।
- **সেলফ-চেক:** প্রোডাকশনে কিছু করার আগে কার অনুমতি, কোন চ্যানেলে? একটি সার্ভিস ডিপ্লয়ের পর healthy কিনা কীভাবে যাচাই করবেন? রোলব্যাক মানে কী (নতুন ইমেজ দিয়ে পুরনো রিভিশন; DB rollback নয়)?

### সেশন ৩১ — রিয়েল ইনসিডেন্ট স্টাডি (BPL 2025)

- **পড়া:** `docs/live-experiences-and-uat-focus.md` — পুরোটা।
- **বিষয়:** ৯টি রিয়েল ইনসিডেন্ট: (1) একই প্রিন্ট-টিকিট একাধিক গেটে, (2) sync delay-তে বৈধ টিকিট false-rejection, (3) UAT-তে ২০-৩০% পেমেন্ট ফেইলিওর, (4) একই সিট দুই ক্রেতার কাছে, (5) সেন্ট্রাল সার্ভারে ৩০-৬০ সেকেন্ড/স্ক্যান, (6) লো-এন্ড ডিভাইস ফেইলিওর, (7) UAT UX defect, (8) শেষ-মুহূর্তের অফলাইন টিকিট চ্যানেল, (9) চেকারদের অভ্যস্ত হতে সময়; সাথে P0-P2 এরিয়া ও OneID/SES/Aurora-failover-জাতীয় architecture-derived ঝুঁকি।
- **হাতে-কলমে:** প্রতিটি ইনসিডেন্টের জন্য ৪-লাইনের কার্ড বানান — **কারণ → লক্ষণ → আমাদের কোডে অবস্থান (ডকের দেওয়া file:line খুলে নিজে যাচাই) → প্রতিকার/প্রতিরোধ**; প্রতিটির সংশ্লিষ্ট ফিচার-ডক ID-ও কার্ডে লিখুন।
- **সেলফ-চেক:** কোন ৫টি এরিয়া P0 এবং কেন? Incident-to-area mapping টেবিলটা মুখস্থভাবে বলতে পারেন?

### সেশন ৩২ — ইনসিডেন্ট সিমুলেশন ড্রিল

- **হাতে-কলমে (লোকালে প্রতিটি সিনারিও সৃষ্টি করে ট্রায়েজ করুন, সময় মেপে):**
  1. **পেমেন্ট callback আসছে না** — কোন লগ, কোন টেবিল, কোন worker প্রথম সন্দেহ করবে?
  2. **Checker false rejection** — sync status, Redis কী, কোন স্ক্রিনে প্রমাণ?
  3. **Capacity oversell-এর রিপোর্ট** — কোন লক/টেবিল চেক, কীভাবে নিশ্চিত?
  4. **টিকিট জেনারেট হচ্ছে না** — queue → worker → S3 কোন ধাপে আটকেছে বের করা।
- **ডেলিভারেবল:** নিজস্ব **ইনসিডেন্ট-রেসপন্স টেমপ্লেট** — লক্ষণ → প্রভাব-পরিসর → সম্ভাব্য কারণের ছক → প্রমাণ-সংগ্রহ (লগ/DB/Redis) → ফিক্স/মাইটিগেশন → যাচাই → রিপোর্ট।
- **সেলফ-চেক:** প্রতিটি ড্রিলে "প্রথম ১০ মিনিটে কী করতেন" বলতে পারেন?

**চেকপয়েন্ট ৬:** মেন্টর যেকোনো একটি সিমুলেটেড ইনসিডেন্ট চালু করবেন — আপনি টেমপ্লেট ধরে ট্রায়েজ করে দেখাবেন।

---

## ১২. ফেজ ৭ — ক্যাপস্টোন: গ্যাপ, লিগ্যাসি ও প্রথম কন্ট্রিবিউশন (সপ্তাহ ১১-১২)

### সেশন ৩৩ — Open queries ও কভারেজ-গ্যাপ রিভিউ

- **পড়া:** `99-open-queries.md` (৭৫টি BS23-প্রশ্ন), `92-appendix-c-coverage.md`, `docs/handover/feature-matrix/GoBCB-Feature-Matrix.xlsx` (Feature Matrix ও Gap Log শিট)।
- **হাতে-কলমে:** প্রশ্নগুলোকে থিমে ভাগ করুন (পেমেন্ট, OneID, offline, infra...); কোন কোনটা আপনি এখন কোড-থেকেই উত্তর দিতে পারেন চিহ্নিত করুন — এটা আপনার অগ্রগতির অডিট; কোন এরিয়ায় ডকুমেন্টেশন পাতলা তা তালিকা করুন।
- **সেলফ-চেক:** ৭৫টির মধ্যে অন্তত ২০টির উত্তর কোড-প্রমাণসহ দিতে পারেন?

### সেশন ৩৪ — লিগ্যাসি, ডরম্যান্ট কোড ও endpoint-সূচি

- **পড়া:** `90-appendix-a-legacy.md`, `91-appendix-b-endpoint-index.md`।
- **হাতে-কলমে:** লিগ্যাসি তালিকার প্রতিটি আইটেম কোডে খুঁজে দেখুন (উদা. disabled SSLCommerz পাথ); endpoint-index থেকে যেকোনো ১০টি endpoint এলোমেলো করে পরীক্ষা — কোন সার্ভিস, কী auth চায়, কী করে বলতে পারেন কি?
- **সেলফ-চেক:** নতুন কাজ শুরুর আগে "এই নামে কিছু আগে থেকেই আছে কি" — কোথায় দেখবেন (reverse index + legacy appendix)?

### সেশন ৩৫ — প্রথম কন্ট্রিবিউশন

- **হাতে-কলমে:** নিচের যেকোনো একটি বেছে নিন এবং শেষ করুন —
  - README §15-এর কোনো known issue-এর ফিক্স (যেমন TicketGenerationService-এর error-spin-এ delay যোগ),
  - কোনো পাতলা-কভারেজ এরিয়ার ডকুমেন্টেশন উন্নত করা (workspace docs-এ),
  - একটি ছোট ইমপ্রুভমেন্ট প্রস্তাব লেখা (সমস্যা + প্রমাণ + প্রস্তাবিত সমাধান + ঝুঁকি)।
  কোড-ফিক্স হলে: সাবমডিউল **নিজ রিপোতে** branch + PR (workspace থেকে কমিট কখনোই নয়), PR মার্জের পর workspace-এ submodule pin আপডেট (`status.ps1` দিয়ে যাচাই)।
- **সেলফ-চেক:** PR-এর description-এ সমস্যা, কারণ, পরিবর্তন, পরীক্ষা — চারটি অংশ আছে? pin-update প্রক্রিয়া বলতে পারেন?

### সেশন ৩৬ — ফাইনাল অ্যাসেসমেন্ট

- **হাতে-কলমে (মেন্টর/টিমের সামনে):**
  1. এলোমেলোভাবে ৫টি ফিচার-ডক টানুন — প্রতিটির: ব্যাখ্যা + কোড trace + লোকালি টেস্ট।
  2. ২টি ইনসিডেন্ট রোল-প্লে (সেশন ৩২-এর টেমপ্লেটে)।
  3. একটি নতুন ফিচারের প্রস্তাব ১০ মিনিটে স্কেচ করুন — কোন সার্ভিসে, কোন টেবিলে, কোন ক্লায়েন্টে, কী ঝুঁকি।
  4. সেকশন ২-এর **Definition of Done** চেকলিস্ট একসাথে বসে পূরণ করুন।

---

## ১৩. একনজরে পুরো টাইমলাইন ও প্রগ্রেস ট্র্যাকার (মাস্টার টেবিল)

৩৬টি সেশনের সম্পূর্ণ তালিকা একসাথে — কোন সপ্তাহে কী, মূল ফোকাস কোন ডক, আর সেশন শেষে হাতে-কলমে কী আউটপুট বের হবে। প্রতিটি সেশনের বিস্তারিত breakdown (পড়ার তালিকা, কোড এরিয়া, সেলফ-চেক) উপরের নিজ নিজ ফেজ-সেকশনে।

**ছন্দ:** ডিফল্ট = সপ্তাহে ৩টি সেশন × ১২ সপ্তাহ। ইনটেনসিভ (৬ সপ্তাহ) হলে টেবিলের **২ সপ্তাহ = আসল ১ সপ্তাহ** (সপ্তাহে ৬ সেশন); ধীরগতি (১৬-১৮ সপ্তাহ) হলে সপ্তাহে ২ সেশন। সেশন শেষ হলে ✓ কলামে টিক দিন; চাইলে পাশে তারিখ-কলাম যোগ করে নিন। ফেজের সীমানা-সপ্তাহ (যেমন সপ্তাহ ৪, ৯-১১) দুই ফেজের মাঝে ভাগ হয় — স্বাভাবিক।

| সপ্তাহ | ফেজ | # | সেশন ও মূল ফোকাস | হাতে-কলমে যা যাবে | ✓ |
|---|---|---|---|---|---|
| ১ | 0 | 1 | **ওরিয়েন্টেশন** — `README.md`, `AGENTS.md`, docs-ম্যাপ | সাবমডিউল-স্ট্যাটাস যাচাই, docs-ভ্রমণ | ☐ |
| ১ | 0 | 2 | **লোকাল সেটআপ** — `local-dev-setup.bn.md`, Floci, user-secrets | ১১ সার্ভিস healthy + 129 migration + `Test-EtpLocal.ps1` | ☐ |
| ১ | 0 | 3 | **ক্লায়েন্ট ও লগইন** — portal-local গাইড, Postman | ২ পোর্টালে লগইন, ৪ pool-এর টোকেন, টেস্ট-ডেটা seed | ☐ |
| ২ | 1 | 4 | **বিজনেস ডোমেইন** — `01-system-map.md` | হাতে-আঁকা টিকিট-জীবনচক্র ডায়াগ্রাম | ☐ |
| ২ | 1 | 5 | **AWS আর্কিটেকচার** — `gobcb-aws-architecture.md` | AWS↔লোকাল ম্যাপিং টেবিল + `[UNCONFIRMED]` তালিকা | ☐ |
| ২ | 1 | 6 | **সার্ভিস ম্যাপ ও কোড-স্ট্রাকচার** — primer `00`/`02`/`03` | ১১ Swagger স্ক্যান + ৩ ফিচারের traceability যাচাই | ☐ |
| ৩ | 2 | 7 | **অথেনটিকেশন** — `X-01`..`X-12` | সব লগইন-ফ্লো লোকালি + JWT claim পরীক্ষা | ☐ |
| ৩ | 2 | 8 | **অথরাইজেশনের ৪ স্তর** — `X-13`..`X-19` | 403 / `X-Program-Id` / authless endpoint পরীক্ষা | ☐ |
| ৩ | 2 | 9 | **স্টোরেজ-নোটিফিকেশন-লগ** — `X-20`..`X-24` | S3 অবজেক্ট, SES ইমেইল, DynamoDB অ্যাক্টিভিটি ইন্সপেক্ট | ☐ |
| ৪ | 2 | 10 | **Redis ও কনফিগ** — `X-25`, `X-26`, `config-reference.md` | লাইভ-ক্যাপাসিটি Redis কী-র লাইভ পর্যবেক্ষণ | ☐ |
| ৪ | 3 | 11 | **ক্যাটালগের ভিত্তি** — `A-01`..`A-08` | শূন্য থেকে program → venue → event তৈরি | ☐ |
| ৪ | 3 | 12 | **Booking I: সিট ও ক্যাপাসিটি** — `P-04`, `A-10`..`A-12`, `S-01`..`S-04` | একই-সিট race পরীক্ষা, Redis lock পর্যবেক্ষণ | ☐ |
| ৫ | 3 | 13 | **Booking II: পেমেন্ট** — `P-06`, `S-05`, `S-06`, `S-10` | পেমেন্ট success + callback-missing pending ফ্লো | ☐ |
| ৫ | 3 | 14 | **Booking III: প্রোমো/ডিসকাউন্ট** — `A-09`, `A-14`..`A-16`, `S-16`, `S-17` | promo/discount apply ও expiry যাচাই | ☐ |
| ৫ | 3 | 15 | **Ticketing I: জেনারেশন পাইপলাইন** — `S-07`..`S-09`, `P-08`, `A-13` | পাইপলাইন ডিবাগ (`ETP_SKIP` + TicketManager breakpoint) | ☐ |
| ৬ | 3 | 16 | **Ticketing II: ডাউনলোড/OneID/অফলাইন** — `P-09`, `P-10` | টিকিট ডাউনলোড + QR যাচাই, offline channel trace | ☐ |
| ৬ | 3 | 17 | **গেট ভ্যালিডেশন** — `C-01`..`C-06`, `A-17`..`A-19`, `S-14`, `S-15` | duplicate / ভুল-গেট / manual কেস + gate report | ☐ |
| ৬ | 3 | 18 | **Worker-ম্যাপ** — `S-11`..`S-17` | worker→লক্ষণ টেবিল (ইনসিডেন্টের মূল হাতিয়ার) | ☐ |
| ৭ | 3 | 19 | **রিপোর্ট/রিকনসিলিয়েশন/রাফল** — `A-20`..`A-23`, `A-27` | ড্যাশবোর্ড-সংখ্যা trace + reconciliation ডিবি-মিলানো | ☐ |
| ৭ | 3 | 20 | **UserIssue/স্টাফ/কনটেন্ট** — `A-24`..`A-26`, `A-28`..`A-31`, `P-12` | issue-chat, নতুন স্টাফ, হোম-কনটেন্ট বদল | ☐ |
| ৭ | 3 | 21 | **ডেটাবেস ও মাইগ্রেশন** — `knowledge_transfer_context.md` | write-ownership ম্যাট্রিক্স + migration প্র্যাকটিস | ☐ |
| ৮ | 4 | 22 | **Admin portal I: ক্যাটালগ স্ক্রিন** — `A-01`..`A-14` (UI-লেন্স) | প্রতিটি স্ক্রিনের API-কল ম্যাপ (Network tab) | ☐ |
| ৮ | 4 | 23 | **Admin portal II: অপারেশন স্ক্রিন** — `A-15`..`A-31` (UI-লেন্স) | সব অপারেশন স্ক্রিন হাতে-কলমে | ☐ |
| ৮ | 4 | 24 | **User portal: ক্রেতার যাত্রা** — `P-01`..`P-13` | পূর্ণ যাত্রা + প্রতিটি ধাপের API-ম্যাপ | ☐ |
| ৯ | 4 | 25 | **User app (Flutter)** — `U-01`..`U-10` | অ্যাপে পূর্ণ যাত্রা + webview পেমেন্ট + push | ☐ |
| ৯ | 4 | 26 | **Checker app: অফলাইন গেট** — `C-01`..`C-06` | অফলাইন স্ক্যান, sync, conflict পরীক্ষা | ☐ |
| ৯ | 5 | 27 | **ফুল লাইফসাইকেল E2E** — `01-system-map.md` (আবার) | "টিকিটের জীবন" টাইমলাইন-ডক | ☐ |
| ১০ | 5 | 28 | **Edge case ও failure ড্রিল** — ৬টি সিনারিও | প্রতিটির পূর্বাভাস + ফলাফল তালিকা | ☐ |
| ১০ | 5 | 29 | **ডিবাগিং ড্রিল** — README §15 known issues | ৮-ধাপের ডিবাগিং রেসিপি + error-spin reproduce | ☐ |
| ১০ | 6 | 30 | **AWS এনভায়রনমেন্ট ও ডিপ্লয়** — AWS-access summary, buildspec | stage লগ-পরীক্ষা বা deploy-রিহার্সাল | ☐ |
| ১১ | 6 | 31 | **রিয়েল ইনসিডেন্ট স্টাডি** — `live-experiences-and-uat-focus.md` | ৯টি ইনসিডেন্ট-কার্ড (কারণ→কোড→প্রতিকার) | ☐ |
| ১১ | 6 | 32 | **ইনসিডেন্ট সিমুলেশন ড্রিল** — ৪টি সিনারিও | নিজস্ব ইনসিডেন্ট-রেসপন্স টেমপ্লেট | ☐ |
| ১১ | 7 | 33 | **Open queries ও কভারেজ-গ্যাপ** — `99-open-queries.md`, xlsx | ২০+ প্রশ্নের কোড-উত্তর অডিট | ☐ |
| ১২ | 7 | 34 | **লিগ্যাসি ও endpoint-সূচি** — appendix `90`/`91` | লিগ্যাসি কোড-যাচাই + ১০ endpoint কুইজ | ☐ |
| ১২ | 7 | 35 | **প্রথম কন্ট্রিবিউশন** — submodule PR প্রক্রিয়া | ফিক্স-PR বা ইমপ্রুভমেন্ট প্রস্তাব | ☐ |
| ১২ | 7 | 36 | **ফাইনাল অ্যাসেসমেন্ট** — Definition of Done | ৫ র‍্যান্ডম ফিচার + ২ ইনসিডেন্ট রোল-প্লে | ☐ |

## ১৪. ফেজ → রিসোর্স ম্যাপ (একনজরে)

| ফেজ | মূল ডক | মূল কোড/টুল |
|---|---|---|
| 0 | `README.md`, `docs/local-dev-setup.bn.md`, `floci/QUICKSTART.md` | Aspire AppHost, `scripts/`, `postman/` |
| 1 | `feature-docs/bn/` primer 00-03, `docs/architecture/gobcb-aws-architecture.md` | `Core/`, `Services/` (স্ট্রাকচার) |
| 2 | `X-01`..`X-26` | `Services/UserAuth`, Redis, Floci (SES/S3/DynamoDB) |
| 3 | `A-*`, `P-*`, `S-*`, `X`-বাকি, `docs/knowledge_transfer_context.md` | `Services/` সব (বিশেষত Booking, Ticketing, TicketChecker) |
| 4 | `A-*`, `P-*`, `U-*`, `C-*` (UI-লেন্স), `docs/*-local.md` | ২ Angular পোর্টাল + ২ Flutter অ্যাপ, `Setup-*.ps1` |
| 5 | `README.md` §15, `01-system-map.md` | `ETP_SKIP` debug-harness, Serilog লগ |
| 6 | `docs/live-experiences-and-uat-focus.md`, `docs/rvl-handover-AWS-access-summary.md` | CloudWatch (অ্যাক্সেস থাকলে), লোকাল সিমুলেশন |
| 7 | `99-open-queries.md`, appendix 90-93, feature-matrix xlsx | সাবমডিউল নিজ রিপো (PR) |

## ১৫. সংলগ্ন নোট ও সতর্কতা

- **`docs/team_upskilling_context.md` সাপ্লিমেন্টারি:** ওই ডকুমেন্টটি upstream-এর পুরনো কনটেক্সটে লেখা (`rvl-ticketbangla-backend` নাম, পুরনো পোর্ট 5001-5011, Helm deploy, `Tests/` ফোল্ডার) — বর্তমান workspace-এর সাথে **অমিল**। ব্যাকএন্ড-ডোমেইন ব্যাখ্যা (সেকশন 3) ও debugging অভ্যাস (সেকশন 5) এখনও মূল্যবান, কিন্তু পোর্ট/ডিপ্লয়-তথ্যের জন্য এই workspace-এর `README.md`-কেই সত্য ধরুন।
- **`[UNCONFIRMED]` চিহ্ন:** আর্কিটেকচার-ডক ও কিছু ফিচার-ডকে `[UNCONFIRMED: Q-nn]` দেখলে সেগুলো অপ্রমাণিত প্রশ্ন — সত্য হিসেবে গ্রহণ করবেন না; BS23-এর উত্তরের অপেক্ষায় থাকা ৭৫টি প্রশ্নের সূচি `99-open-queries.md`-তে।
- **সাবমডিউল-শুচিতা:** প্রতিটি সেশন শেষে সন্দেহ হলে `git status --porcelain` দিয়ে সাবমডিউলগুলো পরিষ্কার কিনা দেখে নিন — কিছু বদলে গেলে `git checkout -- <path>`।
- **প্রশ্ন জমিয়ে রাখুন:** যেখানে ডকুমেন্ট আর কোড মেলে না, সেটা বাগ বা পুরনো ডক হতে পারে — নিজে চুপ করে অনুমান না করে নোট করুন এবং টিম/BS23-কে জিজ্ঞেস করুন।
