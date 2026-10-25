# E-Ticketing Platform — Production Incident & Reliability Review

তুমি যে documentation তৈরি করতে চাচ্ছ, সেটার মূল উদ্দেশ্য হওয়া উচিত **RVL E-Ticketing Platform (ETP) live হওয়ার পর বাস্তবে কী কী technical issue, operational challenge এবং incident-এর মুখোমুখি হয়েছিল—সেগুলোর evidence-based post-launch review তৈরি করা।**

শুধু article-এর challenge-গুলো কপি করলে হবে না। আমাদের আলাদা করে চিহ্নিত করতে হবে:

- **Reported incidents:** প্রকাশিত article-এ যে ঘটনাগুলো সরাসরি উল্লেখ করা হয়েছে।
- **Root cause / contributing factors:** সমস্যাগুলো কেন হয়েছিল, article-এ যা ব্যাখ্যা করা হয়েছে।
- **Production risks:** একই ধরনের ticketing platform-এ যে ঝুঁকিগুলো পরীক্ষা করা দরকার, যদিও এই platform-এ সেগুলো ঘটেছিল বলে প্রমাণ নেই।
- **Recommended actions:** ভবিষ্যতে incident প্রতিরোধ, detection এবং recovery-এর জন্য কী করা উচিত।

আমি তোমার দেওয়া Future Startup-এর article-টি পড়েছি। সেখানে BPL 2025-এর ticket sales এবং stadium gate validation-এর বাস্তব অভিজ্ঞতা নিয়ে বেশ কিছু গুরুত্বপূর্ণ ঘটনা বর্ণনা করা হয়েছে.

## 1. Live হওয়ার পর reported incident ও challenge তালিকা

নিচের তালিকাটি article-এ প্রকাশিত তথ্যের ভিত্তিতে তৈরি। Article-টি একটি vendor-published brand story, তাই এগুলোকে independent incident audit বা সম্পূর্ণ production incident log হিসেবে ধরে নেওয়া ঠিক হবে না.

### INC-01 — Duplicate ticket redemption

**Priority:** High  
**Date:** 30 Dec 2024 · First match  
**Status:** Reported incident

- প্রথম ম্যাচে আনুমানিক 500–1,000 duplicate scan/entry attempt-এর কথা article-এ বলা হয়েছে।
- কিছু দর্শক PDF ticket-এর photocopy ব্যবহার করে একাধিক gate দিয়ে প্রবেশের চেষ্টা করেছিলেন।
- পরের ম্যাচগুলোতে duplicate সংখ্যা কমে আসে; চতুর্থ ম্যাচে single digits-এ পৌঁছানোর দাবি করা হয়েছে।

**Contributing factors:** Offline validation, delayed synchronization, conflict resolution-এর দুর্বলতা এবং একই ticket একাধিক gate-এ উপস্থাপন করা।

**যা যাচাই করতে হবে:** Duplicate attempt-এর সংখ্যা আর বাস্তবে unauthorized entry-এর সংখ্যা এক নয়। Article থেকে কতগুলো fraudulent entry সফল হয়েছিল তা নিশ্চিত হওয়া যায় না.

### INC-02 — Validation synchronization delay

**Priority:** High  
**Status:** Reported production issue

- প্রথম দিনের validation-এ sync delay দেখা যায়।
- Devices-এর মধ্যে ticket usage status সময়মতো propagate না হওয়ায় duplicate detection প্রভাবিত হয়েছিল।
- Sync interval এক মিনিট থেকে 30 seconds করা হয় এবং conflict-resolution logic উন্নত করা হয়।

**যা যাচাই করতে হবে:** Device offline থাকলে, sync API ব্যর্থ হলে, অথবা একই ticket দুটি device প্রায় একই সময়ে scan করলে final state কীভাবে নির্ধারিত হয়?

### INC-03 — Payment failure এবং retry challenge

**Priority:** High  
**Status:** Reported during UAT / pre-launch

- Article-এ payment failure rate 20–30% উল্লেখ করা হয়েছে।
- Payment gateway-এর capacity এবং ভিন্ন gateway-এর scaling behaviour সমস্যা তৈরি করেছিল।
- Retry logic ও একাধিক gateway ব্যবহারের মাধ্যমে resilience বাড়ানোর কথা বলা হয়েছে।

**যা যাচাই করতে হবে:** Payment সফল হলেও ticket তৈরি না হওয়া, payment timeout-এর পরে duplicate charge, callback/webhook দেরিতে আসা এবং refund/reconciliation mismatch ঘটেছিল কি না। এগুলো গুরুত্বপূর্ণ তদন্তের বিষয়, কিন্তু article-এ নিশ্চিত incident হিসেবে উল্লেখ করা হয়নি.

### INC-04 — Gate validation device slowdown / crash

**Priority:** High operational impact  
**Status:** Reported during testing

- কিছু low-memory personal phone প্রায় এক ঘণ্টা ব্যবহারের পর ধীর হয়ে যাচ্ছিল বা crash করছিল।
- এর ফলে gate processing-এ bottleneck হওয়ার ঝুঁকি তৈরি হয়।
- সমাধান হিসেবে standardized validation device ব্যবহারের সিদ্ধান্ত নেওয়া হয়।

**যা যাচাই করতে হবে:** দীর্ঘ সময়ের soak test, memory leak, battery/thermal throttling, scanner camera performance এবং app recovery time.

### INC-05 — Seat overselling / inventory race condition

**Priority:** High business impact  
**Status:** Reported during QA

- একই seat একাধিক ক্রেতার কাছে বিক্রি হয়ে যাওয়ার race condition testing-এ ধরা পড়ে।
- Database locking ও queue management উন্নত করা হয়।

**যা যাচাই করতে হবে:** একই seat-এর concurrent purchase, payment pending অবস্থায় seat hold, hold expiry, cancellation-এর পর inventory release এবং একই inventory একাধিক checkout-এ reserve হওয়ার সম্ভাবনা.

### INC-06 — Slow validation ও gate congestion

**Priority:** High operational impact  
**Status:** Pre-production design failure

- Central database-এ প্রতিটি scan যাচাই করার প্রাথমিক পদ্ধতিতে প্রতি ticket-এ 30–60 seconds লাগছিল।
- এই latency stadium-এর entry throughput-এর জন্য অগ্রহণযোগ্য ছিল।
- Local cache এবং offline-online hybrid validation ব্যবহার করে processing sub-second পর্যায়ে আনার কথা article-এ বলা হয়েছে।

**যা যাচাই করতে হবে:** P95/P99 scan latency, gate প্রতি scans/minute, queue length, এবং network ফিরে এলে synchronization backlog কত দ্রুত clear হয়.

### INC-07 — False rejection ও checker workflow confusion

**Priority:** Customer / operational impact  
**Status:** Reported production challenge

- Sync delay বা database conflict-এর কারণে legitimate ticket holder-ও rejection-এর মুখোমুখি হতে পারেন।
- Checker-দের error message বোঝা এবং edge case সামলানো সহজ ছিল না।
- Article অনুযায়ী নতুন validation process-এ অভ্যস্ত হতে checker-দের প্রায় তিনটি ম্যাচ লেগেছিল।

**যা যাচাই করতে হবে:** False-rejection rate, manual escalation, support response time, এবং gate staff-এর training ও fallback procedure.

### INC-08 — Slow seat map ও unclear payment confirmation

**Priority:** User experience impact  
**Status:** Reported during UAT

- Seat map ধীরে load হচ্ছিল।
- Payment confirmation যথেষ্ট পরিষ্কার ছিল না।
- Validation app-এর feedback-ও checker-দের জন্য অস্পষ্ট ছিল।

**যা যাচাই করতে হবে:** Mobile network-এ page-load time, checkout abandonment, payment-এর পর ticket status, এবং refresh করলে duplicate transaction বা ticket creation হয় কি না.

## 2. Incident timeline

1. **7 December 2024 — UAT**  
   Seat-map performance, payment confirmation এবং checker feedback-এর সমস্যা শনাক্ত।

2. **15 December 2024 — Scope change**  
   Partner-দের জন্য physical/printable ticket-এর ব্যবস্থা করার অনুরোধ আসে। Online-only assumptions পরিবর্তন করে mixed online/offline ticketing যুক্ত করতে হয়।

3. **23–24 December 2024 — Ticket sales launch**  
   Article অনুযায়ী ticket sales শুরুতে ভালোভাবে সামলানো হয়েছিল।

4. **25 December 2024 — Validation stabilization**  
   Offline-online validation app sub-second processing-এ স্থিতিশীল হওয়ার কথা বলা হয়েছে।

5. **30 December 2024 — First live match**  
   Duplicate scan/entry attempts, sync delay এবং checker workflow-এর সমস্যা সামনে আসে।

6. **Match 2–4 — Incident reduction**  
   Sync interval কমানো, conflict-resolution changes এবং device optimization-এর পর duplicate সংখ্যা ক্রমান্বয়ে কমে আসে।

7. **January 2025 — Post-launch improvements**  
   Gate throughput analytics, payment integration refinement এবং validation performance optimization করা হয়। Article-এ scan time আরও 20% কমার কথা বলা হয়েছে।

> **Timeline note:** Future Startup article-এ বর্ণিত তারিখ ও ঘটনাগুলো থেকে সংকলিত; এটি পূর্ণাঙ্গ internal incident log নয়.

## 3. Documentation-এ আর কী কী investigation থাকা উচিত?

এখানে গুরুত্বপূর্ণ পার্থক্য আছে: নিচের বিষয়গুলোকে **confirmed incident** হিসেবে লেখা যাবে না। এগুলো production-readiness review-এর জন্য investigation checklist.

| Area | কী খুঁজবে |
|---|---|
| Payment integrity | Gateway success বনাম order/ticket status mismatch, duplicate charge, callback retry |
| Inventory integrity | Double booking, seat hold expiry, payment timeout-এর পরে seat release |
| Ticket security | QR replay, PDF sharing, signature verification failure, revoked ticket acceptance |
| Offline validation | Sync failure, stale cache, conflicting scans, device clock drift |
| Availability | Traffic spike, API/DB saturation, timeout, service restart, dependency outage |
| Data consistency | Order, payment, ticket, seat ও refund status-এর মধ্যে mismatch |
| Operations | Gate congestion, checker device crash, manual admission, customer complaints |
| Observability | Alert coverage, incident detection time, recovery time, audit log completeness |
| Deployment | Production hotfix regression, app-version mismatch, rollback ও configuration errors |
| Business reconciliation | বিক্রি হওয়া ticket, payment settlement, gate entry এবং refund-এর হিসাবের পার্থক্য |

এগুলোর প্রত্যেকটির ক্ষেত্রে evidence হিসেবে application log, payment gateway report, monitoring dashboard, database audit trail, support ticket, deployment history ও operations report সংগ্রহ করা উচিত.

## 4. Recommended documentation format

আমি এটিকে একটি **Production Incident & Reliability Review** হিসেবে সাজানোর পরামর্শ দেব। শুধু সমস্যা নয়, প্রতিটি সমস্যার impact, evidence এবং follow-up action একই জায়গায় থাকবে.

### Production Incident Record template

প্রতিটি incident-এর জন্য এই template ব্যবহার করতে পারো:

```markdown
# Production Incident Record

- Incident: Duplicate ticket redemption
- Evidence status: Reported in public source
- Impact: Gate operations / ticket security
- Root cause / contributing factors: Offline synchronization delay and conflict resolution
- Evidence / source: Future Startup article; internal logs pending
- Recommended action: Review scan logs, sync conflicts, and duplicate redemption metrics
```

Evidence status-এর সম্ভাব্য মান:

- `Reported` — public source-এ উল্লেখ আছে
- `Verified` — internal evidence দিয়ে যাচাই করা হয়েছে
- `Partially Verified` — কিছু তথ্য যাচাই হয়েছে, সব নয়
- `Unverified` — এখনও internal evidence পাওয়া যায়নি
- `Hypothesis` — তদন্ত করার মতো সম্ভাব্য ঝুঁকি, confirmed incident নয়

## 5. কোন source-গুলো কাজে লাগবে?

- **মূল case study:** [Future Startup — E-Ticketing Platform delivery ও production challenges](https://futurestartup.com/2025/10/20/brain-station-23-built-a-national-e-ticketing-platform-in-eight-weeks/)
- **Official platform documentation:** [goBCB E-Ticketing FAQ](https://www.gobcbticket.com.bd/en/faq) — QR ticket এবং stadium verification-এর user-facing flow বোঝার জন্য।

একটি সীমাবদ্ধতা মনে রাখা জরুরি: এই public article-এ incident-এর বিবরণ আছে, কিন্তু পূর্ণাঙ্গ incident ID, exact timestamps, log evidence, outage duration, payment failure-এর বিস্তারিত breakdown বা প্রতিটি incident-এর verified root-cause report নেই। এগুলো পেতে RVL/ETP-এর internal evidence প্রয়োজন.

## Recommendation

প্রথমে article-এ নিশ্চিতভাবে বর্ণিত ৮টি challenge নিয়ে incident register তৈরি করো। এরপর internal logs এবং operations data দিয়ে প্রতিটির status `Verified`, `Partially Verified` বা `Unverified` করো। এতে documentation-টি অনুমাননির্ভর তালিকা না হয়ে বাস্তব production reliability review হবে।
