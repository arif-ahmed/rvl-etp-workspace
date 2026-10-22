# P-06 · Booking order and payment

> **Bangla name:** বুকিং অর্ডার ও পেমেন্ট
>
> [← 20 · User portal](README.md) · [Contents](../README.md) · [Open queries](../99-open-queries.md)

## 1. Name and purpose

**Booking and payment.** The heart of the business: the customer confirms the selection of [P-04](P-04-seat-selection.md), the platform checks the rules, locks the capacity, creates a `Pending` order with a server-computed price, sends the customer to the **DgePay** payment page, and, when DgePay reports back, marks the order `Paid` and starts everything that follows (capacity deduction, VAT challan, ticket creation). If payment does not arrive in time the order is cancelled and the seats are released ([S-05](../50-system-initiated/S-05-pending-failed-revalidation.md)).

## 2. Trigger and actor

Signed-in customer with a **completed profile** (the server refuses otherwise), pressing **Purchase** on the seats page and confirming in the payment pop-up (`CompletePaymentModalComponent`). The payment itself happens on DgePay's hosted page.

## 3. Business flow

1. The pop-up repeats the choice (event, seats, price) and offers **Pay**; pressing it disables the button while the request runs.
2. The browser is redirected to DgePay (`window.location.href = checkoutUrl`); the customer pays by their method.
3. DgePay tells the platform the result; the platform then sends the customer's browser back to the portal (the configured `DgePay:RedirectUrl`), which shows the booking list ([P-07](P-07-my-bookings.md)).
4. A `Paid` order gets tickets; the customer asks for the final signed tickets later ([P-08](P-08-ticket-generation-request.md)).
5. If the customer abandons the page, nothing is charged; the `Pending` order and its seat lock expire after about 12 minutes.

## 4. Technical flow

1. **[HTTP + user token]** `POST {services.bookings}/booking/api/v1/user-booking-order` with `TicketPurchase` ([P-04](P-04-seat-selection.md) §4 step 6) (`BookingApiService.ticketPurchase`; server `[Authorize(Policy = User)]`). `UserBookingOrderManager.CreateAsync`:
   1. loads the caller's profile from the identity API (`userClient.GetUserAsync()`, **[HTTP, static key]**); no profile or `IsProfileCompleted` false → `Complete your profile first!`;
   2. takes the Redis lock `user_booking:{userId}` (60 s); not acquired → `Simultaneous order is prohibited. Try again later.`;
   3. loads the event through the Event client; not published or not active → `This event is currently unavailable for booking.`;
   4. `ValidateBookingOrderCreate`: gallery, block, level ids > 0; seats > 0; `PricePerSeat > 0`, `TotalCharge > 0`, `Vat ≥ 0` (client values, only checked for sign); `NumberOfSeats ≤ AllowableMaximumSeatPerOrder`; the level's gallery, block and level must exist, be active and sellable, and match the sent ids (`unauthorized_access` otherwise); selling window (`ticket_selling_is_not_started_yet`, `ticket_selling_stopped`); `order_limit_exceeded` and `seat_limit_exceeded` from the customer's earlier orders (see note 5);
   5. for seated levels: the requested seats must all be in the live free-seat list, else `Unavailable seats: ...`;
   6. generates a unique order number `{TicketNumberPrefix}{code}`;
   7. takes the lock `level_booking_{event}_{gallery}_{block}_{level}` (60 s, waits up to 15 s) and calls `CapacityManager.BookLevelCapacity` (**locks** the seats/amount for 12 minutes in the Redis hash `level_locked:*`; live capacity is reduced only after payment, [S-01](../50-system-initiated/S-01-level-capacity-update.md));
   8. **computes the price on the server** from the event settings (VAT inclusive or on top, percentage or fixed), the level price, the system discount (`Discounts` table), the promo code ([P-05](P-05-apply-promo-code.md)) and the platform (service) charge; stores `Vat`, `Discount`, `PromoDiscount`, `PlatformCharge`, `TotalCharge`, status `Pending`, a new `PaymentTransactionId` (GUID), `OneIdUserId` from the profile;
   9. stores one `BookedUserRecords` row per ticket (the holder names and phones sent, empty rows for the rest);
   10. asks DgePay for the checkout link (`InitiateDgePayPayment`) and returns `{ publicId, checkoutUrl }` with HTTP 201. The gateway choice code (`ResolvePaymentGateway`, SSLCommerz) is **commented out**: every order uses DgePay ([Q-19](../99-open-queries.md#q-19)).
2. **[HTTP, static/encrypted] → DgePay:** `DgePayPaymentManager.InitiatePaymentAndGetCheckoutLink` authenticates (`/payment_gateway/authenticate`, Basic client credentials), AES-encrypts the body (amount, transaction id, callback URL `DgePay:CallbackUrl`) and posts to `/payment_gateway/initiate_payment`; the answer's `WebViewUrl` is the checkout link. Any failure returns `null` (logged only).
3. The customer pays on DgePay. DgePay then calls **[HTTP, no token]** `GET /booking/api/v1/user-booking-order/dgepay/payment-status?data=<AES-encrypted>` (anonymous). `HandleDgePayment` decrypts the data, finds the order by `UniqueTxnId`, and:
   - status **Paid** and order younger than 12 minutes: publishes **[SQS: OrderSuccess]** (level capacity update, [S-01](../50-system-initiated/S-01-level-capacity-update.md)), sets the status, stores the callback text and time, calls Ticketing `initiate-user-ticket` (creates the ticket rows, [S-07](../50-system-initiated/S-07-initiate-user-ticket-generation.md)) and publishes **[SQS: VatChallanProcessing]** ([S-10](../50-system-initiated/S-10-vat-challan.md));
   - status **not Paid**: deletes the order from the locked-capacity hash;
   - order **older than 12 minutes**: the status and the capacity message are *not* applied (the order is left for the background cancel); the callback text is still stored. The code after that point does not look at the age: for a `Paid` callback it still calls `initiate-user-ticket` (which refuses because the order is not `Paid`, logged as a warning) and **still publishes the VAT challan message** `[UNCONFIRMED: Q-15]`.
   The action then **always** answers with a 302 to `DgePay:RedirectUrl`, even if processing failed (errors are only logged).
4. Background: orders still `Pending` after the callback window are re-checked against DgePay (`check_transaction_status`) and cancelled if unpaid ([S-05](../50-system-initiated/S-05-pending-failed-revalidation.md)).
5. **Portal after redirect:** the portal route `tickets` (without language) redirects to `/{savedLanguage}/tickets` ([P-07](P-07-my-bookings.md)); no payment result is passed in the URL, the list reads the status from the server.
6. **Test/bypass path:** `GET /booking/api/v1/user-booking-order/payment-status-bypass?rawData=<order public id>` is **anonymous**, does not ask DgePay, forces `Paid` with the text "BY PASS TRANSACTION - TEST", publishes OrderSuccess and initiates tickets ([X-18](../60-cross-cutting/X-18-endpoints-without-auth.md); this is the critical finding of the review).

## 5. Components

| Kind | Component |
|---|---|
| Client | `tickets/components/complete-payment-modal`, `stadium-seat-page` (`openCompletePaymentModal`), `booking-api.service.ts:31-42` |
| Services | Booking (`UserBookingOrderController`, `UserBookingOrderManager`, `CapacityManager`, `DgePayPaymentManager`); Event (event and level info through `EventClient`); Ticketing (`initiate-user-ticket`); identity API (profile) |
| Queues / workers | SQS `OrderSuccess` → [S-01](../50-system-initiated/S-01-level-capacity-update.md); `VatChallanProcessing` → [S-10](../50-system-initiated/S-10-vat-challan.md); re-check job [S-05](../50-system-initiated/S-05-pending-failed-revalidation.md) |
| Tables | `UserBookingOrders`, `BookedUserRecords`, read of `Discounts`, `PromoCodes` |
| Redis | locks `user_booking:{userId}`, `level_booking_...`; hash `level_locked:{e}_{g}_{b}_{l}` ([X-25](../60-cross-cutting/X-25-redis.md)) |
| External | DgePay (`authenticate`, `initiate_payment`, `check_transaction_status`); identity API |

## 6. API contracts

| Method | Path | Auth | Request | Response | Main errors |
|---|---|---|---|---|---|
| POST | `/booking/api/v1/user-booking-order` | User | `UserBookingOrder` (= `TicketPurchase`) | 201 `UserBookingOrderResponse { publicId, checkoutUrl }` | 400 messages in §4 step 1 |
| GET | `/booking/api/v1/user-booking-order/dgepay/payment-status` | anonymous (DgePay callback) | `data` (encrypted) | 302 to `DgePay:RedirectUrl` | none returned |
| GET | `/booking/api/v1/user-booking-order/payment-status-bypass` | **anonymous** | `rawData` (order public id) | 302 | none returned |

Primary sample, `POST /booking/api/v1/user-booking-order` (names from `UserBookingOrder`; values illustrative; `totalCharge`, `pricePerSeat` and `vat` are only sign-checked):

```json
{ "eventId": "9f0b2c1e-3b0e-4a43-9d5e-6f5f3d0c1a11", "galleryId": 5, "blockId": 11, "levelId": 31,
  "numberOfSeats": 2, "pricePerSeat": 1500, "hasSeats": true, "seats": "A1,A2",
  "promoCode": "", "totalCharge": 3450, "vat": 450,
  "bookedUserDetails": [ { "userName": "Nadia Rahman", "phoneNumber": "01711111111" },
                         { "userName": "", "phoneNumber": "" } ] }
```

```json
{ "publicId": "5b1f7a64-6c1e-4c0a-8f6e-0f3d2f9a7b10", "checkoutUrl": "https://pay.example.com/checkout/abc123" }
```

## 7. Data and side effects

`UserBookingOrders` (`Pending`, later `Paid`), `BookedUserRecords`, seat lock in Redis, DgePay session, then (after payment) SQS messages, ticket rows in Ticketing, a VAT message and capacity changes. The activity log records the order changes ([X-24](../60-cross-cutting/X-24-activity-logging.md)).

## 8. Code references

| What | Where |
|---|---|
| Controller | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/UserBookingOrderController.cs:43-86, 239-262` |
| Create | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Domain/Managers/UserBookingOrderManager.cs:61-330` |
| Callback | `.../UserBookingOrderManager.cs:331-452` (DgePay), `495-545` (bypass) |
| Validation, gateway | `.../UserBookingOrderManager.cs:562-760` |
| DgePay client | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Domain/Managers/DgePayPaymentManager.cs:27-130, 188-265` |
| Portal | `rvl-gobcb-user-portal/ETP-Web/src/app/modules/featured/tickets/components/complete-payment-modal/complete-payment-modal.component.ts:37-58` |

## 9. Handover notes

1. **Anyone who knows an order's public id can mark it paid.** `payment-status-bypass` is anonymous and permanent in the code; it also starts ticket creation. Remove it or protect it before production use ([X-18](../60-cross-cutting/X-18-endpoints-without-auth.md)). Locally it is a handy way to simulate a payment (§11).
2. **The checkout failure is invisible to the customer.** If DgePay does not return a link, `checkoutUrl` is `null`; the portal only acts when a URL exists, so the pop-up stays in the loading state with no message (`loading` is not reset).
3. **A paid order after 12 minutes is lost to the platform.** A late DgePay callback neither updates the status nor deducts capacity; the money may have been taken while the order is cancelled by the background job ([S-05](../50-system-initiated/S-05-pending-failed-revalidation.md), `[UNCONFIRMED: Q-11]`).
4. **Two customers choosing the same seats:** the first order takes the lock; the second fails with `Unavailable seats: ...` or a capacity message ([P-04](P-04-seat-selection.md) note 2). A refused purchase keeps its seats locked until the 12-minute lock expires `[UNCONFIRMED: Q-37]`.
5. **Limit checks are loose.** `order_limit_exceeded` fires only when the customer already has *more than* `AllowableMaximumOrderPerUser` orders (so one more than the limit is possible), and `seat_limit_exceeded` compares *all* seats the customer ever booked for the event plus the new ones with the **per-order** maximum `AllowableMaximumSeatPerOrder`, so that setting works as a per-customer total as well `[UNCONFIRMED: Q-38]`.
6. **The server price can differ from the preview** ([P-04](P-04-seat-selection.md) note 1); the amount charged is `TotalCharge` as computed in step 8.
7. **No "resume payment".** The endpoint that would regenerate a checkout link for a pending order is commented out in the controller (`UserBookingOrderController.cs:287`); a customer who closes the DgePay page must buy again.
8. **The callback trusts the encrypted message.** `HandleDgePayment` takes the status from the decrypted `data` (shared AES key) and does not call `check_transaction_status`; only the background re-check does ([S-05](../50-system-initiated/S-05-pending-failed-revalidation.md)). Protect the key like a password ([X-26](../60-cross-cutting/X-26-configuration.md)).
9. **Always a redirect.** A failure while processing the callback is logged as critical and the customer is still sent to the portal, where the order shows `Pending` until the re-check.
10. **Error messages from the server are shown as text** (`err.error.title`); machine codes such as `ticket_selling_stopped` or `order_limit_exceeded` are displayed as they are unless the portal translates them `[UNCONFIRMED: Q-39]`.
11. **Profile call per order.** Each order calls the identity API; if it is down the customer cannot buy (`Complete your profile first!` is also the message for a missing profile).

## 10. Component relationships

```mermaid
sequenceDiagram
  participant U as User portal
  participant B as Booking API
  participant R as Redis
  participant D as DgePay
  participant Q as SQS OrderSuccess / VatChallanProcessing
  participant T as Ticketing API
  U->>B: POST user-booking-order (HTTP + user token)
  B->>R: lock user_booking, level_booking; lock capacity (level_locked)
  B->>D: authenticate + initiate_payment (encrypted)
  D-->>B: WebViewUrl
  B-->>U: 201 publicId, checkoutUrl
  U->>D: browser redirect, customer pays
  D->>B: GET dgepay/payment-status?data (anonymous callback)
  B->>Q: OrderSuccess, VatChallanProcessing
  B->>T: initiate-user-ticket (HTTP, no token)
  B-->>U: 302 to DgePay:RedirectUrl
```

**Depends on:** [P-04](P-04-seat-selection.md), [P-05](P-05-apply-promo-code.md), [A-03](../10-admin-portal/A-03-program-settings.md) and [A-08](../10-admin-portal/A-08-event-settings.md) (VAT, charge, limits), [A-16](../10-admin-portal/A-16-discounts.md), [X-06](../60-cross-cutting/X-06-user-registration.md) (profile). **Affects:** [P-07](P-07-my-bookings.md), [P-08](P-08-ticket-generation-request.md), [S-01](../50-system-initiated/S-01-level-capacity-update.md), [S-05](../50-system-initiated/S-05-pending-failed-revalidation.md), [S-07](../50-system-initiated/S-07-initiate-user-ticket-generation.md), [S-10](../50-system-initiated/S-10-vat-challan.md), [A-22](../10-admin-portal/A-22-reports.md), [A-23](../10-admin-portal/A-23-reconciliation.md).

## 11. Developer test guide

**Local testability: Partial.** DgePay is a dummy locally, so the real payment page and callback cannot run; the order creation and the capacity lock can.

| Item | Detail |
|---|---|
| Test data and accounts | User `+8801700000011` / `Passw0rd!23` (profile complete); nine seeded orders for this user (paid, pending, failed, cancelled) |
| Browser | `http://localhost:4201/en/tickets/{eventId}/seats` → **Purchase** → **Pay**; the redirect to the dummy checkout fails by design; inspect the Network call `user-booking-order` (201 with `checkoutUrl`, or 400) and the new `Pending` row |
| Emulator | — (the app cannot sign in locally, [U-05](../30-user-app/U-05-booking-webview-payment.md)) |
| Postman | `postman/services/etp-booking.postman_collection.json`: "POST /api/v1/user-booking-order", "GET /api/v1/user-booking-order/dgepay/payment-status", "GET /api/v1/user-booking-order/payment-status-bypass" (set `rawData` to the `publicId` to simulate a successful payment locally; never enable this endpoint in a shared environment) |
| Visual Studio debug | `UserBookingOrderManager.CreateAsync` (breakpoints at the validation, `BookLevelCapacity`, price steps 1-7), `HandleDgePayment`; Booking service from the Aspire AppHost |
| Verify | SQL: `select "OrderNumber","Status","TotalCharge","Vat","Discount","PromoDiscount","PlatformCharge","PaymentTransactionId" from etp."UserBookingOrders" order by "CreatedAt" desc limit 5`; Redis `HGETALL level_locked:{e}_{g}_{b}_{l}`; after the bypass call: SQS OrderSuccess message in Floci, status `Paid` |
