# A-10 · Event capacity adjustment

> **Bangla name:** ইভেন্ট ধারণক্ষমতা সমন্বয়
>
> [← 10 · Admin portal](README.md) · [Contents](../README.md) · [Open queries](../99-open-queries.md)

## 1. Name and purpose

**Capacity adjustment.** The number of seats that customers can buy online at a level is `TicketingCapacity` in Booking. An admin changes it by **allocating** seats (adds capacity, optionally naming exact seats) or **deallocating** seats (takes back part of an earlier allocation). Every adjustment is recorded with a number and the admin who made it. Concepts: [Redis live capacity](../00-platform-primer.md#explainer-redis-live-capacity), [distributed locks](../00-platform-primer.md#explainer-distributed-locks), [queue-driven processing](../00-platform-primer.md#explainer-queue-driven).

## 2. Trigger and actor

Staff on the event's **Gallery Update** tab (`/events/event-details/:id`), columns "Remaining Allocated" and "De-allocated". The **server** has no authorization on this controller (`EventCapacityAdjustmentController` has no `[Authorize]`; a comment in the manager says "TODO: add check for admin role").

## 3. Business flow

1. Choose a level, press **Add** under Allocated, enter the number of seats (or a percentage of the level, or the exact seat labels for a seated level) and save.
2. To take seats back, open the allocation list, pick an earlier allocation, and deallocate part of it.
3. The adjustment appears in the history, and the event's online-ticket total changes.

## 4. Technical flow

1. **[HTTP + user token]** The tab lists adjustments with `GET /booking/api/v1/event-capacity-adjustment/by-event-level?eventId&levelId&action&programId` (the Booking service, called directly by the portal).
2. **[HTTP + user token]** Save: `POST /booking/api/v1/event-capacity-adjustment` with `EventCapacityAdjustment` `{eventId, galleryId, blockId, levelId, ticketingCapacity, hasSeats, seats, action, caId}`. `EventCapacityAdjustmentManager.CreateAsync`:
   - **validate:** ids greater than 0; `ticketingCapacity > 0`; the gallery, block and level of the event must be active (`gallery_or_block_or_level_inactive`) and the ids must belong together (`unauthorized_access`); for **Deallocate** a `caId` is required, the earlier allocation must exist ("Selected Adjustment is not found."), the amount must not exceed it ("Ticketing capacity must be less than allocated seats."), must not exceed the live capacity (`no_seats_available`), and the sum of all deallocations of that allocation must not exceed it (`cannot_deallocate_more_than_allocate`); with seats: deallocated seats must all be available ("Unavailable seats: ...") and allocated seats must not already exist ("Cannot allocate these seats because they already exist in the system: ...");
   - take the lock `level_booking_{event}_{gallery}_{block}_{level}` (expiry 30 s, wait 15 s, retry 1 s) ([X-25](../60-cross-cutting/X-25-redis.md));
   - `CapacityManager.BookLevelCapacity(... isIncrease = (action == Allocate), orderType = Admin, capacityAction = Allocation)`: for an admin order it changes the Redis `capacity` hash field `level_live:{...}` at once (increment or decrement) and updates the live seat list, then publishes **[SQS: OrderSuccess]** to update the database capacity ([S-01](../50-system-initiated/S-01-level-capacity-update.md)) and **[SQS: EventCapacity]** to update the event total ([S-02](../50-system-initiated/S-02-event-live-capacity.md));
   - insert the adjustment row (`PublicId`, `AdjustmentNumber` = unique code, `CreatedBy` = the admin's id, `ProgramId`);
   - delete `event_total_online_ticket:{eventId}` from Redis.
3. If the lock is not obtained in 15 s: "Failed to acquire lock to update level capacity."

## 5. Components

| Kind | Component |
|---|---|
| Client | `features/events/components/gallery-update/*`, `services/event.service.ts:95-110` |
| Services | Booking (`EventCapacityAdjustmentController`, `EventCapacityAdjustmentManager`, `CapacityManager`); Event service (`GetEventByEventLongId`) |
| Queue | `OrderSuccess`, `EventCapacity` |
| Tables | Booking `EventCapacityAdjustments`, `Capacities` |
| Redis | `capacity` hash, `event_live:*`, `event_total_online_ticket:*`, lock `level_booking_*` |

## 6. API contracts

| Method | Path | Auth | Request | Response | Main errors |
|---|---|---|---|---|---|
| POST | `/booking/api/v1/event-capacity-adjustment` | **none** | `EventCapacityAdjustment` | `EventCapacityAdjustment` with `publicId`, `adjustmentNumber` | 400 messages in §4 |
| GET | `/booking/api/v1/event-capacity-adjustment/by-event-level` | **none** | `eventId`, `levelId`, `action`, `programId` | adjustments | |
| GET | `/booking/api/v1/event-capacity-adjustment/by-event` | **none** | `eventId`, `action`, `programId` | adjustments | |
| GET | `/booking/api/v1/event-capacity-adjustment/count/{eventId}` | **none** | `action` | seating summary | |

`action`: `0` Allocate, `1` Deallocate (`Enums.Action`). Primary sample (property names from `EventCapacityAdjustment`; values illustrative):

```json
{
  "eventId": 101, "galleryId": 12, "blockId": 40, "levelId": 3305,
  "ticketingCapacity": 50, "hasSeats": false, "seats": null,
  "action": 0, "caId": null
}
```

## 7. Data and side effects

`EventCapacityAdjustments` row; Redis live capacity changed at once; two queue messages; the database capacity changes when the worker runs; activity log ([X-24](../60-cross-cutting/X-24-activity-logging.md)).

## 8. Code references

| What | Where |
|---|---|
| Controller | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/EventCapacityAdjustmentController.cs:11-52` |
| Manager | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Domain/Managers/EventCapacityAdjustmentManager.cs:32-207` |
| Capacity logic | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Domain/Managers/CapacityManager.cs:35-262` |
| Portal | `rvl-gobcb-admin-portal/src/app/features/events/components/gallery-update/gallery-update.component.ts:118-330, 396` |

## 9. Handover notes

1. **No authorization.** Anyone who can reach the Booking service path can allocate or deallocate capacity of any event; the manager records `CreatedBy` from the token's user id (`User.GetId()`), and the controller does not stop a call without a token (what `GetId()` returns then is not checked here) ([X-18](../60-cross-cutting/X-18-endpoints-without-auth.md)).
2. **Redis first, database later.** The live count changes immediately; the database `TicketingCapacity` follows within the worker cycle (up to about 30 seconds per batch). A deallocation validated against the live capacity can pass while the database still shows the old number ([S-01](../50-system-initiated/S-01-level-capacity-update.md) notes 1 and 2).
3. **The adjustment row is written after the capacity change.** If the insert fails, the capacity has changed (live and queued) but no history row exists.
4. **No published or time check.** An adjustment can be made at any time, including during sales and after the event started.
5. **Allocate may exceed the level's seating capacity.** The validation compares only with live capacity for deallocation; for allocation there is no upper bound against `SeatingCapacity`.
6. **The 15-second lock wait** is shared with customers booking the same level, so heavy booking on a level can delay an admin adjustment.

## 10. Component relationships

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

**Depends on:** [A-07](A-07-events.md), [A-09](A-09-event-level-pricing.md). **Affects:** [S-01](../50-system-initiated/S-01-level-capacity-update.md), [S-02](../50-system-initiated/S-02-event-live-capacity.md), seat availability ([P-04](../20-user-portal/P-04-seat-selection.md)), [A-11](A-11-seat-reservation.md), [A-21](A-21-dashboard.md).

## 11. Developer test guide

**Local testability: Full.**

| Item | Detail |
|---|---|
| Test data and accounts | `pwsh ./scripts/Seed-EtpData.ps1`; admin `…01` (a token is attached by the portal even though the API does not require one) |
| Browser | `http://localhost:4200/events` → event → **Gallery Update** → Allocate; Network: `POST .../booking/api/v1/event-capacity-adjustment` |
| Emulator | — |
| Postman | `postman/services/etp-booking.postman_collection.json`: "POST /api/v1/event-capacity-adjustment", "GET /api/v1/event-capacity-adjustment/by-event-level" |
| Visual Studio debug | `EventCapacityAdjustmentManager.CreateAsync`, `CheckValidityOfCreateAdjustment`; then `LevelCapacityUpdateTaskManager` |
| Verify | `redis-cli HGET capacity "level_live:<e>_<g>_<b>_<l>"`; SQL on the Booking `Capacities` row's `TicketingCapacity`; SQS queue depth on `OrderSuccess` |
