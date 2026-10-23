# Extraction report 02 — Backend: TicketChecker, UserIssue, Utility, PushNotification, Scheduler (+ stubs) (Explore agent, 2026-10-22)

Repo root: `rvl-gobcb-backend/`. All paths relative to it.

## 0. Cross-cutting Core infrastructure
- JWT/Cognito auth — `Core/ETP.Core/Configuration/DefaultAuthenticationConfig.cs`: 5 schemes (`user`, `admin` default, `ticket-checker`, `agent`, `service`); config keys `AWS:CognitoPool:{Pool}:Authority|ClientId|Metadata`; audience via `client_id` claim; OnTokenValidated injects roles (admin role injection commented out). SignalR paths `/userissue/chathub`, `/admin/chathub` accept `?access_token=`.
- Policies — `Core/ETP.Core/Configuration/AuthorizationConfig.cs`: `Service`, `Admin`, `User`, `TicketChecker`, `Agent`.
- Route prefixing — `Core/ETP.Core/Conventions/GlobalRoutePrefixConvention.cs` with `Application:ServiceName`.
- X-Program-Id: inbound filter only in Admin; outbound header in `Core/ETP.Core/ServiceClient/AdminClient/AdminClient.cs`. UserIssue scopes by `programId` query/body instead.
- SQS — raw AWS SDK; publisher `Core/ETP.Core/Queue/Services/SqsPublisher.cs` (FIFO via GroupId/OrderId if queue name ends "fifo"); consumers are hand-rolled ReceiveMessageAsync loops.
- Event bus — `Core/ETP.Core.EventBus` MassTransit over SQS registered in Booking, Scheduler, TicketChecker, Utility — no IConsumer found (unused).
- Redis/RedLock — `Core/ETP.Core/Configuration/{RedisConfig,DistributedLockConfig}.cs` (keys `DistributedLock:Redis:EndPoint|Port|Database`).
- Message DTOs — `Core/ETP.Core/Queue/Messages/`: `IMessage {GroupId, OrderId}`, `TicketProcessingRequest`, `SignedTicketGeneration`, `VatChallanProcessing`, `FirebaseNotificationRequest`, `FirebaseBulkNotificationRequest`, `EventLiveCapacityUpdate`, `LevelCapacityUpdate`.
- Service clients (typed HttpClient + DelegatedBearerAuthenticationHandler + Polly): `TicketingClient`, `BookingClient`, `AdminClient`, `EventClient`, `NotificationClient`, `ServerlessClient`, `PushNotificationClient`, `UserClient` in `Core/ETP.Core/ServiceClient/`.

## 1. TicketChecker — `Services/TicketChecker/`
Projects: `ETP.TicketChecker.Client` (empty stub), `ETP.TicketChecker.Domain`, `.Service`, `.Storage`.

Controllers:
- `TicketController` (`Api/TicketController.cs`) — api/v1/tickets: `POST sync-tickets` body `Dictionary<string,int> tickets` (ticket number → scanned count; negative = manual check) → `200 Dictionary<string,int>` (full synced ticket hash). `[Authorize(Policy = AuthScheme.TicketChecker)]`.
- `TestingController` — api/v1/testing: `GET re-initiate-data?numberOfData=1000` (anon), `POST sync-data` (anon perf test).
- `WeatherForecastController` — template leftover (anon).

No workers; AddQueue/AddEventBus registered but unused.

Logic (`Domain/Managers/TicketsManager.cs`, `UpdateAndSyncTickets`): refuses while Redis flag `ticketCheckerDbSync` is true; loads checker's event info from DB; RedLock `ticket_checker_gate_{gateId}` (expiry 2s/5s, wait 5s, retry 0.5s); on first call hydrates Redis hash `ticket_checker_tickets:event_{eventLongId}_gate_{gateId}` from Ticketing API (`GetTicketNumbersByEventAndLevelIdsAsync`); increments posted tickets (HashIncrementAsync +1); maintains per-checker cache `ticket_checker_checked_tickets:{eventLongId}_{gateId}_{userSubId}` (`ConcurrentDictionary<string,TicketInfo>`); returns `HashGetAllAsync<int>`.

DTOs: `TicketInfo` (`int Value, bool IsManual, DateTime EntryTime`); `TicketCheckerEventInfo` (`long TicketCheckerGateId; Guid EventId; long EventLongId; string EventName; string? EventCoverImage; DateTime EventStartDateTime; DateTime? EventEndDateTime; bool IsDownloadEnabled; string EntryGateName; List<long> EntryGateIds; string UserSubId; string UserName`).

EF: `TicketCheckerDbContext` (`ETP.TicketChecker.Storage/DbContexts/`), schema `etp`, conn `ConnectionStrings:TicketChecker`, ActivityLogInterceptor; DbSets TicketCheckerGates, TicketCheckerGateUsers, Events, BlockLevelEntryGates — ALL ExcludeFromMigrations (read-only mirrors). Entities in `Storage/Models/`: TicketCheckerGate `{ProgramId, EventId, VenueId, EntryGateName, EntryGateId (comma-separated string ids), ...}`, TicketCheckerGateUser `{TicketCheckerGateId, UserId, Name, IsDownloadEnable, ...}`, Event `{EventId (Guid string), Name, VenueId, ProgramId, StartDateTime, EndDateTime, IsPublished, IsVatInclusive, ...}`, BlockLevelEntryGates `{Name, BlockLevelId, ...}`.

External: HTTP → Ticketing `ITicketingClient` (`Services:Ticketing`, `ticketing/api/v1/booking-order-ticket/ticket-numbers?eventId=..&levelIds=..`). Redis cache + locks. No S3/SES/Firebase (DgePay keys in appsettings unused). appsettings `Application:ServiceName=ticketChecker`; all conn strings listed; pools Admin/User/TicketChecker/Agent.

## 2. UserIssue — `Services/UserIssue/`
Projects: `ETP.UserIssue.{Domain,Service,Storage}`. Prefix `userissue` (inferred from hub path + launch URL; appsettings.json NOT committed; k8s secret mount commented out).

`ReportIssueController` (`Api/ReportIssueController.cs`) — api/v1/user-issue:
| Method | Route | Request | Response | Auth |
|---|---|---|---|---|
| POST | `` | CreateUserIssue | ReportedUserIssue | Policy User |
| GET | `user/{userId}` | — | List<ReportedUserIssue> | User |
| GET | `user-detail/{orderId}` | public order id | ReportedUserIssueDetails | User |
| GET | `{id}` | long | ReportedUserIssueDetails | Admin |
| GET | `` | search, searchType(orderid/issueid/txnid/phonenumber), sortBy, sortOrder, pageOffset, pageSize, status, programId | IPagedList<ReportedUserIssue> | Admin |
| PUT | `{id}` | UpdateUserIssue | ReportedUserIssue | Admin |
| DELETE | `{id}` | — | ReportedUserIssue | Admin |
| GET | `count?status=&programId=` | — | int | Admin |

`ReportIssueChatController` (`Api/ReportIssueChatController.cs`) — api/v1/user-issue-chat — **no [Authorize] on any action (effectively anonymous)**: `GET {reportedIssueId}/messages?pageOffset&pageSize`; `POST send` (multipart CreateChatMessage); `GET {reportedIssueId}/unread-count?receiverType`; `GET {reportedIssueId}/unread?receiverType`; `POST {reportedIssueId}/mark-read` (receiverType); `GET {reportedIssueId}/last`; `GET {reportedIssueId}/recent?count=10`; `GET message/{messageId}/attachment/download` (streams S3 file).

SignalR hub `UserIssueChatHub` (`Hubs/UserIssueChatHub.cs`) at `/userissue/chathub`, `[Authorize(AuthenticationSchemes = "user,admin")]`. Server methods: SendMessage(CreateChatMessage), BroadcastNewMessage, JoinUserIssueChat, LeaveUserIssueChat, SendTypingIndicator, StopTyping. Client events: NewMessage, MessagesRead, UserJoined, UserLeft, UserTyping, UserStoppedTyping, MessageError. `ChatNotificationService` (`Services/ChatNotificationService.cs`) broadcasts via IHubContext.

No workers; no SQS.

Managers: `ReportIssueManager` — create validates one-issue-per-order, calls `BookingClient.GetUserBookingOrderByPublicIdUser`, generates unique IssueNumber, inserts issue + initial chat message (SenderType "USER"), fetches user via ServerlessClient. Detail views enrich with Booking order (admin/user variants), Cognito user, tickets from shadow Tickets table. `txnid` search resolves PublicIds via shadow UserBookingOrders. `ReportIssueChatManager` — persists message, optional attachment upload to S3 folder `chat-attachments/{reportedIssueId}/{guid}{ext}` (max 10 MB; images/PDF/Office/text), hub broadcast.

DTOs (`Domain/Models/`): `CreateUserIssue { Guid PublicOrderId; string Description (≤600); long ProgramId }`; `UpdateUserIssue { string Feedback; string Status }`; `CreateChatMessage { long UserIssueId [Required]; string? Message; string SenderType [Required]; string? SenderId; string? SenderName; IFormFile? AttachmentFile }`; `ReportedUserIssue { long Id; CognitoUser User; string IssueNumber; string OrderNumber; string? TransactionId; string OrderStatus; DateTime OrderDate; Guid PublicOrderId; string Description; string? Feedback; string Status; DateTime CreatedAt; string? CreatedBy; DateTime? UpdatedAt; string? UpdatedBy; DateTime? ResolvedAt; string? ResolvedBy; bool IsDeleted; bool IsActive }`; `ReportedUserIssueDetails` = ReportedUserIssue + `string EventName; string PaymentInfo; List<TicketInfo> Tickets`; `ReportedUserIssueChatMessage { long Id; long ReportedIssueId; string? Message; string SenderType; string? SenderId; string? SenderName; bool IsRead; string? AttachmentFileName/AttachmentFilePath/AttachmentContentType; long? AttachmentFileSize; DateTime CreatedAt; DateTime? UpdatedAt }`; `TicketInfo { long Id; string TicketNumber; string? Seat; string? TicketHolderName; string? TicketHolderIdentification; string? EntryGates; string Status; string? TicketType; DateTime? GeneratedDate }`; enums `UserIssueStatus {Open, Resolved}`.

EF: `UserIssueDbContext`, schema `etp`, conn `ConnectionStrings:UserIssue`; DbSets ReportedIssues (owned; migrations 20250910…), ReportedIssueChatMessages (owned), Tickets (mirror), UserBookingOrders (ExcludeFromMigrations; PublicId, PaymentTransactionId). Auto-migrates at startup.

External: `IBookingClient` (Services:Booking); `IServerlessClient` (`Serverless:BaseUrl`, static Authorization; `GET user/get-bulk-users?user_ids=...` → CognitoUser list); `ITicketingClient` registered but effectively unused; S3 via ICloudFrontMediaManager (AWS:Bucket:Name) for chat attachments; Cognito client for CognitoUserAttributesMiddleware; Redis cache + lock registered.

Program.cs: auth + policies, Serilog, App Insights health, in-proc + Redis cache, distributed lock, SignalR, gzip, CognitoUserAttributesMiddleware, log headers, forwarded headers, startup migration, hub `/userissue/chathub`.

## 3. Utility — `Services/Utility/`
Projects: `ETP.Utility.{Domain,Service}`. **No controllers** (host serves /health + swagger only).

Worker: `TicketProcessingService` (1-min initial delay, then every 1 min resolves scoped `TicketProcessingTaskManager`) — consumes queue **`AWS:Queue:TicketProcessing`** (`QueueSettings.TicketProcessing`); MaxNumberOfMessages=1; message `TicketProcessingRequest { ReservationId, GroupId, OrderId, ProcessingType Merge|Zip }`:
- RedLock `ticket_processing_service_{reservationId}` (expiry 1 h)
- Skip-if-done via `BookingClient.GetReservationMergeStatusAsync` / `GetReservationZipStatusAsync`
- Merge: `BookingClient.UpdateReservationMergeStatusAsync(Merging)` → `UtilityService.MergeTicketsAsync` → status Merged; Zip analogous (Zipping/Zipped); exception → status Failed, message left on queue (DLQ); success → delete message.

`UtilityService` (`Domain/Managers/UtilityService.cs`): MergeTicketsAsync — `TicketingClient.GetTicketUrlsAsync(reservationId)` → PDFs merged with PdfSharpCore in chunks of `AWS:Ticket:MergeSize` → S3 ticket bucket `{AWS:Ticket:MergeBase}/{reservationId}/{reservationNumber}_Merged_PDF_{i}.pdf`. ZipTicketsAsync — `{reservationNumber}_Individual_Zipped_{i}.zip`. Reservation number from `BookingClient.GetEventIdByReservationIdAsync`; idempotent (`IsObjectExistAsync`).

No EF. External: ITicketingClient, IBookingClient, IAdminClient (registered, used only in commented code), S3 via AwsSimpleStorageTicketMediaManager; Redis + RedLock. Program.cs: NO auth middleware; Serilog, Redis, lock, MassTransit, SQS, prefix `utility`, /health. appsettings: `AWS:Queue:{OrderSuccess,EventCapacity,TicketProcessing}` (only TicketProcessing used), `AWS:Ticket:{Bucket:Name,TemplateBase,BlankBase,SignedBase,ShareBase,MergeBase,MergeBuffer,MergeSize,ShareExpiryMinutes,EmailSender}`.

## 4. PushNotification — `Services/PushNotification/`
Projects: `ETP.PushNotification.{Domain,Service,Storage}`. Prefix `PushNotification` (Application:ServiceName). Controllers without `[Authorize]`; UseAuthentication/UseAuthorization commented out in Program.cs.

`NotificationController` (`Api/NotificationController.cs`) — api/v1/push-notification: `POST send-to-all` body PushNotificationRequest → `202 {message, requestId}`; `POST send-to-users` (requires UserIds) → 202; `POST send-to-user/{userId}` → 202; `GET bulk-status/{requestId}` → `200 {requestId, status:"processing", message}` (stub).

`DeviceTokenController` (`Api/DeviceTokenController.cs`) — api/v1/device-token: POST (DeviceTokenRequest), PUT (UpdateDeviceTokenRequest), DELETE (DeleteDeviceTokenRequest), GET `{userId}` → token list, DELETE `cleanup?retentionDays=30` → `{deletedCount, cutoffDate, retentionDays}`.

No workers — only publishes; FCM delivery happens in Scheduler. `NotificationManager` (`Domain/Managers/NotificationManager.cs`) publishes `FirebaseNotificationRequest` to `AWS:Queue:FirebaseNotification`, batched at 200 tokens per message, GroupId = requestId, OrderId = "{requestId}-batch-N".

DTOs: `PushNotificationRequest` (`Core/ETP.Core/Models/`): `string Title; string Body; Dictionary<string,string>? Data; List<string>? UserIds; bool SendToAll`; `DeviceTokenRequest`/`UpdateDeviceTokenRequest` (`{UserId, FcmToken / OldToken+NewToken, OsType}`)/`DeleteDeviceTokenRequest` (`{UserId, FcmToken}`) — OsType ∈ {android, ios, web}; `FirebaseNotificationRequest`/`FirebaseBulkNotificationRequest` (bulk adds RequestId, BatchNumber, TotalBatches — unused by consumer).

EF: `PushNotificationDbContext` (`Storage/`), schema `etp`, conn `ConnectionStrings:PushNotification`; single DbSet UserDeviceTokens; entity `UserDeviceToken` (`Core/ETP.Core/Domain/Entities/`): `long Id; string UserId; string FcmToken; string OsType; DateTime CreatedAt; DateTime? UpdatedAt`. Migration 20250909114846_AddUserDeviceToken; auto-migrates. Repository `Storage/Repositories/UserDeviceTokenRepository.cs`.

External: SQS + Postgres + Redis only. No direct FCM (FirebaseAdmin only in Scheduler via `Core/ETP.Core/PushNotification/FirebasePushNotificationService.cs`).

## 5. Scheduler — `Services/Scheduler/`
Projects: `ETP.Scheduler.Client` (empty), `ETP.Scheduler.Domain` (only QueueSettings: OrderSuccess, EventCapacity, FirebaseNotification), `ETP.Scheduler.Service`, `ETP.Scheduler.Storage` (empty). **No controllers, no EF** — pure worker host with /health. Only `FirebaseNotification` queue consumed here.

Hosted services (`ETP.Scheduler.Service/Workers/`):
1. `FirebaseNotificationService` (+TaskManager) — SQS consumer of `AWS:Queue:FirebaseNotification`; message FirebaseNotificationRequest; receive 5 msgs, wait 10 s, visibility 60 s; sends via `IPushNotificationService.SendNotificationToMultipleAsync` (FCM `SendEachForMulticastAsync`, FirebaseAdmin, service account from `FirebasePushNotificationConfig` appsettings); **always deletes** message (success or failure). Outer loop every 1 min.
2. `PendingOrFailedBookingStatusUpdateService` — every 2 min; RedLock `pending_cancel_booking_status_updater` (2-min expiry); `BookingClient.UpdatePendingOrFailedBookingStatusToCancelAsync(cutoff = UtcNow − 12 min)` → cancels stale Pending/Failed bookings.
3. `SendNotificationAfterGeneratedTicketService` — every 3 min; RedLock `notification_for_ticket_generated` (3-min expiry, 30 s wait, 1 s retry); `BookingClient.GetNotNotifiedUserBookings(100)` → per booking: `EventClient.GetEventByPublicId`, `TicketingClient.GetGeneratedTicketByOrderId`, `AdminClient.GetEventLevelInfoAsync(eventLongId, levelId)` → `NotificationClient.SendTicketGeneratedNotification(TicketGeneratedNotification)` → `BookingClient.UpdateNotifiedUserBookings(ids)`.
4. `CapacityUpdateService` — every 15 min; RedLock `event_live_capacity_refresher` (15-min expiry); reads Redis hash `capacity`, parses keys `level_live:{eventId}_{blockId}_{levelId}` (split on `_`, 5 parts, parts[1] = eventId), aggregates per event → StringSetAsync `event_{eventId}` (only keys that exist).
5. `DeviceTokenCleanupService` — daily 02:00 UTC (24-h loop); RedLock `device_token_cleanup` (2-h expiry); `EventClient.CleanupOldDeviceTokensAsync(30)` — HTTP cleanup call.

**Correction**: ticket generation/signing/merge-kickoff/VAT are NOT in Scheduler. Ticket generation & signing: Ticketing service workers. VAT challan: Booking service worker. Merge/zip: Utility service. Scheduler participates only via job 3.

Program.cs: auth configured (nothing to protect), Serilog, Redis, lock, MassTransit, SQS, prefix `scheduler`. DependencyConfig registers 5 hosted services + task managers, FirebasePushNotificationService (scoped), HttpClients: IBookingClient→`Services:Booking`, IEventClient→`Services:Admin`, IAdminClient→`Services:Admin`, ITicketingClient→`Services:Ticketing`, INotificationClient→`Notification:Endpoint` static auth (posts `/notification/request`, `/notification/send-message`).

## 6. Platform and UserAuth (near-empty stubs)
- Platform: Program.cs no auth (commented), Serilog/caching/Swagger/CORS/health; sole controller WeatherForecastController (template); DependencyConfig commented out (namespace copy-pasted from ETP.Event.Service); Domain/Storage csprojs empty.
- UserAuth: same skeleton; sole controller TestController (empty class); DependencyConfig commented out (namespace from ETP.User.Service); Client/Domain/Storage empty. **UserAuth appsettings IS committed**; other services carry `Services:UserAuth`/`ConnectionStrings:UserAuth` keys pointing at this stub.

## 7. Open questions
1. UserIssue `Application:ServiceName` — appsettings not committed; prefix inferred.
2. Physical SQS queue names unknown (secrets).
3. Scheduler `OrderSuccess`/`EventCapacity` queue settings unused in Scheduler code.
4. TicketChecker offline sync DB write-back — `ticketCheckerDbSync` Redis flag read but no writer found in this repo.
5. `FirebaseBulkNotificationRequest` exists but consumer uses FirebaseNotificationRequest; bulk-status endpoint stub; tracking not persisted.
6. Dockerfiles use `COPY ../../../../ ./` — odd context.
7. UtilityService.Sanitize + Admin client dead/commented code.
8. Capacity key parsing in CapacityUpdateTaskManager fragile if key prefix contains underscores.
