# 50 · System-initiated (workers and queues)

Work no person starts directly: background workers on timers and SQS queue consumers.

[Back to contents](../README.md)

## Sign-in and access

- [X-18 Endpoints without authorization](../60-cross-cutting/X-18-endpoints-without-auth.md)
- [X-19 Service-to-service communication](../60-cross-cutting/X-19-service-to-service.md)
- [X-25 Redis: cache, live capacity and locks](../60-cross-cutting/X-25-redis.md)

## Features in this section

| ID | Feature | Purpose |
|---|---|---|
| S-01 | [Level capacity update (OrderSuccess queue)](S-01-level-capacity-update.md) | Apply booked/released seats to level capacity after order events. |
| S-02 | [Event live capacity (EventCapacity queue)](S-02-event-live-capacity.md) | Recompute an event's live capacity after capacity changes. |
| S-03 | [Locked-capacity refresh](S-03-locked-capacity-refresh.md) | Release seats locked by unpaid orders after they expire. |
| S-04 | [Scheduler capacity reconcile](S-04-scheduler-capacity-update.md) | Periodic capacity reconciliation triggered from the Scheduler service. |
| S-05 | [Pending/failed payment revalidation](S-05-pending-failed-revalidation.md) | Re-check unfinished payments with DgePay and update order status. |
| S-06 | [Booking status → Generated](S-06-booking-status-generated.md) | Mark orders Generated once all their tickets exist. |
| S-07 | [Initiate user ticket generation](S-07-initiate-user-ticket-generation.md) | Start ticket generation for paid orders that requested it. |
| S-08 | [Ticket signing via TSP (TicketSigning queue)](S-08-ticket-signing.md) | Digitally sign ticket PDFs through the TSP and store them in S3. |
| S-09 | [Reserved ticket merge/zip (TicketProcessing queue)](S-09-ticket-merge-zip.md) | Merge or zip a reservation's signed tickets in the Utility service. |
| S-10 | [VAT challan with NBR (VatChallanProcessing queue)](S-10-vat-challan.md) | Record VAT for paid orders and download the challan from NBR. |
| S-11 | [Push delivery to FCM (FirebaseNotification queue)](S-11-firebase-notification.md) | Deliver queued push messages through Firebase Cloud Messaging. |
| S-12 | [Ticket-generated notification](S-12-ticket-generated-notification.md) | Tell customers their tickets are ready. |
| S-13 | [Device-token cleanup](S-13-device-token-cleanup.md) | Daily removal of stale device tokens. |
| S-14 | [Checked-ticket sync (Redis → database)](S-14-checked-ticket-sync.md) | Persist gate scans collected in Redis to the database. |
| S-15 | [Gate download-status cleanup](S-15-gate-download-status-cleanup.md) | Reset checker download flags on a schedule. |
| S-16 | [Promo-code status update](S-16-promo-code-status.md) | Activate/expire promo codes by their dates. |
| S-17 | [System-discount status update](S-17-discount-status.md) | Activate/expire system discounts by their dates. |
