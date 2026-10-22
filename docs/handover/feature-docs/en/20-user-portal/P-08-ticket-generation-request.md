# P-08 · Ticket generation request

> **Bangla name:** টিকিট জেনারেশন অনুরোধ
>
> [← 20 · User portal](README.md) · [Contents](../README.md) · [Open queries](../99-open-queries.md)

## 1. Name and purpose

**Ticket generation request.** After payment the customer holds a `Paid` order and *draft* ticket rows. When the event's **ticket availability date** arrives, the customer presses **Request tickets**; the platform then prints a blank PDF per ticket, has each one digitally signed with a QR code by the TSP, and the order turns `Requested` and later `Generated`. The customer waits on the page (it re-checks every 30 seconds) until the signed PDFs can be downloaded ([P-09](P-09-ticket-details-downloads.md)).

## 2. Trigger and actor

Signed-in customer on `/{lang}/tickets/ticket-details/{publicId}` (`TicketPreviewComponent`), only when the order is `Paid` and the event's `ticketAvailabilityStartDateTime` has passed (holder names and phones are filled in beforehand, [P-09](P-09-ticket-details-downloads.md)).

## 3. Business flow

1. Before the availability date the button is inactive. From the availability date on, **Request tickets** opens a confirmation pop-up ("Once generated, the ticket details cannot be changed"; the pop-up text is hard-coded in English, not translated).
2. After confirmation the order status becomes `Requested`; a pop-up says generation is in progress; the page shows the "in progress" state and re-checks every 30 seconds.
3. When every ticket is signed the order becomes `Generated` ([S-06](../50-system-initiated/S-06-booking-to-generated.md)); the page reloads the tickets and shows the **Download**, **Share** and, for more than one ticket, **Download all** buttons.

## 4. Technical flow

1. Draft tickets exist because the details call creates them on demand: `GetTicketsInfo` creates the rows of a `Paid` order that has none (`InitiateBulkTicketForNewlyPaidOrder`, under the Redis lock `create_user_ticket_{publicId}`), in addition to the payment callback and the worker ([S-07](../50-system-initiated/S-07-initiate-user-ticket-generation.md)).
2. **[HTTP, no token → Ticketing]** The portal sends `PATCH {services.tickets}/ticketing/api/v1/booking-order-ticket/generate-request/{publicId}` with an empty body (`BookingApiService.requestTicketsById`). The controller action has **no `[Authorize]`** and the manager does not check the caller; the portal's token interceptor still attaches the user token because the URL contains `/ticketing`.
3. `TicketManager.TicketGenerateRequest`:
   1. reads the order from Booking (**[HTTP, no token]** `GET .../user-booking-order/public-id/{id}`);
   2. `ValidateTicketGeneration`: status `Requested` or `Generated` → `Request to generate ticket is already taken.`; not `Paid` → `Only paid order requests can generate tickets`; the event's `TicketAvailabilityStartDateTime` later than now (UTC) → `You can request after ticket availability date.`;
   3. loads the level info and the **published ticket layout** of the program, venue and gallery ([A-13](../10-admin-portal/A-13-ticket-layouts.md));
   4. for each ticket, draws the blank PDF (`GetBlankPdf`) and uploads it to the ticket bucket under `{BlankBase}/user/{userId}/{orderId}/{ticketNumber}.pdf` ([X-20](../60-cross-cutting/X-20-file-storage.md)); sets the ticket status `Requested` and the layout's back-page URL; saves;
   5. for each ticket publishes **[SQS: TicketSigning]** a `SignedTicketGeneration` message (`UnsignedTicketUrl`, `QRPosition` by layout size, `GateId` = the level's entry gate, `Data` = name, phone, date and time (UTC+6), ticket id, event id, gallery, block, level, entry gate, mini gate, seat); the signing worker is [S-08](../50-system-initiated/S-08-ticket-signing.md);
   6. **[HTTP, no token → Booking]** `PATCH .../user-booking-order/generate-ticket-request/{publicId}` sets the order status `Requested`, and returns the order with its tickets.
4. The browser updates the ticket statuses and the order status from the response and opens the "generation" pop-up. From now on `ngOnInit`'s timer (every 30 s) calls **[HTTP + user token]** `GET /booking/api/v1/user-booking-order/check-generated-status?id=` while the status is `Requested`; when it returns `true` the portal reloads the tickets (`details`).
5. Background: [S-08](../50-system-initiated/S-08-ticket-signing.md) signs and stores each ticket (`SignedTicketUrl`); [S-06](../50-system-initiated/S-06-booking-to-generated.md) marks the order `Generated` when all its tickets are signed; [S-12](../50-system-initiated/S-12-ticket-generated-notification.md) sends the push message.

## 5. Components

| Kind | Component |
|---|---|
| Client | `tickets/components/{ticket-preview,request-tickets-modal,ticket-generation-modal,in-progress-ticket-modal}`, `booking-api.service.ts:50-54, 93-98` |
| Services | Ticketing (`BookingOrderTicketController.GenerateTicketRequest`, `TicketManager`); Booking (`generate-ticket-request`, `check-generated-status`); Event (event, layout, level info) |
| Queues / workers | SQS `TicketSigning` → [S-08](../50-system-initiated/S-08-ticket-signing.md); [S-06](../50-system-initiated/S-06-booking-to-generated.md) |
| Tables | `Tickets`, `TicketLayoutConfigs`, `UserBookingOrders` |
| Storage | ticket bucket `{BlankBase}/user/...` (blank), `{SignedBase}` (signed) |
| External | TSP (through the worker) |

## 6. API contracts

| Method | Path | Auth | Request | Response | Main errors |
|---|---|---|---|---|---|
| PATCH | `/ticketing/api/v1/booking-order-ticket/generate-request/{publicId}` | **none** | path | `UserBookingResponse` (order and tickets) | 400 messages in §4 step 3 |
| GET | `/booking/api/v1/user-booking-order/check-generated-status` | User | `id` (order public id) | `true`/`false` | 400 `Booking not found.`, `Privacy error.` |
| PATCH | `/booking/api/v1/user-booking-order/generate-ticket-request/{publicId}` | **none** (internal) | path | `UserBooking` | `Order not found` |

Primary sample, the response of `PATCH /ticketing/api/v1/booking-order-ticket/generate-request/{publicId}` (shortened; values illustrative):

```json
{ "publicId": "5b1f7a64-6c1e-4c0a-8f6e-0f3d2f9a7b10", "status": "Requested", "numberOfSeats": 2,
  "tickets": [ { "id": 301, "ticketNumber": "BDI7K2M9Q-1", "status": "Requested", "seat": "A1",
                 "ticketHolderName": "Nadia Rahman", "ticketHolderIdentification": "01711111111" } ] }
```

## 7. Data and side effects

Blank PDFs in the ticket bucket, ticket and order status changes, one SQS message per ticket, later signed PDFs and a push notification.

## 8. Code references

| What | Where |
|---|---|
| Portal | `rvl-gobcb-user-portal/ETP-Web/src/app/modules/featured/tickets/components/ticket-preview/ticket-preview.component.ts:55-100, 204-250` |
| Controller | `rvl-gobcb-backend/Services/Ticketing/ETP.Ticketing.Service/Api/BookingOrderTicketController.cs:112-119` |
| Manager | `rvl-gobcb-backend/Services/Ticketing/ETP.Ticketing.Domain/Managers/TicketManager.cs:146-208, 261-356, 358-372` |
| Booking side | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/UserBookingOrderController.cs:363-371`; `.../UserBookingOrderManager.cs:903-919, 1019-1042` |

## 9. Handover notes

1. **Anyone can trigger generation for any order** whose public id they know: the Ticketing action and the Booking `generate-ticket-request` action are anonymous ([X-18](../60-cross-cutting/X-18-endpoints-without-auth.md), [S-07](../50-system-initiated/S-07-initiate-user-ticket-generation.md) note 4). The availability-date and `Paid` checks still apply.
2. **Order of the writes is not atomic.** Tickets are marked `Requested` and messages are published before the Booking order is set to `Requested`; if the Booking call fails the tickets are already being signed while the order still shows `Paid`, and pressing the button again is refused (`ValidateTicketGeneration` looks at the order, which is still `Paid`, so a second request re-prints and re-publishes) `[UNCONFIRMED: Q-40]`.
3. **Holder data is frozen at request time.** The QR payload contains the name and phone as stored when the request is made; editing is refused afterwards because the order is no longer `Paid` ([P-09](P-09-ticket-details-downloads.md)).
4. **Availability time uses two clocks.** The button is enabled by the browser's clock (`Date.now()` against `ticketAvailabilityStartDateTime`, refreshed every 30 s) while the server compares with UTC now; a wrong device clock can show the button early (server refuses) or late.
5. **Request time is the TSP's busiest moment.** When the availability date arrives many customers press the button together; the work is queued in `TicketSigning` and signed by the worker ([S-08](../50-system-initiated/S-08-ticket-signing.md)); the customer only waits and polls.
6. **No timeout on the waiting state.** If signing stalls, the order stays `Requested` and the page keeps polling for ever; support finds it in the issue list or reconciliation ([A-23](../10-admin-portal/A-23-reconciliation.md)) `[UNCONFIRMED: Q-12]`.
7. **Layout is read at request time.** A layout published later does not affect tickets already requested ([A-13](../10-admin-portal/A-13-ticket-layouts.md)).

## 10. Component relationships

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

**Depends on:** [P-06](P-06-booking-payment.md), [P-09](P-09-ticket-details-downloads.md) (holder data), [A-13](../10-admin-portal/A-13-ticket-layouts.md), [A-07](../10-admin-portal/A-07-events.md) (availability date). **Affects:** [S-06](../50-system-initiated/S-06-booking-to-generated.md), [S-08](../50-system-initiated/S-08-ticket-signing.md), [S-12](../50-system-initiated/S-12-ticket-generated-notification.md), [P-09](P-09-ticket-details-downloads.md).

## 11. Developer test guide

**Local testability: Partial.** Signing needs the TSP certificate, which is a dummy locally, so tickets reach `Requested` but are not signed.

| Item | Detail |
|---|---|
| Test data and accounts | User `+8801700000011`; a seeded `Paid` order whose event's ticket availability date has passed |
| Browser | open the order from `http://localhost:4201/en/tickets` → **View details** → **Request tickets**; Network: `generate-request` (200), then `check-generated-status` every 30 s |
| Emulator | — ([U-06](../30-user-app/U-06-my-bookings-tickets.md)) |
| Postman | `postman/services/etp-ticketing.postman_collection.json`: "PATCH /api/v1/booking-order-ticket/generate-request/{publicId}"; `etp-booking`: "GET /api/v1/user-booking-order/check-generated-status" |
| Visual Studio debug | `TicketManager.TicketGenerateRequest`, `ValidateTicketGeneration` (Ticketing service); worker: `TicketSigning` consumer ([S-08](../50-system-initiated/S-08-ticket-signing.md)) |
| Verify | SQL: `select "TicketNumber","Status","BlankTicketUrl","SignedTicketUrl" from etp."Tickets" where "BookingOrderPublicId"=...`; Floci SQS `TicketSigning` queue depth; Floci S3 `ls` of the ticket bucket |
