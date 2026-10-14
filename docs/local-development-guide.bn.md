# RVL-ETP (GOBCB) Backend — লোকাল ডেভেলপমেন্ট গাইড

> **কার জন্য:** যে .NET ডেভেলপার repo clone করে নিজের মেশিনে কোড লিখবেন, চালাবেন আর debug করবেন।
>
> **শেষে যা পাবেন:** সব ৯টা সার্ভিস আপনার মেশিনে চলছে, breakpoint-এ থামছে, আর প্রতিদিন কয়েকটা কমান্ডে environment তৈরি হয়ে যাচ্ছে।
>
> **সময়:** প্রথমবার ৩০–৪৫ মিনিট (ডাউনলোড বাদে)। এরপর প্রতিদিন ২–৩ মিনিট।
>
> **Repo অপরিবর্তিত থাকে:** এই গাইড মেনে চললে repo-র কোনো ফাইল বদলাতে বা যোগ করতে হয় না।
>
> 📁 **আপনার ব্যক্তিগত config আর helper script repo-তে নয়, থাকে `C:\Users\<আপনার-নাম>\.etp-local\` ফোল্ডারে** (PowerShell-এ `$env:USERPROFILE\.etp-local`)। Repo বা Visual Studio-তে খুঁজলে পাবেন না — বিস্তারিত: [আপনার লোকাল ফাইল কোথায় থাকে](#-আপনার-লোকাল-ফাইল-কোথায়-থাকে)।
>
> এই গাইডের প্রতিটা ধাপ একটা Windows 11 মেশিনে খালি অবস্থা থেকে চালিয়ে যাচাই করা হয়েছে: ৯টা সার্ভিসই `/health` = 200, ১২৯টা migration apply হয়েছে, IDE mode আর Docker mode দুটোতেই।

---

## সূচিপত্র

- [🚀 নতুন ডেভেলপার: শূন্য থেকে শুরু (এখান থেকে পড়া শুরু করুন)](#-নতুন-ডেভেলপার-শূন্য-থেকে-শুরু)
- [শুরুর আগে: ৫ মিনিটে যা জানা দরকার](#শুরুর-আগে-৫-মিনিটে-যা-জানা-দরকার)
- [📁 আপনার লোকাল ফাইল কোথায় থাকে](#-আপনার-লোকাল-ফাইল-কোথায়-থাকে)
- [অংশ ১ — একবারের প্রস্তুতি](#অংশ-১--একবারের-প্রস্তুতি)
- [অংশ ২ — প্রথমবার চালিয়ে যাচাই](#অংশ-২--প্রথমবার-চালিয়ে-যাচাই)
- [অংশ ৩ — প্রতিদিনের কাজ](#অংশ-৩--প্রতিদিনের-কাজ)
- [অংশ ৪ — ঐচ্ছিক: পুরো Stack Docker-এ](#অংশ-৪--ঐচ্ছিক-পুরো-stack-docker-এ)
- [অংশ ৫ — সমস্যা হলে](#অংশ-৫--সমস্যা-হলে)
- [অংশ ৬ — পরিষ্কার করা ও নতুন করে শুরু](#অংশ-৬--পরিষ্কার-করা-ও-নতুন-করে-শুরু)
- [পরিশিষ্ট ক — Setup block (বাধ্যতামূলক)](#পরিশিষ্ট-ক--setup-block-বাধ্যতামূলক)
- [পরিশিষ্ট খ — VS Code workspace block](#পরিশিষ্ট-খ--vs-code-workspace-block)
- [পরিশিষ্ট গ — Full Docker block](#পরিশিষ্ট-গ--full-docker-block)
- [পরিশিষ্ট ঘ — Codebase নোট ও টিমের জন্য সুপারিশ](#পরিশিষ্ট-ঘ--codebase-নোট-ও-টিমের-জন্য-সুপারিশ)

---

## 🚀 নতুন ডেভেলপার: শূন্য থেকে শুরু

### আপনাকে কিছু হাতে দেওয়া লাগবে না

এই environment তৈরির জন্য দরকারি **সব কিছু এই গাইডের ভেতরেই আছে** — PostgreSQL/Redis চালানোর কমান্ড, config template, আর helper script (পরিশিষ্ট ক–গ-এর block-এ পুরো content লেখা)।

- `.etp-local` ফোল্ডার **কারো কাছ থেকে নিতে বা কোথাও কপি করে রাখতে হবে না।** আপনি পরিশিষ্ট ক-এর block চালালে সেটা আপনার নিজের মেশিনে `C:\Users\<আপনার-নাম>\.etp-local\` নিজেই তৈরি করবে।
- অন্যের `.etp-local` কপি করে ব্যবহার **করবেন না** — তাতে অন্যের মেশিনের path আর (থাকলে) অন্যের ব্যক্তিগত key থাকে। প্রত্যেকে নিজেরটা block দিয়ে বানাবেন।
- PostgreSQL বা Redis মেশিনে ইনস্টল করতে হবে না — Docker-এ চলে।
- শুরুতে কোনো AWS/Cognito key লাগবে না — dummy মান দিয়ে সব সার্ভিস চলে, health/Swagger/auth-ছাড়া API কাজ করে।

### Team lead-এর কাছ থেকে যা চাইবেন

| কী | কখন লাগবে | বাধ্যতামূলক? |
|---|---|---|
| Git repo access (clone করার অনুমতি) | শুরুতেই | ✅ হ্যাঁ |
| dev Cognito **Pool Id + App Client Id** (+ একটা dev test user) | `[Authorize]` দেওয়া API টেস্ট করতে ([৩.৪](#৩৪-protected-api-টেস্ট-cognito-token)) | পরে, প্রয়োজনে |
| dev AWS IAM key + নিজের নামে SQS queue | S3/SQS ফিচারে কাজ করলে | পরে, প্রয়োজনে |
| TSP certificate `tspgw_client.pfx` | Ticketing-এর টিকিট signing নিয়ে কাজ করলে | পরে, প্রয়োজনে |
| sanitized dev DB dump | আসল-ধরনের ডাটা দিয়ে টেস্ট করতে ([৩.৫](#৩৫-database-কাজ)) | ঐচ্ছিক |

> Key/cert পেলে সেগুলো শুধু নিজের `%USERPROFILE%\.etp-local\user-secrets.json`-এ (বা cert-এর ক্ষেত্রে `bin` ফোল্ডারে) রাখবেন — কখনো repo-তে, chat-এ বা ইমেইলে খোলা অবস্থায় নয়।

### শুরু থেকে শেষ: ১০ ধাপ (প্রথম দিন, ~৪৫ মিনিট)

| # | কী করবেন | কোথায় | যাচাই |
|---|---|---|---|
| 1 | Git, .NET 8 SDK, PowerShell 7, Docker Desktop, VS 2022 বা VS Code ইনস্টল | [১.১](#১১-টুল-ইনস্টল) | `dotnet --list-runtimes`-এ `AspNetCore.App 8.0.x` |
| 2 | repo clone করে build | [১.২](#১২-clone-ও-build) | `Build succeeded` |
| 3 | এই গাইডটা খুলুন: repo-র `docs/local-development-guide.bn.md` | — | — |
| 4 | Docker Desktop চালু করে দুটো `docker run` (Postgres, Redis) | [১.৩](#১৩-postgresql-ও-redis-চালু-docker) | `pg_isready` → accepting, `redis-cli ping` → PONG |
| 5 | repo root-এ `pwsh` খুলে পরিশিষ্ট ক-এর block paste | [১.৪](#১৪-configuration--user-secrets-এক-block-এ), [পরিশিষ্ট ক](#পরিশিষ্ট-ক--setup-block-বাধ্যতামূলক) | `User Secrets applied.` + ফোল্ডারের ঠিকানা |
| 6 | `explorer $env:USERPROFILE\.etp-local` দিয়ে ফোল্ডারটা একবার দেখে নিন | [📁 ফাইল কোথায়](#-আপনার-লোকাল-ফাইল-কোথায়-থাকে) | `README.txt`, `run-services.ps1` ইত্যাদি আছে |
| 7 | IDE প্রস্তুত (VS: Multiple startup / VS Code: পরিশিষ্ট খ) | [১.৫](#১৫-ide-প্রস্তুত-করা) | — |
| 8 | Admin আগে চালান, তারপর বাকিগুলো | [২.১](#২১-admin-আগে-চালান-db-তৈরি-হবে), [২.২](#২২-বাকি-সার্ভিসগুলো-চালান) | migration ৮১ → সব মিলিয়ে ১২৯ |
| 9 | `pwsh $env:USERPROFILE\.etp-local\health.ps1` | [২.৩](#২৩-health-check) | ৯টাই 200 |
| 10 | Event-এর breakpoint-এ থামানো | [২.৫](#২৫-breakpoint-দিয়ে-debug-যাচাই) | IDE breakpoint-এ থামে ✅ |

এরপর থেকে প্রতিদিন শুধু [৩.১ সকালের রুটিন](#৩১-সকালের-রুটিন-২৩-মিনিট)।

> **কোথাও আটকে গেলে:** [অংশ ৫ — সমস্যা হলে](#অংশ-৫--সমস্যা-হলে) দেখুন; না মিললে team lead-কে error-এর পুরো টেক্সট আর কোন ধাপে আটকেছেন সেটা পাঠান।

---

## শুরুর আগে: ৫ মিনিটে যা জানা দরকার

### সিস্টেম এক নজরে

- **.NET 8** ASP.NET Core Web API, **EF Core 8 + PostgreSQL** (README-তে SQL Server লেখা — ওটা পুরনো)।
- প্রতিটা সার্ভিসের স্তর: `*.Service` (API/Program.cs) → `*.Domain` (business logic) → `*.Storage` (DbContext, migration)। শেয়ার্ড কোড `Core/`-এ।
- **Redis** (cache + distributed lock), **AWS** (Cognito login, SQS queue, S3 ফাইল), আর কিছু external API (DgePay, TSP, Firebase)।
- সার্ভিসগুলো একে অপরকে HTTP দিয়ে কল করে — ঠিকানা আসে config-এর `Services:<Name>` থেকে।

### সার্ভিস ও পোর্ট (এই গাইড জুড়ে এগুলোই ব্যবহার হবে)

| সার্ভিস | কাজ | লোকাল URL | Swagger | যাদের কল করে |
|---|---|---|---|---|
| **Admin** | ইভেন্ট/ভেন্যু/প্রোগ্রাম/ইউজার ম্যানেজমেন্ট; **DB migration-এর মালিক** | http://localhost:5099 | `/admin/swagger` | Booking, Event, Ticketing, UserIssue, PushNotification |
| **Event** | ইভেন্ট/ভেন্যু তথ্য (public) | http://localhost:5001 | `/event/swagger` | Admin, Booking |
| **Booking** | সিট রিজার্ভেশন, অর্ডার, পেমেন্ট | http://localhost:5086 | `/booking/swagger` | Admin, Event, Ticketing |
| **Ticketing** | টিকিট তৈরি, PDF, signing | http://localhost:5112 | `/ticketing/swagger` | Admin, Booking, Event |
| **TicketChecker** | গেটে টিকিট যাচাই | http://localhost:5274 | `/ticketchecker/swagger` | Admin, Ticketing |
| **Scheduler** | background job, notification | http://localhost:5033 | `/scheduler/swagger` | Admin, Booking, Ticketing |
| **Utility** | টিকিট প্রসেসিং/মার্জ | http://localhost:5034 ¹ | `/utility/swagger` | Admin, Booking, Ticketing |
| **PushNotification** | ডিভাইস টোকেন | http://localhost:5007 | `/pushnotification/swagger` | — |
| **UserIssue** | ইউজার ইস্যু, chat | http://localhost:56774 | `/userissue/swagger` | Booking, Ticketing |

¹ repo-র `launchSettings.json`-এ Utility আর Scheduler দুটোরই পোর্ট 5033 — একসাথে চালানো যায় না। তাই Utility-কে সবসময় `--urls http://localhost:5034` দিয়ে চালানো হয় (গাইডের script/config নিজেই করে)।
Platform ও UserAuth প্রায় খালি stub সার্ভিস — লোকালে চালানোর দরকার নেই।

### ৬টা নিয়ম যা না জানলে সময় নষ্ট হবে

1. **সব সার্ভিস একটাই PostgreSQL DB শেয়ার করে** (schema `etp`)।
2. **সার্ভিস চালু হলেই নিজে থেকে DB migration চলে।** খালি DB-তে **Admin আগে** চালান — মূল টেবিলগুলো সে বানায়।
3. **Redis না থাকলে কোনো সার্ভিস চালুই হয় না।**
4. **Config থাকে User Secrets-এ** — repo-র `appsettings.json`-এ শুধু `"[see User Secrets]"` লেখা।
5. **Login = AWS Cognito।** Swagger থেকে protected API কল করতে dev Cognito-র token লাগবে ([৩.৪](#৩৪-protected-api-টেস্ট-cognito-token))। `/health` আর `[AllowAnonymous]` endpoint token ছাড়াই চলে।
6. ⚠️ **লোকাল থেকে কখনো শেয়ার্ড dev DB বা dev SQS queue-তে connect করবেন না।** আপনার branch-এর migration শেয়ার্ড DB-তে চলে যাবে, আর আপনার লোকাল worker dev-এর queue message খেয়ে ফেলবে।

---

## 📁 আপনার লোকাল ফাইল কোথায় থাকে

এই গাইডের সব helper script আর আপনার ব্যক্তিগত config **ইচ্ছে করেই repo-র বাইরে** রাখা — যাতে ভুল করেও commit/push না হয়, আর আসল key Docker build-এও না ঢোকে। তাই এগুলো **repo-তে, Solution Explorer-এ বা `git status`-এ দেখা যাবে না।**

| কী | কোথায় |
|---|---|
| Helper ফোল্ডার | **`C:\Users\<আপনার-নাম>\.etp-local\`** |
| PowerShell-এ লিখুন | `$env:USERPROFILE\.etp-local` |
| cmd-এ লিখুন | `%USERPROFILE%\.etp-local` |
| ফোল্ডার খুলতে | `explorer $env:USERPROFILE\.etp-local` |
| প্রতিটা সার্ভিসের User Secrets (আলাদা জায়গা) | `%APPDATA%\Microsoft\UserSecrets\<UserSecretsId>\secrets.json` — VS-এ right-click → **Manage User Secrets** |

ফোল্ডারের ভেতরে কী থাকে এবং কোন ধাপে তৈরি হয়:

```
%USERPROFILE%\.etp-local\
├── README.txt                   ← এই তালিকা + গাইডের ঠিকানা (ফোল্ডার খুলেই পড়ুন)
├── user-secrets.json            ← আপনার config — এখানেই এডিট করবেন           [পরিশিষ্ট ক]
├── apply-secrets.ps1            ← config → সব সার্ভিসের User Secrets           [পরিশিষ্ট ক]
├── run-services.ps1             ← সার্ভিস চালায় (Admin আগে)                    [পরিশিষ্ট ক]
├── health.ps1                   ← সব সার্ভিসের /health                         [পরিশিষ্ট ক]
├── logs\                        ← run-services -NoWindow-এর log
├── etp-backend.code-workspace   ← VS Code debug config (ঐচ্ছিক)               [পরিশিষ্ট খ]
├── docker\                      ← Full Docker compose (ঐচ্ছিক)                 [পরিশিষ্ট গ]
└── tools\                       ← পাশাপাশি dotnet-ef 8 (ঐচ্ছিক)                [১.১]
```

মনে রাখার নিয়ম:
- **script চালান সবসময় repo root থেকে** (যেখানে `RVL-ETP.BackEnd.sln`), কিন্তু script-এর path দিন `.etp-local`-এর — যেমন `pwsh $env:USERPROFILE\.etp-local\run-services.ps1`।
- cmd ব্যবহার করলে `$env:USERPROFILE`-এর বদলে `%USERPROFILE%` লিখুন: `pwsh %USERPROFILE%\.etp-local\run-services.ps1`।
- **কোনো ফাইল হারালে/মুছে গেলে:** repo root থেকে [পরিশিষ্ট ক](#পরিশিষ্ট-ক--setup-block-বাধ্যতামূলক)-র block আবার চালান — সব script আবার তৈরি হবে, আর আপনার `user-secrets.json` থাকলে সেটা অপরিবর্তিত থাকবে। (workspace বা docker ফাইল হারালে পরিশিষ্ট খ/গ আবার চালান।)
- `user-secrets.json`-এ আসল key রাখলে তার একটা ব্যাকআপ রাখুন (যেমন password manager-এ) — কিন্তু কখনো repo-র ভেতরে নয়।
- নতুন মেশিনে গেলে: repo clone + পরিশিষ্ট ক চালালেই এই ফোল্ডার আবার তৈরি হয়; শুধু ব্যাকআপ থেকে নিজের `user-secrets.json` বসিয়ে `apply-secrets.ps1` চালান।

---

## অংশ ১ — একবারের প্রস্তুতি

### ১.১ টুল ইনস্টল

PowerShell **Administrator** হিসেবে খুলে (যেগুলো আগে থেকে আছে বাদ দিন):

| টুল | কেন | ইনস্টল |
|---|---|---|
| Git | clone | `winget install Git.Git` |
| **.NET 8 SDK** | build/run (প্রজেক্ট `net8.0`) | `winget install Microsoft.DotNet.SDK.8` |
| **PowerShell 7** | setup script চালাতে | `winget install Microsoft.PowerShell` |
| **Docker Desktop** | PostgreSQL ও Redis | `winget install Docker.DockerDesktop` → restart → Settings-এ *Use WSL 2 based engine* চালু |
| **Visual Studio 2022** (17.8+) *অথবা* **VS Code** | debug | VS: Workload **ASP.NET and web development**। VS Code: `winget install Microsoft.VisualStudioCode` + extension **C# Dev Kit** |
| dotnet-ef **8.0.11** | migration বানাতে (ঐচ্ছিক) | `dotnet tool install --global dotnet-ef --version 8.0.11` ² |
| DBeaver / pgAdmin | DB দেখতে (ঐচ্ছিক) | `winget install dbeaver.dbeaver` |
| Postman / Bruno | API টেস্ট (ঐচ্ছিক) | — |

² global-এ আগে থেকেই dotnet-ef 9/10 থাকলে সেটা এই .NET 8 প্রজেক্টে `Could not load ... System.Runtime, Version=10.0.0.0` error দেয়। অন্য প্রজেক্টে না লাগলে `dotnet tool update --global dotnet-ef --version 8.0.11 --allow-downgrade`; লাগলে পাশাপাশি রাখুন: `dotnet tool install dotnet-ef --version 8.0.11 --tool-path "$env:USERPROFILE\.etp-local\tools"` এবং `"$env:USERPROFILE\.etp-local\tools\dotnet-ef.exe"` দিয়ে চালান।

যাচাই (নতুন terminal-এ):

```powershell
dotnet --list-runtimes   # Microsoft.AspNetCore.App 8.0.x থাকতে হবে
pwsh --version           # 7.x
docker version           # Server অংশও দেখাতে হবে (Docker Desktop চালু থাকলে)
```

> repo-তে `global.json` নেই, তাই .NET 9/10 SDK দিয়েও build হয় — কিন্তু চালাতে **ASP.NET Core 8 runtime** লাগবেই।

### ১.২ Clone ও Build

```powershell
git clone <repository-url> rvl-gobcb-backend
cd rvl-gobcb-backend
dotnet build RVL-ETP.BackEnd.sln
```

`Build succeeded` দেখলেই হবে। ~১৯০০ warning আসবে — এগুলো বিদ্যমান কোডের, উপেক্ষা করুন।

### ১.৩ PostgreSQL ও Redis চালু (Docker)

Docker Desktop চালু করে ("Engine running") নিচের দুটো কমান্ড **একবার** চালান:

```powershell
docker run -d --name etp-postgres --restart unless-stopped -e POSTGRES_DB=etp_local -e POSTGRES_USER=etp -e POSTGRES_PASSWORD=etp_local_pw -p 5433:5432 -v etp-pgdata:/var/lib/postgresql/data postgres:16.4-alpine
docker run -d --name etp-redis --restart unless-stopped -p 6380:6379 -v etp-redisdata:/data redis:7.4-alpine
```

যাচাই:

```powershell
docker exec etp-postgres pg_isready -U etp -d etp_local   # accepting connections
docker exec etp-redis redis-cli ping                       # PONG
```

| | মান |
|---|---|
| PostgreSQL | `localhost:5433` · DB `etp_local` · user `etp` · password `etp_local_pw` · schema `etp` |
| Redis | `localhost:6380` |

- **পোর্ট 5433/6380 কেন?** মেশিনে অন্য প্রজেক্টের Postgres (5432)/Redis (6379) থাকতে পারে — সংঘর্ষ এড়াতে।
- **`--restart unless-stopped`:** Docker Desktop চালু হলেই এ দুটো নিজে থেকে উঠবে। ডাটা থাকে `etp-pgdata`/`etp-redisdata` volume-এ — container মুছলেও ডাটা থাকে।
- এগুলো শুধু লোকাল টেস্ট মান, কোনো আসল password নয়।

### ১.৪ Configuration — User Secrets (এক block-এ)

repo root-এ **PowerShell 7 (`pwsh`)** খুলে [পরিশিষ্ট ক](#পরিশিষ্ট-ক--setup-block-বাধ্যতামূলক)-র পুরো block কপি-পেস্ট করে Enter দিন।

Block-টা repo-র ভেতরে কিছুই লেখে না। এটা `%USERPROFILE%\.etp-local\`-এ বানায়:

| ফাইল | কী |
|---|---|
| `user-secrets.json` | আপনার ব্যক্তিগত config (DB, Redis, সার্ভিস URL, dummy AWS মান)। পরে নিজের মান এখানেই বসাবেন। আগে থেকে থাকলে block এটাকে ছোঁয় না। |
| `apply-secrets.ps1` | `user-secrets.json` থেকে ১০টা সার্ভিস প্রজেক্টের User Secrets-এ বসায় |
| `health.ps1` | সব সার্ভিসের `/health` একবারে দেখায় |
| `run-services.ps1` | build করে সার্ভিসগুলো চালায় (Admin থাকলে আগে Admin, সে ready হলে বাকিগুলো) |
| `README.txt` | এই ফোল্ডারের প্রতিটা ফাইলের বর্ণনা আর গাইডের ঠিকানা |

শেষে `ok  ETP.Admin.Service.csproj` … `User Secrets applied.` এবং ফোল্ডারের ঠিকানা দেখাবে। ফোল্ডারটা একবার খুলে দেখে নিন: `explorer $env:USERPROFILE\.etp-local`। যাচাই:

```powershell
dotnet user-secrets list --project Services/Admin/ETP.Admin.Service
```

> **User Secrets কী?** প্রতিটা প্রজেক্টের config যা repo-র বাইরে (`%APPDATA%\Microsoft\UserSecrets\<id>\secrets.json`) থাকে এবং শুধু `Development` environment-এ লোড হয়। Visual Studio-তে প্রজেক্টে right-click → **Manage User Secrets** দিয়ে সরাসরি দেখা/এডিট করা যায়।
>
> **পরে মান বদলাতে:** `notepad $env:USERPROFILE\.etp-local\user-secrets.json` → save → repo root থেকে `pwsh $env:USERPROFILE\.etp-local\apply-secrets.ps1`।

### ১.৫ IDE প্রস্তুত করা

**Visual Studio 2022**

1. `RVL-ETP.BackEnd.sln` খুলুন → Build Solution (`Ctrl+Shift+B`)।
2. Solution-এ right-click → **Configure Startup Projects…** → **Multiple startup projects** → নিচেরগুলোতে *Action* = **Start**, *Debug Target* = **http**। **Admin সবার উপরে** রাখুন:
   - প্রতিদিনের সেট: `ETP.Admin.Service`, `ETP.Event.Service`, `ETP.Booking.Service`, `ETP.Ticketing.Service` (+ যেটা নিয়ে কাজ করছেন)
3. ⚠️ **Scheduler আর Utility একসাথে Start দেবেন না** (দুটোরই পোর্ট 5033)। দুটো লাগলে একটা VS-এ, অন্যটা terminal থেকে চালান — যেমন `pwsh $env:USERPROFILE\.etp-local\run-services.ps1 Utility`।
4. VS 17.11+-এ উপরে নাম দিয়ে **Launch Profile** save করা যায় — কিন্তু সেটা repo-তে `RVL-ETP.BackEnd.slnLaunch` ফাইল বানায় (repo-র `.gitignore`-এ নেই)। save করলে এটাকে শুধু নিজের clone-এ লুকান: `Add-Content .git/info/exclude '*.slnLaunch'` (এটা কখনো commit/push হয় না)।
5. **IIS Express** বা **https** profile ব্যবহার করবেন না — সবসময় **http**।

**VS Code**

- **সহজ (কোনো ফাইল ছাড়া):** C# Dev Kit ইনস্টল থাকলে Solution Explorer-এ সার্ভিস প্রজেক্টে right-click → **Debug → Start New Instance**। একবারে একটা সার্ভিস debug করার জন্য যথেষ্ট (Utility-র ক্ষেত্রে পোর্ট 5033 নেবে)।
- **একসাথে কয়েকটা সার্ভিস debug:** repo root থেকে [পরিশিষ্ট খ](#পরিশিষ্ট-খ--vs-code-workspace-block)-র block চালান। এটা repo-র বাইরে `%USERPROFILE%\.etp-local\etp-backend.code-workspace` বানিয়ে VS Code-এ খুলে দেয়। এরপর সবসময় এই workspace ফাইল দিয়েই প্রজেক্ট খুলুন (`code $env:USERPROFILE\.etp-local\etp-backend.code-workspace`)। এতে আছে:
  - প্রতিটা সার্ভিসের debug configuration (`Admin :5099`, `Event :5001` …) — সঠিক পোর্টসহ
  - `ETP: Core (Admin+Event+Booking+Ticketing)` আর `ETP: All services` — build করে একসাথে চালায়
  - `build-sln` task (`Ctrl+Shift+B`)

---

## অংশ ২ — প্রথমবার চালিয়ে যাচাই

### ২.১ Admin আগে চালান (DB তৈরি হবে)

যেকোনো একভাবে:
- **VS:** শুধু `ETP.Admin.Service` startup project করে `F5` (profile **http**)
- **VS Code:** Run and Debug → `Admin :5099` → `F5`
- **Terminal:** `dotnet run --project Services/Admin/ETP.Admin.Service --launch-profile http`

> Console-এ "Now listening on…" লাইন **দেখা যাবে না** (Serilog Microsoft-এর log চেপে রাখে)। এটা স্বাভাবিক — নিচের মতো যাচাই করুন।

```powershell
curl.exe http://localhost:5099/health      # Healthy
docker exec etp-postgres psql -U etp -d etp_local -tAc 'select count(*) from etp."__EFMigrationsHistory";'   # 81
```

### ২.২ বাকি সার্ভিসগুলো চালান

- **VS:** Multiple startup projects দিয়ে `F5` ([১.৫](#১৫-ide-প্রস্তুত-করা))
- **VS Code:** `ETP: All services` → `F5`
- **Terminal (সবচেয়ে সহজ):** repo root থেকে
  ```powershell
  pwsh $env:USERPROFILE\.etp-local\run-services.ps1
  ```
  প্রতিটা সার্ভিস আলাদা window-এ খোলে (window-এর নাম `ETP <Name> :<port>`)। শুধু কয়েকটা চাইলে নাম দিন: `run-services.ps1 Admin Event Booking`। window ছাড়া চালাতে `-NoWindow` (log যাবে `%USERPROFILE%\.etp-local\logs\`-এ)।

সব সার্ভিস উঠলে মোট migration হবে **১২৯** (Admin + Logging + Booking + Ticketing + PushNotification + UserIssue)।

### ২.৩ Health check

```powershell
pwsh $env:USERPROFILE\.etp-local\health.ps1
```

প্রত্যাশিত ফলাফল:

```
Admin             http://localhost:5099   200
Event             http://localhost:5001   200
Booking           http://localhost:5086   200
Ticketing         http://localhost:5112   200
TicketChecker     http://localhost:5274   200
Scheduler         http://localhost:5033   200
Utility           http://localhost:5034   200
PushNotification  http://localhost:5007   200
UserIssue         http://localhost:56774  200
```

`DOWN` দেখালে সেই সার্ভিসের window/Output-এর log দেখুন এবং [অংশ ৫](#অংশ-৫--সমস্যা-হলে) মিলিয়ে নিন।

### ২.৪ Swagger ও একটা আসল API কল

ব্রাউজারে যেকোনো Swagger খুলুন, যেমন http://localhost:5099/admin/swagger বা http://localhost:5001/event/swagger।

DB পর্যন্ত পুরো পথ কাজ করছে কিনা দেখতে একটা auth-ছাড়া endpoint:

```powershell
curl.exe http://localhost:5001/event/api/v1/landing-page-image/public
# [] — 200 OK (DB নতুন, তাই খালি তালিকা)
```

### ২.৫ Breakpoint দিয়ে debug যাচাই

1. ফাইল খুলুন: `Services/Event/ETP.Event.Service/Api/LandingPageImageController.cs`
2. এই লাইনে breakpoint দিন (`F9`): `var result = await siteSettingsManager.GetAllPublishedAsync();`
3. Event সার্ভিস **debugger দিয়ে** চলছে নিশ্চিত করুন (VS/VS Code থেকে `F5`; terminal-এর `dotnet run` হলে VS-এ **Debug → Attach to Process** (`Ctrl+Alt+P`) → `ETP.Event.Service.exe`)।
4. Swagger (http://localhost:5001/event/swagger) থেকে `GET /event/api/v1/landing-page-image/public` → **Try it out → Execute** (অথবা উপরের `curl.exe`)।
5. IDE breakpoint-এ থামবে → `F10`/`F11` দিয়ে এগোন, Locals/Watch-এ মান দেখুন → `F5` দিয়ে চালিয়ে দিন।

থামলে আপনার environment পুরোপুরি তৈরি। 🎉

### ২.৬ যে error log দেখা স্বাভাবিক

শুধু লোকাল dummy config-এর কারণে আসে — সার্ভিস ঠিকই চলে:

| কোথায় | Log | কারণ | কী করবেন |
|---|---|---|---|
| Booking, Scheduler, Utility, TicketChecker | AWS / SQS / `UnrecognizedClientException` | dummy AWS key | AWS ফিচারে কাজ না করলে উপেক্ষা করুন ([৩.৪](#৩৪-protected-api-টেস্ট-cognito-token) দেখুন) |
| Scheduler | `Firebase notification: processing failed` (প্রতি মিনিটে) | Firebase config নেই | উপেক্ষা করুন |
| Ticketing | `CryptographicException: The system cannot find the path specified` — **অনবরত, খুব দ্রুত** | TSP certificate (`tspgw_client.pfx`) নেই; worker-এ retry delay নেই | Ticketing নিয়ে কাজ না করলে Ticketing বন্ধ রাখুন; করলে team lead থেকে cert নিয়ে `Services/Ticketing/ETP.Ticketing.Service/bin/Debug/net8.0/Cert/tspgw_client.pfx`-এ রাখুন (`bin/` git-ignored) |
| সব | `Failed to determine the https port for redirect` | http profile | উপেক্ষা করুন |

### ✅ প্রস্তুতির চেকলিস্ট

- [ ] `docker ps`-এ `etp-postgres` আর `etp-redis` চলছে
- [ ] `dotnet user-secrets list --project Services/Admin/ETP.Admin.Service` মান দেখাচ্ছে
- [ ] `health.ps1`-এ ৯টাই 200
- [ ] Swagger খুলছে
- [ ] Event-এর breakpoint-এ থামছে

---

## অংশ ৩ — প্রতিদিনের কাজ

### ৩.১ সকালের রুটিন (২–৩ মিনিট)

```powershell
# 1. Docker Desktop চালু করুন — etp-postgres আর etp-redis নিজে থেকেই উঠবে
docker ps --filter name=etp-              # দুটো দেখাচ্ছে কিনা

# 2. সর্বশেষ কোড
git pull
dotnet build RVL-ETP.BackEnd.sln

# 3. যেটা নিয়ে কাজ করবেন সেই সার্ভিসগুলো চালান (Admin সবসময় প্রথমে)
#    VS: F5 (Multiple startup)  |  VS Code: ETP: Core  |  অথবা:
pwsh $env:USERPROFILE\.etp-local\run-services.ps1 Admin Event Booking Ticketing

# 4. সব ঠিক আছে?
pwsh $env:USERPROFILE\.etp-local\health.ps1
```

> `git pull`-এ অন্য কারো নতুন migration এলে আলাদা কিছু করতে হবে না — মালিক সার্ভিস (সাধারণত Admin) চালু হওয়ার সময় নিজেই apply করবে।

### ৩.২ কোন কাজে কোন সার্ভিস চালাবেন

সব সময় ৯টা চালানোর দরকার নেই (RAM বাঁচে, log কম হয়):

| কাজ | চালান |
|---|---|
| Admin portal-এর ফিচার (ইভেন্ট, ভেন্যু, প্রোগ্রাম, ইউজার) | Admin, Event |
| বুকিং / অর্ডার / পেমেন্ট flow | Admin, Event, Booking, Ticketing |
| টিকিট তৈরি / PDF | Admin, Booking, Event, Ticketing |
| গেটে টিকিট চেক | Admin, Ticketing, TicketChecker |
| ইউজার ইস্যু / chat | Admin, UserIssue, Booking, Ticketing |
| Push notification / scheduled job | Admin, Booking, Ticketing, Scheduler, PushNotification |
| Ticket processing/merge | Admin, Booking, Ticketing, Utility |

### ৩.৩ কোড লেখা → চালানো → debug

- **Breakpoint দিয়ে:** VS/VS Code থেকে `F5`। কোড বদলালে debugger বন্ধ করে আবার `F5` (VS-এ ছোট পরিবর্তনে **Hot Reload** 🔥 বাটনও কাজ করে)।
- **দ্রুত পরিবর্তন-টেস্ট (debugger ছাড়া):** `dotnet watch` — ফাইল save করলেই বদল প্রয়োগ হয়:
  ```powershell
  dotnet watch --project Services/Event/ETP.Event.Service run --launch-profile http
  ```
  (Utility-র জন্য শেষে `--urls http://localhost:5034` যোগ করুন)
- **চলমান সার্ভিসে debugger লাগানো:** VS → **Debug → Attach to Process** (`Ctrl+Alt+P`) → `ETP.<Name>.Service.exe`; VS Code → Command Palette (`Ctrl+Shift+P`) → **Debug: Attach to a .NET 5+ or .NET Core process** → `ETP.<Name>.Service`।
- **Exception যেখানে হয় সেখানেই থামতে:** VS → `Ctrl+Alt+E` → *Common Language Runtime Exceptions* টিক।
- **Background worker debug:** `Workers/BackgroundServices/*`-এর `ExecuteAsync`-এ breakpoint দিন — বেশিরভাগ worker চালুর পর ১ মিনিট অপেক্ষা করে শুরু হয়।
- **সার্ভিস থেকে সার্ভিসে call:** দুটো সার্ভিসই debugger-এ চালালে দুই জায়গার breakpoint-ই কাজ করে।

### ৩.৪ Protected API টেস্ট (Cognito token)

বেশিরভাগ endpoint-এ `[Authorize]` আছে, token যাচাই হয় **dev AWS Cognito**-র বিপরীতে।

1. team lead-এর কাছ থেকে dev Cognito-র **Pool Id** আর **App Client Id** নিন (Admin/User/TicketChecker/Agent — যেটা লাগে)।
2. `notepad $env:USERPROFILE\.etp-local\user-secrets.json` → `AWS.CognitoPool.<Admin|User|...>`-এর `PoolId`, `ClientId`, আর `Authority`/`Metadata`-র `REPLACE_WITH_DEV_POOL_ID` বদলান → save → repo root থেকে `pwsh $env:USERPROFILE\.etp-local\apply-secrets.ps1` → সার্ভিস restart।
3. Token নিন:
   - **dev frontend থেকে:** dev Admin Portal/Web-এ login → Browser DevTools → Network → যেকোনো API request-এর `Authorization: Bearer …` কপি।
   - **AWS CLI দিয়ে** (app client-এ `USER_PASSWORD_AUTH` চালু থাকলে, dev test user দিয়ে):
     ```powershell
     aws cognito-idp initiate-auth --region ap-southeast-1 --auth-flow USER_PASSWORD_AUTH --client-id <DEV_CLIENT_ID> --auth-parameters USERNAME=<dev-user>,PASSWORD=<password>
     ```
     ফলাফলের `AccessToken` নিন।
4. Swagger-এর **Authorize** বাটনে token দিন (শুধু token)।
5. Admin-এর program-ভিত্তিক endpoint-এ header **`X-Program-Id: <id>`** লাগে (Postman-এ দিন)।

> **AWS key:** S3/SQS ফিচার নিয়ে কাজ করলে dev IAM key একইভাবে `user-secrets.json`-এর `AWS.AccessKey/SecretAccessKey`-এ দিন। `AWS.Queue.*`-এ **নিজের নামে আলাদা queue** দিন (যেমন `etp-dev-<আপনার-নাম>-order-success`) — dev environment-এর queue নাম কখনো নয়।
>
> **সার্ভিস-টু-সার্ভিস token:** `GET http://localhost:5099/admin/api/v1/token` header `ServiceApiKey: local-dev-service-api-key` দিলে internal JWT দেয়।

### ৩.৫ Database কাজ

**দেখা:** DBeaver/pgAdmin → Host `localhost`, Port `5433`, DB `etp_local`, user `etp`, pass `etp_local_pw` → schema **`etp`**। অথবা CLI: `docker exec -it etp-postgres psql -U etp -d etp_local` → `\dt etp.*`

**টেস্ট ডাটা:** কোডে seed নেই — DB খালি থাকে। Admin API দিয়ে ইভেন্ট/ভেন্যু বানান, অথবা team lead থেকে **sanitized** dev dump নিয়ে:

```powershell
docker cp .\etp_dev_sanitized.dump etp-postgres:/tmp/etp.dump
docker exec etp-postgres pg_restore -U etp -d etp_local --clean --if-exists --no-owner /tmp/etp.dump
```

**নতুন migration বানানো** (Redis চালু থাকতে হবে, কারণ `dotnet ef` সার্ভিসের Program.cs চালায়):

```powershell
dotnet ef migrations add <MigrationName> -p Services/Admin/ETP.Admin.Storage -s Services/Admin/ETP.Admin.Service -c AdminDbContext
```

| DbContext | `-p` (migration প্রজেক্ট) | `-s` (startup) |
|---|---|---|
| `AdminDbContext` | `Services/Admin/ETP.Admin.Storage` | `Services/Admin/ETP.Admin.Service` |
| `LoggingDbContext` | `Core/ETP.Core.EntityFramework` | `Services/Admin/ETP.Admin.Service` |
| `BookingDbContext` | `Services/Booking/ETP.Booking.Storage` | `Services/Booking/ETP.Booking.Service` |
| `TicketingDbContext` | `Services/Ticketing/ETP.Ticketing.Storage` | `Services/Ticketing/ETP.Ticketing.Service` |
| `PushNotificationDbContext` | `Services/PushNotification/ETP.PushNotification.Storage` | `Services/PushNotification/ETP.PushNotification.Service` |
| `UserIssueDbContext` | `Services/UserIssue/ETP.UserIssue.Storage` | `Services/UserIssue/ETP.UserIssue.Service` |

`dotnet ef database update` লাগে না — সার্ভিস চালু করলেই apply হয়। Admin প্রজেক্টে দুটো context আছে, তাই সেখানে `-c` বাধ্যতামূলক।

**DB একদম খালি করে আবার শুরু:**

```powershell
docker rm -f etp-postgres
docker volume rm etp-pgdata
# তারপর ১.৩-এর postgres কমান্ডটা আবার চালান, এবং Admin আগে চালু করুন
```

### ৩.৬ Commit-এর আগে

- `git status` দেখুন — শুধু আপনার উদ্দেশ্যমূলক কোড ফাইল থাকা উচিত। `git add -A`/`git add .` এড়িয়ে নির্দিষ্ট ফাইল add করুন।
- `launchSettings.json`, `appsettings*.json` লোকাল সুবিধার জন্য বদলাবেন না — পোর্ট/config বদলাতে `--urls`, User Secrets বা environment variable ব্যবহার করুন।
- আসল key কখনো repo-র ভেতরের কোনো ফাইলে নয় — শুধু User Secrets বা `%USERPROFILE%\.etp-local\`-এ।
- Push-এর আগে: `git log --oneline origin/<branch>..HEAD` দিয়ে দেখুন কী কী যাচ্ছে।

### ৩.৭ দিন শেষে

```powershell
# সার্ভিস বন্ধ: VS/VS Code-এ Stop (Shift+F5), run-services-এর window বন্ধ, অথবা একবারে:
Get-Process ETP.*.Service -ErrorAction SilentlyContinue | Stop-Process

# (ঐচ্ছিক) DB/Redis-ও থামাতে — ডাটা থাকে; পরে `docker start etp-postgres etp-redis`
docker stop etp-postgres etp-redis
```

---

## অংশ ৪ — ঐচ্ছিক: পুরো Stack Docker-এ

Frontend/QA-কে পুরো backend দিতে, বা Dockerfile টেস্ট করতে — সব সার্ভিস container-এ, **একই পোর্টে** (তাই `health.ps1` আর URL একই থাকে)। DB/Redis হিসেবে [১.৩](#১৩-postgresql-ও-redis-চালু-docker)-এর `etp-postgres`/`etp-redis`-ই ব্যবহার হয়।

1. repo root থেকে [পরিশিষ্ট গ](#পরিশিষ্ট-গ--full-docker-block)-র block একবার চালান → `%USERPROFILE%\.etp-local\docker\docker-compose.yml` তৈরি হয় (repo-র বাইরে)।
2. IDE/terminal-এ চলা সার্ভিস আগে বন্ধ করুন (একই পোর্ট)।
3. চালান:

```powershell
$dc = "$env:USERPROFILE\.etp-local\docker\docker-compose.yml"
docker compose -f $dc up -d --build          # প্রথমবার ৯টা image build — ৫–১৫ মিনিট
pwsh $env:USERPROFILE\.etp-local\health.ps1
docker compose -f $dc logs -f booking-service   # একটা সার্ভিসের log
docker compose -f $dc up -d --build booking-service   # কোড বদলের পর একটা rebuild
docker compose -f $dc down                     # বন্ধ (DB ডাটা থাকে)
```

- আসল AWS/Cognito মান দিতে `%USERPROFILE%\.etp-local\docker\services.override.env` বানিয়ে `Key__Sub=value` লিখুন (যেমন `AWS__AccessKey=...`)।
- Container-এ debug কঠিন (Release build) — debug করতে [অংশ ২-৩](#অংশ-৩--প্রতিদিনের-কাজ)-এর IDE পদ্ধতি ব্যবহার করুন। একটা সার্ভিস IDE-তে debug করতে চাইলে `docker compose -f $dc stop <name>-service` করে সেটা IDE থেকে চালান (অন্য container থেকে সেটায় call যাবে না — শুধু আপনার/Swagger-এর call)।
- রুটের `docker-compose.yaml` শুধু CI/ECR-এর জন্য — লোকালে কাজ করে না।

---

## অংশ ৫ — সমস্যা হলে

| সমস্যা / Error | কারণ | সমাধান |
|---|---|---|
| `run-services.ps1` / `health.ps1` / `apply-secrets.ps1` খুঁজে পাচ্ছি না (`not recognized` / `does not exist`) | এগুলো repo-তে নেই, থাকে `%USERPROFILE%\.etp-local\`-এ; অথবা cmd-এ `$env:` লেখা হয়েছে; অথবা পরিশিষ্ট ক এখনো চালানো হয়নি | `Test-Path $env:USERPROFILE\.etp-local\run-services.ps1` → `False` হলে repo root থেকে [পরিশিষ্ট ক](#পরিশিষ্ট-ক--setup-block-বাধ্যতামূলক) চালান। cmd-এ `%USERPROFILE%` লিখুন। [বিস্তারিত](#-আপনার-লোকাল-ফাইল-কোথায়-থাকে) |
| `RedisConnectionException` | Redis চলছে না | `docker start etp-redis`; Docker Desktop চালু আছে কিনা |
| `Npgsql… Failed to connect to 127.0.0.1:5433` | Postgres চলছে না | `docker start etp-postgres` |
| `relation "etp.xxx" does not exist` | Admin-এর migration এখনো হয়নি | Admin আগে চালান |
| `FormatException` / `ConfigurationErrorsException: Distributed lock…` startup-এ | User Secrets বসেনি, config-এ এখনো `[see User Secrets]` | `apply-secrets.ps1` চালান; environment `Development` কিনা দেখুন (http profile) |
| `NullReferenceException` Program.cs-এ (`Application:ServiceName`) — UserIssue | UserIssue-এর Application section নেই | `apply-secrets.ps1` আবার চালান |
| `Address already in use` / পোর্ট বন্ধ | অন্য প্রসেস/container সেই পোর্টে | `Get-NetTCPConnection -LocalPort <port> -State Listen` → `OwningProcess` দেখুন; Docker mode চালু থাকলে `down` করুন; Scheduler+Utility একসাথে VS-এ নয় |
| সব request 401 | Cognito মান dummy / token অন্য pool-এর / মেয়াদ শেষ | [৩.৪](#৩৪-protected-api-টেস্ট-cognito-token) |
| `UriFormatException` কোনো client-এ | কোনো URL config-এ placeholder | `user-secrets.json`-এ সঠিক URL (শেষে `/`) |
| ব্রাউজারে Swagger 404 | launch URL ভুল (Utility/Platform/PushNotification-এর launchSettings-এ) | হাতে লিখুন: `/<prefix>/swagger` (উপরের সার্ভিস টেবিল) |
| `dotnet ef` → `System.Runtime, Version=10.0.0.0` | dotnet-ef 10 | dotnet-ef 8.0.11 ([১.১](#১১-টুল-ইনস্টল)) |
| `dotnet ef` চলাকালে Redis error | ef সার্ভিসের Program.cs চালায় | Redis চালু রাখুন |
| `docker run` → `container name "/etp-postgres" is already in use` | আগে বানানো আছে | `docker start etp-postgres` (নতুন বানাতে হবে না) |
| Ticketing log অনবরত `CryptographicException` | TSP cert নেই | [২.৬](#২৬-যে-error-log-দেখা-স্বাভাবিক) |

---

## অংশ ৬ — পরিষ্কার করা ও নতুন করে শুরু

| কী চান | কমান্ড | কী মুছে যায় |
|---|---|---|
| সার্ভিস বন্ধ | `Get-Process ETP.*.Service -ErrorAction SilentlyContinue \| Stop-Process` | কিছু না |
| DB/Redis থামানো | `docker stop etp-postgres etp-redis` | কিছু না (পরে `docker start …`) |
| Docker mode বন্ধ | `docker compose -f $env:USERPROFILE\.etp-local\docker\docker-compose.yml down` | service container |
| Docker mode-এর image মোছা (~৩.৩GB) | ওই কমান্ডের শেষে `--rmi local` | build করা `etp-local/*` image |
| DB/Redis container মোছা | `docker rm -f etp-postgres etp-redis` | container (ডাটা volume-এ থাকে) |
| **সব লোকাল ডাটা মোছা** | `docker volume rm etp-pgdata etp-redisdata` | ⚠️ DB ও Redis-এর সব ডাটা |
| User Secrets মোছা | `Get-ChildItem Services -Recurse -Filter *.Service.csproj \| ? { Select-String -Path $_.FullName -Pattern '<UserSecretsId>' -Quiet } \| % { dotnet user-secrets clear --project $_.FullName }` | ১০টা সার্ভিসের User Secrets |
| ব্যক্তিগত ফাইল মোছা | `Remove-Item -Recurse $env:USERPROFILE\.etp-local` | ⚠️ আপনার config (`user-secrets.json`), script, workspace, compose — আসল key থাকলে আগে ব্যাকআপ নিন |
| Build output | `dotnet clean RVL-ETP.BackEnd.sln` | bin/obj (TSP cert রাখলে আগে ব্যাকআপ) |

> ❌ `docker system prune -a --volumes` চালাবেন না — মেশিনের **সব** প্রজেক্টের container, image, volume মুছে দেয়।

নতুন করে শুরু: [১.৩](#১৩-postgresql-ও-redis-চালু-docker) → [১.৪](#১৪-configuration--user-secrets-এক-block-এ) → [২.১](#২১-admin-আগে-চালান-db-তৈরি-হবে)।

---

## পরিশিষ্ট ক — Setup block (বাধ্যতামূলক)

repo root-এ **`pwsh`** খুলে পুরো block কপি-পেস্ট করে Enter দিন। (অথবা repo-র **বাইরে** কোথাও `etp-setup.ps1` নামে save করে repo root থেকে `pwsh <path>\etp-setup.ps1` চালান।) একাধিকবার চালানো নিরাপদ — আপনার `user-secrets.json` আগে থেকে থাকলে সেটা বদলায় না।

এটা `%USERPROFILE%\.etp-local\`-এ `user-secrets.json`, `apply-secrets.ps1`, `health.ps1`, `run-services.ps1` আর `README.txt` বানায়, তারপর User Secrets বসায়। শেষ লাইনে ফোল্ডারের ঠিকানা দেখায়। ([ফাইলগুলো কোথায় থাকে](#-আপনার-লোকাল-ফাইল-কোথায়-থাকে))

````powershell
# Run from the repo root in PowerShell 7 (pwsh)
if (-not (Test-Path ./RVL-ETP.BackEnd.sln)) { throw 'Run this from the repo root' }
$etp = Join-Path $env:USERPROFILE '.etp-local'
New-Item -ItemType Directory -Force $etp | Out-Null

# (a) your personal config - left alone if it already exists, so your edits are safe
$secretsFile = Join-Path $etp 'user-secrets.json'
if (-not (Test-Path $secretsFile)) {
Set-Content $secretsFile -Encoding utf8NoBOM -Value @'
{
  "ConnectionStrings": {
    "Admin": "Host=localhost;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true",
    "Booking": "Host=localhost;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true",
    "Event": "Host=localhost;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true",
    "Platform": "Host=localhost;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true",
    "Scheduler": "Host=localhost;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true",
    "TicketChecker": "Host=localhost;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true",
    "Ticketing": "Host=localhost;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true",
    "UserAuth": "Host=localhost;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true",
    "UserIssue": "Host=localhost;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true",
    "PushNotification": "Host=localhost;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true"
  },
  "Services": {
    "Admin": "http://localhost:5099/",
    "Booking": "http://localhost:5086/",
    "Event": "http://localhost:5001/",
    "Platform": "http://localhost:5021/",
    "Scheduler": "http://localhost:5033/",
    "TicketChecker": "http://localhost:5274/",
    "Ticketing": "http://localhost:5112/",
    "UserAuth": "http://localhost:5126/",
    "PushNotification": "http://localhost:5007/",
    "UserIssue": "http://localhost:56774/",
    "AppBase": "http://localhost:4200/"
  },
  "Cache": {
    "Redis": {
      "ConnectionString": "localhost:6380",
      "InstanceName": "etp-local:",
      "DefaultDatabase": "0"
    }
  },
  "DistributedLock": {
    "Redis": {
      "EndPoint": "localhost",
      "Port": "6380",
      "Database": "0",
      "AccessKey": ""
    }
  },
  "Authentication": {
    "Jwt": {
      "Key": "local-dev-only-signing-key-change-me-0123456789abcdef",
      "Issuer": "etp-local",
      "Audience": "etp-local-services"
    },
    "ServiceApiKey": "local-dev-service-api-key",
    "TokenIssuer": "http://localhost:5099/admin/api/v1/token",
    "Authority": "etp-local",
    "Audience": "etp-local-services",
    "ClientSecret": "local-dev-only-signing-key-change-me-0123456789abcdef"
  },
  "AWS": {
    "Region": "ap-southeast-1",
    "AccessKey": "REPLACE_WITH_DEV_ACCESS_KEY",
    "SecretAccessKey": "REPLACE_WITH_DEV_SECRET_KEY",
    "Bucket": {
      "Name": "REPLACE_WITH_DEV_BUCKET",
      "BaseUrl": "https://REPLACE_WITH_DEV_CLOUDFRONT/"
    },
    "Ticket": {
      "Bucket": {
        "Name": "REPLACE_WITH_DEV_TICKET_BUCKET",
        "BaseUrl": "https://REPLACE_WITH_DEV_CLOUDFRONT/"
      },
      "TemplateBase": "templates/",
      "BlankBase": "blank/",
      "SignedBase": "signed/",
      "ShareBase": "share/",
      "MergeBase": "merge/",
      "MergeBuffer": "10",
      "MergeSize": "50",
      "ShareExpiryMinutes": "60",
      "EmailSender": "no-reply@example.local"
    },
    "Queue": {
      "OrderSuccess": "REPLACE_WITH_YOUR_OWN_DEV_QUEUE",
      "EventCapacity": "REPLACE_WITH_YOUR_OWN_DEV_QUEUE",
      "VatChallanProcessing": "REPLACE_WITH_YOUR_OWN_DEV_QUEUE",
      "FirebaseNotification": "REPLACE_WITH_YOUR_OWN_DEV_QUEUE",
      "TicketSigning": "REPLACE_WITH_YOUR_OWN_DEV_QUEUE",
      "TicketProcessing": "REPLACE_WITH_YOUR_OWN_DEV_QUEUE"
    },
    "CognitoPool": {
      "Admin": {
        "PoolId": "REPLACE_WITH_DEV_POOL_ID",
        "Authority": "https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID",
        "ClientId": "REPLACE_WITH_DEV_APP_CLIENT_ID",
        "Metadata": "https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID/.well-known/openid-configuration"
      },
      "User": {
        "PoolId": "REPLACE_WITH_DEV_POOL_ID",
        "Authority": "https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID",
        "ClientId": "REPLACE_WITH_DEV_APP_CLIENT_ID",
        "Metadata": "https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID/.well-known/openid-configuration"
      },
      "TicketChecker": {
        "PoolId": "REPLACE_WITH_DEV_POOL_ID",
        "Authority": "https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID",
        "ClientId": "REPLACE_WITH_DEV_APP_CLIENT_ID",
        "Metadata": "https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID/.well-known/openid-configuration"
      },
      "Agent": {
        "PoolId": "REPLACE_WITH_DEV_POOL_ID",
        "Authority": "https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID",
        "ClientId": "REPLACE_WITH_DEV_APP_CLIENT_ID",
        "Metadata": "https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID/.well-known/openid-configuration"
      }
    }
  },
  "PaymentSettings": {
    "DgePay": {
      "MerchantClientId": "REPLACE_ME",
      "MerchantClientSecret": "REPLACE_ME",
      "MerchantApiKey": "REPLACE_ME",
      "BaseUrl": "https://dgepay-sandbox.invalid/",
      "RedirectUrl": "http://localhost:4200/payment/callback"
    }
  },
  "Notification": {
    "Endpoint": "https://notification.invalid/",
    "Authorization": "local-dummy"
  },
  "Serverless": {
    "BaseUrl": "https://serverless.invalid/",
    "Authorization": "local-dummy"
  },
  "TSP": {
    "AuthUrl": "https://tsp.invalid/auth/",
    "SignUrl": "https://tsp.invalid/sign/",
    "UserId": "REPLACE_ME",
    "DigitalIdentityId": "REPLACE_ME"
  },
  "OneIdSettings": {
    "TokenUrl": "https://oneid.invalid/token",
    "DocumentSyncUrl": "https://oneid.invalid/sync",
    "AuthorizationToken": "REPLACE_ME"
  },
  "CloudfrontTicketValidator": {
    "BucketName": "REPLACE_ME",
    "ObjectKey": "REPLACE_ME"
  }
}
'@
}

# (b) apply script - copies that config into every service's User Secrets
Set-Content (Join-Path $etp 'apply-secrets.ps1') -Encoding utf8NoBOM -Value @'
param([string]$Repo = (Get-Location).Path)
$ErrorActionPreference = 'Stop'
$json = Get-Content (Join-Path $env:USERPROFILE '.etp-local\user-secrets.json') -Raw
$null = $json | ConvertFrom-Json   # stops here if the JSON is broken
$projects = Get-ChildItem (Join-Path $Repo 'Services') -Recurse -Filter '*.Service.csproj' |
    Where-Object { Select-String -Path $_.FullName -Pattern '<UserSecretsId>' -Quiet }
if (-not $projects) { throw "No service projects under $Repo\Services. Run this from the repo root." }
foreach ($p in $projects) {
    $json | dotnet user-secrets set --project $p.FullName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "user-secrets failed: $($p.Name)" }
    Write-Host "ok  $($p.Name)"
}
# UserIssue has no appsettings.json in the repo, so its Application section comes from here
$ui = ($projects | Where-Object Name -eq 'ETP.UserIssue.Service.csproj').FullName
dotnet user-secrets set 'Application:ServiceName' 'userissue' --project $ui | Out-Null
dotnet user-secrets set 'Application:Title' 'RVL ETP ETicketing - User Issue API' --project $ui | Out-Null
dotnet user-secrets set 'Application:Description' 'API for user issue related utilities' --project $ui | Out-Null
Write-Host 'User Secrets applied.' -ForegroundColor Green
'@

# (c) daily helpers - health check and service runner
Set-Content (Join-Path $etp 'health.ps1') -Encoding utf8NoBOM -Value @'
# Checks /health of every ETP service (works for both IDE and Docker mode - same ports)
$services = [ordered]@{ Admin = 5099; Event = 5001; Booking = 5086; Ticketing = 5112; TicketChecker = 5274
                        Scheduler = 5033; Utility = 5034; PushNotification = 5007; UserIssue = 56774 }
foreach ($s in $services.GetEnumerator()) {
    $status = try { (Invoke-WebRequest "http://localhost:$($s.Value)/health" -TimeoutSec 3).StatusCode } catch { 'DOWN' }
    $color = if ($status -eq 200) { 'Green' } else { 'DarkGray' }
    Write-Host ('{0,-17} http://localhost:{1,-6} {2}' -f $s.Key, $s.Value, $status) -ForegroundColor $color
}
'@
Set-Content (Join-Path $etp 'run-services.ps1') -Encoding utf8NoBOM -Value @'
# Starts ETP services with `dotnet run` (Admin first if requested - it runs the DB migrations).
#   run-services.ps1                      -> all 9 services
#   run-services.ps1 Admin Event Booking  -> only these
#   -NoWindow                             -> no console windows; logs go to %USERPROFILE%\.etp-local\logs
param([string[]]$Name, [switch]$NoWindow, [string]$Repo = (Get-Location).Path)
$ErrorActionPreference = 'Stop'
$ports = [ordered]@{ Admin = 5099; Event = 5001; Booking = 5086; Ticketing = 5112; TicketChecker = 5274
                     Scheduler = 5033; Utility = 5034; PushNotification = 5007; UserIssue = 56774 }
if (-not $Name) { $Name = @($ports.Keys) }
if (-not (Test-Path (Join-Path $Repo 'RVL-ETP.BackEnd.sln'))) { throw 'Run this from the repo root.' }
$logs = Join-Path $env:USERPROFILE '.etp-local\logs'
New-Item -ItemType Directory -Force $logs | Out-Null

function Start-Etp([string]$n) {
    $proj = Join-Path $Repo "Services/$n/ETP.$n.Service"
    # --urls also fixes the Utility/Scheduler port clash (both are 5033 in launchSettings.json)
    $runArgs = @('run', '--no-build', '--project', $proj, '--launch-profile', 'http', '--urls', "http://localhost:$($ports[$n])")
    if ($NoWindow) {
        Start-Process dotnet $runArgs -WorkingDirectory $Repo -WindowStyle Hidden `
            -RedirectStandardOutput "$logs\$n.log" -RedirectStandardError "$logs\$n.err.log" | Out-Null
    } else {
        $cmd = "`$host.UI.RawUI.WindowTitle='ETP $n :$($ports[$n])'; dotnet run --no-build --project '$proj' --launch-profile http --urls http://localhost:$($ports[$n])"
        Start-Process pwsh @('-NoExit', '-Command', $cmd) -WorkingDirectory $Repo | Out-Null
    }
    Write-Host "started $n on http://localhost:$($ports[$n])"
}

dotnet build (Join-Path $Repo 'RVL-ETP.BackEnd.sln') -nologo -v q -clp:ErrorsOnly
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }

if ($Name -contains 'Admin') {
    Start-Etp 'Admin'
    Write-Host 'waiting for Admin (migrations)...'
    for ($i = 0; $i -lt 90; $i++) {
        try { if ((Invoke-WebRequest 'http://localhost:5099/health' -TimeoutSec 2).StatusCode -eq 200) { break } } catch { }
        Start-Sleep 2
    }
}
$Name | Where-Object { $_ -ne 'Admin' } | ForEach-Object { Start-Etp $_ }
Write-Host 'Check with: pwsh $env:USERPROFILE\.etp-local\health.ps1' -ForegroundColor Green
'@

# (d) README - what each file in this folder is
Set-Content (Join-Path $etp 'README.txt') -Encoding utf8BOM -Value @'
RVL-ETP (GOBCB) backend - personal local-development files
==========================================================
This folder is deliberately OUTSIDE the git repository, so nothing here is ever committed or pushed.
Full guide: <repo>\docs\local-development-guide.bn.md  (section "আপনার লোকাল ফাইল কোথায় থাকে")

user-secrets.json           Your personal config (DB, Redis, service URLs, AWS/Cognito values). Edit this file.
apply-secrets.ps1           Copies user-secrets.json into the User Secrets of every service.
                            Run from the repo root:  pwsh $env:USERPROFILE\.etp-local\apply-secrets.ps1
run-services.ps1            Builds and starts services (Admin first).
                            Run from the repo root:  pwsh $env:USERPROFILE\.etp-local\run-services.ps1 [Admin Event ...] [-NoWindow]
health.ps1                  Shows /health of all 9 services:  pwsh $env:USERPROFILE\.etp-local\health.ps1
logs\                       Service logs when run-services.ps1 is used with -NoWindow.
etp-backend.code-workspace  (optional) VS Code workspace with debug configs - from guide appendix B.
docker\                     (optional) Full-Docker compose files - from guide appendix C.
tools\                      (optional) side-by-side dotnet-ef 8.0.11.

Lost or deleted something? Re-run the guide's appendix A block from the repo root (your user-secrets.json is kept).
Back up user-secrets.json if it holds real keys (e.g. in a password manager) - never inside the repo.
'@

& (Join-Path $etp 'apply-secrets.ps1')
Write-Host "Your local files are in $etp  (open: explorer $etp)" -ForegroundColor Cyan
````

---

## পরিশিষ্ট খ — VS Code workspace block

repo root থেকে `pwsh`-এ চালান। এটা repo-র বাইরে `%USERPROFILE%\.etp-local\etp-backend.code-workspace` বানিয়ে VS Code-এ খোলে। repo অন্য ফোল্ডারে সরালে আবার চালান।

````powershell
# Run from the repo root in pwsh - writes a VS Code workspace file OUTSIDE the repo
$repo = (Get-Location).Path -replace '\\', '/'
$ws = @'
{
  "folders": [ { "name": "etp-backend", "path": "__REPO__" } ],
  "launch": {
    "version": "0.2.0",
    "configurations": [
      {"name": "Admin :5099", "type": "coreclr", "request": "launch", "program": "${workspaceFolder:etp-backend}/Services/Admin/ETP.Admin.Service/bin/Debug/net8.0/ETP.Admin.Service.dll", "cwd": "${workspaceFolder:etp-backend}/Services/Admin/ETP.Admin.Service", "env": {"ASPNETCORE_ENVIRONMENT": "Development", "ASPNETCORE_URLS": "http://localhost:5099"}},
      {"name": "Event :5001", "type": "coreclr", "request": "launch", "program": "${workspaceFolder:etp-backend}/Services/Event/ETP.Event.Service/bin/Debug/net8.0/ETP.Event.Service.dll", "cwd": "${workspaceFolder:etp-backend}/Services/Event/ETP.Event.Service", "env": {"ASPNETCORE_ENVIRONMENT": "Development", "ASPNETCORE_URLS": "http://localhost:5001"}},
      {"name": "Booking :5086", "type": "coreclr", "request": "launch", "program": "${workspaceFolder:etp-backend}/Services/Booking/ETP.Booking.Service/bin/Debug/net8.0/ETP.Booking.Service.dll", "cwd": "${workspaceFolder:etp-backend}/Services/Booking/ETP.Booking.Service", "env": {"ASPNETCORE_ENVIRONMENT": "Development", "ASPNETCORE_URLS": "http://localhost:5086"}},
      {"name": "Ticketing :5112", "type": "coreclr", "request": "launch", "program": "${workspaceFolder:etp-backend}/Services/Ticketing/ETP.Ticketing.Service/bin/Debug/net8.0/ETP.Ticketing.Service.dll", "cwd": "${workspaceFolder:etp-backend}/Services/Ticketing/ETP.Ticketing.Service", "env": {"ASPNETCORE_ENVIRONMENT": "Development", "ASPNETCORE_URLS": "http://localhost:5112"}},
      {"name": "TicketChecker :5274", "type": "coreclr", "request": "launch", "program": "${workspaceFolder:etp-backend}/Services/TicketChecker/ETP.TicketChecker.Service/bin/Debug/net8.0/ETP.TicketChecker.Service.dll", "cwd": "${workspaceFolder:etp-backend}/Services/TicketChecker/ETP.TicketChecker.Service", "env": {"ASPNETCORE_ENVIRONMENT": "Development", "ASPNETCORE_URLS": "http://localhost:5274"}},
      {"name": "Scheduler :5033", "type": "coreclr", "request": "launch", "program": "${workspaceFolder:etp-backend}/Services/Scheduler/ETP.Scheduler.Service/bin/Debug/net8.0/ETP.Scheduler.Service.dll", "cwd": "${workspaceFolder:etp-backend}/Services/Scheduler/ETP.Scheduler.Service", "env": {"ASPNETCORE_ENVIRONMENT": "Development", "ASPNETCORE_URLS": "http://localhost:5033"}},
      {"name": "Utility :5034", "type": "coreclr", "request": "launch", "program": "${workspaceFolder:etp-backend}/Services/Utility/ETP.Utility.Service/bin/Debug/net8.0/ETP.Utility.Service.dll", "cwd": "${workspaceFolder:etp-backend}/Services/Utility/ETP.Utility.Service", "env": {"ASPNETCORE_ENVIRONMENT": "Development", "ASPNETCORE_URLS": "http://localhost:5034"}},
      {"name": "PushNotification :5007", "type": "coreclr", "request": "launch", "program": "${workspaceFolder:etp-backend}/Services/PushNotification/ETP.PushNotification.Service/bin/Debug/net8.0/ETP.PushNotification.Service.dll", "cwd": "${workspaceFolder:etp-backend}/Services/PushNotification/ETP.PushNotification.Service", "env": {"ASPNETCORE_ENVIRONMENT": "Development", "ASPNETCORE_URLS": "http://localhost:5007"}},
      {"name": "UserIssue :56774", "type": "coreclr", "request": "launch", "program": "${workspaceFolder:etp-backend}/Services/UserIssue/ETP.UserIssue.Service/bin/Debug/net8.0/ETP.UserIssue.Service.dll", "cwd": "${workspaceFolder:etp-backend}/Services/UserIssue/ETP.UserIssue.Service", "env": {"ASPNETCORE_ENVIRONMENT": "Development", "ASPNETCORE_URLS": "http://localhost:56774"}}
    ],
    "compounds": [
      { "name": "ETP: Core (Admin+Event+Booking+Ticketing)", "configurations": ["Admin :5099", "Event :5001", "Booking :5086", "Ticketing :5112"], "preLaunchTask": "build-sln", "stopAll": true },
      { "name": "ETP: All services", "configurations": ["Admin :5099", "Event :5001", "Booking :5086", "Ticketing :5112", "TicketChecker :5274", "Scheduler :5033", "Utility :5034", "PushNotification :5007", "UserIssue :56774"], "preLaunchTask": "build-sln", "stopAll": true }
    ]
  },
  "tasks": {
    "version": "2.0.0",
    "tasks": [
      { "label": "build-sln", "type": "process", "command": "dotnet",
        "args": ["build", "${workspaceFolder:etp-backend}/RVL-ETP.BackEnd.sln", "/property:GenerateFullPaths=true", "/consoleloggerparameters:NoSummary;ErrorsOnly"],
        "problemMatcher": "$msCompile", "group": { "kind": "build", "isDefault": true } }
    ]
  }
}
'@
$file = Join-Path $env:USERPROFILE '.etp-local\etp-backend.code-workspace'
Set-Content $file -Encoding utf8NoBOM -Value $ws.Replace('__REPO__', $repo)
code $file
````

---

## পরিশিষ্ট গ — Full Docker block

repo root থেকে `pwsh`-এ চালান। এটা repo-র বাইরে `%USERPROFILE%\.etp-local\docker\`-এ `docker-compose.yml` আর `services.env` বানায় ([অংশ ৪](#অংশ-৪--ঐচ্ছিক-পুরো-stack-docker-এ))।

````powershell
# Run from the repo root in pwsh - compose files go OUTSIDE the repo (%USERPROFILE%\.etp-local\docker)
$dir = Join-Path $env:USERPROFILE '.etp-local\docker'
New-Item -ItemType Directory -Force $dir | Out-Null
$repo = (Get-Location).Path -replace '\\', '/'
$compose = @'
# RVL-ETP: every .NET service in Docker. DB/Redis = the etp-postgres / etp-redis containers (via host.docker.internal).
name: etp-services

x-svc: &svc
  env_file:
    - path: services.env
    - path: services.override.env
      required: false
  extra_hosts: ["host.docker.internal:host-gateway"]
  restart: on-failure

services:
  admin-service:
    <<: *svc
    build: { context: "__REPO__", dockerfile: Services/Admin/ETP.Admin.Service/Dockerfile }
    image: etp-local/admin-service:dev
    ports: ["5099:8080"]
  event-service:
    <<: *svc
    build: { context: "__REPO__", dockerfile: Services/Event/ETP.Event.Service/Dockerfile }
    image: etp-local/event-service:dev
    ports: ["5001:8080"]
  booking-service:
    <<: *svc
    build: { context: "__REPO__", dockerfile: Services/Booking/ETP.Booking.Service/Dockerfile }
    image: etp-local/booking-service:dev
    ports: ["5086:8080"]
  ticketing-service:
    <<: *svc
    build: { context: "__REPO__", dockerfile: Services/Ticketing/ETP.Ticketing.Service/Dockerfile }
    image: etp-local/ticketing-service:dev
    ports: ["5112:8080"]
    # with the TSP cert: volumes: ["./certs/tspgw_client.pfx:/app/Cert/tspgw_client.pfx:ro"]
  ticketchecker-service:
    <<: *svc
    build: { context: "__REPO__", dockerfile: Services/TicketChecker/ETP.TicketChecker.Service/Dockerfile }
    image: etp-local/ticketchecker-service:dev
    ports: ["5274:8080"]
  scheduler-service:
    <<: *svc
    build: { context: "__REPO__", dockerfile: Services/Scheduler/ETP.Scheduler.Service/Dockerfile }
    image: etp-local/scheduler-service:dev
    ports: ["5033:8080"]
  utility-service:
    <<: *svc
    build: { context: "__REPO__", dockerfile: Services/Utility/ETP.Utility.Service/Dockerfile }
    image: etp-local/utility-service:dev
    ports: ["5034:8080"]
  pushnotification-service:
    <<: *svc
    build: { context: "__REPO__", dockerfile: Services/PushNotification/ETP.PushNotification.Service/Dockerfile }
    image: etp-local/pushnotification-service:dev
    ports: ["5007:8080"]
  userissue-service:
    <<: *svc
    build: { context: "__REPO__", dockerfile: Services/UserIssue/ETP.UserIssue.Service/Dockerfile }
    image: etp-local/userissue-service:dev
    ports: ["56774:8080"]
    environment:
      Application__ServiceName: userissue
      Application__Title: RVL ETP ETicketing - User Issue API
      Application__Description: API for user issue related utilities
'@
Set-Content (Join-Path $dir 'docker-compose.yml') -Encoding utf8NoBOM -Value $compose.Replace('__REPO__', $repo)
Set-Content (Join-Path $dir 'services.env') -Encoding utf8NoBOM -Value @'
ASPNETCORE_ENVIRONMENT=Development
ASPNETCORE_URLS=http://+:8080
ConnectionStrings__Admin=Host=host.docker.internal;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true
ConnectionStrings__Booking=Host=host.docker.internal;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true
ConnectionStrings__Event=Host=host.docker.internal;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true
ConnectionStrings__Platform=Host=host.docker.internal;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true
ConnectionStrings__Scheduler=Host=host.docker.internal;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true
ConnectionStrings__TicketChecker=Host=host.docker.internal;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true
ConnectionStrings__Ticketing=Host=host.docker.internal;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true
ConnectionStrings__UserAuth=Host=host.docker.internal;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true
ConnectionStrings__UserIssue=Host=host.docker.internal;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true
ConnectionStrings__PushNotification=Host=host.docker.internal;Port=5433;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true
Services__Admin=http://admin-service:8080/
Services__Booking=http://booking-service:8080/
Services__Event=http://event-service:8080/
Services__Platform=http://platform-service:8080/
Services__Scheduler=http://scheduler-service:8080/
Services__TicketChecker=http://ticketchecker-service:8080/
Services__Ticketing=http://ticketing-service:8080/
Services__UserAuth=http://userauth-service:8080/
Services__PushNotification=http://pushnotification-service:8080/
Services__UserIssue=http://userissue-service:8080/
Services__AppBase=http://localhost:4200/
Cache__Redis__ConnectionString=host.docker.internal:6380
Cache__Redis__InstanceName=etp-local:
Cache__Redis__DefaultDatabase=0
DistributedLock__Redis__EndPoint=host.docker.internal
DistributedLock__Redis__Port=6380
DistributedLock__Redis__Database=0
DistributedLock__Redis__AccessKey=
Authentication__Jwt__Key=local-dev-only-signing-key-change-me-0123456789abcdef
Authentication__Jwt__Issuer=etp-local
Authentication__Jwt__Audience=etp-local-services
Authentication__ServiceApiKey=local-dev-service-api-key
Authentication__TokenIssuer=http://admin-service:8080/admin/api/v1/token
Authentication__Authority=etp-local
Authentication__Audience=etp-local-services
Authentication__ClientSecret=local-dev-only-signing-key-change-me-0123456789abcdef
AWS__Region=ap-southeast-1
AWS__AccessKey=REPLACE_WITH_DEV_ACCESS_KEY
AWS__SecretAccessKey=REPLACE_WITH_DEV_SECRET_KEY
AWS__Bucket__Name=REPLACE_WITH_DEV_BUCKET
AWS__Bucket__BaseUrl=https://REPLACE_WITH_DEV_CLOUDFRONT/
AWS__Ticket__Bucket__Name=REPLACE_WITH_DEV_TICKET_BUCKET
AWS__Ticket__Bucket__BaseUrl=https://REPLACE_WITH_DEV_CLOUDFRONT/
AWS__Ticket__TemplateBase=templates/
AWS__Ticket__BlankBase=blank/
AWS__Ticket__SignedBase=signed/
AWS__Ticket__ShareBase=share/
AWS__Ticket__MergeBase=merge/
AWS__Ticket__MergeBuffer=10
AWS__Ticket__MergeSize=50
AWS__Ticket__ShareExpiryMinutes=60
AWS__Ticket__EmailSender=no-reply@example.local
AWS__Queue__OrderSuccess=REPLACE_WITH_YOUR_OWN_DEV_QUEUE
AWS__Queue__EventCapacity=REPLACE_WITH_YOUR_OWN_DEV_QUEUE
AWS__Queue__VatChallanProcessing=REPLACE_WITH_YOUR_OWN_DEV_QUEUE
AWS__Queue__FirebaseNotification=REPLACE_WITH_YOUR_OWN_DEV_QUEUE
AWS__Queue__TicketSigning=REPLACE_WITH_YOUR_OWN_DEV_QUEUE
AWS__Queue__TicketProcessing=REPLACE_WITH_YOUR_OWN_DEV_QUEUE
AWS__CognitoPool__Admin__PoolId=REPLACE_WITH_DEV_POOL_ID
AWS__CognitoPool__Admin__Authority=https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID
AWS__CognitoPool__Admin__ClientId=REPLACE_WITH_DEV_APP_CLIENT_ID
AWS__CognitoPool__Admin__Metadata=https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID/.well-known/openid-configuration
AWS__CognitoPool__User__PoolId=REPLACE_WITH_DEV_POOL_ID
AWS__CognitoPool__User__Authority=https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID
AWS__CognitoPool__User__ClientId=REPLACE_WITH_DEV_APP_CLIENT_ID
AWS__CognitoPool__User__Metadata=https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID/.well-known/openid-configuration
AWS__CognitoPool__TicketChecker__PoolId=REPLACE_WITH_DEV_POOL_ID
AWS__CognitoPool__TicketChecker__Authority=https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID
AWS__CognitoPool__TicketChecker__ClientId=REPLACE_WITH_DEV_APP_CLIENT_ID
AWS__CognitoPool__TicketChecker__Metadata=https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID/.well-known/openid-configuration
AWS__CognitoPool__Agent__PoolId=REPLACE_WITH_DEV_POOL_ID
AWS__CognitoPool__Agent__Authority=https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID
AWS__CognitoPool__Agent__ClientId=REPLACE_WITH_DEV_APP_CLIENT_ID
AWS__CognitoPool__Agent__Metadata=https://cognito-idp.ap-southeast-1.amazonaws.com/REPLACE_WITH_DEV_POOL_ID/.well-known/openid-configuration
PaymentSettings__DgePay__MerchantClientId=REPLACE_ME
PaymentSettings__DgePay__MerchantClientSecret=REPLACE_ME
PaymentSettings__DgePay__MerchantApiKey=REPLACE_ME
PaymentSettings__DgePay__BaseUrl=https://dgepay-sandbox.invalid/
PaymentSettings__DgePay__RedirectUrl=http://localhost:4200/payment/callback
Notification__Endpoint=https://notification.invalid/
Notification__Authorization=local-dummy
Serverless__BaseUrl=https://serverless.invalid/
Serverless__Authorization=local-dummy
TSP__AuthUrl=https://tsp.invalid/auth/
TSP__SignUrl=https://tsp.invalid/sign/
TSP__UserId=REPLACE_ME
TSP__DigitalIdentityId=REPLACE_ME
OneIdSettings__TokenUrl=https://oneid.invalid/token
OneIdSettings__DocumentSyncUrl=https://oneid.invalid/sync
OneIdSettings__AuthorizationToken=REPLACE_ME
CloudfrontTicketValidator__BucketName=REPLACE_ME
CloudfrontTicketValidator__ObjectKey=REPLACE_ME
'@
Write-Host "Created $dir\docker-compose.yml" -ForegroundColor Green
````

---

## পরিশিষ্ট ঘ — Codebase নোট ও টিমের জন্য সুপারিশ

**আগের টিম কীভাবে চালাত (repo থেকে অনুমান):** প্রতিটা csproj-এ `<UserSecretsId>` আর `appsettings.json`-এ `"[see User Secrets]"` — অর্থাৎ প্রত্যেকে নিজের মেশিনে User Secrets রাখতেন এবং Visual Studio থেকে F5 দিয়ে চালাতেন। পূর্ণ config-এর মূল কপি AWS SSM Parameter Store-এ (`/rvl/<env>/<service>-service-appsettings`, CI এখান থেকে নেয়)। DB/Redis সম্ভবত শেয়ার্ড dev (AWS RDS/ElastiCache) বা নিজে ইনস্টল করা — নিশ্চিত হতে BS-23-কে জিজ্ঞেস করা ভালো। SSM থেকে মান নিলে শুধু Cognito/S3 জাতীয় মান নিন — ConnectionStrings, Redis আর `AWS:Queue:*` কখনো নয় (নিয়ম ৬)।

**Review-এ পাওয়া বিষয় (আলাদা ticket/PR-এ ঠিক করা ভালো):**

1. **Ticketing `TicketGenerationService`:** `catch`-এর পর কোনো delay নেই — exception হলে loop CPU খেয়ে সেকেন্ডে শত শত error log লেখে (লোকালে cert না থাকলে প্রতি সেকেন্ডে ~৭০০)। Production-এও একই ঝুঁকি।
2. **`launchSettings.json`:** Utility ও Scheduler দুটোই `http` 5033; PushNotification ও Ticketing দুটোই `https` 7007; Utility-র launch URL `scheduler/swagger`, Platform (`http`) ও PushNotification-এর `swagger` — ভুল।
3. **README পুরনো:** SQL Server লেখা (আসলে PostgreSQL); `dotnet ef database update` কমান্ডে `-c` নেই; Docker Compose অংশ লোকালে কাজ করে না।
4. **Config:** UserIssue-এর `appsettings.json` repo-তে নেই; `DistributedLock:Redis:Database` key কোনো `appsettings.json`-এ নেই অথচ কোড এটা ছাড়া চালু হয় না।
5. **নিরাপত্তা:** TSP HttpClient-এ `ServerCertificateCustomValidationCallback = (...) => true`; Swagger সব environment-এ খোলা; কিছু জায়গায় region hardcode।
6. UserAuth ও Platform প্রায় খালি stub; ৪টা `*.Client` প্রজেক্ট solution-এ নেই।
7. টিম রাজি হলে একটা অফিসিয়াল লোকাল setup (Postgres+Redis compose, `appsettings.Development.json` template) repo-তে রাখা যায় — তখন পরিশিষ্ট ক–গ-এর দরকার কমবে।
