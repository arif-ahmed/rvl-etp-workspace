-- 02-inventory: seat inventory per match and level (Booking's Capacities), capacity adjustments, reservations.
-- Capacities.EventId is Events."Id" (bigint); Capacities.Id = EventVenueDetails.Id (match * 10 + level).
-- Seats = seats still on offer (sold seats are removed), TicketingCapacity = how many are on offer, LockedSeats = held by a pending
-- order or a reservation (still listed in Seats). Must stay consistent with 03-orders-tickets.sql:
--   sold: match 2 A1,A2 + 3 general | match 1 2 general | match 3 A1,A2 | match 5 4 general | match 6 A5
--   locked: match 2 A3 (pending order), B9,B10 (complimentary reservation)
--   taken out of the online pool: match 2 Student Enclosure (300, partner reservation) -> sold out online;
--                                 match 7 General (275 of 300, partner/hospitality) -> 25 left = limited availability (< 10%)
SET search_path = etp;
BEGIN;

INSERT INTO "Capacities" ("Id","EventId","GalleryId","BlockId","LevelId","TicketingCapacity","HasSeats","Seats","LockedSeats","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
SELECT d."Id", d."EventId", d."VenueGallaryId", d."GalleryBlockId", d."BlockLevelId",
       COALESCE(o.cap, d."SeatingCapacity"), d."HasSeats", COALESCE(o.seats, d."Seats"), o.locked, now(),'seed',true,false
FROM "EventVenueDetails" d
LEFT JOIN (VALUES
   (2, 1,  8, 'A3,A4,A5,A6,A7,A8,A9,A10', 'A3'),
   (2, 2, 10, 'B1,B2,B3,B4,B5,B6,B7,B8,B9,B10', 'B9,B10'),
   (2, 3, 497, NULL, NULL),
   (2, 4, 0,   NULL, NULL),
   (1, 3, 498, NULL, NULL),
   (3, 5,  8, 'A3,A4,A5,A6,A7,A8,A9,A10', NULL),
   (5, 3, 496, NULL, NULL),
   (6, 5,  9, 'A1,A2,A3,A4,A6,A7,A8,A9,A10', NULL),
   (7, 8, 25,  NULL, NULL)
) AS o(ev, lvl, cap, seats, locked) ON o.ev = d."EventId" AND o.lvl = d."BlockLevelId"
WHERE d."Id" < 100
ON CONFLICT ("Id") DO NOTHING;

-- initial allocation of every level to the online ticketing pool
INSERT INTO "EventCapacityAdjustments" ("Id","ProgramId","EventId","GalleryId","BlockId","LevelId","AdjustmentNumber","TicketingCapacity","Action","HasSeats","Seats","PublicId","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
SELECT d."Id", d."ProgramId", d."EventId", d."VenueGallaryId", d."GalleryBlockId", d."BlockLevelId",
       'ADJ-LOCAL-' || lpad(d."Id"::text, 4, '0'), d."SeatingCapacity", 0, d."HasSeats", d."Seats", md5('adj-' || d."Id")::uuid, now(),'seed',true,false
FROM "EventVenueDetails" d WHERE d."Id" < 100
ON CONFLICT ("Id") DO NOTHING;

-- Action 1 = Deallocate: seats moved out of the online pool
INSERT INTO "EventCapacityAdjustments" ("Id","ProgramId","EventId","GalleryId","BlockId","LevelId","AdjustmentNumber","TicketingCapacity","Action","HasSeats","Seats","PublicId","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (91,1,2,3,3,4,'ADJ-LOCAL-0091',300,1,false,null,md5('adj-91')::uuid,now(),'seed',true,false),
 (92,2,7,7,7,8,'ADJ-LOCAL-0092',275,1,false,null,md5('adj-92')::uuid,now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

-- Type 0 = Complimentary, 1 = Partner; Action 0 = Reserved; Status 1 = Generated; ReservationCategory 0 = DigitalPrint, 1 = Printing
INSERT INTO "SeatReservations" ("Id","ProgramId","EventId","GalleryId","BlockId","LevelId","ReservationNumber","NumberOfSeats","RemainingReservedSeat","Action","Type","Status","ReservationCategory","HasSeats","Seats","PublicId","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 -- complimentary: B9,B10 of the 1st ODI held for guests, one already issued (OfflineSoldTickets in 03)
 (1,1,2,1,1,2,'RSV-LOCAL-0001',2,1,0,0,1,0,true,'B9,B10','33333333-3333-4333-8333-000000000001',now(),'seed',true,false),
 -- partner: the whole Student Enclosure of the 1st ODI handed to a partner (university federation), printed tickets
 (2,1,2,3,3,4,'RSV-LOCAL-0002',300,300,0,1,1,1,false,null,'33333333-3333-4333-8333-000000000002',now(),'seed',true,false),
 -- hospitality block of the Sylhet BPL match
 (3,2,7,7,7,8,'RSV-LOCAL-0003',275,275,0,1,1,0,false,null,'33333333-3333-4333-8333-000000000003',now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

COMMIT;
