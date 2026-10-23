# RVL-ETP Backend — DTO Shapes + Error Envelope Report

All paths are relative to `rvl-gobcb-backend/`. Property names/types are exactly as in code. Serialization notes:
- Admin service (`Services/Admin/ETP.Admin.Service/Program.cs`): default MVC JSON options — camelCase, enums as **numbers**, nulls included.
- Booking service (`Services/Booking/ETP.Booking.Service/Program.cs:68-73`): explicit `PropertyNamingPolicy = CamelCase`, `DefaultIgnoreCondition = WhenWritingNull`, `JsonStringEnumConverter` (enums as **strings**), custom `DateTimeConverter`.

---

## 1. Admin Service DTOs

### 1.1 Dashboard

**`TileData`** — `Services/Admin/ETP.Admin.Domain/Models/Dashboard/TileData.cs`
```csharp
public int TotalEvents { get; set; }
public int UnResolveIssue { get; set; }
```

**`EventsByCategory`** — `Services/Admin/ETP.Admin.Domain/Models/Dashboard/EventsByCategory.cs`
```csharp
public int TotalUpcoming { get; set; }
public int TotalPast { get; set; }
public int TotalRunning { get; set; }
```
Endpoints: `GET api/v1/dashboard/get-tile-data?programId=`, `GET api/v1/dashboard/get-event-by-category` (`Services/Admin/ETP.Admin.Service/Api/DashboardController.cs`). Mirrors also exist under `ETP.Admin.Storage/Models/Dashboard/` (storage entities).

### 1.2 Admin users

**`AdminUserResponse`** — `Services/Admin/ETP.Admin.Domain/Models/Users/Admin/AdminUserResponse.cs`
```csharp
public string UserId { get; set; }
public string Name { get; set; } = default!;
public string Email { get; set; } = default!;
public string Phone { get; set; } = default!;
public string Role { get; set; } = default!;
public string ProgramIds { get; set; } = default!;
public string CurrentStatus { get; set; } = default!;
public bool IsActive { get; set; } = true;
public bool IsPhoneNumberVerified { get; set; }
```

**`AdminUpdateUser`** — same folder, `AdminUpdateUser.cs`
```csharp
public string UserId { get; set; }
public string Name { get; set; } = default!;
public string Role { get; set; } = default!;
public string? ProgramIds { get; set; }
```

**`AdminSetPasswordRequest`** — `AdminSetPasswordRequest.cs`: `public string UserId { get; set; } = string.Empty;`

**`AdminForgetSetPassword`** — `AdminForgetSetPassword.cs`
```csharp
public string UserId { get; set; } = default!;
public string Password { get; set; } = default!;
```
Controller: `Services/Admin/ETP.Admin.Service/Api/AdminUsersController.cs` (route `api/v1/admin-users`; PUT `{id}` takes `AdminUpdateUser`; only `ProducesResponseType` for 404/500 declared — no success-code attribute).

### 1.3 Promo codes

**`PromoCode`** (response) — `Services/Admin/ETP.Admin.Domain/Models/PromoCodes/PromoCode.cs`
```csharp
public string Code { get; set; } = string.Empty;
public string Name { get; set; } = string.Empty;
public long ProgramId { get; set; }
public string DiscountType { get; set; } = string.Empty;      // string in response
public double DiscountValue { get; set; }
public string DiscountAppliedTo { get; set; } = string.Empty; // string in response
public int TotalUsageLimit { get; set; }
public int LimitPerUser { get; set; }
public string Status { get; set; } = string.Empty;
public DateTime StartDateTime { get; set; }
public DateTime EndDateTime { get; set; }
public List<PromoCodeAssign> AssignTo { get; set; }
```

**`PromoCodeAssign`** (response child) — `PromoCodeAssign.cs`
```csharp
public long Id { get; set; }
public long PromoCodeId { get; set; }
public string AssignType { get; set; }             // string in response
public long ProgramId { get; set; }
public Program Program { get; set; }               // ETP.Admin.Domain.Models.Events.Program
public ICollection<Event>? Events { get; set; }
public ICollection<VenueGallery>? Galleries { get; set; }
public ICollection<PromoCodeVenueEventGallery>? VenueEventGalleryNames { get; set; }
```

**Create request** `CreateOrUpdatePromoCode` + `CreateOrUpdatePromoCodeAssign` + `PromoCodeVenueEventGallery` — `CreateOrUpdatePromoCode.cs`
```csharp
// CreateOrUpdatePromoCode
public string Code; public string Name; public long ProgramId;
public DiscountType DiscountType;                  // enum here
public double DiscountValue;
public DiscountAppliedType DiscountAppliedTo;      // enum here
public DateTime StartDateTime; public DateTime EndDateTime;
public int TotalUsageLimit; public int LimitPerUser;
public List<CreateOrUpdatePromoCodeAssign> AssignTo;
// CreateOrUpdatePromoCodeAssign
public AssignType AssignType; public long ProgramId;
public ICollection<long>? EventIds; public ICollection<long>? GalleryIds;
public ICollection<PromoCodeVenueEventGallery>? VenueEventGalleryNames;
// PromoCodeVenueEventGallery
public long PromoCodeAssignId; public long VenueId; public long EventId; public long GalleryId;
public string VenueEventGalleryName;
```

### 1.4 Enums — `Services/Admin/ETP.Admin.Domain/Enums/Enums.cs` (nested in `class Enums`)
```csharp
enum DiscountType        { Percentage = 1, FixedAmount = 2 }
enum DiscountAppliedType { BasePrice = 1, DiscountedPrice = 2 }
enum AssignType          { Event = 1, Gallery = 2 }
enum PromoCodeStatus     { Active = 1, Expired = 2, Upcoming = 3, LimitReached = 4 }
enum DiscountStatus      { Active = 1, Expired = 2, Upcoming = 3, LimitReached = 4 }
enum TicketLayoutType    { SingleSegmentUser, MultipleSegmentUser, SingleSegmentPartner,
                           MultipleSegmentPartner, SingleSegmentComplimentary,
                           MultipleSegmentComplimentary }   // unnamed => 0..5
enum VenueType           { Stadium = 1, ExhibitionHall = 2 }
enum LandingPageImageType { Hero, Sponsors, Graffiti, Advertisement, Gallery_Page_Segment_1,
                            Gallery_Page_Segment_2, Contact_Us, Registration, Notice,
                            Terms_Condition, Privacy_Policy, FAQ }
```
(Admin service serializes enums as numbers by default.)

### 1.5 Discounts

**`Discount`** (response) — `Services/Admin/ETP.Admin.Domain/Models/Discounts/Discount.cs`
```csharp
public string Name { get; set; } = string.Empty;
public long ProgramId { get; set; }
public string DiscountType { get; set; } = string.Empty;  // string in response
public double DiscountValue { get; set; }
public string Status { get; set; } = string.Empty;
public DateTime StartDateTime { get; set; }
public DateTime EndDateTime { get; set; }
public ICollection<DiscountAssign> DiscountAssigns { get; set; }
```

**`DiscountAssign`** (response child) — `DiscountAssign.cs`: `long DiscountId`, `string AssignType`, `long ProgramId`, `Program Program`, `ICollection<Event>? Events`, `ICollection<VenueGallery>? Galleries`, `ICollection<DiscountVenueEventGallery>? VenueEventGalleryNames`.

**`CreateOrUpdateDiscount` + `CreateOrUpdateDiscountAssign` + `DiscountVenueEventGallery`** — `CreateOrUpdateDiscount.cs`
```csharp
// CreateOrUpdateDiscount
public string Name; public long ProgramId;
public DiscountType DiscountType;            // enum
public double DiscountValue;
public DateTime StartDateTime; public DateTime EndDateTime;
public ICollection<CreateOrUpdateDiscountAssign> DiscountAssigns;
// CreateOrUpdateDiscountAssign
public AssignType AssignType; public long ProgramId;
public ICollection<long>? EventIds; public ICollection<long>? GalleryIds;
public ICollection<DiscountVenueEventGallery>? VenueEventGalleryNames;
// DiscountVenueEventGallery
public long DiscountAssignId; public long VenueId; public long EventId; public long GalleryId;
public string VenueEventGalleryName;
```

### 1.6 General notices

**`GeneralNotice`** — `Services/Admin/ETP.Admin.Domain/Models/Settings/GeneralNotice/GeneralNotice.cs`
```csharp
public long Id; public long ProgramId;
public string Description = string.Empty;
public DateTime StartDateTime; public DateTime EndDateTime;
public bool IsPublished; public bool IsDeleted = false; public bool IsActive = true;
public DateTime CreatedAt; public string? CreatedBy;
public DateTime? UpdatedAt; public string? UpdatedBy;
```
**`GeneralNoticePublic`** — `GeneralNoticePublic.cs`: single property `public string Description { get; set; }`
**`CreateOrUpdateGeneralNotice`** — `CreateOrUpdateGeneralNotice.cs`: `long ProgramId`, `string Description = string.Empty`, `DateTime StartDateTime`, `DateTime EndDateTime`, `bool IsPublished`.

### 1.7 Landing page images

**`LandingPageImage`** — `Services/Admin/ETP.Admin.Domain/Models/Settings/LandingPageImage/LandingPageImage.cs`
```csharp
public long Id; public long? ProgramId;
public string? Title; public string? Question; public string? Description; public string? ActionUrl;
public string ImageUrl; public string? ThumbnailUrl;
public string Type; public int DisplayOrder; public bool IsPublished;
public DateTime? StartDateTime; public DateTime? EndDateTime;
public bool IsDeleted = false; public bool IsActive = true;
public DateTime CreatedAt; public string? CreatedBy;
public DateTime? UpdatedAt; public string? UpdatedBy;
```
**`LandingPageImagePublic`** — `LandingPageImagePublic.cs`: `string? Title, Question, Description, ActionUrl; string ImageUrl; string? ThumbnailUrl; string Type; int DisplayOrder; DateTime? StartDateTime, EndDateTime;`
**`CreateOrUpdateLandingPageImage`** — `CreateOrUpdateLandingPageImage.cs`: same text fields as public model plus `bool IsPublished`, plus `IFormFile? ImageFile`, `IFormFile? ThumbnailFile` (multipart).
**`GalleryPageSegmentImages`** — `GalleryPageSegmentImages.cs`: `string? FirstSegmentTitle; List<IFormFile>? FirstSegmentImageFiles; string? SecondSegmentTitle; List<IFormFile>? SecondSegmentImageFiles;`

### 1.8 Ticket attributes

**`TicketAttributes`**, **`CreateTicketAttributesRequest`**, **`UpdateTicketAttributesRequest`** — all in `Services/Admin/ETP.Admin.Domain/Models/TicketLayoutConfig/TicketAttributes.cs`
```csharp
// TicketAttributes (response)
public long Id; public long ProgramId; public string VenueType = "Stadium";
public bool ShowGallery, ShowBlock, ShowLevelRow, ShowEntryGate, ShowMiniGate,
            ShowVenueName, ShowSegmentDateTime;                    // show/hide flags
public int GalleryPriority, BlockPriority, LevelRowPriority,
           EntryGatePriority, MiniGatePriority;                    // order fields
public bool ShowTicketType, ShowEntryTime, ShowExitTime;           // DITF flags
public int TicketTypePriority, EntryTimePriority, ExitTimePriority;// DITF order
public DateTime CreatedAt; public string? CreatedBy;
public DateTime? UpdatedAt; public string? UpdatedBy;

// CreateTicketAttributesRequest: same show/priority fields, no Id/audit;
// VenueType default "Stadium"; flags default true; priorities default 1..8
// (Gallery=1, Block=2, LevelRow=3, EntryGate=4, MiniGate=5, TicketType=6, EntryTime=7, ExitTime=8)

// UpdateTicketAttributesRequest: every field nullable (bool?/int?/string?)
```

### 1.9 Ticket layout configs

**`TicketLayoutConfig`** — `Services/Admin/ETP.Admin.Domain/Models/TicketLayoutConfig/TicketLayoutConfig.cs`
```csharp
public long Id; public string TicketLayoutName;
public long ProgramId; public long VenueId; public long? VenueGalleryId;
public string? TicketType; public string? DefaultText; public string TicketSize = string.Empty;
public string? PartnerSaleDefaultText;
public string? SingleSegmentUserTicketUrl; public string? MultipleSegmentUserTicketUrl;
public string? SingleSegmentPartnerTicketUrl; public string? MultipleSegmentPartnerTicketUrl;
public string? SingleSegmentComplimentaryTicketUrl; public string? MultipleSegmentComplimentaryTicketUrl;
public string? SingleSegmentUserTicketPreviewUrl; public string? MultipleSegmentUserTicketPreviewUrl;
public string? SingleSegmentPartnerTicketPreviewUrl; public string? MultipleSegmentPartnerTicketPreviewUrl;
public string? SingleSegmentComplimentaryTicketPreviewUrl; public string? MultipleSegmentComplimentaryTicketPreviewUrl;
public string? BackPageTicketUrl;
public bool IsPublished; public bool HasActiveEvents;
public DateTime CreatedAt; public string? CreatedBy;
public DateTime? UpdatedAt; public string? UpdatedBy;
public Program Program { get; set; }
public Venue Venue { get; set; }
public VenueGallery VenueGallery { get; set; }
```
**`TicketLayoutConfigCreated`** and **`TicketLayoutConfigUpdated`** (both in the same file, identical shapes): `long Id`, `string TicketLayoutName`, `string? TicketType`, `string? DefaultText`, `string TicketSize = string.Empty`, `string? PartnerSaleDefaultText`, `long ProgramId`, `long VenueId`, `long? VenueGalleryId`.

Route/response map (`Services/Admin/ETP.Admin.Service/Api/TicketLayoutConfigsController.cs`, route `api/v1/ticket-layout`, interface `ITicketLayoutConfigsManager.cs`):
- `GET ""` (searchText/pageOffset/pageSize) → `IPagedList<TicketLayoutConfig>` (serialized as `{ items, totalCount }`, see §3)
- `GET program/{programId}` → `List<TicketLayoutConfig>`
- `GET venue/{programId}/{venueId}` → `List<TicketLayoutConfig>`
- `GET configs/{programId}/{venueId}/{venueGalleryId}` → `List<TicketLayoutConfig>`
- `GET published/...` → single `TicketLayoutConfig`; `GET back-page/...` → `TicketLayoutConfig`
- `GET {id:long}` → `TicketLayoutConfig`; `POST` (body `TicketLayoutConfigCreated`) / `PUT {id}` (body `TicketLayoutConfigUpdated`) → `Ok(TicketLayoutConfig)` (200, not 201)
- `GET {id:long}/{ticketLayoutType}` → `string`; `GET download-backpage/{eventId}` → `application/pdf` FileResult

### 1.10 Venues / layouts / gates

**`Venue`** — `Services/Admin/ETP.Admin.Domain/Models/Events/Venue.cs`
```csharp
public long Id; public string Type = string.Empty; public string ShortName = string.Empty;
public string Name = string.Empty; public string? Location;
public string SvgMapImage; public int? TotalCapacity; public bool IsAssigned;
public DateTime? UpdatedAt;
public ICollection<VenueGallery> VenueGalleries = new List<VenueGallery>();
```
**`VenueGallery`** — `VenueGallery.cs`
```csharp
public long Id; public long VenueId; public string Name = string.Empty;
public string SeatType = string.Empty; public bool IsSeatMapped; public bool IsSellable;
public bool IsActive; public string SvgKey; public string? TicketColor;
public ICollection<GalleryBlock> GalleryBlocks = new List<GalleryBlock>();
```
**`GalleryBlock`** — `GalleryBlock.cs`
```csharp
public long Id; public long VenueId; public long VenueGalleryId;
public string Name = string.Empty; public bool IsSeatMapped; public bool IsSellable;
public bool IsActive; public string SvgKey;
public ICollection<GalleryBlockEntryGates>? GalleryBlockEntryGates = new List<...>();
public ICollection<BlockLevel> BlockLevels = new List<BlockLevel>();
```
**`BlockLevel`** — `BlockLevel.cs`
```csharp
public long Id; public long VenueId; public long VenueGalleryId; public long GalleryBlockId;
public string Name = string.Empty; public int SeatingCapacity; public bool HasSeats = false;
public string? Seats; public bool IsSeatMapped; public bool IsSellable; public bool IsActive;
public string SvgKey;
public ICollection<BlockLevelEntryGates> BlockLevelEntrieGates = new List<...>(); // note property name typo
public ICollection<BlockLevelMiniGates> BlockLevelMiniGates = new List<...>();
```
**`CreateOrUpdateVenue`** — `CreateOrUpdateVenue.cs`: `long Id`, `VenueType Type` (enum), `string ShortName = ""`, `string Name = ""`, `string? Location`, `IFormFile SvgMapImageFile`, `IList<string>? SvgKeys`.
**`CreateOrUpdateVenueLayout`** — `CreateOrUpdateVenueLayout.cs`: `int VenueId`, `ICollection<VenueGallery> VenueGalleries`.
**Mini-gate models** (same folder):
- `BlockLevelEntryGates.cs` / `BlockLevelMiniGates.cs` (identical): `long Id, VenueId, VenueGalleryId, GalleryBlockId, BlockLevelId; string Name = ""; bool IsActive`
- `GalleryBlockEntryGates.cs`: `long Id; long GalleryBlockId; string Name = ""`
**`CreateOrUpdateBlockLevelEntryGates`** — `CreateOrUpdateBlockLevelEntryGates.cs`: `long? Id; long VenueId, VenueGalleryId, GalleryBlockId, BlockLevelId; string Name = ""; bool IsActive`. (Mini-gate create variant: `CreateOrUpdateBlockLevelMiniGates.cs` in same folder — same shape.)

### 1.11 Ticket checker gates

**`TicketCheckerGateReportData`** — `Services/Admin/ETP.Admin.Domain/Models/TicketChecker/TicketCheckerGateReportData.cs`
```csharp
public long EventId; public string TicketCheckerGateId;
public string EventName = string.Empty; public string TicketCheckerGateName = string.Empty;
public string TicketCheckerName = string.Empty;
public int EntryCount; public int ManualEntryCount; public int DuplicateEntryCount;
```
Same file also defines `TicketCheckerGateNode { TicketCheckerGateData Data; List<TicketCheckerGateNode> Children; }` and `TicketCheckerGateData` (same fields as ReportData plus `bool IsDetailsShow`).

**`CheckedTicketExportData`** — `CheckedTicketExportData.cs`: `string TicketNumber = default!`, `string TicketCheckerGateName = default!`, `string TicketCheckerName = default!`, `int EntryCount`, `string? TicketType`.

**`TicketCheckerGate`** — `TicketCheckerGate.cs`
```csharp
public long Id; public long ProgramId; public long EventId; public long VenueId;
public string EntryGateName; public string EntryGateId; public string GalleryNames;
public DateTime CreatedAt; public string? CreatedBy;
public DateTime? UpdatedAt; public string? UpdatedBy;
public bool IsDeleted = false; public bool IsActive = true;
public List<TicketCheckerGateUser> TicketCheckerGateUsers { get; set; }
```
**`TicketCheckerGateUser`** — `TicketCheckerGateUser.cs`: `long Id; string UserId = ""; string Name = ""; bool IsDownloadEnable;`
**`TicketCheckerGateDetails` — does not exist** anywhere in the repo (grep across the whole backend returns nothing). Gate detail/list endpoints return `TicketCheckerGate` (see `Services/Admin/ETP.Admin.Service/Api/TicketCheckerGateController.cs`).

**`AssignTicketCheckerGate`** — `AssignTicketCheckerGate.cs`
```csharp
public long EventId; public string EntryGateName; public string EntryGateId;
public List<TicketCheckerUser> TicketCheckerUsers;
// TicketCheckerUser (same file): string UserId; string Name; bool IsEnabled;
```

### 1.12 Raffle draw

**`RaffleDraw`** — `Services/Admin/ETP.Admin.Domain/Models/RaffleDraw/RaffleDraw.cs`
```csharp
public string TicketNumber = string.Empty;
public string? TicketType = string.Empty;
public string? UserId = string.Empty;
public string? TicketHolderName;
public string? TicketHolderIdentification;
public long EventLongId;
public string EventPublicId = string.Empty;
public long? BookingOrderId;
public string? BookingOrderPublicId = string.Empty;
public DateTime? BookingOrderDateTime;
public string? OrderNumber;
```

### 1.13 Settings

**`ProgramSettings`** — `Services/Admin/ETP.Admin.Domain/Models/Settings/ProgramSettings.cs`
```csharp
public long Id; public long ProgramId;
public decimal? LimitedAvailabilityThreshold = 0;
public int AllowableMaximumOrderPerUser; public int AllowableMaximumSeatPerOrder;
public decimal TicketSellingStartFromHour; public decimal TicketSellingStopFromHour;
public decimal TicketAvailableFromHour;
public string? TicketNumberPrefix;
public decimal? Vat; public bool IsVatPercentage;
public decimal? ServiceCharge; public bool IsServiceChargePercentage;
public bool? IsVatInclusive;
public PaymentGateway? PaymentGateway;   // enum: DgePay = 1, SSLCommerz = 2
```
(`EventSettings` — `Models/Events/EventSettings.cs`, `sealed class` — identical field set except `long EventId` replaces `ProgramId` position (has both `Id` and `EventId` + `ProgramId`).) PUT `api/v1/program-settings` takes the same `ProgramSettings` class as body (`ProgramSettingsController.cs:57-62`).

**`SystemSettings`** — `SystemSettings.cs`: `long Id; bool AllowUserSignInWithUserPassword; int SeatLockTimeout;`
**`SocialMediaSettings`** — `SocialMediaSettings.cs`: `string? FacebookUrl; string? InstagramUrl; string? LinkedInUrl; string? TwitterUrl;`
**`HeaderFooter`** — `HeaderFooter.cs`: `string? BrandImageUrl; string? PoweredByImageUrl; string? FacebookUrl; string? InstagramUrl; string? LinkedInUrl; string? TwitterUrl; string Title; string? PhoneNumber; string? Email; string? OfficeAddress;`
**`UpdateHeaderFooter`** — `UpdateHeaderFooter.cs`: same but `BrandImageUrl`/`PoweredByImageUrl` are `IFormFile?` (multipart upload).
**`Currency`** — `Currency.cs`: `long Id; string Name; string Code; string Sign; bool IsDefault;`
**`CreateOrUpdateProgramTeam`** — `CreateOrUpdateProgramTeam.cs`: `long Id; long ProgramId; string Name; string ShortName; IFormFile? Logo; bool? IsFlag; bool IsActive; IFormFile? Flag;`

### 1.14 Program venue / sync

**`CreateOrUpdateProgramVenue`** — `Models/Events/CreateOrUpdateProgramVenue.cs`: `long Id; long ProgramId; long VenueId;`
**`CreateOrUpdateProgramVenueDetails`** — `CreateOrUpdateProgramVenueDetails.cs`
```csharp
public long Id;
public bool? IsGalleryActive; public bool? IsSeatMappedInGallery; public bool? IsGallerySellable;
public bool? IsBlockActive;   public bool? IsSeatMappedInBlock;   public bool? IsBlockSellable;
public bool? IsLevelActive;   public bool? IsSeatMappedInLevel;   public bool? IsLevelSellable;
public int? SeatingCapacity; public decimal? PricePerSeat;
public bool? HasSeats; public string? Seats;
```
**Sync-status** — `ProgramVenueDetailsController.cs:131-139`, `GET sync-status/{programId}/{venueId}` returns anonymous object: `{ "needsSync": <bool> }` (`Ok(new { NeedsSync = needsSync })`, camelCase).

### 1.15 Activity log

**`ActivityLog`** (entry model) — `Services/Admin/ETP.Admin.Domain/Models/ActivityLog.cs`
```csharp
public string ServiceName; public string EntityName; public string EntityId; public string Action;
public string? OldValues; public string? NewValues; public string? EntityContext;
public string TransactionId; public DateTime Timestamp;
public string UserId; public string UserName = string.Empty; public string IpAddress;
```
**Batch API models** — `Services/Admin/ETP.Admin.Client/Models/ActivityLogs/`
- `ActivityLogsBatchRequest.cs`: `public required List<ActivityLogsRequest> Requests { get; set; } = new();`
- `ActivityLogsBatchResponse.cs`: `public required string ServiceName; public required string EntityName; public string? EntityId; public PagedList<ActivityLogsResponse> ActivityLogs { get; set; } = new();`
- `ActivityLogsRequest.cs`: `required string ServiceName; required string EntityName; string? EntityId; int PageOffset = 0; int PageSize = 100;`
- `ActivityLogsResponse.cs`: same fields as `ActivityLog` above.

---

## 2. Booking Service DTOs

### 2.1 Dashboard — `Services/Booking/ETP.Booking.Domain/Models/Dashboard/`

**`TicketSalesSummary`** (`TicketSalesSummary.cs`, has 2-arg ctor)
```csharp
public int NumberOfTotalTicketSale { get; set; }
public double AmountOfTotalTicketSale { get; set; }
```
**`DashboardChartData`** (`DashboardChartData.cs`)
```csharp
public List<string> Labels { get; set; } = new List<string>();
public List<Dataset> Datasets { get; set; } = new List<Dataset>();
// nested class Dataset { string Label; List<double> Data = new(); }
```
**`DashboardLabel`** (`DashboardLabel.cs`) — enum: `Sold, Capacity, Available`.
Endpoints (`Services/Booking/ETP.Booking.Service/Api/BookingReportController.cs`): `GetTicketSalesSummaryAsync` → `Ok(TicketSalesSummary)`; upcoming-events/last-week/last-month → `Ok(DashboardChartData)` (manager returns single object even though the attribute says `List<DashboardChartData>`).

### 2.2 Reports

**`BookingMetrics`** — `Services/Booking/ETP.Booking.Domain/Models/Report/BookingMetrics.cs`
```csharp
public int TotalCapacity; public int TotalOnlineGeneratedTicket; public int TotalSoldTickets;
public int TotalReservedTickets; public int AvailableTickets;
public int TotalOrders; public int TotalPaidOrders; public double TotalPaidOrdersInPercentage;
public int TotalRequestedOrders; public double TotalRequestedOrdersInPercentage;
public int TotalGeneratedOrders; public double TotalGeneratedOrdersInPercentage;
public int TotalCancelledOrders; public double TotalCancelledOrderInPercentage;  // note: "Order" singular
public int TotalSuccessfulOrders; public double TotalSuccessfulOrdersInPercentage;
```
**`RevenueReport`** — `Report/RevenueReport.cs`
```csharp
public string EventName; public string EventDateTime; public string? Date;
public int TicketsSold; public double TicketRevenueWithoutVatCharge;
public double Vat; public double ServiceCharge; public double TotalRevenue;
```
**Additional report response models** (returned by `ReportController` via `IBookingReportManager`, but living under `ETP.Booking.Storage/Models/Report/`):
- `EventRevenueSummary.cs`: `string EventName = default!; int TotalCapacity; int OnlineCapacity; double OnlineCapacityPercentage; int OnlineSold; double OnlineSoldPercentage; int RemainingOnlineSeats; double OnlineRevenue; double VAT;`
- `EventSalesSummary.cs`: same minus `OnlineRevenue`/`VAT`.
- `EventSalesDetailsReportData.cs`: `string EventName; DateTime StartDateTime; DateTime? EndDateTime; string Gallery; int TotalCapacity; int OnlineCapacity; decimal OnlineCapacityPercentage; int OnlineSold; decimal OnlineSoldPercentage; int RemainingOnlineSeats; int TotalReserved; decimal ReservedPercentage; int FOC; decimal FOCPercentage; int PartnerSale; decimal PartnerSalePercentage; int PartnerSalePrint; decimal PartnerSalePrintPercentage; int PartnerSaleInHand; decimal PartnerSaleInHandPercentage;`
- `EventSalesRevenueDetailsReportData.cs`: identical field names but all percentages/revenue are `double` (plus `OnlineRevenue`, `VAT`).

### 2.3 Reservations / capacity

**`ReservationSummary`** — `Services/Booking/ETP.Booking.Domain/Models/ReservationSummary.cs`
```csharp
public long Id; public Guid PublicId; public required string Ref;
public long EventId; public long GalleryId; public long BlockId; public long LevelId; public long ProgramId;
public ReservationStatus? Status; public ReservationType? Type; public ReservationCategory? ReservationCategory;
public MergeStatus MergeStatus = MergeStatus.None; public ZipStatus ZipStatus = ZipStatus.None;
public int TicketGeneratedCount; public string? GeneratedSeats;
public int TicketRequestedCount; public string? RequestedSeats;
public int Reserved; public int? RemainingReserved; public string? ReservedSeats;
public int Released; public string? ReleasedSeats;
public string? BlankTicketPreviewUrl;
```
**`ReservationCount`** — `ReservationCount.cs`: `long Id; Guid PublicId; long EventId, GalleryId, BlockId, LevelId, ProgramId; ReservationStatus? Status; int TicketCount;`
**`EventCapacityAdjustment`** — `EventCapacityAdjustment.cs`
```csharp
public long Id; public long EventId; public long GalleryId; public long BlockId; public long LevelId;
public int TicketingCapacity; public bool HasSeats; public string? Seats; public string? AvailableSeats;
public Action Action;                 // enum: Allocate, Deallocate
public long? CaId; public Guid? PublicId; public long? ProgramId; public string? AdjustmentNumber;
```
Booking enums (`Services/Booking/ETP.Booking.Domain/Models/Enum.cs`): `Status { Pending, Failed, Paid, Cancelled, Requested, Generated }`, `ReservationStatus { Draft, Generated, Requested, Closed, Locked, Merging, Merged }`, `ReservationType { Complimentary, Partner }`, `ReservationCategory { DigitalPrint, Printing, ReservedOnly }`, `MergeStatus { None, Requested, Merging, Merged, Failed }`, `ZipStatus { None, Requested, Zipping, Zipped, Failed }`, `Action { Allocate, Deallocate }`, `SortOrder { Ascending, Descending }`, `SearchType { OrderNumber, TransactionId, TicketNumber, PhoneNo }`.

### 2.4 Promo code / bookings

**`ApplyPromoCodeRequest`** — `ApplyPromoCodeRequest.cs`: `required string PromoCode; long ProgramId; Guid EventId; long GalleryId;`
**`ApplyPromoCodeResponse`** — `ApplyPromoCodeResponse.cs`
```csharp
public bool IsSuccess { get; set; }
public string? DiscountType { get; set; }
public double DiscountValue { get; set; }
public string? DiscountAppliedTo { get; set; }
```

**`UserBooking`** (both list item and GET-by-id payload) — `Services/Booking/ETP.Booking.Domain/Models/UserBooking.cs`
```csharp
public long Id; public CognitoUser User;   // Core/ETP.Core/ServiceClient/ServerlessClient/CognitoUser.cs:
                                           // string UserId, Name, Phone, Email, VerificationType, VerificationId
public Guid PublicId; public long ProgramId;
public Guid EventId; public long EventLongId;
public long GalleryId; public long BlockId; public long LevelId;
public string? UserId; public string OrderNumber;
public int NumberOfSeats; public bool HasSeats; public string? Seats;
public double PricePerSeat; public string? PromoCode; public double PromoDiscount;
public double TotalCharge; public double Vat; public double VatIncludedBasePricePerSeat;
public double PlatformCharge; public bool IsVatInclusive; public double Discount;
public Status Status;                       // enum
public string? PaymentInfo; public string? PaymentTransactionId;
public DateTime CreatedAt;
public string EventName; public DateTime EventStartDateTime; public DateTime EventEndDateTime;
public DateTime CancelledAt; public DateTime CallbackReceivedAt; public DateTime TicketAvaiableFrom;  // typo "Avaiable"
public string? VatInvoiceId; public string? VatInvoiceInfo; public string? VatInvoiceDownloadUrl;
public string? SmartChallanNumber;
public string? OneIdUserId; public bool OneIdSync;
```
GET `user-booking-order/{id}` — `UserBookingOrderController.cs:312-318` calls `GetByPublicId(Guid)` which returns `Task<UserBooking?>` (`IUserBookingOrderManager.cs:16`) → plain `Ok(entity)` with the full `UserBooking`. Same DTO for `GET list` and `GET admin/list/{eventId}` (both `Task<IPagedList<UserBooking>>`). Other related DTOs in the same folder: `UserBookingOrder` (create request; note lowercase property `bookedUserDetails`) and `UserBookingOrderResponse` (`Guid PublicId; string? CheckoutUrl;`).

**`UpdateBookingStatusRequest`** — `UpdateBookingStatusRequest.cs`: `int? Limit; DateTime CutoffTime;`
Handler behavior (`UserBookingOrderController.cs:397-417`, PUT `update-status`, no auth/`don't expose to gateway`): fires two parallel background `Task.Run` scopes — `CancelBookingAsync(request.CutoffTime, ct)` and `RevaildateRecentPendingBookingsAsync(request.CutoffTime, ct)` (note typo "Revaildate") — awaits both, then returns `Ok(true)` → body `true`. `Limit` is not used by the controller.

**`BookedUserRecord`** — `Services/Booking/ETP.Booking.Storage/Models/BookedUserRecord.cs` (entity, `Entity<long>, IAuditEntity`)
```csharp
public long ProgramId; public Guid EventId; public long? EventLongId;
public long UserBookingOrderId;
public string? OrderNumber; public double PricePerSeat;
public string? UserName; public string? PhoneNumber;
public DateTime CreatedAt;
[JsonIgnore] public string? CreatedBy; [JsonIgnore] public DateTime? UpdatedAt;
public string? UpdatedBy;
[JsonIgnore] public bool IsDeleted; [JsonIgnore] public bool IsActive = true;
```
(Exposed via `GET user-booking-order/booked-user-record/{bookingOrderId}`.)

---

## 3. Error envelope + pagination

### 3.1 `ErrorResponseExceptionFilter` — `Core/ETP.Core.Web/Filters/ErrorResponseExceptionFilter.cs`
Registered globally in both services: `Services/Admin/ETP.Admin.Service/Program.cs:50-54` and `Services/Booking/ETP.Booking.Service/Program.cs:66` (`opts.Filters.Add<ErrorResponseExceptionFilter>()`). Emits a serialized `Microsoft.AspNetCore.Mvc.ProblemDetails` via `JsonResult`. Mapping (there is no class named `ErrorResponseException` — the carrier class is `ApiException`):

| Exception type | HTTP status | Body |
|---|---|---|
| `ArgumentException` | 400 | `{ status: 400, title: <exception.Message> }` |
| `ApiException` (`Core/ETP.Core/ApiException.cs`) | **always 400** (response code forced to BadRequest regardless of `Details.Status`) | body = `exception.Details` (a `ProblemDetails`; ctor `ApiException(int errorCode, string message)` puts the code inside `Details.Status` — but the HTTP status is still 400) |
| `UnauthorizedAccessException` | 403 | `{ status: 403, title: "Unauthorized access", detail: <exception.Message> }` |
| anything else (incl. `BadHttpRequestException`, `EntityNotFoundException`, `BookingConflictException`) | 500 | `{ status: 500, title: <exception.Message in Development, else "An unexpected error occurred."> }` |

In Development a `StackTrace` property is added to the `ProblemDetails`. JSON property names follow standard ProblemDetails camelCase: `type`, `title`, `status`, `detail`, `instance` (only non-null members are written; Booking additionally drops nulls globally). A last-resort middleware `Core/ETP.Core.Web/Middleware/ExceptionMiddlewareExtensions.cs` also returns 500 `{ status: 500, title: "An unexpected error occurred." }` for anything that escapes.

Exception classes found in Core: `Core/ETP.Core/ApiException.cs` (`Details` ProblemDetails + 3 ctors), `Core/ETP.Core/Domain/Entities/EntityNotFoundException.cs` (`EntityType`, `Id`, message `$"There is no such an entity. Entity type: {type}, id: {id}"`), `Core/ETP.Core/Exceptions/BookingConflictException.cs` and `BookingFailedException.cs` (plain `Exception` wrappers, default message `"Booking conflict occured"` — typo, and note `BookingFailedException` also says "conflict"), plus `DbConcurrencyException`, `StorageException`, `EmailException`.

### 3.2 `PagedOkResult` — `Core/ETP.Core.Web/Results/PagedOkResult.cs`
- Body = **bare JSON array** of `content.Items.ToArray()`.
- Adds response header **`X-Total-Count`** with `TotalCount`.
- **Important caveat:** grep shows **no controller actually uses `PagedOk`/`PagedOkResult`** (zero usages under `Services/`). Controllers return plain `Ok(IPagedList<T>)`, which serializes as an object: `Core/ETP.Core/Collections/PagedList.cs` → `{ "items": [ ... ], "totalCount": <int> }` (camelCase; no `X-Total-Count` header).

### 3.3 Representative thrown business exceptions (exact class + message + resulting code)

| Where | Throw | HTTP result |
|---|---|---|
| `Services/Admin/ETP.Admin.Domain/Managers/TicketLayoutConfigsManager.cs:85` | `ArgumentException($"Ticket Layout Config with ID {id} not found.")` | 400 |
| `Services/Admin/ETP.Admin.Domain/Managers/...` (7x) | `ArgumentException($"Entity is missing with id '{id}'")` | 400 |
| `Services/Booking/ETP.Booking.Domain/Managers/UserBookingOrderManager.cs:613,616` | `ArgumentException("unauthorized_access")` | 400 (despite the name) |
| `Services/Booking/ETP.Booking.Domain/Managers/UserBookingOrderManager.cs:631` | `ArgumentException("seat_limit_exceeded")` | 400 |
| `Services/Booking/ETP.Booking.Domain/Managers/CapacityManager.cs:134` / `SeatReservationManager.cs:262` | `ArgumentException("no_seats_available")` | 400 |
| `Services/Booking/ETP.Booking.Domain/Managers/UserBookingOrderManager.cs:1138,1144` | `ArgumentException("Invalid promo code. Please enter a valid code.")` | 400 |
| `Services/Booking/ETP.Booking.Domain/Managers/...` (NBR client, 2x) | `UnauthorizedAccessException("NBR authentication token expired")` | 403 |
| `Services/Admin/ETP.Admin.Domain/Managers/...` (many, e.g. `"Name must not exceed 60 characters."`) | `BadHttpRequestException(...)` | **500** per filter (not 400 — `BadHttpRequestException` is not `ArgumentException`; falls into the default branch) |

(`ApiException` is never thrown inside `Services/` — only defined in Core; `BookingConflictException`/`BookingFailedException` are also never thrown in Admin/Booking managers.)

---

## 4. `[ProducesResponseType]` success-code reality check

- **True 201:** `UserBookingOrderController.CreateUserBookingOrderAsync` (`Services/Booking/ETP.Booking.Service/Api/UserBookingOrderController.cs:47-53`) declares `typeof(UserBookingOrderResponse), Created` and actually returns `StatusCode(StatusCodes.Status201Created, result)`.
- **Declared 201 but actually returns 200 `Ok`:** `PromoCodeController.cs:92,98` (POST promo code declares `PromoCode/Created` but `return Ok(result)`); `DiscountController.cs:75`; `EventCapacityAdjustmentController.cs:29,35`; `TicketLayoutConfigsController.CreateAsync` declares only 404/500 and returns `Ok` (200) for creates/updates/deletes/publish.
- **Typical listing/get pattern:** `[ProducesResponseType(typeof(void), 404)] + [ProducesResponseType(typeof(ProblemDetails), 500)]` and implicit 200 — e.g. `AdminUsersController`, `DashboardController` (Admin), `TicketCheckerGateController` (all `Ok(...)`), `BookingReportController` declares explicit `typeof(TicketSalesSummary), OK` / `typeof(List<DashboardChartData>), OK`, `ReportController` uses `typeof(Object), OK` for all report endpoints.

---

## Could not verify
- Exact JSON casing of the `X-Total-Count`/paged body at runtime (inferred from code + MVC defaults; `PagedOkResult` itself is dead code).
- Whether `ProblemDetails.StackTrace` actually serializes (it is set only in Development; depends on the .NET 8 `ProblemDetails` contract).
- Swagger/example generation behavior (Swagger examples are registered in Admin `Program.cs` but not inspected).
- `Program` / `Event` nested response shapes referenced by `PromoCodeAssign`/`DiscountAssign`/`TicketLayoutConfig` (`Models/Events/Program.cs`, `Event.cs`) — not requested, not fully read.
- `TicketCheckerGateController` manager return types beyond what the DTO files imply (response types not annotated with `typeof(...)` on most actions).