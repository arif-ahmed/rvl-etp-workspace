-- 03-orders-tickets: bookings in every status, the people/tickets they produced, a complimentary ticket, raffle rows.
-- psql variables (set by Seed-EtpData.ps1 from Floci Cognito): :user_sub (User pool +8801700000011), :operator_sub (Admin pool +8801700000004)
-- Status: 0 Pending, 1 Failed, 2 Paid, 3 Cancelled.  PaymentGateway 1 = DgePay.
-- Money, series (VAT added on top, 15%, platform 2%):  Vat = 15% of (base - discounts), PlatformCharge = 2% of (base - discounts),
--   TotalCharge = base - discounts + Vat + PlatformCharge.
-- Money, BPL (VAT inclusive, platform 3%): Vat = base * 15/115 (already inside the price), TotalCharge = base + PlatformCharge.
-- Orders: 1-5 1st ODI (Mirpur) | 6 Test | 7 2nd ODI (Chattogram, promo) | 8 BPL Mirpur | 9 BPL Chattogram
SET search_path = etp;
BEGIN;

INSERT INTO "UserBookingOrders"
 ("Id","PublicId","OrderNumber","EventId","EventLongId","ProgramId","GalleryId","BlockId","LevelId","NumberOfSeats","HasSeats","Seats","PricePerSeat","Discount","PromoDiscount","PromoCode",
  "Vat","PlatformCharge","TotalCharge","IsVatInclusive","VatIncludedBasePricePerSeat","Status","PaymentGateway","PaymentTransactionId","PaymentInfo","CallbackReceivedAt","CancelledAt","IsTicketStatusNotified","UserId",
  "CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 -- 1 Paid: 1st ODI, Pavilion Row A, A1+A2, early bird 10% (600)
 (1,'44444444-4444-4444-8444-000000000001','ORD-LOCAL-0001','11111111-1111-4111-8111-000000000002',2,1,1,1,1,2,true,'A1,A2',3000,600,0,null,
  810,108,6318,false,3000,2,1,'DGE-LOCAL-0001','{"status":1,"unique_txn_id":"DGE-LOCAL-0001","amount":6318}',now() - interval '2 days',null,true,:'user_sub',now() - interval '2 days','seed',true,false),
 -- 2 Pending: 1st ODI, Row A, A3 (seat locked in Capacities), awaiting payment
 (2,'44444444-4444-4444-8444-000000000002','ORD-LOCAL-0002','11111111-1111-4111-8111-000000000002',2,1,1,1,1,1,true,'A3',3000,300,0,null,
  405,54,3159,false,3000,0,1,null,null,null,null,false,:'user_sub',now() - interval '5 minutes','seed',true,false),
 -- 3 Paid: 1st ODI, Grand Stand general admission, 3 seats
 (3,'44444444-4444-4444-8444-000000000003','ORD-LOCAL-0003','11111111-1111-4111-8111-000000000002',2,1,2,2,3,3,false,null,500,0,0,null,
  225,30,1755,false,500,2,1,'DGE-LOCAL-0002','{"status":1,"unique_txn_id":"DGE-LOCAL-0002","amount":1755}',now() - interval '1 day',null,true,:'user_sub',now() - interval '1 day','seed',true,false),
 -- 4 Failed: 1st ODI, Row B, B1+B2, payment declined (seats released)
 (4,'44444444-4444-4444-8444-000000000004','ORD-LOCAL-0004','11111111-1111-4111-8111-000000000002',2,1,1,1,2,2,true,'B1,B2',2000,0,0,null,
  600,80,4680,false,2000,1,1,'DGE-LOCAL-0003','{"status":0,"unique_txn_id":"DGE-LOCAL-0003","message":"declined"}',now() - interval '3 hours',null,false,:'user_sub',now() - interval '3 hours','seed',true,false),
 -- 5 Cancelled: 1st ODI, Row B, B3 (seat released)
 (5,'44444444-4444-4444-8444-000000000005','ORD-LOCAL-0005','11111111-1111-4111-8111-000000000002',2,1,1,1,2,1,true,'B3',2000,0,0,null,
  300,40,2340,false,2000,3,1,null,null,null,now() - interval '1 hour',false,:'user_sub',now() - interval '2 hours','seed',true,false),
 -- 6 Paid: Test (5 days, multi-segment ticket), Grand Stand, 2 seats
 (6,'44444444-4444-4444-8444-000000000006','ORD-LOCAL-0006','11111111-1111-4111-8111-000000000001',1,1,2,2,3,2,false,null,500,0,0,null,
  150,20,1170,false,500,2,1,'DGE-LOCAL-0004','{"status":1,"unique_txn_id":"DGE-LOCAL-0004","amount":1170}',now() - interval '6 hours',null,true,:'user_sub',now() - interval '6 hours','seed',true,false),
 -- 7 Paid: 2nd ODI, Chattogram Pavilion Row A, A1+A2, promo BCBWELCOME10 (10% of 5000)
 (7,'44444444-4444-4444-8444-000000000007','ORD-LOCAL-0007','11111111-1111-4111-8111-000000000003',3,1,4,4,5,2,true,'A1,A2',2500,0,500,'BCBWELCOME10',
  675,90,5265,false,2500,2,1,'DGE-LOCAL-0005','{"status":1,"unique_txn_id":"DGE-LOCAL-0005","amount":5265}',now() - interval '4 hours',null,true,:'user_sub',now() - interval '4 hours','seed',true,false),
 -- 8 Paid: BPL Mirpur, General, 4 seats (VAT inclusive: 1200 incl. 156.52 VAT)
 (8,'44444444-4444-4444-8444-000000000008','ORD-LOCAL-0008','11111111-1111-4111-8111-000000000005',5,2,2,2,3,4,false,null,300,0,0,null,
  156.52,36,1236,true,260.87,2,1,'DGE-LOCAL-0006','{"status":1,"unique_txn_id":"DGE-LOCAL-0006","amount":1236}',now() - interval '3 hours',null,true,:'user_sub',now() - interval '3 hours','seed',true,false),
 -- 9 Paid: BPL Chattogram, Pavilion Row A, A5 (VAT inclusive: 1200 incl. 156.52 VAT)
 (9,'44444444-4444-4444-8444-000000000009','ORD-LOCAL-0009','11111111-1111-4111-8111-000000000006',6,2,4,4,5,1,true,'A5',1200,0,0,null,
  156.52,36,1236,true,1043.48,2,1,'DGE-LOCAL-0007','{"status":1,"unique_txn_id":"DGE-LOCAL-0007","amount":1236}',now() - interval '2 hours',null,true,:'user_sub',now() - interval '2 hours','seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

-- one record per paid order (the buyer, as shown to admins/support)
INSERT INTO "BookedUserRecords" ("Id","UserBookingOrderId","ProgramId","EventId","EventLongId","OrderNumber","PricePerSeat","UserName","PhoneNumber","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
SELECT o."Id", o."Id", o."ProgramId", o."EventId", o."EventLongId", o."OrderNumber", o."PricePerSeat", 'Local User', '+8801700000011', o."CreatedAt", 'seed', true, false
FROM "UserBookingOrders" o WHERE o."Status" = 2 AND o."Id" < 100
ON CONFLICT ("Id") DO NOTHING;

-- tickets for the paid orders (Status: 0 Active, 1 Requested, 2 Generated). Seat is null for general admission.
-- numbering is per program prefix: BDI-L-nnnnnn (series), BPL-L-nnnnnn (tournament)
INSERT INTO "Tickets"
 ("Id","BookingOrderId","BookingOrderPublicId","EventId","EventLongId","GalleryId","BlockId","LevelId","TicketNumber","Seat","EntryGates","MiniGates","TicketType","TicketHolderName","Status","SignedTicketUrl","BlankTicketUrl",
  "CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,'44444444-4444-4444-8444-000000000001','11111111-1111-4111-8111-000000000002',2,1,1,1,'BDI-L-000001','A1','Gate 1','Mini Gate A','Online','Local User',2,'etp-local/seed/tickets/BDI-L-000001.pdf','etp-local/seed/tickets/blank-bdi.pdf',now() - interval '2 days','seed',true,false),
 (2,1,'44444444-4444-4444-8444-000000000001','11111111-1111-4111-8111-000000000002',2,1,1,1,'BDI-L-000002','A2','Gate 1','Mini Gate A','Online','Local User',2,'etp-local/seed/tickets/BDI-L-000002.pdf','etp-local/seed/tickets/blank-bdi.pdf',now() - interval '2 days','seed',true,false),
 (3,3,'44444444-4444-4444-8444-000000000003','11111111-1111-4111-8111-000000000002',2,2,2,3,'BDI-L-000003',null,'Gate 5',null,'Online','Local User',0,null,null,now() - interval '1 day','seed',true,false),
 (4,3,'44444444-4444-4444-8444-000000000003','11111111-1111-4111-8111-000000000002',2,2,2,3,'BDI-L-000004',null,'Gate 5',null,'Online','Local User',0,null,null,now() - interval '1 day','seed',true,false),
 (5,3,'44444444-4444-4444-8444-000000000003','11111111-1111-4111-8111-000000000002',2,2,2,3,'BDI-L-000005',null,'Gate 5',null,'Online','Local User',0,null,null,now() - interval '1 day','seed',true,false),
 (6,6,'44444444-4444-4444-8444-000000000006','11111111-1111-4111-8111-000000000001',1,2,2,3,'BDI-L-000006',null,'Gate 5',null,'Online','Local User',1,null,null,now() - interval '6 hours','seed',true,false),
 (7,6,'44444444-4444-4444-8444-000000000006','11111111-1111-4111-8111-000000000001',1,2,2,3,'BDI-L-000007',null,'Gate 5',null,'Online','Local User',1,null,null,now() - interval '6 hours','seed',true,false),
 (8,7,'44444444-4444-4444-8444-000000000007','11111111-1111-4111-8111-000000000003',3,4,4,5,'BDI-L-000008','A1','Gate A','Mini Gate A','Online','Local User',2,'etp-local/seed/tickets/BDI-L-000008.pdf','etp-local/seed/tickets/blank-bdi.pdf',now() - interval '4 hours','seed',true,false),
 (9,7,'44444444-4444-4444-8444-000000000007','11111111-1111-4111-8111-000000000003',3,4,4,5,'BDI-L-000009','A2','Gate A','Mini Gate A','Online','Local User',2,'etp-local/seed/tickets/BDI-L-000009.pdf','etp-local/seed/tickets/blank-bdi.pdf',now() - interval '4 hours','seed',true,false),
 (10,8,'44444444-4444-4444-8444-000000000008','11111111-1111-4111-8111-000000000005',5,2,2,3,'BPL-L-000001',null,'Gate 5',null,'Online','Local User',0,null,null,now() - interval '3 hours','seed',true,false),
 (11,8,'44444444-4444-4444-8444-000000000008','11111111-1111-4111-8111-000000000005',5,2,2,3,'BPL-L-000002',null,'Gate 5',null,'Online','Local User',0,null,null,now() - interval '3 hours','seed',true,false),
 (12,8,'44444444-4444-4444-8444-000000000008','11111111-1111-4111-8111-000000000005',5,2,2,3,'BPL-L-000003',null,'Gate 5',null,'Online','Local User',0,null,null,now() - interval '3 hours','seed',true,false),
 (13,8,'44444444-4444-4444-8444-000000000008','11111111-1111-4111-8111-000000000005',5,2,2,3,'BPL-L-000004',null,'Gate 5',null,'Online','Local User',0,null,null,now() - interval '3 hours','seed',true,false),
 (14,9,'44444444-4444-4444-8444-000000000009','11111111-1111-4111-8111-000000000006',6,4,4,5,'BPL-L-000005','A5','Gate A','Mini Gate A','Online','Local User',2,'etp-local/seed/tickets/BPL-L-000005.pdf','etp-local/seed/tickets/blank-bpl.pdf',now() - interval '2 hours','seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

-- complimentary ticket issued by the ticket operator from reservation 1 (B9, 1st ODI)
INSERT INTO "OfflineSoldTickets" ("Id","UserId","EventId","EventLongId","GalleryId","BlockId","LevelId","ReservationId","ReservationPublicId","TicketNumber","TicketHolderIdentification","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,:'operator_sub','11111111-1111-4111-8111-000000000002',2,1,1,2,1,'33333333-3333-4333-8333-000000000001','BDI-L-C00001','NID-1234567890',now() - interval '1 day','seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

-- raffle entries for the two Row A tickets of order 1
INSERT INTO "RaffleDraws" ("Id","TicketNumber","TicketType","UserId","TicketHolderName","EventLongId","EventPublicId","BookingOrderId","BookingOrderPublicId","BookingOrderDateTime","OrderNumber","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,'BDI-L-000001','Online',:'user_sub','Local User',2,'11111111-1111-4111-8111-000000000002',1,'44444444-4444-4444-8444-000000000001',now() - interval '2 days','ORD-LOCAL-0001',now(),'seed',true,false),
 (2,'BDI-L-000002','Online',:'user_sub','Local User',2,'11111111-1111-4111-8111-000000000002',1,'44444444-4444-4444-8444-000000000001',now() - interval '2 days','ORD-LOCAL-0001',now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

COMMIT;
