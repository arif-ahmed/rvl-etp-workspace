# GoBCB ফিচার ডকুমেন্টেশন (বাংলা)

[English version](../en/README.md)

## 0. এই ডকুমেন্ট সম্পর্কে

**উদ্দেশ্য।** GoBCB (rvl-etp) ইভেন্ট ও টিকিটিং প্ল্যাটফর্মের প্রতিটি ব্যবসায়িক ফিচারের জন্য এই ডকুমেন্ট দেখায় — কোন স্ক্রিন থেকে শুরু হয়, কোন endpoint ও service একে সামলায়, কোন queue ও worker এগিয়ে নেয়, কোন table, Redis key ও file ব্যবহার করে, কোন বাইরের সিস্টেমকে ডাকে, এবং কোড কোথায় আছে। এটি লেখা হয়েছে RVL-এর tech lead-এর জন্য: একজন অভিজ্ঞ .NET ডেভেলপার যিনি আগে কখনো microservices সিস্টেমে কাজ করেননি। Microservice-এর ধারণাগুলো একবার ব্যাখ্যা করা হয়েছে [platform primer](00-platform-primer.md)-এ, এবং প্রতিটি ফিচার প্রয়োজনীয় ব্যাখ্যার লিঙ্ক দেয়।

**কে লিখেছেন এবং কী থেকে।** এটি handover-এর জন্য BS23 delivery পাশ থেকে লেখা হয়েছে, মাত্র দুটি উৎস থেকে:

1. পাঁচটি repository-র সোর্স কোড (read-only), [Evidence baseline](#evidence-baseline)-এ তালিকাভুক্ত commit-গুলোতে;
2. [`docs/architecture/gobcb-aws-architecture.md`](../../../architecture/gobcb-aws-architecture.md) — কীভাবে প্ল্যাটফর্মটি AWS-এ চালানো হয়।

ডেভেলপার টেস্ট গাইড (প্রতিটি ফিচারের ১১ নম্বর অংশ) এই workspace-এর local-development tooling-ও ব্যবহার করে (`docs/local-dev.md`, `docs/*-local.md`, `aspire/`, `floci/`, `postman/`, `scripts/`); দেখুন [Appendix D](93-appendix-d-local-test-reference.md)।

এই ডকুমেন্টে কিছুই বানানো নয়। কোড যেখানে কোনো প্রশ্নের উত্তর দিতে পারে না, সেখানে লেখা থাকে এবং একটি `[UNCONFIRMED: Q-nn]` মার্কার থাকে যা [Open queries](99-open-queries.md)-এর প্রশ্নের সাথে যুক্ত। একটি `[UNCONFIRMED]` বক্তব্য BS23-এর জন্য একটি খোলা প্রশ্ন, কোনো তথ্য নয়।

### Evidence baseline

| Repository (submodule) | Commit |
|---|---|
| `rvl-gobcb-backend` | `430ec16d7554254ff4f6adfa21f9c0c10d3234b2` |
| `rvl-gobcb-admin-portal` | `f62d2756bd9bbd4bfaa92585ae3f999d9f4c213f` |
| `rvl-gobcb-user-portal` | `36aaf58c0dae070da9f958da09451d33e6e47c73` |
| `rvl-gobcb-user-app` | `365b8bee71454d94747b75bef7cb07e8b47b6f8a` |
| `rvl-gobcb-checker-app` | `e919c54dad40a33aecc9922a68637a4a887513e6` |

কোড রেফারেন্সে (`File.cs:123`) লাইন নম্বরগুলো এই commit-গুলোর জন্য বৈধ। কোনো submodule সরে গেলে আপনি যে ফিচারগুলোর উপর নির্ভর করেন তার রেফারেন্স আবার দেখুন।

## কীভাবে পড়বেন

ফিচারগুলো ভাগ করা হয়েছে **কী শুরু করে তা** অনুযায়ী: admin portal-এ একজন কর্মকর্তা (`A-xx`), web portal-এ একজন গ্রাহক (`P-xx`) বা app-এ (`U-xx`), checker app-এ gate-এর কর্মকর্তা (`C-xx`), নিজে থেকে system বা timer/queue থেকে (`S-xx`), অথবা অনেক ফিচারের সাধারণ বিষয় (`X-xx`, authentication ও authorization-এর সবকিছু এখানে)। প্রতিটি ফিচার একটি ফাইল, এবং প্রতিটি ফাইলে একই এগারোলো ভাগ:

| # | Section | এটি কী বলে |
|---|---|---|
| 1 | নাম ও উদ্দেশ্য | ফিচারটি কীর জন্য, ব্যবসায়িক ভাষায় (ইংরেজি ও বাংলা নাম) |
| 2 | ট্রিগার ও অ্যাক্টর | কে শুরু করে, কোন client ও স্ক্রিন থেকে, কোন Cognito pool, role ও program scope-এ |
| 3 | ব্যবসায়িক প্রবাহ | ব্যবসায়িক ব্যবহারকারীর যেভাবে ধাপগুলো দেখেন |
| 4 | কারিগরি প্রবাহ | একই ধাপগুলো component-এর মধ্যে hop হিসেবে; প্রতিটি hop ট্যাগ করা (নিচে দেখুন) |
| 5 | কম্পোনেন্ট | client, service, queue, worker, table, Redis key, bucket ও বাইরের সিস্টেম |
| 6 | API কন্ট্র্যাক্ট | ফিচারটির প্রতিটি endpoint (method, পূর্ণ path, auth, DTO, প্রধান error); মূল endpoint-এর জন্য সম্পূর্ণ JSON নমুনা |
| 7 | ডেটা ও পার্শ্বপ্রতিক্রিয়া | কী লেখা হয়: row, queue message, file, email, push, cache entry |
| 8 | কোড রেফারেন্স | কোথা থেকে পড়া শুরু করবেন: controller, manager, worker, client ফাইল, লাইন নম্বরসহ |
| 9 | হ্যান্ডওভার নোট | সহজেই বাদ পড়া আচরণ, কোডে পাওয়া ঝুঁকি, এবং `[UNCONFIRMED: Q-nn]` বিষয় |
| 10 | কম্পোনেন্ট সম্পর্ক | শুধু এই ফিচারের ছোট একটি ডায়াগ্রাম, এর উপর নির্ভরতা ও যারা এর উপর নির্ভর করে |
| 11 | ডেভেলপার টেস্ট গাইড | স্থানীয়ভাবে কীভাবে চালাবেন: browser, emulator, Postman, Visual Studio debug, ও ফল যাচাই |

**অংশ ৪-এ ব্যবহৃত hop ট্যাগ:**

| ট্যাগ | অর্থ |
|---|---|
| **[HTTP + user token]** | সমন্বয় HTTP কল, কলার Cognito access token বহন করে (client থেকে, বা service করে forward করা) |
| **[HTTP, no token]** | সমন্বয় HTTP কল, token ছাড়া — সাধারণত কোনো background worker থেকে এমন endpoint-এ যেখানে `[Authorize]` নেই |
| **[HTTP, static key]** | configuration-এর কোনো key দিয়ে বাইরের সিস্টেমে HTTP কল |
| **[SQS: Name]** | `AWS:Queue:Name` হিসেবে configured SQS queue-তে message রাখা বা সেখান থেকে পড়া |
| **[Worker: interval, lock]** | কোনো service-এর background worker, তার hard-coded interval ও নেওয়া Redis lock (যদি থাকে) |
| **[SignalR]** | SignalR hub-এর মাধ্যমে WebSocket message |
| **[Shared table]** | একটি service অন্য service যে table লেখে সেটি পড়ে (একই database, দেখুন [primer](00-platform-primer.md#explainer-shared-database)) |

**Path।** Endpoint path সেইভাবেই লেখা হয় যেভাবে service-এর প্রকাশ করে, যেমন `/booking/api/v1/user-booking-order`। প্রথম segment হলো service prefix (দেখুন [path-prefix routing](00-platform-primer.md#explainer-path-prefix-routing))।

## সূচিপত্র

- [00 · Platform primer](00-platform-primer.md): service, client, request path, error format, explainer box
- [01 · System map](01-system-map.md): প্রতিটি component এবং তারা কীভাবে যোগাযোগ করে
- [02 · Traceability matrix](02-traceability-matrix.md): feature → client → endpoint → service → async → data → external
- [03 · Component reverse index](03-component-reverse-index.md): component → সেই ফিচারগুলো যেগুলো তার উপর নির্ভর করে
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

## কোথা থেকে শুরু করবেন

| আপনি… | এই ক্রমে পড়ুন |
|---|---|
| **প্ল্যাটফর্মে নতুন** | [00 · Platform primer](00-platform-primer.md) → [01 · System map](01-system-map.md) → প্রতিটি section থেকে একটি ফিচার |
| **প্রথমবার microservice-এর সামনে একজন .NET ডেভেলপার** | [00 · Platform primer](00-platform-primer.md) — explainer box-গুলো path-prefix routing, shared database, queue ও RedLock ব্যাখ্যা করে। তারপর [X-19](60-cross-cutting/X-19-service-to-service.md) ও [X-25](60-cross-cutting/X-25-redis.md) |
| **নিরাপত্তা-ঝুঁকি যাচাই করছেন** | [01 §8](01-system-map.md#8-where-the-risk-is), তারপর [X-18](60-cross-cutting/X-18-endpoints-without-auth.md), তারপর [99 §5](99-open-queries.md#5-defects--code-that-appears-wrong) |
| **Backend ধরছেন** | [02 · Traceability matrix](02-traceability-matrix.md) §2, তারপর [50 · System-initiated](50-system-initiated/README.md) |
| **কোনো client ধরছেন** | আপনার client-এর section-এর জন্য [02](02-traceability-matrix.md) §2, তারপর [93 · Local test reference](93-appendix-d-local-test-reference.md) |
| **কোনো table, queue বা Redis key বদলাচ্ছেন** | [03 · Component reverse index](03-component-reverse-index.md) — এটি প্রতিটি reader তালিকাভুক্ত করে |
| **এমন প্রশ্ন করেছেন যার উত্তর কোড দিতে পারে না** | [99 · Open queries](99-open-queries.md) — ৭৫টি বিষয়, প্রতিটি external, deployment, ambiguity বা defect হিসেবে চিহ্নিত |
| **স্থানীয়ভাবে সেটআপ করছেন** | [`docs/local-dev.md`](../../../local-dev.md), তারপর [93](93-appendix-d-local-test-reference.md) — কী কী কাজ করে না এবং কেন |
| **কী মুছবেন তা ঠিক করছেন** | [90 · Appendix A](90-appendix-a-legacy.md) |

## সংখ্যা

| | |
|---|---|
| ফিচার ফাইল | **১০৩** (৩১ admin, ১৩ portal, ১০ app, ৬ checker, ১৭ system, ২৬ cross-cutting) |
| Backend service | ৯টি সত্যিকারের + ২টি stub |
| সূচিভুক্ত HTTP endpoint | ৫৮টি controller-এ ৩৫৪টি route |
| Background worker | ১৭ |
| SQS queue | ৬ |
| খোলা প্রশ্ন | **৭৫** (Q-01 … Q-77; Q-21 ও Q-24 অব্যবহৃত) |
| "defect" হিসেবে চিহ্নিত finding | ২৩ — যেগুলো আগে ঠিক করা দরকার |

## আগের খসড়ার সংশোধন

আগের খসড়ার দুটি বক্তব্য ভুল ছিল, এবং কোডের বিপরীতে সংশোধন করা হয়েছে:

| দাবি | সংশোধন |
|---|---|
| "User portal `getAllGeneralNotices` কোথাও কল করে না — এর কোনো caller নেই।" | এটি **কল করা হয়** এবং row-গুলো **নিয়ে ছেঁকে নেওয়া হয়**; শুধু `notices` কখনো template-এ bind করা হয় না (`// Fetch notices but do not start the marquee`)। দেখুন [P-01](20-user-portal/P-01-home-content.md) note 2 এবং [A-31](10-admin-portal/A-31-general-notices.md) note 2। |
| "গ্রাহকের pricing page admin যে ticket-pricing content বদলায় সেটাই পড়ে।" | এটি `program-pricing` পড়ে (event table থেকে live event price)। `getTicketPricingList()`-এর কোনো caller নেই, তাই [A-14](10-admin-portal/A-14-ticket-pricing-content.md)-এ প্রকাশিত কিছুই কখনো দেখানো হয় না। |