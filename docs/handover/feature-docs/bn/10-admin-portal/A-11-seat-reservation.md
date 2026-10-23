# A-11 · সিট রিজার্ভেশন (কমপ্লিমেন্টারি / পার্টনার)

> **Bangla name:** সিট রিজার্ভেশন (কমপ্লিমেন্টারি / পার্টনার)
>
> [← 10 · অ্যাডমিন পোর্টাল](README.md) · [সূচিপত্র](../README.md) · [ওপেন কোয়ারি](../99-open-queries.md)

## 1. নাম ও উদ্দেশ্য

**সিট রিজার্ভেশন।** অ্যাডমিন কোনো level-এর কিছু আসন পাশে রেখে দেন যাতে সেগুলো অনলাইনে বিক্রি না হয় — **complimentary** টিকিটের (বিনামূল্যে দেওয়া) জন্য বা **partner** টিকিটের (পার্টনারকে দেওয়া বা অফলাইনে বিক্রি) জন্য। একটি রিজার্ভেশন level-এর অনলাইন ক্যাপাসিটি কমিয়ে দেয়, এর একটি নম্বর থাকে, এবং পরে সেখান থেকে টিকিট তৈরি হয় ([A-12](A-12-reserved-tickets.md)); আসন **release** করলে সেগুলো অনলাইন বিক্রিতে ফিরে যায় বা কীভাবে ব্যবহৃত হয়েছে তা চিহ্নিত হয়। ধারণাগুলো: [Redis live capacity](../00-platform-primer.md#explainer-redis-live-capacity), [distributed locks](../00-platform-primer.md#explainer-distributed-locks), [queue-driven processing](../00-platform-primer.md#explainer-queue-driven)।

## 2. ট্রিগার ও অ্যাক্টর

ইভেন্টের **Gallery Update** ট্যাবে (`/events/event-details/:id`, "Remaining Reserved" ও "Released" কলাম) এবং **Generate Tickets** মেনুতে (`/events/event-ticket`, `/events/generate-ticket/:id`) থাকা কর্মী। সার্ভারে কেবল `summary/{eventId}` ও `event/{eventId}`-এর জন্য `admin` policy প্রয়োজন; `POST /seat-reservation`-এর নিজে কোনো `[Authorize]` নেই ([X-18](../60-cross-cutting/X-18-endpoints-without-auth.md))।

## 3. ব্যবসায়িক প্রবাহ

1. **রিজার্ভ:** level বাছুন, ধরন (`Complimentary` বা `Partner`), ক্যাটাগরি (`DigitalPrint`, `Printing`, `ReservedOnly`), আসনের সংখ্যা (অথবা আসন থাকা level-এর নির্দিষ্ট আসন, অথবা level-এর একটি শতকরা)।
2. রিজার্ভেশনের একটি **রিজার্ভেশন নম্বর** ও `Draft` স্ট্যাটাস হয়; এটি "Remaining Reserved"-এ দেখা যায়।
3. **Release:** একটি রিজার্ভেশন থেকে একটি release ক্যাটাগরি দিয়ে কিছু বা সব আসন ছেড়ে দিন: `DigitalPrint`, `Printing`, `ReservedOnly` (আসনগুলো টিকিটের জন্য ব্যবহৃত হয়েছে) বা `ToOnline` (আসনগুলো অনলাইন বিক্রিতে ফেরত যায়)।
4. একটি রিজার্ভেশনের সব আসন release হলে প্যারেন্ট রিজার্ভেশন `Closed` হয়ে যায়।

## 4. প্রযুক্তিগত প্রবাহ

1. **[HTTP + user token]** তালিকা `GET /booking/api/v1/seat-reservation/by-event-level?eventId&levelId&actionType&programId`; Generate Tickets পেজের সারসংক্ষেপ `GET /booking/api/v1/seat-reservation/summary/{eventId}?levelId&programId` (admin policy); সংখ্যা `GET .../count/{eventId}`, `GET .../remainingReserveCount/{eventId}`, `GET .../reservations-count?eventId&levelId`।
2. **[HTTP + user token]** সেভ `SeatReservation` সহ `POST /booking/api/v1/seat-reservation`। `SeatReservationManager.CreateAsync`:
   - যাচাই: id 0-এর বেশি, `NumberOfSeats > 0`, release-এর জন্য প্যারেন্ট `ReservationId` আবশ্যক, gallery, block ও level সক্রিয় হতে হবে (`gallery_or_block_or_level_inactive`), এবং release-এর জন্য প্যারেন্ট থাকতে হবে ("Selected Reservation is not found."), release করা পরিমাণ reserved পরিমাণের কম হতে হবে ("Released Number of seats must be less than reserved seats."), এবং প্যারেন্ট `Locked` হওয়া চলবে না ("Can't release right now. Reservation is in ticket process.");
   - লক নেয় `level_booking_{event}_{gallery}_{block}_{level}` (মেয়াদ ৩০ সে, অপেক্ষা ১৫ সে) ([X-25](../60-cross-cutting/X-25-redis.md));
   - একটি **release**, বা একটি **নতুন রিজার্ভেশন** (প্যারেন্ট নেই) হলে `CapacityManager.BookLevelCapacity(... isIncrease = (action == Released), orderType = Admin, capacityAction = Reservation)` কল করে: Redis live ক্যাপাসিটি সঙ্গে সঙ্গে হ্রাস পায় (reserve) বা বাড়ে (release), live আসনের তালিকা আপডেট হয়, এবং `OrderSuccess` ও `EventCapacity` বার্তা প্রকাশ হয় ([S-01](../50-system-initiated/S-01-level-capacity-update.md), [S-02](../50-system-initiated/S-02-event-live-capacity.md));
   - `SeatReservation` সারি ইনসার্ট করে: `PublicId`, `ReservationNumber` (অনন্য কোড), `Status = Draft`, `Type`, `ReservationCategory`, `ReleaseCategory`, আসন, `RemainingReservedSeat`, `MergeStatus`/`ZipStatus = None`, `CreatedBy`;
   - প্যারেন্ট রিজার্ভেশন নম্বরের বিপরীতে release করলে `ReduceRemainingReservedSeatAsync` প্যারেন্টের অবশিষ্ট সংখ্যা কমায়; সম্পূর্ণ release হওয়া প্যারেন্টকে `Closed` করে দেয়;
   - `event_total_online_ticket:{eventId}` মুছে ফেলে।
3. বাল্ক: `POST /booking/api/v1/seat-reservation/event/{eventId}?percentage=65` (admin policy) ইভেন্টের **প্রতিটি** level-এ `TotalCapacity`-এর `ceil(percentage %)` আসন সংরক্ষণ করে, প্রতি level-এ একটি করে রিজার্ভেশন (শতকরা ০ থেকে ১০০)।
4. অন্য ফিচার ব্যবহার করে এমন স্ট্যাটাস আপডেট: `PATCH .../update-reservation-status/{publicId}`, `update-merge-status`, `update-zip-status`, `GET .../merge-status/{publicId}`, `zip-status/{publicId}` ([S-09](../50-system-initiated/S-09-ticket-merge-zip.md))।

## 5. কম্পোনেন্ট

| ধরন | কম্পোনেন্ট |
|---|---|
| ক্লায়েন্ট | `features/events/components/gallery-update/*` (রিজার্ভেশন ও release ডায়ালগ), `components/gallery-reservation/*`, `services/event.service.ts:111-120, 186` |
| সার্ভিস | Booking (`SeatReservationController`, `SeatReservationManager`, `CapacityManager`) |
| কিউ | `OrderSuccess`, `EventCapacity` |
| টেবিল | Booking `SeatReservations`, `Capacities` |
| Redis | live ক্যাপাসিটি hash, `level_booking_*` লক, `event_total_online_ticket:*` |

## 6. API কন্ট্রাক্ট

| মেথড | পাথ | অথ | রিকোয়েস্ট | রেসপন্স |
|---|---|---|---|---|
| POST | `/booking/api/v1/seat-reservation` | none | `SeatReservation` | `SeatReservation` |
| POST | `/booking/api/v1/seat-reservation/event/{eventId}` | `admin` policy | query `percentage` | `200` |
| GET | `/booking/api/v1/seat-reservation/by-event-level`, `by-event`, `count/{eventId}`, `remainingReserveCount/{eventId}`, `reservations-count` | none | query | তালিকা ও সংখ্যা |
| GET | `/booking/api/v1/seat-reservation/summary/{eventId}` | `admin` policy | `levelId`, `programId` | `ReservationSummary[]` |
| PATCH | `/booking/api/v1/seat-reservation/update-reservation-status/{publicId}` এবং merge/zip-এর সমতুল্য | none (ওয়ার্কার ব্যবহারের জন্য) | `status` | `SeatReservation` |

Enum: `ActionType` `Reserved`/`Released`; `ReservationType` `Complimentary`/`Partner`; `ReservationCategory` `DigitalPrint`/`Printing`/`ReservedOnly`; `ReleaseCategory`-এ অতিরিক্ত `ToOnline`; `ReservationStatus` `Draft`, `Generated`, `Requested`, `Closed`, `Locked`, `Merging`, `Merged`।

প্রধান নমুনা, একটি level-এ ১০০টি partner আসন সংরক্ষণ (প্রপার্টির নাম `SeatReservation` থেকে; enum সংখ্যা: `action` 0 Reserved, `type` 1 Partner, `reservationCategory` 0 DigitalPrint; id উদাহরণবিশেষ):

```json
{
  "eventId": 101, "galleryId": 12, "blockId": 40, "levelId": 3305,
  "numberOfSeats": 100, "hasSeats": false, "action": 0,
  "type": 1, "reservationCategory": 0
}
```

## 7. ডেটা ও পার্শ্বপ্রতিক্রিয়া

`SeatReservations` সারি; [A-10](A-10-capacity-adjustment.md)-এর মতো live ক্যাপাসিটি ও কিউ বার্তা; ক্যাশ মুছে ফেলা; অ্যাক্টিভিটি লগ ([X-24](../60-cross-cutting/X-24-activity-logging.md))।

## 8. কোড রেফারেন্স

| কী | কোথায় |
|---|---|
| কন্ট্রোলার | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/SeatReservationController.cs:31-225` |
| ম্যানেজার | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Domain/Managers/SeatReservationManager.cs:44-172` (তৈরি/release), `:533-582` (বাল্ক) |
| Enum | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Domain/Models/Enum.cs:3-65` |
| পোর্টাল | `rvl-gobcb-admin-portal/src/app/features/events/services/event.service.ts:111-120` |

## 9. হ্যান্ডওভার নোট

1. **তৈরি ও পড়ায় কোনো অথরাইজেশন নেই।** আসন সংরক্ষণ বা release করতে সার্ভারে কোনো টোকেন লাগে না, শুধু summary ও bulk এন্ডপয়েন্টে লাগে।
2. **রিজার্ভেশন অনলাইন ক্যাপাসিটি সঙ্গে সঙ্গে, Redis-এ কমায়**, আর ডেটাবেস কিউ-র মাধ্যমে অনুসরণ করে ([S-01](../50-system-initiated/S-01-level-capacity-update.md)); একটি level-এ দুটি সমান্তরাল রিজার্ভেশন ১৫-সেকেন্ডের লক দিয়ে সিরিয়ালাইজ হয়।
3. **এই পর্যালোচনায় বাল্ক এন্ডপয়েন্টের পোর্টালে কোনো কলকারী পাওয়া যায়নি**, এবং এর ডিফল্ট `65 %` একটি ব্যাখ্যাহীন ধ্রুব (`CreateBulk(long eventId, int percentage = 65)`); ব্যবসা ব্যবহার নিশ্চিত না করা পর্যন্ত এটি ইন্টারফেসে রাখবেন না `[UNCONFIRMED: Q-22]`।
4. **`ReservationStatusUpdateService` নিবন্ধিত নয়**: `Requested` রিজার্ভেশনগুলো `Generated`-এ নেওয়ার Booking ওয়ার্কার ক্লাসটি বিদ্যমান, কিন্তু কোথাও তা হোস্ট করে না ([Appendix A](../90-appendix-a-legacy.md)); স্ট্যাটাস সুনির্দিষ্ট PATCH কলের মাধ্যমে বদলায়।
5. **Release ক্যাটাগরি হিসাব নির্ধারণ করে**: `ToOnline` আবার অনলাইন ক্যাপাসিটি বাড়ায়; বাকি তিনটি আসন অনলাইন বিক্রির বাইরে রাখে এবং কীভাবে ব্যবহৃত হয়েছে তা রেকর্ড করে। reserved ও released আসন যোগ করা যেকোনো রিপোর্টে এই বিষয় বিবেচনা করতে হবে ([A-22](A-22-reports.md))।
6. **`Locked` Ticketing সেট করে** — রিজার্ভেশনের রিজার্ভড টিকিট তৈরি করার সময় (`TicketManager.cs:1357`), আর সাইনিং কাজ কিউ করার পর `Requested` সেট করে (`:1424`); এই সময়ে release বাধা পায় "Can't release right now. Reservation is in ticket process." দিয়ে। টিকিট তৈরি অর্ধেক থেমে গেলে রিজার্ভেশন `Locked`-এ আটকে যেতে পারে এবং স্ট্যাটাস রিসেট না করা পর্যন্ত release করা যায় না ([A-12](A-12-reserved-tickets.md))।

## 10. কম্পোনেন্ট সম্পর্ক

```mermaid
sequenceDiagram
  participant A as Admin portal
  participant BK as Booking API
  participant R as Redis
  participant Q as Queues
  participant DB as Booking DB
  A->>BK: POST seat-reservation (HTTP + token)
  BK->>R: lock level_booking_*; live capacity -= seats
  BK->>Q: OrderSuccess + EventCapacity
  BK->>DB: insert SeatReservation (Draft)
  Note over A,BK: A-12 later generates tickets for the reservation
```

**নির্ভর করে:** [A-07](A-07-events.md), [A-09](A-09-event-level-pricing.md)। **প্রভাব ফেলে:** [A-12](A-12-reserved-tickets.md), [S-01](../50-system-initiated/S-01-level-capacity-update.md), [S-09](../50-system-initiated/S-09-ticket-merge-zip.md), আসনের উপলব্ধতা ([P-04](../20-user-portal/P-04-seat-selection.md))।

## 11. ডেভেলপার টেস্ট গাইড

**লোকালে টেস্টযোগ্যতা: সম্পূর্ণ।**

| আইটেম | বিবরণ |
|---|---|
| টেস্ট ডেটা ও অ্যাকাউন্ট | `pwsh ./scripts/Seed-EtpData.ps1`; অ্যাডমিন `…01` বা একজন `ticket_manager` |
| ব্রাউজার | `http://localhost:4200/events` → event → **Gallery Update** → রিজার্ভেশন ডায়ালগ; Network: `POST .../booking/api/v1/seat-reservation` |
| ইমুলেটর | — |
| Postman | `postman/services/etp-booking.postman_collection.json`: "POST /api/v1/seat-reservation", "GET /api/v1/seat-reservation/by-event-level", "GET /api/v1/seat-reservation/summary/{eventId}" (admin টোকেন) |
| Visual Studio debug | `SeatReservationManager.CreateAsync`, `CheckValidityOfCreateReservation` |
| যাচাই | SQL: `select "ReservationNumber","Action","NumberOfSeats","RemainingReservedSeat","Status" from etp."SeatReservations"`; `redis-cli HGET capacity "level_live:<e>_<g>_<b>_<l>"` |
