# P-06 · বুকিং অর্ডার ও পেমেন্ট

> **Bangla name:** বুকিং অর্ডার ও পেমেন্ট
>
> [← 20 · ইউজার পোর্টাল](README.md) · [সূচিপত্র](../README.md) · [ওপেন কোয়ারি](../99-open-queries.md)

## 1. নাম ও উদ্দেশ্য

**বুকিং ও পেমেন্ট।** ব্যবসার কেন্দ্রবিন্দু: গ্রাহক [P-04](P-04-seat-selection.md)-এর বাছাই নিশ্চিত করে, প্ল্যাটফর্ম নিয়মগুলো যাচাই করে, ক্যাপাসিটি লক করে, সার্ভার-হিসাব করা দামসহ একটি `Pending` অর্ডার তৈরি করে, গ্রাহককে **DgePay** পেমেন্ট পেজে পাঠায়, এবং DgePay ফিরিয়ে জানালে অর্ডারটিকে `Paid` চিহ্নিত করে ও এরপরের সবকিছু শুরু করে (ক্যাপাসিটি বাদ দেওয়া, VAT চালান, টিকিট তৈরি)। পেমেন্ট সময়মতো না এলে অর্ডার বাতিল হয় এবং আসন মুক্ত হয় ([S-05](../50-system-initiated/S-05-pending-failed-revalidation.md))।

## 2. ট্রিগার ও অ্যাক্টর

**সম্পূর্ণ প্রোফাইলসহ** সাইন-ইন করা গ্রাহক (সার্ভার অন্যথায় প্রত্যাখ্যান করে), সিট পেজে **Purchase** চাপে এবং পেমেন্টের পপ-আপে নিশ্চিত করে (`CompletePaymentModalComponent`)। পেমেন্ট নিজে DgePay-এর হোস্ট করা পেজে হয়।

## 3. ব্যবসায়িক প্রবাহ

1. পপ-আপ বাছাইটি আবার দেখায় (ইভেন্ট, আসন, দাম) এবং **Pay** দেয়; চাপলে রিকোয়েস্ট চলাকালীন বোতামটি নিষ্ক্রিয় হয়।
2. ব্রাউজার DgePay-এ রিডাইরেক্ট হয় (`window.location.href = checkoutUrl`); গ্রাহক নিজের পদ্ধতিতে টাকা দেন।
3. DgePay প্ল্যাটফর্মকে ফল জানায়; এরপর প্ল্যাটফর্ম গ্রাহকের ব্রাউজারকে আবার পোর্টালে পাঠায় (কনফিগার করা `DgePay:RedirectUrl`), যেখানে বুকিং তালিকা দেখায় ([P-07](P-07-my-bookings.md))।
4. `Paid` অর্ডার পায় টিকিট; গ্রাহক পরে চূড়ান্ত সাইন করা টিকিটগুলো চায় ([P-08](P-08-ticket-generation-request.md))।
5. গ্রাহক পেজ ছেড়ে দিলে কোনো টাকা নেওয়া হয় না; `Pending` অর্ডার ও তার আসনের লক প্রায় ১২ মিনিট পরে মেয়াদোত্তীর্ণ হয়।

## 4. কারিগরি প্রবাহ

1. **[HTTP + user token]** `POST {services.bookings}/booking/api/v1/user-booking-order` শরীরে `TicketPurchase` ([P-04](P-04-seat-selection.md) §4 ধাপ 6) (`BookingApiService.ticketPurchase`; সার্ভার `[Authorize(Policy = User)]`)। `UserBookingOrderManager.CreateAsync`:
   1. identity API থেকে কলার প্রোফাইল লোড করে (`userClient.GetUserAsync()`, **[HTTP, static key]**); প্রোফাইল না থাকলে বা `IsProfileCompleted` মিথ্যা হলে → `Complete your profile first!`;
   2. Redis লক `user_booking:{userId}` নেয় (৬০ সে); না পেলে → `Simultaneous order is prohibited. Try again later.`;
   3. Event ক্লায়েন্টের মাধ্যমে ইভেন্ট লোড করে; প্রকাশিত বা সক্রিয় না হলে → `This event is currently unavailable for booking.`;
   4. `ValidateBookingOrderCreate`: গ্যালারি, ব্লক, লেভেলের id > 0; আসন > 0; `PricePerSeat > 0`, `TotalCharge > 0`, `Vat ≥ 0` (ক্লায়েন্টের মান, শুধু চিহ্ন যাচাই করা হয়); `NumberOfSeats ≤ AllowableMaximumSeatPerOrder`; লেভেলের গ্যালারি, ব্লক ও লেভেল থাকতে হবে, সক্রিয় ও বিক্রিযোগ্য হতে হবে, এবং পাঠানো id-এর সাথে মিলতে হবে (অন্যথায় `unauthorized_access`); বিক্রয়ের সময়সীমা (`ticket_selling_is_not_started_yet`, `ticket_selling_stopped`); গ্রাহকের আগের অর্ডার থেকে `order_limit_exceeded` ও `seat_limit_exceeded` (নোট 5 দেখুন);
   5. সিটযুক্ত লেভেলের জন্য: চাওয়া আসনগুলো সবই লাইভ খালি আসনের তালিকায় থাকতে হবে, নয়তো `Unavailable seats: ...`;
   6. একটি অনন্য অর্ডার নম্বর তৈরি করে `{TicketNumberPrefix}{code}`;
   7. লক `level_booking_{event}_{gallery}_{block}_{level}` নেয় (৬০ সে, সর্বোচ্চ ১৫ সে অপেক্ষা) এবং `CapacityManager.BookLevelCapacity` কল করে (আসন/পরিমাণ Redis hash `level_locked:*`-এ **লক** করে ১২ মিনিটের জন্য; লাইভ ক্যাপাসিটি কেবল পেমেন্টের পরে কমে, [S-01](../50-system-initiated/S-01-level-capacity-update.md));
   8. **দাম সার্ভারে হিসাব করে** ইভেন্ট সেটিংস (VAT অন্তর্ভুক্ত না উপরে, শতাংশ বা fixed), লেভেলের দাম, সিস্টেম ডিসকাউন্ট (`Discounts` টেবিল), প্রোমো কোড ([P-05](P-05-apply-promo-code.md)) এবং প্ল্যাটফর্ম (সার্ভিস) চার্জ থেকে; জমা করে `Vat`, `Discount`, `PromoDiscount`, `PlatformCharge`, `TotalCharge`, স্ট্যাটাস `Pending`, নতুন `PaymentTransactionId` (GUID), প্রোফাইল থেকে `OneIdUserId`;
   9. প্রতিটি টিকিটের জন্য একটি `BookedUserRecords` সারি জমা করে (পাঠানো হোল্ডারের নাম ও ফোন, বাকিগুলো ফাঁকা সারি);
   10. DgePay-এর কাছে চেকআউট লিংক চায় (`InitiateDgePayPayment`) এবং HTTP 201 সহ `{ publicId, checkoutUrl }` ফেরত দেয়। গেটওয়ে বেছে নেওয়ার কোড (`ResolvePaymentGateway`, SSLCommerz) **কমেন্ট করা**: প্রতিটি অর্ডার DgePay ব্যবহার করে ([Q-19](../99-open-queries.md#q-19))।
2. **[HTTP, static/encrypted] → DgePay:** `DgePayPaymentManager.InitiatePaymentAndGetCheckoutLink` প্রমাণীকরণ করে (`/payment_gateway/authenticate`, Basic client credentials), শরীরটি AES-এ এনক্রিপ্ট করে (পরিমাণ, ট্রানজেকশন আইডি, callback URL `DgePay:CallbackUrl`) এবং `/payment_gateway/initiate_payment`-এ পোস্ট করে; উত্তরের `WebViewUrl` হলো চেকআউট লিংক। যেকোনো ব্যর্থতা `null` ফেরত দেয় (শুধু লগ হয়)।
3. গ্রাহক DgePay-তে টাকা দেন। এরপর DgePay কল করে **[HTTP, no token]** `GET /booking/api/v1/user-booking-order/dgepay/payment-status?data=<AES-encrypted>` (anonymous)। `HandleDgePayment` ডেটা ডিক্রিপ্ট করে, `UniqueTxnId` দিয়ে অর্ডার খোঁজে, এবং:
   - স্ট্যাটাস **Paid** এবং অর্ডার ১২ মিনিটের কম বয়সী: প্রকাশ করে **[SQS: OrderSuccess]** (লেভেল ক্যাপাসিটি আপডেট, [S-01](../50-system-initiated/S-01-level-capacity-update.md)), স্ট্যাটাস বসায়, callback টেক্সট ও সময় সংরক্ষণ করে, Ticketing-কে `initiate-user-ticket` কল করে (টিকিট সারি তৈরি করে, [S-07](../50-system-initiated/S-07-initiate-user-ticket-generation.md)) এবং প্রকাশ করে **[SQS: VatChallanProcessing]** ([S-10](../50-system-initiated/S-10-vat-challan.md));
   - স্ট্যাটাস **Paid নয়**: লকড-ক্যাপাসিটি hash থেকে অর্ডারটি মুছে দেয়;
   - অর্ডার **১২ মিনিটের বেশি পুরোনো**: স্ট্যাটাস ও ক্যাপাসিটি বার্তা *প্রয়োগ* হয় না (অর্ডারটি ব্যাকগ্রাউন্ড বাতিলের জন্য থেকে থাকে); callback টেক্সট তবুও সংরক্ষিত হয়। এরপরের কোড বয়স দেখে না: একটি `Paid` callback-এও এটি এখনো `initiate-user-ticket` কল করে (যা প্রত্যাখ্যান করে কারণ অর্ডারটি `Paid` নয়, সতর্কতা হিসেবে লগ হয়) এবং **তবুও VAT চালানের বার্তা প্রকাশ করে** `[UNCONFIRMED: Q-15]`।
   এরপর অ্যাকশনটি প্রক্রিয়াকরণ ব্যর্থ হলেও **সবসময়** `DgePay:RedirectUrl`-এ 302 দেয় (এরর শুধু লগ হয়)।
4. ব্যাকগ্রাউন্ড: callback-এর সময়সীমার পরেও `Pending` থাকা অর্ডার DgePay-এর কাছে আবার যাচাই হয় (`check_transaction_status`) এবং অপরিশোধিত হলে বাতিল হয় ([S-05](../50-system-initiated/S-05-pending-failed-revalidation.md))।
5. **রিডাইরেক্টের পর পোর্টাল:** পোর্টাল রুট `tickets` (ভাষা ছাড়া) `/{savedLanguage}/tickets`-এ রিডাইরেক্ট করে ([P-07](P-07-my-bookings.md)); URL-এ কোনো পেমেন্ট ফলাফল পাঠানো হয় না, তালিকা স্ট্যাটাস সার্ভার থেকে পড়ে।
6. **টেস্ট/বাইপাস পথ:** `GET /booking/api/v1/user-booking-order/payment-status-bypass?rawData=<order public id>` **anonymous**, DgePay-কে জিজ্ঞাসা করে না, টেক্সট "BY PASS TRANSACTION - TEST" দিয়ে `Paid` জোর করে, OrderSuccess প্রকাশ করে এবং টিকিট শুরু করে ([X-18](../60-cross-cutting/X-18-endpoints-without-auth.md); এটি রিভিউয়ের সবচেয়ে গুরুত্বপূর্ণ ফলাফল)।

## 5. কম্পোনেন্ট

| ধরন | কম্পোনেন্ট |
|---|---|
| ক্লায়েন্ট | `tickets/components/complete-payment-modal`, `stadium-seat-page` (`openCompletePaymentModal`), `booking-api.service.ts:31-42` |
| সার্ভিস | Booking (`UserBookingOrderController`, `UserBookingOrderManager`, `CapacityManager`, `DgePayPaymentManager`); Event (`EventClient`-এর মাধ্যমে ইভেন্ট ও লেভেলের তথ্য); Ticketing (`initiate-user-ticket`); identity API (প্রোফাইল) |
| কিউ / ওয়ার্কার | SQS `OrderSuccess` → [S-01](../50-system-initiated/S-01-level-capacity-update.md); `VatChallanProcessing` → [S-10](../50-system-initiated/S-10-vat-challan.md); রি-চেক কাজ [S-05](../50-system-initiated/S-05-pending-failed-revalidation.md) |
| টেবিল | `UserBookingOrders`, `BookedUserRecords`, `Discounts` ও `PromoCodes` রিড |
| Redis | লক `user_booking:{userId}`, `level_booking_...`; hash `level_locked:{e}_{g}_{b}_{l}` ([X-25](../60-cross-cutting/X-25-redis.md)) |
| বাহ্যিক | DgePay (`authenticate`, `initiate_payment`, `check_transaction_status`); identity API |

## 6. API কন্ট্রাক্ট

| মেথড | পথ | অথ | রিকোয়েস্ট | রেসপন্স | প্রধান এরর |
|---|---|---|---|---|---|
| POST | `/booking/api/v1/user-booking-order` | User | `UserBookingOrder` (= `TicketPurchase`) | 201 `UserBookingOrderResponse { publicId, checkoutUrl }` | §4 ধাপ 1-এর 400 বার্তাগুলো |
| GET | `/booking/api/v1/user-booking-order/dgepay/payment-status` | anonymous (DgePay callback) | `data` (encrypted) | `DgePay:RedirectUrl`-এ 302 | কিছু ফেরত হয় না |
| GET | `/booking/api/v1/user-booking-order/payment-status-bypass` | **anonymous** | `rawData` (order public id) | 302 | কিছু ফেরত হয় না |

প্রধান নমুনা, `POST /booking/api/v1/user-booking-order` (নাম `UserBookingOrder` থেকে; মানগুলো কাল্পনিক; `totalCharge`, `pricePerSeat` ও `vat` শুধু চিহ্ন যাচাই করা হয়):

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

## 7. ডেটা ও পার্শ্বপ্রতিক্রিয়া

`UserBookingOrders` (`Pending`, পরে `Paid`), `BookedUserRecords`, Redis-এ আসনের লক, DgePay সেশন, তারপর (পেমেন্টের পর) SQS বার্তা, Ticketing-এ টিকিট সারি, একটি VAT বার্তা ও ক্যাপাসিটি পরিবর্তন। অ্যাক্টিভিটি লগ অর্ডারের পরিবর্তনগুলো রেকর্ড করে ([X-24](../60-cross-cutting/X-24-activity-logging.md))।

## 8. কোড রেফারেন্স

| কী | কোথায় |
|---|---|
| কন্ট্রোলার | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Service/Api/UserBookingOrderController.cs:43-86, 239-262` |
| তৈরি | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Domain/Managers/UserBookingOrderManager.cs:61-330` |
| Callback | `.../UserBookingOrderManager.cs:331-452` (DgePay), `495-545` (bypass) |
| যাচাই, গেটওয়ে | `.../UserBookingOrderManager.cs:562-760` |
| DgePay ক্লায়েন্ট | `rvl-gobcb-backend/Services/Booking/ETP.Booking.Domain/Managers/DgePayPaymentManager.cs:27-130, 188-265` |
| পোর্টাল | `rvl-gobcb-user-portal/ETP-Web/src/app/modules/featured/tickets/components/complete-payment-modal/complete-payment-modal.component.ts:37-58` |

## 9. হ্যান্ডওভার নোট

1. **যে কেউ অর্ডারের public id জানে তাকেই পরিশোধিত বানাতে পারে।** `payment-status-bypass` কোডে anonymous ও স্থায়ী; এটি টিকিট তৈরিও শুরু করে। প্রোডাকশনে ব্যবহারের আগে সরান বা সুরক্ষিত করুন ([X-18](../60-cross-cutting/X-18-endpoints-without-auth.md))। লোকালে এটি পেমেন্ট অনুকরণের সুবিধাজনক উপায় (§11)।
2. **চেকআউটের ব্যর্থতা গ্রাহকের চোখে পড়ে না।** DgePay লিংক না ফেরত করলে `checkoutUrl` হয় `null`; পোর্টাল কেবল URL থাকলেই কাজ করে, তাই পপ-আপটি কোনো বার্তা ছাড়াই লোডিং অবস্থায় আটকে থাকে (`loading` রিসেট হয় না)।
3. **১২ মিনিট পরের পরিশোধিত অর্ডার প্ল্যাটফর্মের কাছে হারিয়ে যায়।** দেরি করে আসা DgePay callback না স্ট্যাটাস আপডেট করে না, না ক্যাপাসিটি বাদ দেয়; টাকা নেওয়া হয়ে থাকতে পারে অথচ অর্ডারটি ব্যাকগ্রাউন্ড কাজ বাতিল করে ([S-05](../50-system-initiated/S-05-pending-failed-revalidation.md), `[UNCONFIRMED: Q-11]`)।
4. **দুই গ্রাহক একই আসন বাছাই করলে:** প্রথম অর্ডারটি লক নেয়; দ্বিতীয়টি `Unavailable seats: ...` বা ক্যাপাসিটি সংক্রান্ত বার্তা দিয়ে ব্যর্থ হয় ([P-04](P-04-seat-selection.md) নোট 2)। প্রত্যাখ্যাত কেনাকাটা ১২ মিনিটের লক মেয়াদোত্তীর্ণ না হওয়া পর্যন্ত আসন ধরে রাখে `[UNCONFIRMED: Q-37]`।
5. **সীমার যাচাই আলগা।** `order_limit_exceeded` কেবল তখনই ঘটে যখন গ্রাহকের কাছে ইতিমধ্যে `AllowableMaximumOrderPerUser`-এর চেয়ে *বেশি* অর্ডার থাকে (তাই সীমার চেয়ে একটি বেশি সম্ভব), আর `seat_limit_exceeded` গ্রাহক ইভেন্টের জন্য ইতিমধ্যে যে কোনো সময় বুক করা *সব* আসনের সাথে নতুনগুলোকে যোগ করে **প্রতি-অর্ডার** সর্বোচ্চ `AllowableMaximumSeatPerOrder`-এর সাথে তুলনা করে, ফলে সেই সেটিং প্রতি-গ্রাহক মোট হিসেবেও কাজ করে `[UNCONFIRMED: Q-38]`।
6. **সার্ভারের দাম প্রিভিউ থেকে আলাদা হতে পারে** ([P-04](P-04-seat-selection.md) নোট 1); শরিফ করা পরিমাণ ধাপ ৮-এ হিসাব করা `TotalCharge`।
7. **কোনো "পেমেন্ট চালিয়ে যান" নেই।** একটি pending অর্ডারের জন্য চেকআউট লিংক আবার তৈরি করার এন্ডপয়েন্ট কন্ট্রোলারে কমেন্ট করা (`UserBookingOrderController.cs:287`); DgePay পেজ বন্ধ করে দেওয়া গ্রাহককে আবার কিনতে হয়।
8. **Callback এনক্রিপ্ট করা বার্তাকে বিশ্বাস করে।** `HandleDgePayment` ডিক্রিপ্ট করা `data` থেকে স্ট্যাটাস নেয় (শেয়ার করা AES key) এবং `check_transaction_status` কল করে না; শুধু ব্যাকগ্রাউন্ড রি-চেক করে ([S-05](../50-system-initiated/S-05-pending-failed-revalidation.md))। key-টিকে পাসওয়ার্ডের মতোই সুরক্ষিত করুন ([X-26](../60-cross-cutting/X-26-configuration.md))।
9. **সবসময় রিডাইরেক্ট।** callback প্রক্রিয়াকরণের সময় কোনো ব্যর্থতা critical হিসেবে লগ হয় এবং গ্রাহককেও পোর্টালে পাঠানো হয়, যেখানে রি-চেক না হওয়া পর্যন্ত অর্ডারটি `Pending` দেখায়।
10. **সার্ভারের এরর বার্তা লেখা হিসেবে দেখায়** (`err.error.title`); `ticket_selling_stopped` বা `order_limit_exceeded`-এর মতো মেশিন কোড পোর্টাল অনুবাদ না করলে যেমন আছে তেমনই দেখায় `[UNCONFIRMED: Q-39]`।
11. **অর্ডারপ্রতি প্রোফাইল কল।** প্রতিটি অর্ডার identity API কল করে; সেটি বন্ধ থাকলে গ্রাহক কিনতে পারেন না (`Complete your profile first!` প্রোফাইল না থাকার বার্তাটিও এটিই)।

## 10. কম্পোনেন্ট সম্পর্ক

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

**নির্ভর করে:** [P-04](P-04-seat-selection.md), [P-05](P-05-apply-promo-code.md), [A-03](../10-admin-portal/A-03-program-settings.md) ও [A-08](../10-admin-portal/A-08-event-settings.md) (VAT, চার্জ, সীমা), [A-16](../10-admin-portal/A-16-discounts.md), [X-06](../60-cross-cutting/X-06-user-registration.md) (প্রোফাইল)। **প্রভাব ফেলে:** [P-07](P-07-my-bookings.md), [P-08](P-08-ticket-generation-request.md), [S-01](../50-system-initiated/S-01-level-capacity-update.md), [S-05](../50-system-initiated/S-05-pending-failed-revalidation.md), [S-07](../50-system-initiated/S-07-initiate-user-ticket-generation.md), [S-10](../50-system-initiated/S-10-vat-challan.md), [A-22](../10-admin-portal/A-22-reports.md), [A-23](../10-admin-portal/A-23-reconciliation.md)।

## 11. ডেভেলপার টেস্ট গাইড

**লোকাল টেস্টযোগ্যতা: আংশিক।** DgePay লোকালে ডামি, তাই প্রকৃত পেমেন্ট পেজ ও callback চলে না; অর্ডার তৈরি ও ক্যাপাসিটি লক চলে।

| আইটেম | বিবরণ |
|---|---|
| টেস্ট ডেটা ও অ্যাকাউন্ট | ইউজার `+8801700000011` / `Passw0rd!23` (প্রোফাইল সম্পূর্ণ); এই ব্যবহারকারীর জন্য নয়টি সিড করা অর্ডার (paid, pending, failed, cancelled) |
| ব্রাউজার | `http://localhost:4201/en/tickets/{eventId}/seats` → **Purchase** → **Pay**; ডামি চেকআউটে রিডাইরেক্ট ডিজাইন করেই ব্যর্থ হয়; Network-এর `user-booking-order` কল দেখুন (201 সহ `checkoutUrl`, বা 400) এবং নতুন `Pending` সারি |
| এমুলেটর | — (অ্যাপ লোকালে সাইন ইন করতে পারে না, [U-05](../30-user-app/U-05-booking-webview-payment.md)) |
| Postman | `postman/services/etp-booking.postman_collection.json`: "POST /api/v1/user-booking-order", "GET /api/v1/user-booking-order/dgepay/payment-status", "GET /api/v1/user-booking-order/payment-status-bypass" (`rawData` হিসেবে `publicId` দিয়ে লোকালে সফল পেমেন্ট অনুকরণ করুন; শেয়ার করা পরিবেশে এই এন্ডপয়েন্ট কখনো চালু করবেন না) |
| Visual Studio debug | `UserBookingOrderManager.CreateAsync` (যাচাই, `BookLevelCapacity`, দামের ধাপ ১-৭-এ ব্রেকপয়েন্ট), `HandleDgePayment`; Aspire AppHost থেকে Booking সার্ভিস |
| যাচাই | SQL: `select "OrderNumber","Status","TotalCharge","Vat","Discount","PromoDiscount","PlatformCharge","PaymentTransactionId" from etp."UserBookingOrders" order by "CreatedAt" desc limit 5`; Redis `HGETALL level_locked:{e}_{g}_{b}_{l}`; bypass কলের পর: Floci-তে SQS OrderSuccess বার্তা, স্ট্যাটাস `Paid` |
