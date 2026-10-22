# DTO Shapes for User-Facing Flows — Handover Report

Paths are relative to each repo root (`rvl-gobcb-backend`, `rvl-gobcb-user-app`, `rvl-gobcb-user-portal`), which live side-by-side under the workspace root.

Serialization note (applies to JSON bodies below): Ticketing/Booking/Event services configure ASP.NET Core as **camelCase, `JsonStringEnumConverter` (enums as strings), `JsonIgnoreCondition.WhenWritingNull`** — e.g. `Services/Ticketing/ETP.Ticketing.Service/Program.cs` lines 63–69 (Booking and Event `Program.cs` have the same). The Admin service does **not** register `JsonStringEnumConverter` (its enums would be numbers; the Discount model below uses strings anyway).

---

## 1. Ticketing Service (`api/v1/booking-order-ticket`)

Controller: `Services/Ticketing/ETP.Ticketing.Service/Api/BookingOrderTicketController.cs`
Manager: `Services/Ticketing/ETP.Ticketing.Domain/Managers/TicketManager.cs`

### 1.1 GET `details?publicId={guid}` — response `UserBookingResponse`
Built by `TicketManager.GetTicketsInfo` (lines 146–208; adapts Booking-service `UserBooking` via Mapster, clears `PaymentInfo` to `""`, nulls `SignedTicketUrl`/`BlankTicketUrl` on tickets, computes `SubTotal = PricePerSeat * NumberOfSeats`, extracts `TransactionId`/`PaymentMethod` from stored DgePay `PaymentInfo` JSON).

`Services/Ticketing/ETP.Ticketing.Domain/Models/UserBookingResponse.cs` (inherits base below):

| Property | C# type |
|---|---|
| TransactionId | `string` |
| PaymentMethod | `string` |
| SubTotal | `double` |
| IsVatInclusive | `bool` |
| VatIncludedBasePricePerSeat | `double` |
| Tickets | `List<Ticket>?` |
| EventDetails | `Event.Domain.Models.Event?` (ETP.Event.Domain model, shape in §3) |
| VenueDetails | `UserLevelWithGates?` (`ETP.Core.ServiceClient.AdminClient.Models`) |
| TicketAttributes | `TicketDynamicAttributesResponse?` |

Base class `Services/Ticketing/ETP.Ticketing.Domain/Models/UserBooking.cs`:

| Property | Type |
|---|---|
| Id | `long` |
| User | `CognitoUser` (`Core/ETP.Core/ServiceClient/ServerlessClient/CognitoUser.cs`: user_id, name, phone, email, verification_type, verification_id — all `string`) — not populated in this flow |
| PublicId | `Guid` |
| ProgramId | `long` |
| EventId | `Guid` |
| EventLongId | `long` |
| GalleryId / BlockId / LevelId | `long` |
| UserId | `string?` |
| OrderNumber | `string` |
| NumberOfSeats | `int` |
| HasSeats | `bool` |
| Seats | `string?` |
| PricePerSeat | `double` |
| PromoCode | `string?` |
| PromoDiscount | `double` |
| TotalCharge | `double` |
| Vat | `double` |
| VatIncludedBasePricePerSeat | `double` |
| PlatformCharge | `double` |
| IsVatInclusive | `bool` |
| Discount | `double` |
| Status | `Status` enum: `Pending, Failed, Paid, Cancelled, Requested, Generated` (string in JSON) |
| PaymentInfo | `string?` (returned as `""`) |
| PaymentTransactionId | `string?` |
| CreatedAt | `DateTime` |
| EventName | `string` |
| EventStartDateTime / EventEndDateTime | `DateTime` |
| CancelledAt / CallbackReceivedAt | `DateTime` |
| TicketAvaiableFrom | `DateTime` (typo "Avaiable" is the wire name; app parses `ticketAvaiableFrom`) |

`Ticket` — `Services/Ticketing/ETP.Ticketing.Storage/Models/Ticket.cs` (user-facing fields; audit fields `[JsonIgnore]`):

| Property | Type |
|---|---|
| Id | `long` (from `Entity<long>`) |
| BookingOrderId | `long` |
| BookingOrderPublicId | `Guid` |
| EventId / EventLongId | `Guid?` / `long?` |
| GalleryId / BlockId / LevelId | `long` |
| ConsecutiveNumber | `long` |
| TicketNumber | `string` |
| TicketHolderName / TicketHolderIdentification | `string?` |
| BlankTicketUrl / SignedTicketUrl | `string?` (nulled in `details` response) |
| EntryGates / MiniGates | `string?` |
| Seat | `string?` |
| Status | `TicketStatus` enum: `Active, Requested, Generated` (string in JSON) |
| Action / TicketType / BackPageTicketUrl | `string?` |
| CreatedAt | `DateTime` |
| OneIdSync | `bool` |
| OneIdSyncedAt | `DateTime?` |

`TicketDynamicAttributesResponse` + `TicketAttribute` — `Services/Ticketing/ETP.Ticketing.Domain/Models/TicketAttributesModel.cs`:
- `TicketDynamicAttributesResponse`: ProgramId `long`, VenueType `string` (default "Stadium"), DynamicAttributes `List<TicketAttribute>`, ShowVenueName `bool`, ShowSegmentDateTime `bool`
- `TicketAttribute`: Name `string`, Value `string`, IsVisible `bool`, Priority `int`

### 1.2 GET `share?ticketNumber=`
Controller line 415–421 → `TicketManager.ShareTicketAsync` (lines 1890–1907) returns a **`string`**; controller returns `Ok(ticket)` → body is a JSON-quoted URL:
`{TicketOptions.ShareBase}?ticketNumber={ticketNumber}&signature={X-Amz-Signature}` where `ShareBase`/`ShareExpiryMinutes` come from user secrets (`Services/Ticketing/ETP.Ticketing.Service/appsettings.json` lines ~100/103: `"[see User Secrets]"`). The presigned S3 URL is cached in Redis under `sharedTicket:{ticketNumber}_{signature}` for expiry minutes; the companion `GET shared?ticketNumber=&signature=` (AllowAnonymous, controller line 398) streams the PDF. Portal consumes share with `responseType: 'text'`.

### 1.3 GET `download?ticketNumber=` / `download-all/{orderPublicId}` / `download-invoice/{publicId}`
All return **byte streams, not redirects or URLs**:
- `download` (line 380–390): `File(pdfStream, "application/pdf", "{ticketNumber}.pdf")` — `FileStreamResult`, `Content-Disposition: attachment`.
- `download-all/{orderPublicId}` (line 346–356): `File(pdfStream, "application/zip", "{eventName}.zip")` — zip stream via `GetUserAllTicketStreamAsync`.
- `download-invoice/{publicId}` (line 505–515): `File(pdfBytes, "application/pdf", "TicketInvoice.pdf")` — `FileContentResult` from `byte[]` (`DownloadInvoiceByPublicId`, TicketManager line 2008).

### 1.4 GET `check-generated-status` (Booking service)
`Services/Booking/ETP.Booking.Service/Api/UserBookingOrderController.cs` line 268–277 (route `api/v1/user-booking-order/check-generated-status?id=`) → `UserBookingOrderManager.CheckGeneratedStatus` (`Services/Booking/ETP.Booking.Domain/Managers/UserBookingOrderManager.cs` lines 1019–1042) returns `Task<bool>` → **raw JSON `true`/`false`** (throws `ArgumentException` "Booking not found." / "Privacy error." otherwise).

### 1.5 PATCH `generate-request/{publicId}`
Controller line 112–117 → `TicketManager.TicketGenerateRequest` (lines 261–356). Returns **`UserBookingResponse`** (same shape as §1.1): order re-fetched from Booking, tickets set to `Status = Requested` with `BlankTicketUrl = null`, blank PDFs uploaded and signing jobs published to SQS. Throws 400 `"Request to generate ticket is already taken."` / `"Only paid order requests can generate tickets"` / `"You can request after ticket availability date."`.

Related: PATCH (no route) update ticket → `TicketUpdateRequest` (`Services/Ticketing/ETP.Ticketing.Domain/Models/Tickets/TicketUpdateRequest.cs`): `Id` long, `TicketHolderName` string, `TicketHolderIdentification` string — echoed back as response.

### 1.6 `sync-to-oneid` / `sync-order-to-oneid`
Both `[HttpPost]`, user policy, in the same controller (lines 536–573). Request: **no body** (route params only).
- `sync-to-oneid/{ticketNumber}` → `OneIdSyncResponse` (`Services/Ticketing/ETP.Ticketing.Domain/Models/OneIdSync/OneIdSyncResponse.cs`): Success `bool`, Message `string`, TicketNumber `string`, AlreadySynced `bool`, SyncedAt `DateTime?`. 404 body `{ message: "Ticket not found" }` when not found.
- `sync-order-to-oneid/{orderPublicId}` → `OneIdOrderSyncResponse` (same folder): Success `bool`, Message `string`, TotalTickets `int`, SyncedTickets `int`, FailedTickets `int`, AlreadySyncedTickets `int`, Results `List<OneIdSyncResponse>`. 404 body `{ message: "Order not found" }`.

### 1.7 POST `generate-signed-token` (Admin policy)
Controller line 488–498. **Request: no body** — it reads the caller's `Authorization: Bearer …` header. Response: `Ok(string)` → HMAC-SHA512 hash of the bearer token (`TicketManager.GenerateSignedTokenAsync`, lines 1995–2006), cached in Redis 60 s. (The `ProducesResponseType` declares `Redirect` but it actually returns 200 with a JSON string.)

---

## 2. Booking Service

### 2.1 `ApplyPromoCodeResponse`
`Services/Booking/ETP.Booking.Domain/Models/ApplyPromoCodeResponse.cs` — returned by POST `api/v1/user-booking-order/apply-promo-code` (route at `Services/Booking/ETP.Booking.Service/Api/UserBookingOrderController.cs` line 444):

| Property | Type |
|---|---|
| IsSuccess | `bool` |
| DiscountType | `string?` |
| DiscountValue | `double` |
| DiscountAppliedTo | `string?` |

### 2.2 GET `admin/api/v1/discount/program/{programId}/{eventId}/{galleryId}`
Note: this endpoint is in the **Admin service**, not Booking — `Services/Admin/ETP.Admin.Service/Api/DiscountController.cs` lines 128–139 (`[AllowAnonymous]`, `GET api/v1/discount/program/{programId(long)}/{eventId(string)}/{galleryId(long)}`). Returns `Discount` (`Services/Admin/ETP.Admin.Domain/Models/Discounts/Discount.cs`):

| Property | Type |
|---|---|
| Name | `string` |
| ProgramId | `long` |
| DiscountType | `string` |
| DiscountValue | `double` |
| Status | `string` |
| StartDateTime / EndDateTime | `DateTime` |
| DiscountAssigns | `ICollection<DiscountAssign>` |

`DiscountAssign` (same folder, `DiscountAssign.cs`): DiscountId `long`, AssignType `string`, ProgramId `long`, Program `Program` (`ETP.Admin.Domain.Models.Events`), Events `ICollection<Event>?`, Galleries `ICollection<VenueGallery>?`, VenueEventGalleryNames `ICollection<DiscountVenueEventGallery>?`.
Clients (app/portal) only read `name`, `discountType`, `discountValue`.

### 2.3 `CapacityController` — `Services/Booking/ETP.Booking.Service/Api/CapacityController.cs` (route `api/v1/capacity`), manager `Services/Booking/ETP.Booking.Domain/Managers/CapacityManager.cs`
- GET `level-user-portal-seats?eventId&galleryId&blockId&levelId` (lines 54–64) → `AvailableSeatsCapacity` (`Services/Booking/ETP.Booking.Domain/Models/Capacity.cs` lines 15–19): **Total** `string`, **Available** `string` — comma-separated seat-number lists (empty string when none).
- GET `level-live-seats?…` (lines 39–49) → `Task<string?>` (manager line 298) — a bare JSON string of comma-separated available seats (all seats minus purchased minus locked < 12 min).
- GET `event-live-capacity?eventId` (lines 69–79) → `int`.
- GET `online-tickets-count?eventId` (lines 99–109) → `int`.
- (also present: `level-live-capacity` → `int`.)
- Entity `Capacity` (same file): Id/EventId/GalleryId/BlockId/LevelId `long`, TicketingCapacity `int`, HasSeats `bool`, Seats `string?`.

---

## 3. Event Service

### 3.1 GET `api/v1/events/venue-details/{eventId}` — what users actually receive
`Services/Event/ETP.Event.Service/Api/EventsController.cs` lines 63–76 → `EventManager.GetEventVenueDetailsByEventIdAsync` (`Services/Event/ETP.Event.Domain/Managers/EventManager.cs` line 391) returns **`ETP.Event.Domain.Models.Event`** (not a separate tree DTO) with live capacity injected per level. Model `Services/Event/ETP.Event.Domain/Models/Event.cs`:

Id `long`, EventId `string`, EventName `string`, ProgramId `long`, VenueId `long`, ProgramName/ProgramLogo/ProgramShortName/ProgramStartDateTime/ProgramEndDateTime `string`, BannerImage `string`, EventStartDateTime `DateTime`, EventEndDateTime `DateTime?`, TicketSellingStartDateTime/TicketSellingStopDateTime/TicketAvailabilityStartDateTime `DateTime`, MinimumPrice `decimal`, AvailabilityStatus `AvailabilityStatus` (enum), Vat `decimal?`, IsVatPercentage `bool`, ServiceCharge `decimal?`, IsServiceChargePercentage `bool`, AllowableMaximumSeatPerOrder/AllowableMaximumOrderPerUser `int`, IsVatInclusive `bool?`, IsPublished/IsActive `bool`, EventSettings `EventSettings`, Segments `List<Segment>`, Venue `Venue`, Program `Program`.

Nested user-facing venue tree (`Services/Event/ETP.Event.Domain/Models/Venue.cs`, `VenueGallery.cs`, `GalleryBlock.cs`, `BlockLevel.cs`, `Segment.cs`):
- `Venue`: Name `string`, Location `string`, SvgFile `string`, SvgMapImage `string`, VenueGalleries `List<VenueGallery>`
- `VenueGallery`: Id `long`, Name `string`, SvgKey `string?`, IsSeatMapped `bool`, GalleryBlocks `List<GalleryBlock>`
- `GalleryBlock`: Id `long`, Name `string`, SvgKey `string?`, IsSeatMapped `bool`, BlockLevels `List<BlockLevel>`
- `BlockLevel`: Id `long`, Name `string`, SvgKey `string`, IsSeatMapped `bool`, HasSeats `bool`, Seats `string?`, PricePerSeat `decimal`, IsVatInclusive `bool?`, CurrentCapacity `int`, AvailableCapacity `int`
- `Segment`: Id `long`, Name `string`, BannerImage `string`, SegmentType `string`, StartDateTime/EndDateTime `DateTime`, Team1/Team1Logo/Team2/Team2Logo `string`, Team1IsFlag/Team2IsFlag `bool?`, Team1Flag/Team2Flag `string?`

### 3.2 `EventVenueDetailsTree` / "EventVenueDetailsRedis"
There is **no class literally named `EventVenueDetailsRedis`** anywhere — `EventVenueDetailsRedis.cs` is the *file name* containing `EventVenueDetailsTree`. Multiple variants exist:
- `Services/Event/ETP.Event.Domain/Models/EventVenueDetailsRedis.cs` (ns `ETP.Event.Domain.Models.Redis.Events`): EventId `string`, EventName `string`, EventStartDateTime `DateTime`, TicketSellingStartDateTime/`TicketSellingStopDateTime` `DateTime`, Segments `List<Segment { Name: string }>`, Venue `{ Name, Location, SvgFile: string; VenueGalleries }` → VenueGallery `{ Id: long, Name, SvgKey: string?, IsSeatMapped: bool, GalleryBlocks }` → GalleryBlock `{ Id: long, …, BlockLevels }` → BlockLevel `{ Id: long, Name, SvgKey: string?, IsSeatMapped, HasSeats: bool, Seats: string?, PricePerSeat: decimal }`.
- `Services/Admin/ETP.Admin.Domain/Models/Events/EventVenueDetailsRedis.cs` (ns `ETP.Admin.Domain.Models.Redis.Events`): same skeleton but Ids are `string` and `PricePerSeat` is `string`, no HasSeats/Seats.
- `Services/Admin/ETP.Admin.Domain/Models/Events/EventVenueDetailsTree.cs` (ns `ETP.Admin.Domain.Models.Events`) — admin flat row: ProgramId/EventId/VenueId/VenueGalleryId/GalleryBlockId/BlockLevelId `long`, IsGalleryActive/IsSeatMappedInGallery/IsGallerySellable/IsBlockActive/IsSeatMappedInBlock/IsBlockSellable/IsLevelActive/IsSeatMappedInLevel/IsLevelSellable `bool`, GalleryName/BlockName/LevelName `string`, HasSeats `bool`, Seats `string?`, CurrencyId `long`, SeatingCapacity `int`, PricePerSeat `decimal`, IsPublish/IsDeleted/IsActive `bool`, CreatedAt `DateTime`, CreatedBy `string?`, UpdatedAt `DateTime?`, UpdatedBy `string?`; plus `Node { Data Data; List<Node> Children }` and `Data { GalleryId/BlockId/LevelId long?, Name/GalleryName/BlockName/LevelName/DefaultSeats/UnitPrice string, IsUnitPriceEditing/IsAllocateViewing/IsDeAllocateViewing/IsReservedViewing/IsReleasedViewing/IsTicketGenerated/HasSeats bool, Allocated/TotalAllocated/DeAllocated/TotalReserved/Reserved/ReservedOnly/Released/TotalCapacity/AvailableCapacity int, AllocatedSeats/DeAllocatedSeats/ReservedSeats/ReleasedSeats/Seats/AvailableForReserveSeats/PendingSeats/PurchasedSeats string?, AvailableOnlineCapacity int?, RemainingReservedSeat int }`. A near-copy exists at `Core/ETP.Core/ServiceClient/AdminClient/Models/EventVenueDetailsTree.cs` (Data lacks TotalPending/TotalPurchased).

### 3.3 `HeaderFooter` — `Services/Event/ETP.Event.Domain/Models/HeaderFooter.cs` (GET `api/v1/header-footer` returns a list, `Services/Event/ETP.Event.Service/Api/HeaderFooterController.cs`)
BrandImageUrl `string?`, PoweredByImageUrl `string?`, FacebookUrl `string?`, InstagramUrl `string?`, LinkedInUrl `string?`, TwitterUrl `string?`, Title `string`, PhoneNumber `string?`, Email `string?`, OfficeAddress `string?`.

### 3.4 `LandingPageImagePublic` — `Services/Event/ETP.Event.Domain/Models/LandingPageImagePublic.cs` (GET `api/v1/landing-page-image/public`)
Title `string?`, Description `string?`, ActionUrl `string?`, ImageUrl `string`, ThumbnailUrl `string?`, Type `string`, DisplayOrder `int`, StartDateTime `DateTime?`, EndDateTime `DateTime?`.

---

## 4. User App (Flutter, repo `rvl-gobcb-user-app`)

### 4.1 Identity/auth endpoints — `data/lib/remote/api_service/auth_api_service/auth_api_service_impl.dart` (base URL env `AUTH_API_BASE_URL`, `data/lib/remote/api_client/auth_api_client.dart`)
- POST `user/register-cached` — request: `name`, `email`, `phone`, `address`, `verification_type`, `verification_id` (strings), `dob` (`yyyy-MM-dd` string). Response ignored (`Future<void>`).
- POST `otp/send-otp` — request: `type` (`"email"` | `"sms"`), `destination`. Response ignored.
- POST `otp/verify-otp` — request: `type`, `destination`, `otp`. SMS variant reads **`user_id`** (string) from response (`response["user_id"]`); email variant ignores response. Model `data/lib/remote/response/verify_otp_sms_response.dart`: `message`, `user_id` (`String?`).
- POST `user/register` — request: `user_id`, `ekyc`, `address`, `password` (strings).
- POST `otp/password-reset-request` — request: `phone`.
- POST `otp/password-reset` — request: `phone`, `otp`, `password`.
- POST `user/register-sso` — in `data/lib/remote/api_service/profile_api_service/profile_api_service_impl.dart`: request `{ "name": "", "cognito_sub": <sub> }`.
- DELETE `user/delete-my-profile` — no body.
- GET `user/my-profile?user_id=` — parsed by `data/lib/remote/response/user_response.dart`: top-level `user_data`; `UserData` fields: `nonsensitive_data` (`verification{verification_type, verification_id}`, `ekyc{verified, data}`), `sensitive_data` (`verification`, `payment{verified, id}`, `ekyc`), `registration_datetime`, `address`, `email`, `verified` (bool), `name`, `isProfileCompleted` (string `"true"`), `user_id`, `role`, `dob`, `temp_user_id?`, `phone`, `sso_provider?`.
- PUT `user/my-profile` — request: `verification_type`, `verification_id`, `address`, `dob` (`yyyy-MM-dd`).
- GET `user/allowed-app-version` — `data/lib/remote/api_service/app_version_api_service/app_version_api_service_impl.dart`; response `data/lib/remote/response/app_version_response.dart`: `{ message?, status?, data?: { up?: { android?, ios? }, tc?: { android?, ios? } } }`, each version `{ version: string?, build_number: int?, app_link: string? }`.

### 4.2 Ticket download consumption
- URLs are built client-side in `data/lib/remote/api_service/ticket_api_service/ticket_api_service_impl.dart`: `getTicketDownloadUrl` → `{API_BASE_URL}/ticketing/api/v1/booking-order-ticket/download?ticketNumber=…`, `getAllTicketDownloadUrl` → `…/download-all/{publicId}`, `getInvoiceUrl` → `…/download-invoice/{publicId}`; headers carry `Authorization` + `accept: application/pdf|application/zip`.
- Downloaded with **flutter_downloader** (`pubspec.yaml`: flutter_downloader 1.12.0): `data/lib/service/download_service.dart` (`FlutterDownloader.enqueue`, isolate callback port `downloader_send_port`), invoked from `data/lib/repository/booking_details_repository_impl.dart` (single ticket → `$ticketId.pdf`; all tickets → `$publicId.zip`, `saveInPublicStorage: true`) and `data/lib/repository/ticket_booking_repository_impl.dart` (invoice → `$orderId-invoice.pdf`). View model: `lib/presentation/feature/booking_details/booking_details_view_model.dart`.
- Sharing uses **share_plus** (12.0.0) `SharePlus.instance.share(ShareParams(files:[XFile(path)], subject:'Ticket PDF', title:'Share Ticket'))` in the same view model (`_shareOnSocialMedia`, lines 252–278).

### 4.3 Payment flow (webview navigation detection)
- `lib/presentation/feature/ticket_booking/ticket_booking_view_model.dart` lines 501–557: after POST `booking/api/v1/user-booking-order` returns `CheckoutResponse { publicId: String, checkoutUrl: String }` (`data/lib/remote/response/check_out_response.dart`), navigates to `PaymentRoute` with `targetUrl: dotenv.env['PAYMENT_SUCCESS_URL'] ?? 'ticket-bangla.com/tickets'` and an `onPaymentSuccess(url)` callback.
- `lib/presentation/feature/payment/payment_view_model.dart` (`webview_flutter`): `NavigationDelegate.onNavigationRequest` (lines 109–126) — if the request URL **contains** `targetUrlHostName` (substring match, not equality) and not already popped, fires `onPaymentSuccess(request.url)` and pops (`NavigationDecision.prevent`). `PAYMENT_SUCCESS_URL` is a required env var (`lib/main/main.dart` line 20).

### 4.4 Cross-check notes (app ↔ backend)
- `BookingDetailsResponse` (`data/lib/remote/response/booking_details_response.dart`) parses the §1.1 payload incl. `ticketAvaiableFrom`, `venueDetails { venueName, gallery, block, level, entryGate, miniGate }`, `ticketAttributes`, tickets incl. `seat`, `oneIdSync`.
- Seat endpoint parsed by `data/lib/remote/response/ticket_booking/seat_availability_response.dart` reading `total`/`available` strings and splitting on `,` — matches §2.3.
- System discount parsed by `data/lib/remote/response/system_discount_response.dart` reading `name`/`discountType`/`discountValue` — matches §2.2.

---

## 5. User Portal (Angular, repo `rvl-gobcb-user-portal`)

### 5.1 Identity endpoints — `ETP-Web/src/app/modules/core/services/api/identity-api.service.ts` (base `${environment.services.identity}`; adds `Authorization: environment.headerkey`)
- `initSignUp` POST `user/register-cached` — `InitSignUpPayload` (`ETP-Web/src/app/modules/core/models/user-auth.ts`): `name`, `email`, `phone`, `dob`, `address` strings; `verification_type?`, `verification_id?`. (Same field names as the app.)
- `sendOtp` POST `otp/send-otp` — `SendOtp { type: string; destination: string }`.
- `verifyOtp` POST `otp/verify-otp` — `VerifyOtp { type; destination; otp }`.
- `signUp` POST `user/register` — `SignUpPayload { user_id: string; password: string }` (narrower than app's, which also sends `ekyc`/`address`).
- `fetchUserProfile` GET `user/my-profile` → `UserProfile` (`ETP-Web/src/app/modules/core/models/user-profile.ts`): `user_data { nonsensitive_data{ekyc{verified,data}, verification{verification_id, verification_type}}, sensitive_data{ekyc, payment{verified,id}, verification}, registration_datetime, address, email, name, verified, isProfileCompleted, user_id, role, dob, temp_user_id, phone, one_id?, sso_provider? }` — matches app names (portal additionally expects `one_id`).
- `updateUserProfile` PUT `user/my-profile` — `UpdateProfile { verification_id, verification_type, address, dob }`.
- `resetPasswordRequest` POST `otp/password-reset-request` — `ResetPasswordRequest { phone }`; `resetPassword` POST `otp/password-reset` — `ResetPassword { phone, otp, password }`.
- `deleteUserProfile` DELETE `user/delete-my-profile`; `registerSSOUser` POST `user/register-sso` (payload typed `any`).
- Legacy no-op endpoints also present: `POST /token`, `/refreshToken`, `/forgotpassword`, `/password` (`SignInPayload`, `TokenResponse { access_token, token_type, expires_in, refresh_token }`, `RefreshTokenPayload`, `forgotPasswordPayload`, `changePasswordPayload`).

### 5.2 `complete-payment-modal.component.ts` — `ETP-Web/src/app/modules/featured/tickets/components/complete-payment-modal/complete-payment-modal.component.ts`
`onSubmit()` calls `BookingApiService.ticketPurchase(TicketPurchase)` (POST `booking/api/v1/user-booking-order`, `ETP-Web/src/app/modules/core/services/api/booking-api.service.ts` lines 33–38). If response has `checkoutUrl`, it does **`window.location.href = booked.checkoutUrl`** (full page navigation away to DgePay) and closes the dialog. On error shows `err.error.title`.

### 5.3 DgePay callback redirect route
- Backend lands the user on the portal via `payment-status-bypass` redirect → `paymentSettings.DgePay.RedirectUrl` (user secret; `Services/Booking/ETP.Booking.Service/appsettings.json` line 48).
- `ETP-Web/src/app/app-routing.module.ts` lines 56–64: path `tickets` (comment "Handle payment redirect without language") is a `redirectTo` closure that prepends the saved language → `/{lang}/tickets`, which loads `AllBookingsPageComponent` (`ETP-Web/src/app/modules/featured/tickets/ticket-routing.module.ts` line 9; component `pages/all-bookings-page/all-bookings-page.component.ts`).
- **No URL-query / payment-result parsing exists**: `AllBookingsPageComponent.ngOnInit` simply calls `getAllbookings(0,50,Descending)` and re-renders the booking list; `BookingDetailsComponent` (`pages/booking-details/booking-details.component.ts`) reads only the `:id` route param and the first segment (`ticket-details` vs `payment-invoice`). Payment outcome is inferred from the order `status` returned by the API (`Paid`/`Pending`/…), and ticket generation is polled via `checkGeneratedStatus(id)` (booking-api.service.ts lines 50–54).

### 5.4 Portal consumption of ticketing endpoints (cross-check, booking-api.service.ts)
`downloadTicketByTicketNumber`/`downloadAllTicketsByBookingId`/`downloadInvoice` → `responseType: 'blob'` (confirms byte streams); `shareTicketByTicketNumber` → `responseType: 'text'` (confirms string URL); `requestTicketsById` PATCH `generate-request/{id}` with `null` body; `syncOrderToOneId` POST `sync-order-to-oneid/{orderId}`; `getAvailableSeats` GET `capacity/level-user-portal-seats`; `getDiscount` GET `admin/api/v1/discount/program/...`.

---

## Could not verify
1. **Identity backend implementation** — `Services/UserAuth` in the backend repo is effectively empty (only a stub `TestController`). The server implementing `user/register-cached`, `otp/*`, `user/my-profile`, `user/allowed-app-version`, `user/register-sso` is not in this workspace (likely external/serverless; `floci/` at workspace root is only nginx/docker scaffolding), so server-side DTOs for identity are inferred solely from the app/portal clients.
2. **Secret values**: `TicketOptions.ShareBase`/`ShareExpiryMinutes` and `DgePay:RedirectUrl` are `"[see User Secrets]"` — actual runtime URLs unknown.
3. **Portal environment files** — `ETP-Web/src/environments/*` (incl. `services.identity`, `headerkey`) are absent from the repo (gitignored/generated), so the exact identity base URL per environment is unverifiable.
4. **`UserBooking` serialization in `details` for `Guid` types** — `PublicId`/`EventId` serialize as GUID strings, but I did not trace the custom `DateTimeConverter` (Ticketing Program.cs line 68) to confirm exact datetime wire format.
5. Whether the Flutter app's unused `PaymentDetails`/`getInvoiceUrl` flow uses `ticketBanglaApiClient` (separate `API_BASE_URL` host) in production — wiring is present but env values not in repo.