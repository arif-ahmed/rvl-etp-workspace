# Extraction report 01 — Backend: Admin, Booking, Event, Ticketing (Explore agent, 2026-10-22)

Repo root: `rvl-gobcb-backend/`. Solution: `RVL-ETP.BackEnd.sln` — .NET 8 microservices, PostgreSQL (Npgsql) with shared DB schema `etp` (README says SQL Server — stale), AWS SQS, Redis (cache + RedLock), AWS S3/CloudFront, SES, DynamoDB, AWS Cognito.

## 0. Overall solution structure

### Service projects (all under `Services/`)
| Area | Projects |
|---|---|
| Admin | `Services/Admin/ETP.Admin.Client`, `ETP.Admin.Domain`, `ETP.Admin.Integration`, `ETP.Admin.Service`, `ETP.Admin.Storage` |
| Booking | `Services/Booking/ETP.Booking.Client`, `ETP.Booking.Domain`, `ETP.Booking.Service`, `ETP.Booking.Storage` |
| Event | `Services/Event/ETP.Event.Client`, `ETP.Event.Domain`, `ETP.Event.Service`, `ETP.Event.Storage` |
| Ticketing | `Services/Ticketing/ETP.Ticketing.Client`, `ETP.Ticketing.Domain`, `ETP.Ticketing.Service`, `ETP.Ticketing.Storage` |
| Platform | `Services/Platform/ETP.Platform.{Domain,Service,Storage}` |
| PushNotification | `Services/PushNotification/ETP.PushNotification.{Domain,Service,Storage}` |
| Scheduler | `Services/Scheduler/ETP.Scheduler.{Client,Domain,Service,Storage}` |
| TicketChecker | `Services/TicketChecker/ETP.TicketChecker.{Client,Domain,Service,Storage}` |
| UserAuth | `Services/UserAuth/ETP.UserAuth.{Client,Domain,Service,Storage}` |
| UserIssue | `Services/UserIssue/ETP.UserIssue.{Domain,Service,Storage}` |
| Utility | `Services/Utility/ETP.Utility.{Domain,Service}` (consumes `TicketProcessing` SQS queue — merge/zip of PDFs) |

### Shared/Core libraries (`Core/`)
| Project | Purpose / key pieces |
|---|---|
| `Core/ETP.Core` | Base entities (`Domain/Entities/Entity.cs`, `IAuditEntity`), repository/UoW abstractions, `PagedList`, `BaseFilter`, security (`Security/ClientCredentialsTokenProvider.cs`, `Claims/*`), constants (`Constant/AppConstant.cs` — `AuthScheme`, `Role`), SQS (`Queue/Services/SqsPublisher.cs` + `ISqsPublisher`, `Queue/Extensions/ServiceExtension.cs` `AddQueue()`), queue message DTOs (`Queue/Messages/*`), typed HTTP service clients (`ServiceClient/{AdminClient,BookingClient,EventClient,TicketingClient,UserClient,NotificationClient,PushNotificationClient,ServerlessClient,UserIssueClient}`), Redis (`Caching/RedisService.cs`), Firebase (`PushNotification/FirebasePushNotificationService.cs`), options (`Options/{AwsOptions,PaymentSettings,TspOptions,OneIdSettings,FirebaseOptions}.cs`), `GlobalRoutePrefixConvention` |
| `Core/ETP.Core.Web` | `BaseController.cs`, `Results/PagedOkResult.cs` (pagination envelope: body array + `X-Total-Count` header), `Security/DelegatedBearerAuthenticationHandler.cs` (token forwarding), `Security/ApiTokenAuthenticationHandler.cs`, `Filters/ErrorResponseExceptionFilter.cs`, `Middleware/ExceptionMiddlewareExtensions.cs`, CORS, Redis lock (`ConcurrencyLock/RedisLockManager.cs`) |
| `Core/ETP.Core.EntityFramework` | `LoggingDbContext.cs` (ActivityLog table, own migrations), `ActivityLogInterceptor.cs`, `Repositories/EfCoreRepository.cs`, UoW (`Uow/*`) |
| `Core/ETP.Core.BlobStorage` | S3 + CloudFront: `AWSS3/AwsSimpleStorageMediaManager.cs` (`ICloudFrontMediaManager`), `AwsSimpleStorageTicketMediaManager.cs` (`ITicketMediaManager`), `S3CloudFrontStroge.cs` (signed URLs/cookies), `TicketingCookieManager.cs`, Imgix cache purge |
| `Core/ETP.Core.Storage` | S3 + `DynamoDB/DynamoDbRepository.cs` |
| `Core/ETP.Core.Email` | SES-based `Services/EmailService.cs` (`IEmailService`), SendGrid legacy |
| `Core/ETP.Core.SMS`, `Core/ETP.Core.EventBus` | SMS sending; event bus (mass-transit-style, only used by Booking) |

### Cross-cutting: authentication & token forwarding
- `Core/ETP.Core/Configuration/DefaultAuthenticationConfig.cs` (`AddJwtBearerAuthentication`) registers 5 JWT bearer schemes: `AuthScheme.Admin` (= `admin`, default scheme; `AWS:CognitoPool:Admin:{Authority,ClientId,Metadata}`), `user`, `ticket-checker`, `agent` (Cognito), `service` (symmetric key `Authentication:Jwt:{Issuer,Audience,Key}`). On token validated: raw token stored as claim `AppClaimTypes.AccessToken`; `ClaimTypes.Role` claim added (`user`/`ticket-checker`/`agent`/`service`; admin role injection commented out). Query-string `?access_token=` accepted for SignalR hubs.
- Policies (`Core/ETP.Core/Configuration/AuthorizationConfig.cs`): `admin` (any authenticated admin-scheme token, no role requirement), `user`, `ticket-checker`, `agent`, `service` (role claim required).
- Roles (`Core/ETP.Core/Constant/AppConstant.cs`): `admin`, `user`, `ticket-checker`, `agent`, `service`, plus admin-portal roles `ticket_operator` (BCBPersonnel), `event_manager`, `customer_support`, `ticket_manager`.
- **Token forwarding**: `Core/ETP.Core.Web/Security/DelegatedBearerAuthenticationHandler.cs` copies `AccessToken` claim onto outgoing requests; attached via `.AddHttpMessageHandler<>()` to inter-service clients in all services' `DependencyConfig.cs`.
- Non-forwarding clients: `NotificationClient` (`Notification:Endpoint` + `Notification:Authorization` header), `ServerlessClient` (`Serverless:BaseUrl` + `Serverless:Authorization` header), TSP clients (mTLS cert + TSP token handler).
- **Program scoping (Admin only)**: `X-Program-Id` header → `Middleware/ProgramIdMiddleware.cs` → `HttpContext.Items["ProgramId"]` → `IProgramIdAccessor` (impl `Services/Admin/ETP.Admin.Storage/Repositories/ProgramIdAccessor.cs`) → global EF query filter on entities implementing `IHasProgramId` when ProgramId > 0. `Attributes/AuthorizeProgramAttribute.cs` verifies user's `program_id` claims contain header value (admin/user roles bypass); 400 if header missing/invalid, 403 if not allowed. Booking/Ticketing pass `programId` as explicit query parameter instead.
- **Route prefix**: `GlobalRoutePrefixConvention` with `Application:ServiceName` → effective base paths `/admin/…`, `/booking/…`, `/event/…`, `/ticketing/…` (matches k8s ingress paths).

## 1. ADMIN service

Projects: `Services/Admin/ETP.Admin.Service` (host), `ETP.Admin.Domain`, `ETP.Admin.Storage`, `ETP.Admin.Integration`, `ETP.Admin.Client`.

Program.cs: Serilog, App Insights, caching + Redis, RedLock; auth + authorization; Swagger at `/admin/swagger`; CORS; GlobalRoutePrefixConvention("admin"); ErrorResponseExceptionFilter; gzip compression; forwarded headers; health `/health`; SignalR hub `/admin/chathub` (`Hubs/UserIssueChatHub.cs`; `[Authorize(AuthenticationSchemes = user,admin)]`; groups `UserIssue_{id}`, `User_{userId}`); middleware order: `ProgramIdMiddleware` → `CognitoUserAttributesMiddleware`; `MigratePendingDatabase` at startup. HttpClients: Event, Booking, Ticketing, UserIssue, PushNotification (token-forwarded), Notification + Serverless (static auth). Cognito `AmazonCognitoIdentityProviderClient`; SES; S3/CloudFront media managers (`AWS:Bucket:Name`, `AWS:Ticket:Bucket:Name`). Local ports 5099/7001.

### Controllers (in `Services/Admin/ETP.Admin.Service/Api/`, class-level route `api/v1/...`, prefix `/admin`)
| Controller | Route | Class auth | Actions |
|---|---|---|---|
| ActivityLogController | api/v1/activity-log | [Authorize(Roles=admin,event_manager)] | GET `` (query: serviceName, entityNames, entityNamesToExclude, entityId, pageOffset, pageSize) paged; POST `batch` body ActivityLogsBatchRequest → ActivityLogsBatchResponse; GET `event/{eventId}` |
| AdminUsersController | api/v1/admin-users | [Authorize(Roles=admin)] | GET `forget-password?phoneNo=` [AllowAnonymous]; GET `` list AdminUserResponse; GET `{id}`; POST `` AdminCreateUser; PUT `{id}` AdminUpdateUser; DELETE `{id}`; POST `disable/{id}`; POST `enable/{id}`; POST `set-password` AdminSetPasswordRequest; POST `set-forget-password` AdminForgetSetPassword [AllowAnonymous]. Cognito-backed (`Integration/Services/AdminUserProvider.cs`) |
| AgentUserController (class AgentController) | api/v1/agent-users | **none (anonymous)** | GET ``; GET `{id}`; POST `` AgentCreateUser; PUT `{id}`; DELETE `{id}`; POST `disable|enable/{id}`; POST `set-password?userId=`. DTOs in `Domain/Models/Users/Agent/` |
| BlockLevelEntryGateController | api/v1/block-level-entry-gate | [Authorize(Roles=admin)] | GET `ids?entryGateIds=` |
| CurrencyController | api/v1/currency | none | GET `` → currencies |
| DashboardController | api/v1/dashboard | [Authorize(Roles=admin,ticket_operator)] [AuthorizeProgram] | GET `get-tile-data?programId=` → TileData; GET `get-event-by-category` → EventsByCategory |
| DiscountController | api/v1/discount | [Authorize(Roles=admin)] | GET `` paged (sortBy,sortOrder,pageOffset,pageSize); GET `list`; GET `{id}`; POST/PUT `{id}` CreateOrUpdateDiscount; DELETE `{id}`; GET `program/{programId}/{eventId}/{galleryId}` [AllowAnonymous]; GET `exists?eventIds=&discountId=` |
| EventSettingsController | api/v1/event-settings | none | GET `{eventId}`; PUT `{eventId}` body EventSettings |
| EventsController | api/v1/events | [Authorize(Roles=admin,event_manager,ticket_manager,ticket_operator)] ([AuthorizeProgram] commented out) | GET `` (search,sortBy,sortOrder,pageOffset,pageSize); GET `search?search=`; GET `list`; GET `published/list`; GET `{startDatetime}/{endDateTime}/{eventId?}`; GET `filtered-list/{status}/{count}`; GET `{id}` (long); GET `by-public-id/{eventId}` (Guid); POST `` [FromForm] CreateEvent → Event; PUT `{id}` [FromForm] UpdateEvent; DELETE `{id}`; PUT `publish/{id}`; PUT `unpublish/{id}`; GET `program/{programId}/events`; GET `programs/{programId}/events/no-end-date-check`; PUT `toggle-status/{id}`; POST `duplicate/{id}` |
| EventsVenueDetailsController | api/v1/eventsVenueDetails | [Authorize(admin,event_manager,ticket_manager,ticket_operator)] | GET `get-level/{eventId}/{levelId}` → UserLevelWithGates; GET `{eventId}?isForTicket=`; GET `venue-details/{eventId}` → EventVenueDetailsTree; PUT `{eventId}/{levelId}/{price}` (seat price); POST `galleries/by-event-ids` body List<long> |
| GalleryController | api/v1/gallery | [Authorize(Roles=admin)] | GET `` (from GallerySettings config) |
| GeneralNoticeController | api/v1/general-notice | [Authorize(admin,event_manager)] | GET ``; GET `public` [AllowAnonymous] → GeneralNoticePublic; GET `{id}`; POST/PUT `{id}` CreateOrUpdateGeneralNotice; DELETE `{id}` |
| HeaderFooterController | api/v1/header-footer | none | GET ``; PUT `` [FromForm] UpdateHeaderFooter |
| LandingPageImageController | api/v1/landing-page-image | [Authorize(admin,event_manager)] | GET ``; GET `public` [AllowAnonymous]; GET `{id}`; POST `` [FromForm] CreateOrUpdateLandingPageImage; POST `add-gallery-image` [FromForm] GalleryPageSegmentImages; PUT `{id}`; PUT `display-order/{type}/{displayOrder1}/{displayOrder2}`; DELETE `{id}`; PUT `publish|unpublish|duplicate/{id}` |
| PortalUsersController | api/v1/portal-users | none | GET `{phoneNo}` → portal user lookup |
| ProgramController | api/v1/program | [Authorize(admin,event_manager,...)] | GET ``; GET `{id}`; POST `` [FromForm] CreateOrUpdateProgram; PUT `{id}`; DELETE `{id}` |
| ProgramSettingsController | api/v1/program-settings | [Authorize(admin,event_manager)] | GET ``; GET `{programId}`; PUT `` body ProgramSettings |
| ProgramVenueController | api/v1/programVenue | [Authorize(admin,event_manager)] | POST `` CreateOrUpdateProgramVenue; GET `{programId}` |
| ProgramVenueDetailsController | api/v1/programVenueDetails | [Authorize(admin,event_manager)] | POST `{programId}` (generate); POST `{programId}/{venueId}` (sync); GET `{programId}/{venueId}`; PUT `update/{id}` CreateOrUpdateProgramVenueDetails; GET `venue-galleries/{programId}/{venueId}`; GET `venue-details/{programId}`; GET `sync-status/{programId}/{venueId}` |
| PromoCodeController | api/v1/promo-codes | [Authorize(Roles=admin)] | GET `` paged; GET `list`; GET `{id}`; GET `code/{code}/{eventId}`; POST/PUT `{id}` CreateOrUpdatePromoCode; DELETE `{id}`; GET `exists` |
| RaffleDrawController | api/v1/raffle-draw | [Authorize(admin,event_manager)] | GET ``?eventId=; GET `details/{eventId}/{ticketNumber}`; POST `` body RaffleDraw; DELETE `{id}` |
| SocialMediaSettingsController | api/v1/social-media-settings | [Authorize(Roles=admin)] | GET ``; PUT `` body SocialMediaSettings |
| SystemSettingsController | api/v1/system-settings | [Authorize(Roles=admin)] | GET `` |
| TeamsController | api/v1/teams | [Authorize(admin,event_manager)] | GET `program/{programId}`; GET `{id}`; GET `` paged; GET `list`; POST `` [FromForm] CreateOrUpdateProgramTeam; PUT `{id}`; DELETE `{id}`; PUT `toggle-status/{id}` |
| TicketAttributesController | api/v1/ticket-attributes | [Authorize(admin,event_manager,ticket_manager,ticket_operator)] | GET `program/{programId}`; GET `{id}`; POST `` CreateTicketAttributesRequest; PUT `{id}` UpdateTicketAttributesRequest |
| TicketCheckerController | api/v1/ticket-checker | [Authorize(admin,event_manager,ticket_manager,ticket_operator)] (GET `search` additionally admin/event_manager) | GET `search?name=`; GET `search-by-userid?sub=`; GET ``; GET `{id}`; POST `` TicketCheckerCreateUser; PUT `{id}` TicketCheckerUpdateUser; PUT `change-password` TicketCheckerChangePassword; DELETE `{id}`; POST `disable|enable/{id}`; POST `set-password?userId=`. Cognito-backed |
| TicketCheckerGateController | api/v1/ticket-checker-gate | [Authorize(AuthenticationSchemes = admin,ticket-checker, Roles=...)] | GET `report/{eventId}` → TicketCheckerGateReportData; GET `export/{eventId}` → Excel (CheckedTicketExportData); GET `{eventId}` (admin/em) gate users; POST `` AssignTicketCheckerGate; POST `force-assign` / `force-unassign` body List<AssignTicketCheckerGate>; GET `event-info` [Authorize(Policy=ticket-checker)] → TicketCheckerEventInfo; GET `user/{userId}`; PUT `update-download-status/{userId}/{gateId}/{status}`; DELETE `remove-user/{id}`; POST `duplicate-tickets/{eventLongId}`; POST `manual-entry-tickets/{eventLongId}`; GET `reports/duplicate-entries`; GET `reports/duplicate-entries/details` |
| TicketLayoutConfigsController | api/v1/ticket-layout | [Authorize(admin,event_manager,ticket_manager,ticket_operator)] | GET `` paged (searchText); GET `program/{programId}`; GET `venue/{programId}/{venueId}`; GET `configs/{programId}/{venueId}/{venueGalleryId}`; GET `published/...`; GET `back-page/...`; GET `{id}`; POST `` TicketLayoutConfigCreated; PUT `{id}` TicketLayoutConfigUpdated; DELETE `{id}`; PUT `publish|unpublish|duplicate/{id}`; POST `upload/{id}` (IFormFile + TicketLayoutType); POST `upload/back-page/{id}`; DELETE `delete-pdf/{id}` (+ back-page variant); GET `{id}/{ticketLayoutType}`; GET `download-backpage/{eventId}` |
| TicketPricingController | api/v1/ticket-pricing | none | GET `` paged; GET `list`; GET `{id}`; POST/PUT `{id}` CreateOrUpdateTicketPricing; DELETE `{id}`; PUT `publish|unpublish/{id}`; DELETE `attribute/{attributeId}` |
| TokenIssuerController | api/v1/token | none (guarded by ServiceApiKey header check) | GET `` — issues 1-day symmetric JWT (service scheme) |
| UserIssueChatController | api/v1/user-issue-chat | none (downstream UserIssue) | POST `send` [FromForm] CreateChatMessage; GET `{userIssueId}/messages`; GET `{userIssueId}/unread`; GET `{userIssueId}/unread/count`; POST `{userIssueId}/mark-read`; GET `{userIssueId}/last`; GET `{userIssueId}/recent`; GET `message/{messageId}/attachment/download`. Uses UserIssueClient + SignalR ChatNotificationService + PushNotificationClient |
| UserIssueController | api/v1/user-issue | [Authorize(Roles=admin,customer_support)], per-action overrides | POST `` [Authorize(Policy=user)] CreateUserIssue; GET `user/{userId}` (user); GET `user-detail/{orderId}` [AllowAnonymous]; GET `{id}` [Authorize]; GET `` paged (status,programId); PUT `{id}` UpdateUserIssue; DELETE `{id}` |
| VenuesController | api/v1/venues | [Authorize(admin,event_manager)] | GET `` paged search; GET `{programId}`; GET `venue?venueId=`; GET `gallery`; GET `galleryBlocks`; GET `blockLevel`; POST `` [FromForm] CreateOrUpdateVenue; PUT `venue/{venueId}`; POST/PUT `venueGallery`; POST/PUT `galleryBlocks`; POST/PUT `blockLevel`; POST `venueLayout` CreateOrUpdateVenueLayout; GET `entry-gate` / `mini-gate`; POST `entry-gate` List<CreateOrUpdateBlockLevelEntryGates>; POST `mini-gate`; GET `has-running-events/{venueId}` |

### Admin background workers (timer-based; no SQS in Admin)
All in `Services/Admin/ETP.Admin.Service/Workers/BackgroundServices/` + `Workers/TaskManagers/`:
- `CheckedTicketService` (+TaskManager) — every 30 min, RedLock `checked_ticket` — drains checked-ticket entries from Redis into `CheckedTickets` table.
- `GateCheckerDownloadStatusCleanupService` — every 15 min — cleans gate-checker offline download statuses.
- `PromoCodeStatusUpdateService` — every 2 min — auto expires/activates promo codes by date.
- `SystemDiscountStatusUpdateService` — every 2 min — auto expires/activates system discounts by date.

### Admin key DTOs
- `CreateEvent`: `long ProgramId; int VenueId; string Name; DateTime StartDateTime; DateTime? EndDateTime; IFormFile EventCoverImageFile; List<CreateEventSegment> Segments` — CreateEventSegment `{ string Name; SegmentType SegmentType; DateTime StartDateTime; DateTime EndDateTime; long? Team1Id; long? Team2Id; IFormFile BannerImageFile }`
- `Event` (response): `long Id; string EventId; long ProgramId; long VenueId; string Name; DateTime StartDateTime; DateTime? EndDateTime; DateTime TicketSellingStartDateTime/StopDateTime; DateTime TicketAvailabilityStartDateTime; string EventCoverImage; decimal MinimumPrice; bool IsPublished; bool IsActive; decimal Vat; bool IsVatParcentage; bool? IsVatInclusive; Venue Venue; Program Program; EventSettings EventSettings; List<EventSegment> Segments`
- `CreateOrUpdateProgram`: `long Id; string Name; string ShortName; DateTime StartDateTime; DateTime? EndDateTime; IFormFile? Logo`
- `AdminCreateUser`: `string Name; string Phone; string Email; string Role; string? ProgramIds`
- `CreateOrUpdateTicketPricing`: `string ProgramName; string VenueName; bool IsPublished; List<CreateOrUpdateTicketPricingAttribute> Attributes` (attribute `{ string AttributeName; long AttributePrice }`)
- `CreateOrUpdatePromoCode`: `string Code; string Name; long ProgramId; DiscountType DiscountType; double DiscountValue; DiscountAppliedType DiscountAppliedTo; DateTime StartDateTime; DateTime EndDateTime; int TotalUsageLimit; int LimitPerUser; List<CreateOrUpdatePromoCodeAssign> AssignTo` (assign `{ AssignType AssignType; long ProgramId; ICollection<long>? EventIds; ICollection<long>? GalleryIds; ICollection<PromoCodeVenueEventGallery>? VenueEventGalleryNames }`)
- `CreateOrUpdateDiscount`: `string Name; long ProgramId; DiscountType DiscountType; double DiscountValue; DateTime StartDateTime; DateTime EndDateTime; ICollection<CreateOrUpdateDiscountAssign> DiscountAssigns`
- `CreateChatMessage`: `long UserIssueId; string? Message; string SenderType; string? SenderId; string? SenderName; IFormFile? AttachmentFile`
- `CreateUserIssue`: `Guid PublicOrderId; string Description; long ProgramId`
- Others: UpdateEvent, EventSegment, Venue, VenueGallery, GalleryBlock, BlockLevel(+EntryGates,MiniGates), ProgramVenue(Details), CreateOrUpdateVenue(Layout), ProgramTeam, Currency, ProgramSettings/SystemSettings/SocialMediaSettings/HeaderFooter/UpdateHeaderFooter, GeneralNotice(+Public,CreateOrUpdate), LandingPageImage(+Public,CreateOrUpdate), GalleryPageSegmentImages, PromoCode(PromoCodeAssign), Discount(DiscountAssign), RaffleDraw, TicketChecker* models, AssignTicketCheckerGate, TicketCheckerGate(User/Details/ReportData/EventInfo), CheckedTicket(ExportData), TicketInfo, TicketLayoutConfig(Created/Updated), TicketAttributes, AdminUpdateUser/AdminSetPasswordRequest/AdminForgetSetPassword, Agent*, PortalUser, UserIssue(+Details)/UpdateUserIssue/UserIssueChatMessage, TileData, EventsByCategory, ActivityLogs{Request,Response,BatchRequest,BatchResponse}, Gallery.

### Admin EF Core
`AdminDbContext` (`Services/Admin/ETP.Admin.Storage/DbContexts/AdminDbContext.cs`), schema `etp`, global ProgramId query filter, ActivityLogInterceptor via LoggingDbContext. 39 DbSets: PromoCodes, PromoCodeAssigns, Discounts, DiscountAssigns, Venues, VenueGalleries, GalleryBlocks, GalleryBlockEntryGates, BlockLevels, BlockLevelEntryGates, Programs, ProgramVenues, ProgramVenueDetails, EventVenueDetails, Events, EventSegments, ProgramTeams, Currencies, ProgramSettings, SystemSettings, GeneralNotices, SocialMediaSettings, LandingPageImage, HeaderFooter, BlockLevelMiniGates, UserIssues, UserIssueChatMessages, TicketCheckerGates, TicketCheckerGateUsers, CheckedTickets, RaffleDraws, TicketLayoutConfigs, TicketAttributes, EventSettings, TicketPricings, TicketPricingAttributes (+ PromoCodeVenueEventGallery, DiscountVenueEventGallery join tables). Migrations 2024-11 → present.

### Admin external calls
HTTP token-forwarded: Event, Booking, Ticketing, UserIssue, PushNotification (`pushnotification/api/v1/push-notification/send-to-users|send-to-all`). HTTP static: Notification (`/notification/request`, `/notification/send-message`); Serverless (`user/get-bulk-users`, `user/my-profile`). AWS Cognito user CRUD (`Integration/Services/*UserProvider.cs`, `AuthProvider.cs`). S3/CloudFront media managers. SES. Redis (cache + locks + checked-ticket buffer). No DgePay/TSP/OneID/Firebase direct usage.

## 2. BOOKING service

Projects: `Services/Booking/ETP.Booking.{Client,Domain,Service,Storage}`. Program.cs: shared auth; prefix `booking`; Swagger `/booking/swagger` (CustomSchemaIds FullName, AuthorizationHeaderParameterOperationFilter); JSON camelCase + string enums; `AddEventBus` (only service), `AddQueue`, `AddDistributedLock`; CustomFontResolver (PDF fonts); HttpClients: Event, Ticketing, User (`Services:AppBase`), Serverless, Notification, **DgePay** (`PaymentSettings:DgePay:BaseUrl`), **SSLCommerz** (`PaymentSettings:SSLCommerz:BaseUrl`), **NBR OpenAPI** (`PaymentSettings:NBROpenApi:BaseUrl`); `PaymentGatewayFactory`; Cognito; media managers. Local 5086/7002.

### Controllers (`Services/Booking/ETP.Booking.Service/Api/`)
- `UserBookingOrderController` — api/v1/user-booking-order: POST `` body UserBookingOrder → 201 UserBookingOrderResponse [Policy=user]; GET `dgepay/payment-status` (callback, query `data=`, redirect) anonymous; POST `sslcommerz/payment-success|payment-fail|payment-cancel|payment-ipn` (form tran_id) anonymous; GET `sslcommerz/payment-methods` [user]; GET `payment-status-bypass?rawData=` anonymous (test bypass, calls TicketingClient.InitiateTicket); GET `check-generated-status?id=` [user]; GET `list` (page,pageSize,sortOrder) [user]; GET `{id}` [user]; GET `admin/{id}` [admin]; GET `admin/reconciliation/{searchType}/{searchText}` [admin]; GET `public-id/{id}` anonymous (internal); PATCH `generate-ticket-request/{publicId}` internal; GET `admin/list/{eventId:guid}` (page,status,orderNumber,sortOrder,programId) [admin]; PUT `update-status` body UpdateBookingStatusRequest internal (Scheduler); GET `not-notified-list?limit=`; PUT `update-notification-status` body List<string>; POST `apply-promo-code` body ApplyPromoCodeRequest [user] → ApplyPromoCodeResponse; GET `promo-code/{code}`; GET `booked-user-record/{bookingOrderId}`
- `SeatReservationController` — api/v1/seat-reservation: POST `` body SeatReservation; POST `event/{eventId}?percentage=` [admin] (bulk reserve); GET `by-event-level?eventId&levelId&actionType&programId`; GET `by-event`; GET `count/{eventId}?actionType=`; GET `remainingReserveCount/{eventId}`; GET `summary/{eventId}?levelId&programId` [admin] → List<ReservationSummary>; GET `reservations-count?eventId&levelId` → List<ReservationCount>; PATCH `update-reservation-status/{publicId}?status=`; PATCH `update-merge-status/{publicId}`; GET `merge-status/{publicId}`; PATCH `update-zip-status/{publicId}`; GET `zip-status/{publicId}`; PATCH `update-reservation-ticket-preview/{publicId}?blankTicketPreviewUrl=`; GET `event-id/{publicId}` (last several = internal, no explicit auth)
- `CapacityController` — api/v1/capacity (no class auth): GET `level-live-capacity?eventId&galleryId&blockId&levelId` (int); GET `level-live-seats`; GET `level-user-portal-seats`; GET `event-live-capacity?eventId`; POST `` body List<Capacity> (internal); GET `online-tickets-count?eventId`; GET `event-pending-seats-capacity`; GET `event-purchased-and-reserved-capacity`; GET `by-event?eventId`
- `EventCapacityAdjustmentController` — api/v1/event-capacity-adjustment: POST `` EventCapacityAdjustment; GET `by-event-level?eventId&levelId&action&programId`; GET `by-event`; GET `count/{eventId}?action=`
- `ReportController` — api/v1/report (no explicit auth): GET `admin/export-booking-orders?eventId&programId`; GET `admin/revenue-report-list?startDate&endDate&eventId&programId`; GET `admin/booking-metrics?eventId`; GET `admin/event-revenue-summary?programId`; GET `admin/event-sales-summary?programId`; GET `admin/event-sales-details?id&programId`; GET `admin/event-revenue-sales-details`; GET `admin/payment-discrepancy?programId&eventId` — Excel export via ClosedXML
- `BookingReportController` — api/v1/dashboard: GET `get-ticket-sales-summary?programId` → TicketSalesSummary; GET `get-upcomming-seven-events`; GET `get-last-week-seats-sale-amount`; GET `get-last-Month-seats-sale-amount` → List<DashboardChartData>

### Booking workers / SQS
- `LevelCapacityUpdateService` → TaskManager — consumes `AWS:Queue:OrderSuccess`, message `LevelCapacityUpdate`; GroupId = `{eventLongId}_{galleryId}_{blockId}_{levelId}`; persists capacity; for user orders decrements Redis live capacity hash (`capacity` / `LevelLiveCapacity:{groupId}`), removes locked capacity, updates live seat list; deletes message.
- `EventLiveCapacityUpdateService` — consumes `AWS:Queue:EventCapacity`, message `EventLiveCapacityUpdate`; serially applies event-level live-capacity deltas (DB + Redis).
- `VatChallanProcessingService` — consumes `AWS:Queue:VatChallanProcessing`, message `VatChallanProcessing`; calls NBR OpenAPI (`vendor_authenticate`, `record_vat`, `download_schallan` via `INBROpenApiManager`), stores challan on booking record; retries with exponential backoff (max 3, `RetryCount` in message); uses IServerlessClient, IEventClient.
- `BookingStatusUpdateService` — timer 2 min — flips bookings to Generated when TicketingClient ticket counts match seat count.
- `InitiateUserTicketGenerationService` — timer 15 min, RedLock `user_ticket_generator_{eventId}` — finds paid bookings for events whose `TicketAvailabilityStartDateTime` passed → `ITicketingClient.InitiateUserTicket(publicId)` (HTTP → `ticketing/api/v1/booking-order-ticket/initiate-user-ticket`).
- `RefreshLockedCapacityService` — timer, RedLock `locked_order_refresher_{0-9}` — releases stale locked capacity for abandoned checkouts.
- `ReservationStatusUpdateService` — timer 30 min — updates reservation statuses (expiry).

### Booking SQS publishing (SqsPublisher; FIFO if queue name ends "fifo")
- `UserBookingOrderManager.cs` (lines ~345, 514, 1072, 1361 — payment success/cancel paths incl. HandleDgePayment, bypass path): `LevelCapacityUpdate` to `AWS:Queue:OrderSuccess` (OrderId = booking PublicId; GroupId = `{EventLongId}_{GalleryId}_{BlockId}_{LevelId}`; Amount; OrderType; HasSeats/Seats; IsIncrease=false on success)
- `UserBookingOrderManager.cs` (~433, 1280): `VatChallanProcessing` to `AWS:Queue:VatChallanProcessing`
- `CapacityManager.cs` (~235): `LevelCapacityUpdate` to OrderSuccess (admin order capacity changes)
- `CapacityManager.cs` (~249): `EventLiveCapacityUpdate` to `AWS:Queue:EventCapacity`
- QueueSettings: `Domain/Models/QueueSettings.cs` (`OrderSuccess, EventCapacity, TicketSigning, VatChallanProcessing, FirebaseNotification` from `AWS:Queue`)

### Booking key DTOs
- `UserBookingOrder` (create): `Guid EventId; long GalleryId; long BlockId; long LevelId; int NumberOfSeats; bool HasSeats; string? Seats; double PricePerSeat; string? PromoCode; double TotalCharge; double Vat; List<BookedUserDetails>? bookedUserDetails`
- `UserBookingOrderResponse`: `Guid PublicId; string? CheckoutUrl`
- `SeatReservation`: `long Id; long EventId; long GalleryId; long BlockId; long LevelId; int NumberOfSeats; int RemainingReservedSeat; bool HasSeats; string? Seats; string? AvailableSeats; string? BlankTicketPreviewUrl; ActionType Action; ReservationStatus? Status; ReservationType? Type; ReservationCategory; ReleaseCategory; MergeStatus; ZipStatus; long? ReservationId; Guid? PublicId; long? ProgramId; string? ReservationNumber`
- `Capacity`: `long Id; long EventId; long GalleryId; long BlockId; long LevelId; int TicketingCapacity; bool HasSeats; string? Seats`
- `BookedUserDetails`: `string UserName; string PhoneNumber`; entity BookedUserRecord adds program/event/order/audit fields
- `ApplyPromoCodeRequest`: `string PromoCode; long ProgramId; Guid EventId; long GalleryId` → ApplyPromoCodeResponse
- `UpdateBookingStatusRequest`: `int? Limit; DateTime CutoffTime`
- `DgePayInitiatePaymentRequest`: `double amount; string? note; DgePayPayeeInformation? payee_information; string unique_txn_id; string? redirect_url; string? customer_token; string? payment_method` (snake_case JSON); `DgePayResponse`/`Data` with `MappedStatus` ("3"/"Success" → Status.Paid)
- SSLCommerz models: initiate/status + SSLCommerzPaymentMethod.PaymentCategories
- NBR models: `Domain/Models/NBR/NBR{Authentication,VatInvoice,DownloadChallan}{Request,Response}.cs`
- Others: UserBooking, IssuedSeats, LockedCapacity, ReservationDetails, SeatingSummery, EventCapacityAdjustment, PaymentGateway, Dashboard/{TicketSalesSummary,DashboardChartData,DashboardLabel}, Report/{BookingMetrics,RevenueReport}, Enum.cs

### Booking EF Core
`BookingDbContext` (`Storage/DbContexts/BookingDbContext.cs`), schema `etp`, `ConnectionStrings:Booking`. DbSets: Capacities, SeatReservations, EventCapacityAdjustments, UserBookingOrders, BookedUserRecords + read-only mirrors (VenueGalleries, GalleryBlocks, BlockLevels, EventVenueDetails, Events, Currencies, Discounts, DiscountAssigns, PromoCodes, PromoCodeAssigns). Entity `UserBookingOrder` (long PK, PublicId, payment fields, VAT fields, OneIdUserId, PreMergeNativeUserID, audit). Mapping files `DbContexts/Mapping/{UserBookingOrderMapping,SeatReservationMapping,EventCapacityAdjustmentMapping}.cs`.

### Booking external calls
- DgePay (`Domain/Managers/DgePayPaymentManager.cs`): `{BaseUrl}/payment_gateway/initiate_payment`, `/check_transaction_status`, `/authenticate` (AES/RSA crypto, token cached in Redis)
- SSLCommerz (`Domain/Managers/SSLCommerzPaymentManager.cs`): `{BaseUrl}/gwprocess/v4/api.php` (initiate), `/validator/api/validationserverAPI.php` (validation); sandbox default `https://securepay.sslcommerz.com`
- NBR OpenAPI (`Domain/Managers/NBROpenApiManager.cs`): `/vschallan/v3/integration/{vendor_authenticate,record_vat,download_schallan}`
- HTTP to Event/Ticketing/User(Services:AppBase)/Serverless/Notification (token-forwarded except last two)
- Redis: live capacity hashes, locked capacity, distributed locks. No S3/SES/Firebase directly.

## 3. EVENT service

Projects: `Services/Event/ETP.Event.{Client,Domain,Service,Storage}`. Program.cs: auth; prefix `event`; Swagger `/event/swagger`; NO own migrations (all entities ExcludeFromMigrations); no locks/SignalR; single HttpClient: BookingClient (`Services:Booking`, token-forwarded, used by EventManager); Redis caching instead of Admin HTTP (AdminClient commented out). Local 5001/7003. `ETP.Event.Client/Clients/EventClient.cs` is consumed BY Ticketing.

### Controllers
- `EventsController` — api/v1/events (no class Authorize): GET `{eventId}` → Event (public Guid); GET `{eventId}/for-ticketing`; GET `venue-details/{eventId}` → EventVenueDetailsTree; GET `list?numberOfEvents&programId` → List<EventDetails.Event>; GET `client-list`; GET `published/list`; GET `get-level/{eventId}/{levelId}` → UserLevelWithGates; GET `EventLongId/{id}`; GET `client-filtered-list/{status}/{count}?programId=`
- `ProgramController` — api/v1/events/programs: GET `` (active); GET `programId/{id}`
- `HeaderFooterController` — api/v1/header-footer: GET ``
- `LandingPageImageController` — api/v1/landing-page-image: GET `public` [AllowAnonymous]
- `TicketPricingController` — api/v1/ticket-pricing: GET `list` → List<TicketPricingProgram> (Redis-cached); GET `program-pricing?programId&eventId` → List<ProgramPricingResponse>
- `HomeController` (conventional): redirect to `~/event/swagger`

No workers. `AWS:Queue:FirebaseNotification` registered but unused (dead/placeholder).

### Event key DTOs
- `Domain/Models/Event.cs` (main response): `long Id; string EventId; string EventName; long ProgramId; long VenueId; string ProgramName; string ProgramLogo; string ProgramShortName; string ProgramStartDateTime; string ProgramEndDateTime; string BannerImage; DateTime EventStartDateTime; DateTime? EventEndDateTime; DateTime TicketSellingStartDateTime/StopDateTime; DateTime TicketAvailabilityStartDateTime; decimal MinimumPrice; AvailabilityStatus AvailabilityStatus; decimal? Vat; bool IsVatPercentage; decimal? ServiceCharge; bool IsServiceChargePercentage; int AllowableMaximumSeatPerOrder; int AllowableMaximumOrderPerUser; bool? IsVatInclusive; bool IsPublished; bool IsActive; EventSettings EventSettings; List<Segment> Segments; Venue Venue; Program Program`
- `EventDetails/Event.cs`: `string EventId; string Name; string BannerImage; double StartingPrice; DateTime EventStartDateTime; EventEndDateTime; TicketSellingStartDateTime; TicketSellingStopDateTime; Venue Venue; List<EventSegment> EventSegments`
- `UserLevelWithGates`: `long GalleryId; bool IsGalleryActive; bool IsGallerySellable; long BlockId; bool IsBlockActive/IsBlockSellable; long LevelId; bool IsLevelActive/IsLevelSellable; long VenueId; decimal PricePerSeat; string VenueName; string Gallery; string Block; string Level; string EntryGate; long EntryGateId; string MiniGate; string? TicketColor`
- `TicketPricingProgram`: `long Id; long TicketPricingId; string ProgramName; string VenueName; bool IsPublished; ICollection<TicketPricingAttribute> Attributes` (`{ long Id; long TicketPricingProgramId; string AttributeName; long AttributePrice }`)
- `ProgramPricingResponse`: `{ long ProgramId; string ProgramName; DateTime ProgramStartDate; List<EventPricingData> Events }`, EventPricingData `{ long EventId; string EventName; long VenueId; string VenueName; string GalleryName; string TicketType; decimal Price }`
- Others: EventVenueDetailsRedis, EventVenueDetailsTree, EventSegment, Segment, Program, ProgramTeam, Venue, VenueGallery, GalleryBlock, BlockLevel, HeaderFooter, LandingPageImagePublic, EventSettings, EventModel, mock repos under Models/Mock/

### Event EF Core
`EventDbContext`, schema `etp`, `ConnectionStrings:Event`, NO own migrations — every entity `ToTable(..., ExcludeFromMigrations(true))` (read-only shared tables). DbSets: Venues, VenueGalleries, GalleryBlocks, BlockLevels, BlockLevelEntryGates, BlockLevelMiniGates, Programs, EventVenueDetails, Events, EventSegments, EventSettings, ProgramTeams, Currencies, ProgramSettings, UserIssues, TicketCheckerGates, TicketCheckerGateUsers, Capacities, SeatReservations, LandingPageImage, HeaderFooter.

### Event external calls
Booking HTTP (token-forwarded); Redis heavily (cached event lists, venue details 15-day TTL, ticket pricing `CachePrefix.TicketPricingAll`, live capacity keys). No S3/SES/DgePay/TSP/OneID/Firebase direct.

## 4. TICKETING service

Projects: `Services/Ticketing/ETP.Ticketing.{Client,Domain,Service,Storage}`. Program.cs: prefix `ticketing`; Swagger `/ticketing/swagger`; compression (excludes application/zip); `AddDistributedLock`; `AddQueue`; `MigratePendingDatabase`. DI: DynamoDB (`IAmazonDynamoDB` with hardcoded ServiceURL `http://localhost:8000` + generic `IDynamoDbRepository<T>`); DbContext uses **`ConnectionStrings:Booking`** (schema etp; own tables Tickets, OfflineSoldTickets; rest ExcludeFromMigrations); S3 ticket media (`AWS:Ticket:Bucket:Name`), `S3CloudFrontStroge` + `CloudfrontTicketValidator` + `TicketingCookieManager` (CloudFront signed cookies); SES + EmailService; hosted `TicketGenerationService`; HttpClients: Event ×2 (`Services:Event`), Booking, User (`Services:AppBase`), Serverless (static); TSP: `IAuthProvider → TspAuthProvider` (`TSP:AuthUrl`) + `ITspSignedTicketProvider → TspSignedTicketProvider` (`TSP:SignUrl`) with mTLS cert `Cert/tspgw_client.pfx` (server cert validation disabled) + `TspTokenHandler`; OneID: `IOneIdManager → OneIdManager` (`OneIdSettings:TokenUrl/DocumentSyncUrl` + Basic AuthorizationToken). Local 5112/7007. appsettings: `AWS:Ticket:{Bucket,TemplateBase,BlankBase,SignedBase,ShareBase,MergeBase,MergeBuffer,ShareExpiryMinutes,EmailSender}`; `AWS:Queue:{TicketSigning,TicketProcessing}`; `TSP:{AuthUrl,SignUrl,UserId,DigitalIdentityId}`; `OneIdSettings`; `CloudfrontTicketValidator`.

### Controllers
- `BookingOrderTicketController` — api/v1/booking-order-ticket: GET `initiate?orderId=` (internal, Booking calls after payment; blank PDFs → S3 → publish SignedTicketGeneration); GET `initiate-user-ticket?orderId=` (internal, user orders); GET `details?publicId=` [user]; GET `admin/details/{ticketNum}` [admin]; PATCH `` body TicketUpdateRequest [user]; PATCH `generate-request/{publicId}` (internal); POST `ticket-counts` body List<long> (+onlyGenerated,createdBy); POST `reserve-ticket` body List<ReservedTicketRequest>?eventId&levelId [admin]; GET `reserve-ticket?eventId&levelId` [admin]; PUT `reserve-ticket` (ticketNumbers, action) [admin]; POST `sign-reserve-ticket?eventId&levelId` [admin]; POST `download-reserved` body TicketRequest + query signedToken [admin] (zip stream); POST `download-test-blank-reserved` body BlankTicketRequest [admin]; GET `download-merged?reservationId&signedToken` [admin]; GET `merged-ticket-number/{reservationId}` [admin]; GET `merge-reserved/{reservationId}` [admin]; GET `zip-reserved/{reservationId}` [admin]; GET `zipped-ticket-number/{reservationId}` [admin]; POST `send-reserved` body TicketRequest [admin] (emails zip via SES); GET `download-all/{orderPublicId}` [user]; GET `by-gallery-block-level?galleryId&blockId&levelId`; GET `download?ticketNumber=` [user]; GET `shared?ticketNumber&signature` [AllowAnonymous]; GET `share?ticketNumber=` [user] (signed share URL, expiry `AWS:Ticket:ShareExpiryMinutes`); GET `ticket-numbers?eventId&levelIds`; GET `` ?id=; POST `booking-order-id` body List<long>; GET `reserved-urls?reservationId`; POST `generate-signed-token` [admin]; GET `download-invoice/{publicId}` [user]; GET `signed-cookie` [admin]; POST `sync-to-oneid/{ticketNumber}` [user]; POST `sync-order-to-oneid/{orderPublicId}` [user]
- `OfflineTicketSoldController` — api/v1/offline-sold-ticket: POST `` body OfflineSoldTicketCreateRequest [Authorize(Policy=agent)]
- `TestTicketGeneratorController` — api/TestTicketGenerator: GET `` (writes TicketGeneratorQueue item to DynamoDB; test hook)

### Ticketing worker
`TicketGenerationService` → `TicketGenerationTaskManager` — consumes `AWS:Queue:TicketSigning`, message `SignedTicketGeneration`; skips if already signed (`IsTicketSigned`); downloads unsigned PDF (`ticket.UnsignedTicketUrl`), base64-encodes, builds `TicketSigningPayload` (`TSP:DigitalIdentityId`, `UserId`, `Document { Data, FileName, VdsData { QrCodeData(Dictionary<string,QRCodeField>), QrCodeSize, QrCodeXPosition, QrCodeYPosition } }`); calls `TspSignedTicketProvider.GetSignedBase64TicketAsync`; `TicketManager.GenerateSignedTicketAsync(orderId, signedData, complimentaryType, gateId)` (uploads signed PDF to S3 `AWS:Ticket:SignedBase`, updates Ticket row); deletes message. TSP auth token cached in Redis key `tsp_token` by `TspAuthProvider` (1 min).

### Ticketing SQS publishing (TicketManager)
- ~line 291: `SignedTicketGeneration` to `AWS:Queue:TicketSigning` (FileName, UnsignedTicketUrl, GateId, Data QR fields incl. Seat/Complimentary, QRPosition [x,y,size] by TicketLayoutConfig.TicketSize) — on InitiateTicket/InitiateUserTicket (user order blank tickets)
- ~1382, 1481: `SignedTicketGeneration` — reserved/admin ticket generation (`reserve-ticket`, `sign-reserve-ticket`)
- ~1740: `TicketProcessingRequest { ProcessingType=Merge }` to `AWS:Queue:TicketProcessing` — `merge-reserved`
- ~1858: `TicketProcessingRequest { ProcessingType=Zip }` — `zip-reserved`

### Ticketing key DTOs
- `SignedTicketGeneration` (Core/ETP.Core/Queue/Messages): `string FileName; string UnsignedTicketUrl; long? GateId; Dictionary<string,QRCodeField> Data; int[] QRPosition; string GroupId; string OrderId`
- `TicketProcessingRequest`: `string ReservationId; string GroupId; string OrderId; TicketProcessingType ProcessingType { Merge, Zip }`
- `ReservedTicketRequest`: `long Id; int Amount; bool HasSeats; IList<string>? Seats; string? TicketType; bool IsTest`
- `TicketUpdateRequest`: `long Id; string TicketHolderName; string TicketHolderIdentification`
- `OfflineSoldTicketCreateRequest`: `List<string> TicketNumbers; string? TicketHolderIdentification`
- `TicketRequest`: `string[] TicketNumbers; string? FileName; Email? Email` (`Email { string Recipient; string? Subject; string? Body }`); `BlankTicketRequest`
- `TicketGeneratorQueue` (DynamoDB): `string Id (GUID); string OrderFor; string OrderId; string TicketNumber`
- EF entity `Ticket`: `long Id; long BookingOrderId; Guid BookingOrderPublicId; Guid? EventId; long? EventLongId; long GalleryId/BlockId/LevelId; long ConsecutiveNumber; string TicketNumber; string? TicketHolderName/TicketHolderIdentification/BlankTicketUrl/SignedTicketUrl/EntryGates/MiniGates/Seat/BackPageTicketUrl; TicketStatus Status; string? Action/TicketType; audit; bool OneIdSync; DateTime? OneIdSyncedAt`
- Others: OneId/{OneIdAuthenticationResponse,OneIdDocumentSyncResponse}, OneIdSync/*, TspClient/Models/* (TicketSigningPayload, Document, VdsData, TspResponse), Core/Models/QRCodeField, TicketingClient/Models/{Ticket,UserBookingResponse,TicketCount,TicketSeats}

### Ticketing EF Core
`TicketingDbContext`, schema `etp`, connection **`ConnectionStrings:Booking`**. Own migrated tables: Tickets, OfflineSoldTickets (migrations 2024-12 → 2025-05). Other DbSets (Events, EventVenueDetails, VenueGalleries, GalleryBlocks, BlockLevels, TicketLayoutConfigs, BookedUserRecords, Currencies, Discounts, DiscountAssigns, ProgramTeams, Venues, EventSegments, EventSettings) are ExcludeFromMigrations mirrors. DynamoDB: TicketGeneratorQueue via `Core/ETP.Core/Storage/DynamoDB/DynamoDbRepository.cs`.

### Ticketing external calls
TSP Gateway: auth GET `TSP:AuthUrl` (mTLS, token cached 1 min Redis `tsp_token`), sign POST `TSP:SignUrl` (TicketSigningPayload, mTLS + TspTokenHandler bearer) — `Domain/TspClient/*`. OneID: `OneIdSettings:TokenUrl` (OAuth2 client_credentials, Basic auth, token cached Redis `OneId:AuthToken`), `DocumentSyncUrl` (sync tickets) — `Domain/Managers/OneIdManager.cs`. Event (×2), Booking (token-forwarded), User profiles `Services:AppBase`, Serverless (static). S3: blank/signed/merged/share PDFs; CloudFront signed URLs + cookies; SES email with zip attachment (`emailService.SendEmailWithZipAttachmentAsync`); Redis; DynamoDB; PDF generation via PdfSharpCore (BlankPdf, CustomFontResolver fonts Inter/Oswald).

## Open questions from this extraction
1. Actual queue names + credentials in User Secrets / SSM (`AWS:Queue:*`); "fifo" suffix would enable FIFO semantics.
2. DynamoDB ServiceURL hardcoded `http://localhost:8000` in `Services/Ticketing/ETP.Ticketing.Service/Configurations/DependencyConfig.cs` (lines 62–74) — local-dev leftover? [confirmed in code]
3. Ticketing DB connection uses `ConnectionStrings:Booking`; `ConnectionStrings:Ticketing` exists but unused.
4. Several Booking/Ticketing/Event endpoints have no `[Authorize]` (CapacityController, ReportController, SeatReservation updates, initiate*, Event EventsController) — rely on network placement.
5. Event SQS registration dead code.
6. Admin `AgentUserController` anonymous — verify intentional.
7. README claims SQL Server — stale.
8. Swagger served in all envs; TSP HttpClient `ServerCertificateCustomValidationCallback => true`.
9. `CheckedTicketService` drains Redis → CheckedTickets every 30 min (20-min RedLock); TicketChecker service reads Redis directly.
10. Default auth scheme is `admin`, so plain `[Authorize]` accepts admin-scheme tokens only; endpoints with no attribute are anonymous.
