# P-08 · টিকিট তৈরির অনুরোধ

> **Bangla name:** টিকিট জেনারেশন অনুরোধ
>
> [← 20 · ইউজার পোর্টাল](README.md) · [সূচিপত্র](../README.md) · [ওপেন কোয়ারি](../99-open-queries.md)

## 1. নাম ও উদ্দেশ্য

**টিকিট তৈরির অনুরোধ।** পেমেন্টের পর গ্রাহকের কাছে একটি `Paid` অর্ডার ও *খসখসে* (draft) টিকিট সারি থাকে। ইভেন্টের **টিকিটের প্রাপ্যতার তারিখ** এলে গ্রাহক **Request tickets** চাপেন; এরপর প্ল্যাটফর্ম প্রতিটি টিকিটের জন্য ফাঁকা PDF ছাপে, সেগুলোর প্রতিটিকে TSP-এর মাধ্যমে QR কোডসহ ডিজিটালি সই করে, এবং অর্ডারটি `Requested` ও পরে `Generated` হয়। গ্রাহক পেজে অপেক্ষা করেন (এটি প্রতি ৩০ সেকেন্ডে আবার যাচাই করে) যেতে যেতে সাইন করা PDF ডাউনলোড করা যায় ([P-09](P-09-ticket-details-downloads.md))।

## 2. ট্রিগার ও অ্যাক্টর

সাইন-ইন করা গ্রাহক `/{lang}/tickets/ticket-details/{publicId}`-এ (`TicketPreviewComponent`), কেবল তখনই যখন অর্ডারটি `Paid` এবং ইভেন্টের `ticketAvailabilityStartDateTime` পেরিয়েছে (হোল্ডারের নাম ও ফোন আগেই পূরণ করা থাকে, [P-09](P-09-ticket-details-downloads.md))।

## 3. ব্যবসায়িক প্রবাহ

1. প্রাপ্যতার তারিখের আগে বোতামটি নিষ্ক্রিয়। প্রাপ্যতার তারিখ থেকে **Request tickets** একটি নিশ্চিতকরণের পপ-আপ খোলে ("তৈরি হওয়ার পর টিকিটের তথ্য আর বদলানো যাবে না"; পপ-আপের লেখা ইংরেজিতে হার্ড-কোড করা, অনূদিত নয়)।
2. নিশ্চিত করার পর অর্ডারের স্ট্যাটাস `Requested` হয়; একটি পপ-আপ জানায় তৈরি চলছে; পেজটি "চলছে" অবস্থা দেখায় এবং প্রতি ৩০ সেকেন্ডে আবার যাচাই করে।
3. সব টিকিট সই হলে অর্ডার `Generated` হয় ([S-06](../50-system-initiated/S-06-booking-status-generated.md)); পেজটি টিকিট রিলোড করে এবং **Download**, **Share** এবং একাধিক টিকিট হলে **Download all** বোতামগুলো দেখায়।

## 4. কারিগরি প্রবাহ

1. খসখসে টিকিট থাকে কারণ বিস্তারিতের কল সেগুলো চাহিয়া তৈরি করে: `GetTicketsInfo` কোনো সারি নেই এমন একটি `Paid` অর্ডারের সারি তৈরি করে (Redis লক `create_user_ticket_{publicId}`-এর নিচে, `InitiateBulkTicketForNewlyPaidOrder`), এর সাথে পেমেন্ট callback ও ওয়ার্কার ছাড়াও ([S-07](../50-system-initiated/S-07-initiate-user-ticket-generation.md))।
2. **[HTTP, no token → Ticketing]** পোর্টাল পাঠায় `PATCH {services.tickets}/ticketing/api/v1/booking-order-ticket/generate-request/{publicId}` ফাঁকা শরীরে (`BookingApiService.requestTicketsById`)। কন্ট্রোলার অ্যাকশনে **কোনো `[Authorize]` নেই** এবং ম্যানেজারও কলার যাচাই করে না; তবু পোর্টালের টোকন ইন্টারসেপ্টর ইউজার টোকেন যুক্ত করে কারণ URL-এ `/ticketing` আছে।
3. `TicketManager.TicketGenerateRequest`:
   1. Booking থেকে অর্ডার পড়ে (**[HTTP, no token]** `GET .../user-booking-order/public-id/{id}`);
   2. `ValidateTicketGeneration`: স্ট্যাটাস `Requested` বা `Generated` → `Request to generate ticket is already taken.`; `Paid` নয় → `Only paid order requests can generate tickets`; ইভেন্টের `TicketAvailabilityStartDateTime` এখনের (UTC) চেয়ে পরে → `You can request after ticket availability date.`;
   3. লেভেলের তথ্য এবং প্রোগ্রাম, ভেন্যু ও গ্যালারির **প্রকাশিত টিকিট লেআউট** লোড করে ([A-13](../10-admin-portal/A-13-ticket-layouts.md));
   4. প্রতিটি টিকিটের জন্য ফাঁকা PDF আঁকে (`GetBlankPdf`) এবং টিকিট বাকেটে `{BlankBase}/user/{userId}/{orderId}/{ticketNumber}.pdf` পাথে আপলোড করে ([X-20](../60-cross-cutting/X-20-file-storage.md)); টিকিটের স্ট্যাটাস `Requested` ও লেআউটের ব্যাক-পেজ URL বসায়; সেভ করে;
   5. প্রতিটি টিকিটের জন্য প্রকাশ করে **[SQS: TicketSigning]** একটি `SignedTicketGeneration` বার্তা (`UnsignedTicketUrl`, লেআউটের সাইজ অনুযায়ী `QRPosition`, `GateId` = লেভেলের এন্ট্রি গেট, `Data` = নাম, ফোন, তারিখ ও সময় (UTC+6), টিকিট আইডি, ইভেন্ট আইডি, গ্যালারি, ব্লক, লেভেল, এন্ট্রি গেট, মিনি গেট, আসন); সই করার ওয়ার্কার [S-08](../50-system-initiated/S-08-ticket-signing.md);
   6. **[HTTP, no token → Booking]** `PATCH .../user-booking-order/generate-ticket-request/{publicId}` অর্ডারের স্ট্যাটাস `Requested` বসায়, এবং তার টিকিটসহ অর্ডারটি ফেরত দেয়।
4. ব্রাউজার রেসপন্স থেকে টিকিট ও অর্ডারের স্ট্যাটাস হালনাগাদ করে এবং "তৈরি" পপ-আপ খোলে। এরপর থেকে `ngOnInit`-এর টাইমার (প্রতি ৩০ সে) স্ট্যাটাস `Requested` থাকা অবস্থায় **[HTTP + user token]** `GET /booking/api/v1/user-booking-order/check-generated-status?id=` কল করে; `true` ফেরত এলে পোর্টাল টিকিটগুলো রিলোড করে (`details`)।
5. ব্যাকগ্রাউন্ড: [S-08](../50-system-initiated/S-08-ticket-signing.md) প্রতিটি টিকিট সই করে ও সংরক্ষণ করে (`SignedTicketUrl`); [S-06](../50-system-initiated/S-06-booking-status-generated.md) সব টিকিট সই হলে অর্ডার `Generated` চিহ্নিত করে; [S-12](../50-system-initiated/S-12-ticket-generated-notification.md) পুশ বার্তা পাঠায়।

## 5. কম্পোনেন্ট

| ধরন | কম্পোনেন্ট |
|---|---|
| ক্লায়েন্ট | `tickets/components/{ticket-preview,request-tickets-modal,ticket-generation-modal,in-progress-ticket-modal}`, `booking-api.service.ts:50-54, 93-98` |
| সার্ভিস | Ticketing (`BookingOrderTicketController.GenerateTicketRequest`, `TicketManager`); Booking (`generate-ticket-request`, `check-generated-status`); Event (ইভেন্ট, লেআউট, লেভেলের তথ্য) |
| কিউ / ওয়ার্কার | SQS `TicketSigning` → [S-08](../50-system-initiated/S-08-ticket-signing.md); [S-06](../50-system-initiated/S-06-booking-status-generated.md) |
| টেবিল | `Tickets`, `TicketLayoutConfigs`, `UserBookingOrders` |
| স্টোরেজ | টিকিট বাকেট `{BlankBase}/user/...` (ফাঁকা), `{SignedBase}` (সই করা) |
| বাহ্যিক | TSP (ওয়ার্কারের মাধ্যমে) |

## 6. API কন্ট্রাক্ট

| মেথড | পথ | অথ | রিকোয়েস্ট | রেসপন্স | প্রধান এরর |
|---|---|---|---|---|---|
| PATCH | `/ticketing/api/v1/booking-order-ticket/generate-request/{publicId}` | **none** | path | `UserBookingResponse` (অর্ডার ও টিকিট) | §4 ধাপ 3-এর 400 বার্তাগুলো |
| GET | `/booking/api/v1/user-booking-order/check-generated-status` | User | `id` (order public id) | `true`/`false` | 400 `Booking not found.`, `Privacy error.` |
| PATCH | `/booking/api/v1/user-booking-order/generate-ticket-request/{publicId}` | **none** (internal) | path | `UserBooking` | `Order not found` |

প্রধান নমুনা, `PATCH /ticketing/api/v1/booking-order-ticket/generate-request/{publicId}`-এর রেসপন্স (সংক্ষিপ্ত; মানগুলো কাল্পনিক):

```json
{ "publicId": "5b1f7a64-6c1e-4c0a-8f6e-0f3d2f9a7b10", "status": "Requested", "numberOfSeats": 2,
  "tickets": [ { "id": 301, "ticketNumber": "BDI7K2M9Q-1", "status": "Requested", "seat": "A1",
                 "ticketHolderName": "Nadia Rahman", "ticketHolderIdentification": "01711111111" } ] }
```

## 7. ডেটা ও পার্শ্বপ্রতিক্রিয়া

টিকিট বাকেটে ফাঁকা PDF, টিকিট ও অর্ডারের স্ট্যাটাস পরিবর্তন, প্রতি টিকিটে একটি SQS বার্তা, পরে সই করা PDF ও একটি পুশ নোটিফিকেশন।

## 8. কোড রেফারেন্স

| কী | কোথায় |
|---|---|
| পোর্টাল | `rvl-gobcb-user-portal/ETP-Web/src/app/modules/featured/tickets/components/ticket-preview/ticket-preview.component.ts:55-100, 204-250` |
| কন্ট্রোলার | `rvl-gobcb-backend/Services/Ticketing/ETP.Ticketing.Service/Api/BookingOrderTicketController.cs:112-119` |
| ম্যানেজার | `rvl-gobcb-backend/Services/Ticketing/ETP.Ticketing.Domain/Managers/TicketManager.cs:146-208, 261-356, 358-372` |
| বুকিং দিক | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/UserBookingOrderController.cs:363-371`; `.../UserBookingOrderManager.cs:903-919, 1019-1042` |

## 9. হ্যান্ডওভার নোট

1. **যে কেউ public id জানে যেকোনো অর্ডারের জন্য তৈরি চালু করতে পারে:** Ticketing অ্যাকশন ও Booking-এর `generate-ticket-request` অ্যাকশন দুটোই anonymous ([X-18](../60-cross-cutting/X-18-endpoints-without-auth.md), [S-07](../50-system-initiated/S-07-initiate-user-ticket-generation.md) নোট 4)। প্রাপ্যতার তারিখ ও `Paid` যাচাই তবুও প্রযোজ্য।
2. **লেখার ক্রম atomic নয়।** টিকিট `Requested` চিহ্নিত ও বার্তা প্রকাশ করা হয় আগে, এরপর Booking অর্ডারটি `Requested` হয়; Booking কল ব্যর্থ হলে টিকিট ইতিমধ্যে সই হচ্ছে অথচ অর্ডার এখনো `Paid` দেখায়, আর বোতামটি আবার চাপলে প্রত্যাখ্যান হয় (`ValidateTicketGeneration` অর্ডারটি দেখে, যা এখনো `Paid`, তাই দ্বিতীয় অনুরোধ আবার ছাপে ও আবার প্রকাশ করে) `[UNCONFIRMED: Q-40]`।
3. **হোল্ডারের ডেটা অনুরোধের সময়ই ফ্রিজ হয়।** QR পেলোডে থাকে অনুরোধের সময় সংরক্ষিত নাম ও ফোন; এরপর সম্পাদনা প্রত্যাখ্যাত হয় কারণ অর্ডার আর `Paid` নয় ([P-09](P-09-ticket-details-downloads.md))।
4. **প্রাপ্যতার সময় দুটো ঘড়ি ব্যবহার করে।** বোতামটি ব্রাউজারের ঘড়ি দিয়ে চালু হয় (`Date.now()` বনাম `ticketAvailabilityStartDateTime`, প্রতি ৩০ সে রিফ্রেশ হয়) অথচ সার্ভার UTC "এখন" দিয়ে তুলনা করে; ভুল ডিভাইস ঘড়ি বোতামটি তাড়াতাড়ি দেখাতে পারে (সার্ভার প্রত্যাখ্যান করে) বা দেরি করে।
5. **অনুরোধের সময় TSP-এর সবচেয়ে ব্যস্ত মুহূর্ত।** প্রাপ্যতার তারিখ এলে অনেক গ্রাহক একসাথে বোতাম চাপেন; কাজটি `TicketSigning`-এ সারিবদ্ধ হয় এবং ওয়ার্কার সই করে ([S-08](../50-system-initiated/S-08-ticket-signing.md)); গ্রাহক কেবল অপেক্ষা করে ও পোল করে।
6. **অপেক্ষার অবস্থায় কোনো টাইমআউট নেই।** সই করা আটকে গেলে অর্ডার `Requested` থাকে এবং পেজটি চিরকাল পোল করে; সাপোর্ট ইস্যু তালিকা বা reconciliation-এ ([A-23](../10-admin-portal/A-23-reconciliation.md)) তা খুঁজে পায় `[UNCONFIRMED: Q-12]`।
7. **লেআউট অনুরোধের সময়ই পড়া হয়।** পরে প্রকাশিত লেআউট ইতিমধ্যে অনুরোধ করা টিকিটগুলোকে প্রভাবিত করে না ([A-13](../10-admin-portal/A-13-ticket-layouts.md))।

## 10. কম্পোনেন্ট সম্পর্ক

```mermaid
sequenceDiagram
  participant U as User portal
  participant T as Ticketing API
  participant B as Booking API
  participant S3 as S3 ticket bucket
  participant Q as SQS TicketSigning
  participant W as Signing worker (S-08)
  U->>T: PATCH generate-request/{publicId} (no server auth)
  T->>B: GET public-id/{id} (HTTP, no token)
  T->>S3: blank PDF per ticket
  T->>Q: SignedTicketGeneration per ticket
  T->>B: PATCH generate-ticket-request (status Requested)
  T-->>U: order + tickets (Requested)
  W->>S3: signed PDF; ticket Generated
  U->>B: GET check-generated-status every 30 s (HTTP + user token)
```

**নির্ভর করে:** [P-06](P-06-booking-payment.md), [P-09](P-09-ticket-details-downloads.md) (হোল্ডারের ডেটা), [A-13](../10-admin-portal/A-13-ticket-layouts.md), [A-07](../10-admin-portal/A-07-events.md) (প্রাপ্যতার তারিখ)। **প্রভাব ফেলে:** [S-06](../50-system-initiated/S-06-booking-status-generated.md), [S-08](../50-system-initiated/S-08-ticket-signing.md), [S-12](../50-system-initiated/S-12-ticket-generated-notification.md), [P-09](P-09-ticket-details-downloads.md)।

## 11. ডেভেলপার টেস্ট গাইড

**লোকাল টেস্টযোগ্যতা: আংশিক।** সই করার জন্য TSP সার্টিফিকেট লাগে, যা লোকালে ডামি, তাই টিকিট `Requested` হয় কিন্তু সই হয় না।

| আইটেম | বিবরণ |
|---|---|
| টেস্ট ডেটা ও অ্যাকাউন্ট | ইউজার `+8801700000011`; একটি সিড করা `Paid` অর্ডার যার ইভেন্টের টিকিট প্রাপ্যতার তারিখ পেরিয়েছে |
| ব্রাউজার | `http://localhost:4201/en/tickets` থেকে অর্ডার খুলুন → **View details** → **Request tickets**; Network: `generate-request` (200), তারপর প্রতি ৩০ সে `check-generated-status` |
| এমুলেটর | — ([U-06](../30-user-app/U-06-my-bookings-tickets.md)) |
| Postman | `postman/services/etp-ticketing.postman_collection.json`: "PATCH /api/v1/booking-order-ticket/generate-request/{publicId}"; `etp-booking`: "GET /api/v1/user-booking-order/check-generated-status" |
| Visual Studio debug | `TicketManager.TicketGenerateRequest`, `ValidateTicketGeneration` (Ticketing সার্ভিস); ওয়ার্কার: `TicketSigning` কনজিউমার ([S-08](../50-system-initiated/S-08-ticket-signing.md)) |
| যাচাই | SQL: `select "TicketNumber","Status","BlankTicketUrl","SignedTicketUrl" from etp."Tickets" where "BookingOrderPublicId"=...`; Floci SQS `TicketSigning` কিউয়ের গভীরতা; Floci S3-এ টিকিট বাকেটের `ls` |
