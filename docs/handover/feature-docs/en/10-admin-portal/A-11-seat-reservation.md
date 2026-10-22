# A-11 · Seat reservation (complimentary / partner)

> **Bangla name:** সিট রিজার্ভেশন (কমপ্লিমেন্টারি / পার্টনার)
>
> [← 10 · Admin portal](README.md) · [Contents](../README.md) · [Open queries](../99-open-queries.md)

## 1. Name and purpose

**Seat reservation.** An admin sets seats of a level aside so that they are not sold online, for **complimentary** tickets (given free) or **partner** tickets (given to a partner or sold offline). A reservation reduces the online capacity of the level, has a number, and later produces tickets ([A-12](A-12-reserved-tickets.md)); **releasing** seats returns them to online sale or marks how they were used. Concepts: [Redis live capacity](../00-platform-primer.md#explainer-redis-live-capacity), [distributed locks](../00-platform-primer.md#explainer-distributed-locks), [queue-driven processing](../00-platform-primer.md#explainer-queue-driven).

## 2. Trigger and actor

Staff on the event's **Gallery Update** tab (`/events/event-details/:id`, columns "Remaining Reserved" and "Released") and the **Generate Tickets** menu (`/events/event-ticket`, `/events/generate-ticket/:id`). On the server only `summary/{eventId}` and `event/{eventId}` require the `admin` policy; `POST /seat-reservation` itself has no `[Authorize]` ([X-18](../60-cross-cutting/X-18-endpoints-without-auth.md)).

## 3. Business flow

1. **Reserve:** pick the level, type (`Complimentary` or `Partner`), category (`DigitalPrint`, `Printing`, `ReservedOnly`), number of seats (or exact seats for a seated level, or a percentage of the level).
2. The reservation gets a **reservation number** and status `Draft`; it appears in "Remaining Reserved".
3. **Release:** from a reservation, release some or all of the seats with a release category: `DigitalPrint`, `Printing`, `ReservedOnly` (the seats were used for tickets) or `ToOnline` (the seats go back to online sale).
4. When all seats of a reservation have been released, the parent reservation becomes `Closed`.

## 4. Technical flow

1. **[HTTP + user token]** List `GET /booking/api/v1/seat-reservation/by-event-level?eventId&levelId&actionType&programId`; summary for the Generate Tickets page `GET /booking/api/v1/seat-reservation/summary/{eventId}?levelId&programId` (admin policy); counts `GET .../count/{eventId}`, `GET .../remainingReserveCount/{eventId}`, `GET .../reservations-count?eventId&levelId`.
2. **[HTTP + user token]** Save `POST /booking/api/v1/seat-reservation` with `SeatReservation`. `SeatReservationManager.CreateAsync`:
   - validate: ids greater than 0, `NumberOfSeats > 0`, a release needs the parent `ReservationId`, the gallery, block and level must be active (`gallery_or_block_or_level_inactive`), and for a release the parent must exist ("Selected Reservation is not found."), the released amount must be below the reserved amount ("Released Number of seats must be less than reserved seats."), and the parent must not be `Locked` ("Can't release right now. Reservation is in ticket process.");
   - take the lock `level_booking_{event}_{gallery}_{block}_{level}` (expiry 30 s, wait 15 s) ([X-25](../60-cross-cutting/X-25-redis.md));
   - for a **release**, or a **new reservation** (no parent), call `CapacityManager.BookLevelCapacity(... isIncrease = (action == Released), orderType = Admin, capacityAction = Reservation)`: Redis live capacity is decremented (reserve) or incremented (release) at once, the live seat list is updated, and `OrderSuccess` and `EventCapacity` messages are published ([S-01](../50-system-initiated/S-01-level-capacity-update.md), [S-02](../50-system-initiated/S-02-event-live-capacity.md));
   - insert the `SeatReservation` row: `PublicId`, `ReservationNumber` (unique code), `Status = Draft`, `Type`, `ReservationCategory`, `ReleaseCategory`, seats, `RemainingReservedSeat`, `MergeStatus`/`ZipStatus = None`, `CreatedBy`;
   - when releasing against a parent reservation number, `ReduceRemainingReservedSeatAsync` lowers the parent's remaining count; a fully released parent is set to `Closed`;
   - delete `event_total_online_ticket:{eventId}`.
3. Bulk: `POST /booking/api/v1/seat-reservation/event/{eventId}?percentage=65` (admin policy) reserves `ceil(percentage % of TotalCapacity)` seats on **every level** of the event, one reservation per level (percentage 0 to 100).
4. Status updates used by other features: `PATCH .../update-reservation-status/{publicId}`, `update-merge-status`, `update-zip-status`, `GET .../merge-status/{publicId}`, `zip-status/{publicId}` ([S-09](../50-system-initiated/S-09-ticket-merge-zip.md)).

## 5. Components

| Kind | Component |
|---|---|
| Client | `features/events/components/gallery-update/*` (reservation and release dialogs), `components/gallery-reservation/*`, `services/event.service.ts:111-120, 186` |
| Services | Booking (`SeatReservationController`, `SeatReservationManager`, `CapacityManager`) |
| Queue | `OrderSuccess`, `EventCapacity` |
| Tables | Booking `SeatReservations`, `Capacities` |
| Redis | live capacity hash, `level_booking_*` lock, `event_total_online_ticket:*` |

## 6. API contracts

| Method | Path | Auth | Request | Response |
|---|---|---|---|---|
| POST | `/booking/api/v1/seat-reservation` | none | `SeatReservation` | `SeatReservation` |
| POST | `/booking/api/v1/seat-reservation/event/{eventId}` | `admin` policy | query `percentage` | `200` |
| GET | `/booking/api/v1/seat-reservation/by-event-level`, `by-event`, `count/{eventId}`, `remainingReserveCount/{eventId}`, `reservations-count` | none | query | lists and counts |
| GET | `/booking/api/v1/seat-reservation/summary/{eventId}` | `admin` policy | `levelId`, `programId` | `ReservationSummary[]` |
| PATCH | `/booking/api/v1/seat-reservation/update-reservation-status/{publicId}` and merge/zip equivalents | none (worker use) | `status` | `SeatReservation` |

Enums: `ActionType` `Reserved`/`Released`; `ReservationType` `Complimentary`/`Partner`; `ReservationCategory` `DigitalPrint`/`Printing`/`ReservedOnly`; `ReleaseCategory` adds `ToOnline`; `ReservationStatus` `Draft`, `Generated`, `Requested`, `Closed`, `Locked`, `Merging`, `Merged`.

Primary sample, reserve 100 partner seats on a level (property names from `SeatReservation`; enum numbers: `action` 0 Reserved, `type` 1 Partner, `reservationCategory` 0 DigitalPrint; ids illustrative):

```json
{
  "eventId": 101, "galleryId": 12, "blockId": 40, "levelId": 3305,
  "numberOfSeats": 100, "hasSeats": false, "action": 0,
  "type": 1, "reservationCategory": 0
}
```

## 7. Data and side effects

`SeatReservations` row; live capacity and queue messages as in [A-10](A-10-capacity-adjustment.md); cache delete; activity log ([X-24](../60-cross-cutting/X-24-activity-logging.md)).

## 8. Code references

| What | Where |
|---|---|
| Controller | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/SeatReservationController.cs:31-225` |
| Manager | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Domain/Managers/SeatReservationManager.cs:44-172` (create/release), `:533-582` (bulk) |
| Enums | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Domain/Models/Enum.cs:3-65` |
| Portal | `rvl-gobcb-admin-portal/src/app/features/events/services/event.service.ts:111-120` |

## 9. Handover notes

1. **No authorization on create and read.** Reserving or releasing seats needs no token on the server, only the summary and bulk endpoints do.
2. **Reservation reduces online capacity at once, in Redis**, and the database follows by queue ([S-01](../50-system-initiated/S-01-level-capacity-update.md)); two parallel reservations on one level are serialised by the 15-second lock.
3. **The bulk endpoint has no caller in the portal** that this review found, and its default `65 %` is an unexplained constant (`CreateBulk(long eventId, int percentage = 65)`); keep it out of the interface unless the business confirms its use `[UNCONFIRMED: Q-22]`.
4. **`ReservationStatusUpdateService` is not registered**: the Booking worker class that would move `Requested` reservations to `Generated` exists but nothing hosts it ([Appendix A](../90-appendix-a-legacy.md)); statuses move through the explicit PATCH calls.
5. **Release categories decide the accounting**: `ToOnline` increases online capacity again; the other three keep the seats out of online sale and record how they were used. A report that sums reserved and released seats must account for this ([A-22](A-22-reports.md)).
6. **`Locked` is set by Ticketing** while it creates the reserved tickets of a reservation (`TicketManager.cs:1357`) and sets `Requested` after queuing the signing jobs (`:1424`); during that time a release is refused with "Can't release right now. Reservation is in ticket process." If ticket creation stops half-way, the reservation can stay `Locked` and cannot be released until its status is reset ([A-12](A-12-reserved-tickets.md)).

## 10. Component relationships

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

**Depends on:** [A-07](A-07-events.md), [A-09](A-09-event-level-pricing.md). **Affects:** [A-12](A-12-reserved-tickets.md), [S-01](../50-system-initiated/S-01-level-capacity-update.md), [S-09](../50-system-initiated/S-09-ticket-merge-zip.md), seat availability ([P-04](../20-user-portal/P-04-seat-selection.md)).

## 11. Developer test guide

**Local testability: Full.**

| Item | Detail |
|---|---|
| Test data and accounts | `pwsh ./scripts/Seed-EtpData.ps1`; admin `…01` or `ticket_manager` |
| Browser | `http://localhost:4200/events` → event → **Gallery Update** → reservation dialogs; Network: `POST .../booking/api/v1/seat-reservation` |
| Emulator | — |
| Postman | `postman/services/etp-booking.postman_collection.json`: "POST /api/v1/seat-reservation", "GET /api/v1/seat-reservation/by-event-level", "GET /api/v1/seat-reservation/summary/{eventId}" (admin token) |
| Visual Studio debug | `SeatReservationManager.CreateAsync`, `CheckValidityOfCreateReservation` |
| Verify | SQL: `select "ReservationNumber","Action","NumberOfSeats","RemainingReservedSeat","Status" from etp."SeatReservations"`; `redis-cli HGET capacity "level_live:<e>_<g>_<b>_<l>"` |
