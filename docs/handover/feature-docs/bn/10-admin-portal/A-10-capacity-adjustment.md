# A-10 · ইভেন্ট ধারণক্ষমতা সমন্বয়

> **Bangla name:** ইভেন্ট ধারণক্ষমতা সমন্বয়
>
> [← 10 · অ্যাডমিন পোর্টাল](README.md) · [সূচিপত্র](../README.md) · [ওপেন কোয়ারি](../99-open-queries.md)

## 1. নাম ও উদ্দেশ্য

**ধারণক্ষমতা সমন্বয়।** কোনো level-এ গ্রাহকেরা অনলাইনে কত আসন কিনতে পারবেন তা Booking-এর `TicketingCapacity`। অ্যাডমিন এটি বদলান **আসন বরাদ্দ** করে (ধারণক্ষমতা বাড়ানো, ঐচ্ছিকভাবে নির্দিষ্ট আসনের নাম দিয়ে) বা **অবরাদ্দ** করে (আগের বরাদ্দের একটি অংশ ফেরত নেওয়া)। প্রতিটি সমন্বয় একটি সংখ্যা ও সেটি করা অ্যাডমিনের সঙ্গে রেকর্ড করা হয়। ধারণাগুলো: [Redis live capacity](../00-platform-primer.md#explainer-redis-live-capacity), [distributed locks](../00-platform-primer.md#explainer-distributed-locks), [queue-driven processing](../00-platform-primer.md#explainer-queue-driven)।

## 2. ট্রিগার ও অ্যাক্টর

ইভেন্টের **Gallery Update** ট্যাবে (`/events/event-details/:id`) থাকা কর্মী, "Remaining Allocated" ও "De-allocated" কলাম। **সার্ভার** এই কন্ট্রোলারে কোনো অথরাইজেশন নেই (`EventCapacityAdjustmentController`-এ কোনো `[Authorize]` নেই; ম্যানেজারের একটি মন্তব্য বলছে "TODO: add check for admin role")।

## 3. ব্যবসায়িক প্রবাহ

1. একটি level বাছুন, Allocated-এর নিচে **Add** চাপুন, আসনের সংখ্যা লিখুন (অথবা level-এর একটি শতকরা, অথবা আসন থাকা level-এর নির্দিষ্ট আসনের লেবেল) এবং সেভ করুন।
2. আসন ফেরত নিতে বরাদ্দের তালিকা খুলুন, আগের একটি বরাদ্দ বাছুন, এবং তার একটি অংশ অবরাদ্দ করুন।
3. সমন্বয়টি ইতিহাসে দেখা যায় এবং ইভেন্টের অনলাইন-টিকিট মোট বদলায়।

## 4. প্রযুক্তিগত প্রবাহ

1. **[HTTP + user token]** ট্যাবটি `GET /booking/api/v1/event-capacity-adjustment/by-event-level?eventId&levelId&action&programId` দিয়ে সমন্বয় তালিকাভুক্ত করে (Booking সার্ভিস, পোর্টাল সরাসরি কল করে)।
2. **[HTTP + user token]** সেভ: `EventCapacityAdjustment` `{eventId, galleryId, blockId, levelId, ticketingCapacity, hasSeats, seats, action, caId}` সহ `POST /booking/api/v1/event-capacity-adjustment`। `EventCapacityAdjustmentManager.CreateAsync`:
   - **যাচাই:** id 0-এর বেশি; `ticketingCapacity > 0`; ইভেন্টের gallery, block ও level সক্রিয় হতে হবে (`gallery_or_block_or_level_inactive`) এবং id-গুলো একসঙ্গে বিধু হতে হবে (`unauthorized_access`); **Deallocate**-এর জন্য একটি `caId` আবশ্যক, আগের বরাদ্দটি থাকতে হবে ("Selected Adjustment is not found."), পরিমাণ তার বেশি হতে পারবে না ("Ticketing capacity must be less than allocated seats."), live ক্যাপাসিটির বেশিও হতে পারবে না (`no_seats_available`), আর ওই বরাদ্দের সব অবরাদ্দের যোগ তার বেশি হতে পারবে না (`cannot_deallocate_more_than_allocate`); আসন থাকলে: অবরাদ্দ করা সব আসন উপলব্ধ হতে হবে ("Unavailable seats: ...") এবং বরাদ্দ করা আসন আগে থেকেই থাকতে পারবে না ("Cannot allocate these seats because they already exist in the system: ...");
   - লক নেয় `level_booking_{event}_{gallery}_{block}_{level}` (মেয়াদ ৩০ সে, অপেক্ষা ১৫ সে, রিট্রাই ১ সে) ([X-25](../60-cross-cutting/X-25-redis.md));
   - `CapacityManager.BookLevelCapacity(... isIncrease = (action == Allocate), orderType = Admin, capacityAction = Allocation)`: অ্যাডমিন অর্ডারের জন্য এটি সঙ্গে সঙ্গে Redis `capacity` hash-এর `level_live:{...}` ফিল্ড বদলায় (বৃদ্ধি বা হ্রাস) এবং live আসনের তালিকা আপডেট করে, তারপর ডেটাবেসের ক্যাপাসিটি আপডেট করতে **[SQS: OrderSuccess]** প্রকাশ করে ([S-01](../50-system-initiated/S-01-level-capacity-update.md)) এবং ইভেন্টের মোট আপডেট করতে **[SQS: EventCapacity]** প্রকাশ করে ([S-02](../50-system-initiated/S-02-event-live-capacity.md));
   - সমন্বয়ের সারি ইনসার্ট করে (`PublicId`, `AdjustmentNumber` = অনন্য কোড, `CreatedBy` = অ্যাডমিনের id, `ProgramId`);
   - Redis থেকে `event_total_online_ticket:{eventId}` মুছে ফেলে।
3. ১৫ সেকেন্ডে লক না পেলে: "Failed to acquire lock to update level capacity."

## 5. কম্পোনেন্ট

| ধরন | কম্পোনেন্ট |
|---|---|
| ক্লায়েন্ট | `features/events/components/gallery-update/*`, `services/event.service.ts:95-110` |
| সার্ভিস | Booking (`EventCapacityAdjustmentController`, `EventCapacityAdjustmentManager`, `CapacityManager`); Event সার্ভিস (`GetEventByEventLongId`) |
| কিউ | `OrderSuccess`, `EventCapacity` |
| টেবিল | Booking `EventCapacityAdjustments`, `Capacities` |
| Redis | `capacity` hash, `event_live:*`, `event_total_online_ticket:*`, লক `level_booking_*` |

## 6. API কন্ট্রাক্ট

| মেথড | পাথ | অথ | রিকোয়েস্ট | রেসপন্স | প্রধান ত্রুটি |
|---|---|---|---|---|---|
| POST | `/booking/api/v1/event-capacity-adjustment` | **none** | `EventCapacityAdjustment` | `publicId`, `adjustmentNumber`-সহ `EventCapacityAdjustment` | 400 §4-এর বার্তা |
| GET | `/booking/api/v1/event-capacity-adjustment/by-event-level` | **none** | `eventId`, `levelId`, `action`, `programId` | সমন্বয় | |
| GET | `/booking/api/v1/event-capacity-adjustment/by-event` | **none** | `eventId`, `action`, `programId` | সমন্বয় | |
| GET | `/booking/api/v1/event-capacity-adjustment/count/{eventId}` | **none** | `action` | বসার সারসংক্ষেপ |

`action`: `0` Allocate, `1` Deallocate (`Enums.Action`)। প্রধান নমুনা (প্রপার্টির নাম `EventCapacityAdjustment` থেকে; মানগুলো উদাহরণবিশেষ):

```json
{
  "eventId": 101, "galleryId": 12, "blockId": 40, "levelId": 3305,
  "ticketingCapacity": 50, "hasSeats": false, "seats": null,
  "action": 0, "caId": null
}
```

## 7. ডেটা ও পার্শ্বপ্রতিক্রিয়া

`EventCapacityAdjustments` সারি; Redis live ক্যাপাসিটি সঙ্গে সঙ্গে বদলায়; দুটি কিউ বার্তা; ওয়ার্কার চললে ডেটাবেসের ক্যাপাসিটি বদলায়; অ্যাক্টিভিটি লগ ([X-24](../60-cross-cutting/X-24-activity-logging.md))।

## 8. কোড রেফারেন্স

| কী | কোথায় |
|---|---|
| কন্ট্রোলার | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/EventCapacityAdjustmentController.cs:11-52` |
| ম্যানেজার | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Domain/Managers/EventCapacityAdjustmentManager.cs:32-207` |
| ক্যাপাসিটি লজিক | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Domain/Managers/CapacityManager.cs:35-262` |
| পোর্টাল | `rvl-gobcb-admin-portal/src/app/features/events/components/gallery-update/gallery-update.component.ts:118-330, 396` |

## 9. হ্যান্ডওভার নোট

1. **কোনো অথরাইজেশন নেই।** যে কেউ Booking সার্ভিসের এই পাথে পৌঁছাতে পারেন, সে যেকোনো ইভেন্টের ক্যাপাসিটি বরাদ্দ বা অবরাদ্দ করতে পারেন; ম্যানেজার `CreatedBy` টোকেনের user id থেকে (`User.GetId()`) নেয়, আর কন্ট্রোলার টোকেন ছাড়া কল আটকায় না (তখন `GetId()` যা ফেরত দেয় তা এখানে যাচাই করা হয়নি) ([X-18](../60-cross-cutting/X-18-endpoints-without-auth.md))।
2. **আগে Redis, পরে ডেটাবেস।** live সংখ্যা সঙ্গে সঙ্গে বদলায়; ডেটাবেসের `TicketingCapacity` ওয়ার্কার চক্রের মধ্যে আসে (প্রতি ব্যাচে প্রায় ৩০ সেকেন্ড পর্যন্ত)। live ক্যাপাসিটির বিপরীতে যাচাই করা একটি অবরাদ্দ ডেটাবেসে এখনো পুরনো সংখ্যা দেখা সত্ত্বেও পাস করতে পারে ([S-01](../50-system-initiated/S-01-level-capacity-update.md) নোট ১ ও ২)।
3. **সমন্বয়ের সারি ক্যাপাসিটি বদলানোর পরে লেখা হয়।** ইনসার্ট ব্যর্থ হলে ক্যাপাসিটি বদলে গেছে (live ও কিউ-তে) কিন্তু কোনো ইতিহাস সারি নেই।
4. **প্রকাশিত বা সময়ের কোনো যাচাই নেই।** যেকোনো সময় সমন্বয় করা যায়, এমনকি বিক্রি চলাকালীন ও ইভেন্ট শুরু হওয়ার পরেও।
5. **Allocate level-এর বসার ধারণক্ষমতা ছাড়াতে পারে।** যাচাই কেবল অবরাদ্দের ক্ষেত্রে live ক্যাপাসিটির সঙ্গে তুলনা করে; বরাদ্দের ক্ষেত্রে `SeatingCapacity`-এর বিপরীতে কোনো ঊর্ধ্বমুখী সীমা নেই।
6. **১৫-সেকেন্ডের লক অপেক্ষা** একই level বুকিং করা গ্রাহকদের সঙ্গে ভাগ করা, তাই কোনো level-এ ভারী বুকিং অ্যাডমিনের সমন্বয় বিলম্বিত করতে পারে।

## 10. কম্পোনেন্ট সম্পর্ক

```mermaid
sequenceDiagram
  participant A as Admin portal
  participant BK as Booking API
  participant R as Redis
  participant Q as OrderSuccess / EventCapacity queues
  participant W as Booking workers
  participant DB as Booking DB
  A->>BK: POST event-capacity-adjustment (HTTP + token)
  BK->>R: lock level_booking_*; hash capacity += / -=
  BK->>Q: LevelCapacityUpdate, EventLiveCapacityUpdate
  BK->>DB: insert adjustment
  W->>Q: receive
  W->>DB: TicketingCapacity +/-
```

**নির্ভর করে:** [A-07](A-07-events.md), [A-09](A-09-event-level-pricing.md)। **প্রভাব ফেলে:** [S-01](../50-system-initiated/S-01-level-capacity-update.md), [S-02](../50-system-initiated/S-02-event-live-capacity.md), আসনের উপলব্ধতা ([P-04](../20-user-portal/P-04-seat-selection.md)), [A-11](A-11-seat-reservation.md), [A-21](A-21-dashboard.md)।

## 11. ডেভেলপার টেস্ট গাইড

**লোকালে টেস্টযোগ্যতা: সম্পূর্ণ।**

| আইটেম | বিবরণ |
|---|---|
| টেস্ট ডেটা ও অ্যাকাউন্ট | `pwsh ./scripts/Seed-EtpData.ps1`; অ্যাডমিন `…01` (API টোকেন চাইলেও পোর্টাল একটি টোকেন সংযুক্ত করে) |
| ব্রাউজার | `http://localhost:4200/events` → event → **Gallery Update** → Allocate; Network: `POST .../booking/api/v1/event-capacity-adjustment` |
| ইমুলেটর | — |
| Postman | `postman/services/etp-booking.postman_collection.json`: "POST /api/v1/event-capacity-adjustment", "GET /api/v1/event-capacity-adjustment/by-event-level" |
| Visual Studio debug | `EventCapacityAdjustmentManager.CreateAsync`, `CheckValidityOfCreateAdjustment`; তারপর `LevelCapacityUpdateTaskManager` |
| যাচাই | `redis-cli HGET capacity "level_live:<e>_<g>_<b>_<l>"`; Booking-এর `Capacities` সারির `TicketingCapacity`-তে SQL; `OrderSuccess`-এ SQS কিউ ডেপথ |
