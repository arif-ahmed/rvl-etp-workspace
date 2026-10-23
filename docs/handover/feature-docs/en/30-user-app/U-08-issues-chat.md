# U-08 · Report an issue and support chat

> **Bangla name:** ইস্যু রিপোর্ট ও সাপোর্ট চ্যাট
>
> [← 30 · User app](README.md) · [Contents](../README.md) · [Open queries](../99-open-queries.md)

## 1. Name and purpose

**Report an issue and support chat.** The customer raises a problem against one of their orders and then talks to support about it. The rules are the server's: **one issue per order** and **600 characters per description**. The app is the counterpart of [P-12](../20-user-portal/P-12-issues-chat.md); the server-side findings in that entry — the unauthenticated chat REST API, the missing unique index, the size-limit mismatch — apply here unchanged.

## 2. Trigger and actor

Signed-in customer. Routes `/issues` (list), `/reportIssue` (raise), `/chatCommunication` (thread).

## 3. Business flow

1. From **My bookings** the customer opens *Report issue* for an order.
2. They write up to 600 characters, optionally attach a file, and submit; the description becomes the first chat message.
3. The customer sees their issue list with its status (`Open` or `Resolved`).
4. In the thread they send text, see replies, typing indicators and attachments, and download any attachment.

## 4. Technical flow

1. **[HTTP + user token]** `POST userissue/api/v1/user-issue` with `CreateReportIssue { publicOrderId, programId, description }` — the same DTO as the portal ([P-12](../20-user-portal/P-12-issues-chat.md) §6). The 600-character limit and the one-issue-per-order rule are enforced in `ReportIssueManager`, not by a database constraint ([Q-47](../20-user-portal/P-12-issues-chat.md)).
2. **[HTTP + user token]** `GET userissue/api/v1/user-issue/user/{userId}` — the list; `GET userissue/api/v1/user-issue/user-detail/{publicOrderId}` — one issue.
3. **[HTTP + user token]** `GET userissue/api/v1/user-issue-chat/$issueId/messages` — chat history, via `ChatApiService.getMessages(issueId: …)`.
4. **Sending is SignalR-first with REST fallback** (`chat_communication_repository_impl.dart:32-36`):
   ```dart
   try {
     await signalRService.sendMessage(chatModel.toJson());
   } catch (e) {
     await chatApiService.sendMessage(issueId: issueId, chatModel: chatModel);
   }
   ```
   So the app is **not** REST-only: it holds a live SignalR connection (`signal_r_service.dart`, `startConnection(issueId, onNewMessage: …)` / `stopConnection()`), and falls back to `POST userissue/api/v1/user-issue-chat/send` only when the hub call throws. This corrects the assumption recorded in the plan that the app's chat is REST-only.
5. **[HTTP, no auth] → chat REST** `POST userissue/api/v1/user-issue-chat/send` and `GET userissue/api/v1/user-issue-chat/message/$messageId/attachment/download`. `[UNCONFIRMED: Q-46]` — the fallback path is the **unauthenticated** chat API whose `senderId`/`senderType` are client-supplied ([P-12](../20-user-portal/P-12-issues-chat.md) note 1), so the app's fallback path is the exposed one.
6. **Attachments** are uploaded as multipart and downloaded through `DownloadService.downloadFile(url: await chatApiService.getUrl(messageId: …), headers: await chatApiService.getAttachmentHeaders(), …, saveInPublicStorage: true, …)` (`:41-58`), then opened with `openFile`.
7. The 600-character limit is mirrored client-side, but the file-size limit differs from the server's 10 MB ([Q-48](../20-user-portal/P-12-issues-chat.md)) `[UNCONFIRMED: Q-48]`.

## 5. Components

| Kind | Component |
|---|---|
| Client | `lib/presentation/feature/issues/`, `feature/report_issue/`, `feature/chat_communication/` |
| Client services | `ChatCommunicationRepositoryImpl`, `SignalRService`, `ChatApiService`, `DownloadService` |
| Services | UserIssue (REST + SignalR hub) |
| Tables | `UserIssues`, chat messages |
| S3 | `chat-attachments/{reportedIssueId}/…` |
| External | none |

## 6. API contracts

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/userissue/api/v1/user-issue` | User | `CreateReportIssue`; >600 chars or a second issue throws |
| GET | `/userissue/api/v1/user-issue/user/{userId}` | User | issue list |
| GET | `/userissue/api/v1/user-issue/user-detail/{publicOrderId}` | User | one issue |
| WS | `/userissue/chathub` | User or Admin bearer | live send and receive |
| POST | `/userissue/api/v1/user-issue-chat/send` | **none** | REST fallback for a failed hub send |
| GET | `/userissue/api/v1/user-issue-chat/$issueId/messages` | User (used) | history |
| GET | `/userissue/api/v1/user-issue-chat/message/$messageId/attachment/download` | **none** | attachment download |

## 7. Data and side effects

`UserIssues` row, chat message rows, an S3 object per attachment, and a SignalR group membership — identical to the portal ([P-12](../20-user-portal/P-12-issues-chat.md) §7).

## 8. Code references

| What | Where |
|---|---|
| Chat repository | `rvl-gobcb-user-app/data/lib/repository/chat_communication_repository_impl.dart:24-77` |
| SignalR service | `rvl-gobcb-user-app/data/lib/service/signal_r_service.dart` |
| Chat API | `rvl-gobcb-user-app/data/lib/remote/api_service/chat_api_service/` |
| Issue API | `rvl-gobcb-user-app/data/lib/remote/api_service/issue_api_service/` |
| Features | `rvl-gobcb-user-app/lib/presentation/feature/issues/`, `feature/report_issue/`, `feature/chat_communication/` |
| Package | `rvl-gobcb-user-app/pubspec.yaml` (`signalr` client dependency, `open_file`) |
| Server | `rvl-gobcb-backend/Services/UserIssue/ETP.UserIssue.Service/Hubs/UserIssueChatHub.cs`, `Api/ReportIssueChatController.cs` |

## 9. Handover notes

1. **The app's chat is SignalR-first, not REST-only** (§4 note 4). The plan's earlier assumption is corrected here; the portal is SignalR-only and the app adds the REST fallback.
2. **The REST fallback is the unauthenticated endpoint** ([Q-46](../20-user-portal/P-12-issues-chat.md)). A customer on a flaky connection at an event — exactly when support matters most — silently downgrades to the anonymous API.
3. **A failed hub send is swallowed into the fallback**, so a genuine send error surfaces as a REST error and the original SignalR cause is lost (`catch (e)` with an unused `e`).
4. **Attachment download also uses the anonymous endpoint**, and writes into public storage (`saveInPublicStorage: true`), which means any app on the device can read support attachments.
5. **No read receipts from the app** — the unread-count endpoints exist on the server but the app does not call them, so a badge count cannot be shown.
6. **Issue-resolved push is not implemented server-side** ([Q-50](../20-user-portal/P-12-issues-chat.md)), so the app will not notify the customer when support answers.

## 10. Component relationships

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

**Depends on:** [U-06](U-06-my-bookings-tickets.md) (the order), [U-07](U-07-profile-settings.md) (the prefetched user). **Affects:** [A-24](../10-admin-portal/A-24-user-issues-admin.md), the other end of the same thread.

## 11. Developer test guide

**Local testability: Full** for issues and REST; **Partial** for the hub (needs the UserIssue service's WebSocket route).

| Item | Detail |
|---|---|
| Test data and accounts | seeded user `+8801700000011` with at least one paid order |
| Browser | portal equivalents — see [P-12](../20-user-portal/P-12-issues-chat.md) |
| Emulator | run the app; open My tickets → an order → report an issue; watch the app log to see which path a message takes (hub or REST fallback) |
| Postman | `postman/services/etp-userissue.postman_collection.json`: "POST /api/v1/user-issue", "GET /api/v1/user-issue/user/{userId}", "GET /api/v1/user-issue/user-detail/{orderId}", "GET /api/v1/user-issue-chat/{reportedIssueId}/messages", "POST /api/v1/user-issue-chat/send"; set `{{access_token_user}}` |
| Visual Studio debug | `ReportIssueManager.CreateAsync`, `ReportIssueChatManager.SendMessageAsync`, `UserIssueChatHub.JoinUserIssueChat`; client: `ChatCommunicationRepositoryImpl.sendMessage` |
| Verify | SQL on `etp."UserIssues"`; the chat rows; the S3 object under `chat-attachments/{id}/` in Floci; to force the fallback, block the WebSocket URL and send a message |