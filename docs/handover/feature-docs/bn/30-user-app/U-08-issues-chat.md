# U-08 · ইস্যু রিপোর্ট ও সাপোর্ট চ্যাট

> **Bangla name:** ইস্যু রিপোর্ট ও সাপোর্ট চ্যাট
>
> [← 30 · ইউজার অ্যাপ](README.md) · [সূচিপত্র](../README.md) · [ওপেন কোয়ারি](../99-open-queries.md)

## 1. নাম ও উদ্দেশ্য

**ইস্যু রিপোর্ট ও সাপোর্ট চ্যাট।** গ্রাহক তার একটি অর্ডারের বিপরীতে একটি সমস্যা তোলেন এবং এরপর সেটি নিয়ে সাপোর্টের সাথে কথা বলেন। নিয়মগুলো সার্ভারের: **অর্ডারপ্রতি একটি ইস্যু** এবং **বিবরণে ৬০০ অক্ষর**। অ্যাপটি [P-12](../20-user-portal/P-12-issues-chat.md)-এর সংশ্লিষ্ট সংস্করণ; সেই অংশের সার্ভার-সাইড ফলাফলগুলো — unauthenticated chat REST API, অনুপস্থিত unique index, সাইজ-লিমিটের অসামঞ্জস্য — এখানে হুবহু প্রযোজ্য।

## 2. ট্রিগার ও অ্যাক্টর

সাইন-ইন করা গ্রাহক। রুট `/issues` (তালিকা), `/reportIssue` (তোলা), `/chatCommunication` (থ্রেড)।

## 3. ব্যবসায়িক প্রবাহ

1. **My bookings** থেকে গ্রাহক কোনো অর্ডারের জন্য *Report issue* খোলেন।
2. তিনি সর্বোচ্চ ৬০০ অক্ষর লেখেন, চাইলে একটি ফাইল সংযুক্ত করেন এবং জমা দেন; বিবরণটিই চ্যাটের প্রথম বার্তা হয়ে যায়।
3. গ্রাহক তার ইস্যুর তালিকা দেখেন তার স্ট্যাটাসসহ (`Open` বা `Resolved`)।
4. থ্রেডে তিনি টেক্সট পাঠান, উত্তর দেখেন, টাইপিং ইন্ডিকেটর ও সংযুক্তি দেখেন, এবং যেকোনো সংযুক্তি ডাউনলোড করেন।

## 4. কারিগরি প্রবাহ

1. **[HTTP + ইউজার টোকেন]** `CreateReportIssue { publicOrderId, programId, description }` সহ `POST userissue/api/v1/user-issue` — পোর্টালের সঙ্গে একই DTO ([P-12](../20-user-portal/P-12-issues-chat.md) §6)। ৬০০-অক্ষরের সীমা ও অর্ডারপ্রতি একটি ইস্যুর নিয়ম প্রয়োগ করে `ReportIssueManager`, কোনো ডেটাবেস constraint নয় ([Q-47](../20-user-portal/P-12-issues-chat.md))।
2. **[HTTP + ইউজার টোকেন]** `GET userissue/api/v1/user-issue/user/{userId}` — তালিকা; `GET userissue/api/v1/user-issue/user-detail/{publicOrderId}` — একটি ইস্যু।
3. **[HTTP + ইউজার টোকেন]** `GET userissue/api/v1/user-issue-chat/$issueId/messages` — চ্যাটের ইতিহাস, `ChatApiService.getMessages(issueId: …)`-এর মাধ্যমে।
4. **পাঠানো SignalR-প্রথম, REST fallback-সহ** (`chat_communication_repository_impl.dart:32-36`):
   ```dart
   try {
     await signalRService.sendMessage(chatModel.toJson());
   } catch (e) {
     await chatApiService.sendMessage(issueId: issueId, chatModel: chatModel);
   }
   ```
   তাই অ্যাপ **শুধুই REST নয়**: এটি একটি লাইভ SignalR কানেকশন ধরে রাখে (`signal_r_service.dart`, `startConnection(issueId, onNewMessage: …)` / `stopConnection()`), এবং কেবল hub কল থ্রো করলেই `POST userissue/api/v1/user-issue-chat/send`-এ নেমে আসে। এতে প্ল্যানে নথিভুক্ত সেই অনুমান সংশোধিত হয় যে অ্যাপের চ্যাট শুধুই REST।
5. **[HTTP, কোনো auth নেই] → chat REST** `POST userissue/api/v1/user-issue-chat/send` এবং `GET userissue/api/v1/user-issue-chat/message/$messageId/attachment/download`। `[UNCONFIRMED: Q-46]` — fallback পথটি হলো **unauthenticated** chat API, যার `senderId`/`senderType` ক্লায়েন্ট দেয় ([P-12](../20-user-portal/P-12-issues-chat.md) নোট ১), তাই অ্যাপের fallback পথটিই খোলা পথ।
6. **সংযুক্তি** multipart হিসেবে আপলোড হয় এবং `DownloadService.downloadFile(url: await chatApiService.getUrl(messageId: …), headers: await chatApiService.getAttachmentHeaders(), …, saveInPublicStorage: true, …)` (`:41-58`) দিয়ে ডাউনলোড হয়, তারপর `openFile` দিয়ে খোলা হয়।
7. ৬০০-অক্ষরের সীমা ক্লায়েন্ট-সাইডে মিরাল করা আছে, কিন্তু ফাইল-সাইজের সীমা সার্ভারের ১০ MB থেকে আলাদা ([Q-48](../20-user-portal/P-12-issues-chat.md)) `[UNCONFIRMED: Q-48]`।

## 5. কম্পোনেন্ট

| ধরন | কম্পোনেন্ট |
|---|---|
| ক্লায়েন্ট | `lib/presentation/feature/issues/`, `feature/report_issue/`, `feature/chat_communication/` |
| ক্লায়েন্ট সার্ভিস | `ChatCommunicationRepositoryImpl`, `SignalRService`, `ChatApiService`, `DownloadService` |
| সার্ভিস | UserIssue (REST + SignalR hub) |
| টেবিল | `UserIssues`, চ্যাটের বার্তা |
| S3 | `chat-attachments/{reportedIssueId}/…` |
| বাহ্যিক | নেই |

## 6. API কন্ট্র্যাক্ট

| মেথড | পাথ | অথ | নোট |
|---|---|---|---|
| POST | `/userissue/api/v1/user-issue` | User | `CreateReportIssue`; ৬০০-এর বেশি অক্ষর বা দ্বিতীয় ইস্যু থ্রো করে |
| GET | `/userissue/api/v1/user-issue/user/{userId}` | User | ইস্যু তালিকা |
| GET | `/userissue/api/v1/user-issue/user-detail/{publicOrderId}` | User | একটি ইস্যু |
| WS | `/userissue/chathub` | User বা Admin bearer | লাইভ পাঠানো ও নেওয়া |
| POST | `/userissue/api/v1/user-issue-chat/send` | **নেই** | ব্যর্থ hub পাঠানোর জন্য REST fallback |
| GET | `/userissue/api/v1/user-issue-chat/$issueId/messages` | User (ব্যবহৃত) | ইতিহাস |
| GET | `/userissue/api/v1/user-issue-chat/message/$messageId/attachment/download` | **নেই** | সংযুক্তি ডাউনলোড |

## 7. ডেটা ও পার্শ্বপ্রতিক্রিয়া

`UserIssues` রো, চ্যাট বার্তার রো, প্রতিটি সংযুক্তির জন্য একটি S3 অবজেক্ট, এবং একটি SignalR গ্রুপ মেম্বারশিপ — পোর্টালের হুবহু ([P-12](../20-user-portal/P-12-issues-chat.md) §7)।

## 8. কোড রেফারেন্স

| কী | কোথায় |
|---|---|
| চ্যাট রিপোজিটরি | `rvl-gobcb-user-app/data/lib/repository/chat_communication_repository_impl.dart:24-77` |
| SignalR সার্ভিস | `rvl-gobcb-user-app/data/lib/service/signal_r_service.dart` |
| চ্যাট API | `rvl-gobcb-user-app/data/lib/remote/api_service/chat_api_service/` |
| ইস্যু API | `rvl-gobcb-user-app/data/lib/remote/api_service/issue_api_service/` |
| ফিচার | `rvl-gobcb-user-app/lib/presentation/feature/issues/`, `feature/report_issue/`, `feature/chat_communication/` |
| প্যাকেজ | `rvl-gobcb-user-app/pubspec.yaml` (`signalr` client dependency, `open_file`) |
| সার্ভার | `rvl-gobcb-backend/Services/UserIssue/ETP.UserIssue.Service/Hubs/UserIssueChatHub.cs`, `Api/ReportIssueChatController.cs` |

## 9. হ্যান্ডওভার নোট

1. **অ্যাপের চ্যাট SignalR-প্রথম, শুধুই REST নয়** (§4 নোট ৪)। প্ল্যানের আগের অনুমান এখানে সংশোধিত; পোর্টাল SignalR-শুধু এবং অ্যাপ সেই সাথে REST fallback যোগ করে।
2. **REST fallback-টি হলো unauthenticated এন্ডপয়েন্ট** ([Q-46](../20-user-portal/P-12-issues-chat.md))। ইভেন্টের ময়দানে দুর্বল কানেকশনে থাকা একজন গ্রাহক — ঠিক যখন সাপোর্ট সবচেয়ে বেশি দরকার — নীরবে anonymous API-তে নেমে আসে।
3. **ব্যর্থ hub পাঠানো fallback-এ গিলে যায়**, ফলে আসল পাঠানোর ত্রুটি একটি REST ত্রুটি হিসেবে দেখা যায় এবং মূল SignalR কারণ হারিয়ে যায় (`catch (e)`-তে অব্যবহৃত `e`)।
4. **সংযুক্তি ডাউনলোডও anonymous এন্ডপয়েন্ট ব্যবহার করে**, আর public storage-এ লেখে (`saveInPublicStorage: true`), যার মানে ডিভাইসের যেকোনো অ্যাপ সাপোর্টের সংযুক্তি পড়তে পারে।
5. **অ্যাপ থেকে কোনো read receipt নেই** — unread-count এন্ডপয়েন্টগুলো সার্ভারে আছে কিন্তু অ্যাপ সেগুলো কল করে না, তাই badge-এর কাউন্ট দেখানো যায় না।
6. **ইস্যু resolved হওয়ার পুশ সার্ভার-সাইডে বাস্তবায়িত নয়** ([Q-50](../20-user-portal/P-12-issues-chat.md)), তাই সাপোর্ট উত্তর দিলে অ্যাপ গ্রাহককে জানাবে না।

## 10. কম্পোনেন্ট সম্পর্ক

```mermaid
flowchart LR
  C["Customer"] --> RI["/reportIssue"]
  RI -->|"POST user-issue"| API["UserIssue API"]
  API --> M["ReportIssueManager"]
  M --> DB[("UserIssues + messages")]
  RI --> CH["/chatCommunication"]
  CH <-->|"WebSocket chathub"| HUB["UserIssueChatHub"]
  CH -->|"fallback only"| REST["user-issue-chat REST<br/>(anonymous)"]
  CH --> S3[("S3 chat-attachments")]
  A["Support agent"] -.-> see A-24
```

**নির্ভর করে:** [U-06](U-06-my-bookings-tickets.md) (অর্ডার), [U-07](U-07-profile-settings.md) (আগেই আনা ব্যবহারকারী)। **প্রভাব ফেলে:** [A-24](../10-admin-portal/A-24-user-issues-admin.md), একই থ্রেডের অপার প্রান্ত।

## 11. ডেভেলপার টেস্ট গাইড

**লোকালভাবে টেস্টযোগ্য:** ইস্যু ও REST-এর জন্য **সম্পূর্ণ**; hub-এর জন্য **আংশিক** (UserIssue সার্ভিসের WebSocket রুট দরকার)।

| আইটেম | বিস্তারিত |
|---|---|
| টেস্ট ডেটা ও অ্যাকাউন্ট | কমপক্ষে একটি পরিশোধিত অর্ডারসহ seeded ইউজার `+8801700000011` |
| ব্রাউজার | পোর্টালে সমতুর্য — [P-12](../20-user-portal/P-12-issues-chat.md) দেখুন |
| এমুলেটর | অ্যাপ চালু করুন; My tickets খুলুন → একটি অর্ডার → ইস্যু রিপোর্ট করুন; কোন পথে বার্তা যাচ্ছে (hub নাকি REST fallback) তা দেখতে অ্যাপের লগ দেখুন |
| Postman | `postman/services/etp-userissue.postman_collection.json`: "POST /api/v1/user-issue", "GET /api/v1/user-issue/user/{userId}", "GET /api/v1/user-issue/user-detail/{orderId}", "GET /api/v1/user-issue-chat/{reportedIssueId}/messages", "POST /api/v1/user-issue-chat/send"; `{{access_token_user}}` সেট করুন |
| Visual Studio ডিবাগ | `ReportIssueManager.CreateAsync`, `ReportIssueChatManager.SendMessageAsync`, `UserIssueChatHub.JoinUserIssueChat`; ক্লায়েন্ট: `ChatCommunicationRepositoryImpl.sendMessage` |
| যাচাই | `etp."UserIssues"`-এ SQL; চ্যাটের রো; Floci-তে `chat-attachments/{id}/`-এর নিচে S3 অবজেক্ট; fallback বাধ্য করতে WebSocket URL ব্লক করে একটি বার্তা পাঠান |