-- 01-catalog: BCB cricket catalogue. Reference data, 2 programs (a bilateral series and a franchise tournament), teams,
-- 3 grounds (gallery > block > level + gates), 7 matches, per-level price/capacity, promotions, landing page.
-- Idempotent: fixed Ids + ON CONFLICT DO NOTHING. Run through scripts/Seed-EtpData.ps1 (psql -v ON_ERROR_STOP=1).
-- Seed Ids are below 100 (the script bumps every identity sequence to 99+ at the end), so API-created rows never collide.
-- Names of grounds are real; stand names/layouts, fixtures and prices are SAMPLE data, not the real schedule or tariff.
SET search_path = etp;
BEGIN;

-- ---- reference ---------------------------------------------------------------------------------
INSERT INTO "Currencies" ("Id","Name","Code","Sign","IsDefault","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
VALUES (1,'Bangladeshi Taka','BDT','৳',true,now(),'seed',true,false) ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "SystemSettings" ("Id","AllowUserSignInWithUserPassword","SeatLockTimeout","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
VALUES (1,true,300,now(),'seed',true,false) ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "HeaderFooter" ("Id","Title","PhoneNumber","Email","OfficeAddress","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
VALUES (1,'BCB Tickets (local)','+8801700000000','support@etp.local','Dhaka, Bangladesh (local seed)',now(),'seed',true,false) ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "SocialMediaSettings" ("Id","FacebookUrl","InstagramUrl","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
VALUES (1,'https://facebook.com/etp.local','https://instagram.com/etp.local',now(),'seed',true,false) ON CONFLICT ("Id") DO NOTHING;

-- ---- programs (Cognito users carry custom:program_ids = 1,2) -------------------------------------
--  1 = bilateral series (Test + ODIs + T20I)  | 2 = franchise tournament (BPL)
INSERT INTO "Programs" ("Id","Name","ShortName","Logo","StartDateTime","EndDateTime","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,'Bangladesh vs India Series','BDI','etp-local/seed/programs/bdi.png',now() - interval '10 days', now() + interval '40 days',now(),'seed',true,false),
 (2,'Bangladesh Premier League','BPL','etp-local/seed/programs/bpl.png',now() + interval '20 days', now() + interval '70 days',now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

-- series: 15% VAT added on top, 2% platform charge | tournament: prices include 15% VAT, 3% platform charge
INSERT INTO "ProgramSettings" ("Id","ProgramId","AllowableMaximumOrderPerUser","AllowableMaximumSeatPerOrder","TicketSellingStartFromHour","TicketSellingStopFromHour","TicketAvailableFromHour",
  "IsVatPercentage","Vat","IsServiceChargePercentage","ServiceCharge","IsVatInclusive","LimitedAvailabilityThreshold","TicketNumberPrefix","PaymentGateway","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,5,4,336,1,2,true,15,true,2,false,10,'BDI',1,now(),'seed',true,false),
 (2,2,5,6,336,1,2,true,15,true,3,true, 10,'BPL',1,now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "ProgramTeams" ("Id","ProgramId","Name","ShortName","Logo","Flag","IsFlag","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,'Bangladesh','BAN','etp-local/seed/teams/ban.png','etp-local/seed/flags/ban.png',true,now(),'seed',true,false),
 (2,1,'India','IND','etp-local/seed/teams/ind.png','etp-local/seed/flags/ind.png',true,now(),'seed',true,false),
 (3,2,'Dhaka Capitals','DHC','etp-local/seed/teams/dhc.png',null,false,now(),'seed',true,false),
 (4,2,'Chattogram Challengers','CHC','etp-local/seed/teams/chc.png',null,false,now(),'seed',true,false),
 (5,2,'Rangpur Riders','RGR','etp-local/seed/teams/rgr.png',null,false,now(),'seed',true,false),
 (6,2,'Sylhet Strikers','SYS','etp-local/seed/teams/sys.png',null,false,now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "GeneralNotices" ("Id","ProgramId","Description","StartDateTime","EndDateTime","IsPublished","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,'Gates open 3 hours before the first ball. Carry a valid ID; no outside food, bags or flags with poles.',now() - interval '5 days', now() + interval '40 days',true,now(),'seed',true,false),
 (2,2,'BPL ticket sales open soon. Tickets are not transferable.',now() - interval '1 days', now() + interval '70 days',true,now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "TicketAttributes" ("Id","ProgramId","CreatedAt") OVERRIDING SYSTEM VALUE VALUES (1,1,now()),(2,2,now())
ON CONFLICT ("Id") DO NOTHING;

-- ---- grounds -----------------------------------------------------------------------------------------
--  1 Sher-e-Bangla National Cricket Stadium (Mirpur, Dhaka)   2 Zahur Ahmed Chowdhury Stadium (Chattogram)   3 Sylhet International Cricket Stadium
INSERT INTO "Venues" ("Id","Name","ShortName","Type","Location","SvgMapImage","TotalCapacity","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,'Sher-e-Bangla National Cricket Stadium','SBNCS','Stadium','Mirpur, Dhaka','etp-local/seed/venues/sbncs.svg',820,now(),'seed',true,false),
 (2,'Zahur Ahmed Chowdhury Stadium','ZACS','Stadium','Chattogram','etp-local/seed/venues/zacs.svg',410,now(),'seed',true,false),
 (3,'Sylhet International Cricket Stadium','SICS','Stadium','Sylhet','etp-local/seed/venues/sics.svg',310,now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

-- galleries: 1 Pavilion(seated) 2 Grand Stand 3 Student Enclosure | 4 Pavilion 5 General Stand | 6 Pavilion 7 General Stand
INSERT INTO "VenueGalleries" ("Id","VenueId","Name","SeatType","IsSeatMapped","IsSellable","SvgKey","TicketColor","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,'Pavilion','Seated',true,true,'etp-local/seed/venues/sbncs-pavilion.svg','#1E88E5',now(),'seed',true,false),
 (2,1,'Grand Stand','Standing',false,true,null,'#43A047',now(),'seed',true,false),
 (3,1,'Student Enclosure','Standing',false,true,null,'#FB8C00',now(),'seed',true,false),
 (4,2,'Pavilion','Seated',true,true,'etp-local/seed/venues/zacs-pavilion.svg','#1E88E5',now(),'seed',true,false),
 (5,2,'General Stand','Standing',false,true,null,'#43A047',now(),'seed',true,false),
 (6,3,'Pavilion','Seated',true,true,'etp-local/seed/venues/sics-pavilion.svg','#1E88E5',now(),'seed',true,false),
 (7,3,'General Stand','Standing',false,true,null,'#43A047',now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "GalleryBlocks" ("Id","VenueId","VenueGalleryId","Name","IsSeatMapped","IsSellable","SvgKey","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,1,'Pavilion Block',true,true,'etp-local/seed/venues/sbncs-pavilion-block.svg',now(),'seed',true,false),
 (2,1,2,'East Stand',false,true,null,now(),'seed',true,false),
 (3,1,3,'Student Block',false,true,null,now(),'seed',true,false),
 (4,2,4,'Pavilion Block',true,true,'etp-local/seed/venues/zacs-pavilion-block.svg',now(),'seed',true,false),
 (5,2,5,'North Stand',false,true,null,now(),'seed',true,false),
 (6,3,6,'Pavilion Block',true,true,'etp-local/seed/venues/sics-pavilion-block.svg',now(),'seed',true,false),
 (7,3,7,'West Stand',false,true,null,now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

-- levels: 1 Row A, 2 Row B (10 seats each), 3 General 500, 4 Student 300 | 5 Row A 10, 6 General 400 | 7 Row A 10, 8 General 300
INSERT INTO "BlockLevels" ("Id","VenueId","VenueGalleryId","GalleryBlockId","Name","SeatingCapacity","IsSeatMapped","IsSellable","HasSeats","Seats","SvgKey","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,1,1,'Row A',10,true,true,true,'A1,A2,A3,A4,A5,A6,A7,A8,A9,A10','etp-local/seed/venues/sbncs-row-a.svg',now(),'seed',true,false),
 (2,1,1,1,'Row B',10,true,true,true,'B1,B2,B3,B4,B5,B6,B7,B8,B9,B10','etp-local/seed/venues/sbncs-row-b.svg',now(),'seed',true,false),
 (3,1,2,2,'General',500,false,true,false,null,null,now(),'seed',true,false),
 (4,1,3,3,'Student Enclosure',300,false,true,false,null,null,now(),'seed',true,false),
 (5,2,4,4,'Row A',10,true,true,true,'A1,A2,A3,A4,A5,A6,A7,A8,A9,A10','etp-local/seed/venues/zacs-row-a.svg',now(),'seed',true,false),
 (6,2,5,5,'General',400,false,true,false,null,null,now(),'seed',true,false),
 (7,3,6,6,'Row A',10,true,true,true,'A1,A2,A3,A4,A5,A6,A7,A8,A9,A10','etp-local/seed/venues/sics-row-a.svg',now(),'seed',true,false),
 (8,3,7,7,'General',300,false,true,false,null,null,now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "GalleryBlockEntryGates" ("Id","GalleryBlockId","Name","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,'Gate 1',now(),'seed',true,false),(2,2,'Gate 5',now(),'seed',true,false),(3,3,'Gate 7',now(),'seed',true,false),
 (4,4,'Gate A',now(),'seed',true,false),(5,5,'Gate C',now(),'seed',true,false),
 (6,6,'Gate 1',now(),'seed',true,false),(7,7,'Gate 3',now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "BlockLevelEntryGates" ("Id","VenueId","VenueGalleryId","GalleryBlockId","BlockLevelId","Name","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,1,1,1,'Gate 1',now(),'seed',true,false),(2,1,1,1,2,'Gate 1',now(),'seed',true,false),
 (3,1,2,2,3,'Gate 5',now(),'seed',true,false),(4,1,3,3,4,'Gate 7',now(),'seed',true,false),
 (5,2,4,4,5,'Gate A',now(),'seed',true,false),(6,2,5,5,6,'Gate C',now(),'seed',true,false),
 (7,3,6,6,7,'Gate 1',now(),'seed',true,false),(8,3,7,7,8,'Gate 3',now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "BlockLevelMiniGates" ("Id","VenueId","VenueGalleryId","GalleryBlockId","BlockLevelId","Name","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,1,1,1,'Mini Gate A',now(),'seed',true,false),(2,1,1,1,2,'Mini Gate A',now(),'seed',true,false),(3,2,4,4,5,'Mini Gate A',now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

-- both programs use all three grounds
INSERT INTO "ProgramVenues" ("Id","ProgramId","VenueId","SVGMapImage","IsSynced","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
SELECT (p-1)*3 + v, p, v, 'etp-local/seed/venues/' || lower(vn."ShortName") || '.svg', true, now(),'seed',true,false
FROM generate_series(1,2) p CROSS JOIN generate_series(1,3) v JOIN "Venues" vn ON vn."Id"=v
ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "TicketLayoutConfigs" ("Id","TicketLayoutName","ProgramId","VenueId","IsPublished","SingleSegmentUserTicketUrl","MultipleSegmentUserTicketUrl","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
SELECT (p-1)*3 + v, vn."ShortName" || ' ticket layout', p, v, true,
       'etp-local/seed/layouts/single.svg', 'etp-local/seed/layouts/multi.svg', now(),'seed',true,false
FROM generate_series(1,2) p CROSS JOIN generate_series(1,3) v JOIN "Venues" vn ON vn."Id"=v
ON CONFLICT ("Id") DO NOTHING;

-- ---- price + capacity per level and program (template; copied to each match below) ---------------------
--  series (VAT on top): Pavilion Row A 3000 / Row B 2000, General 500, Student 200; Ctg 2500 / 400; Sylhet 2500 / 400
--  BPL (VAT inclusive): 1500 / 1000, 300, 100;                                       Ctg 1200 / 250; Sylhet 1200 / 250
INSERT INTO "ProgramVenueDetails" ("Id","ProgramId","VenueId","VenueGallaryId","IsGalleryActive","IsSeatMappedInGallery","IsGallerySellable","GalleryBlockId","IsBlockActive","IsSeatMappedInBlock","IsBlockSellable",
  "BlockLevelId","IsLevelActive","IsSeatMappedInLevel","IsLevelSellable","CurrencyId","SeatingCapacity","PricePerSeat","HasSeats","Seats","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
SELECT (v.prog-1)*10 + l."Id", v.prog, l."VenueId", l."VenueGalleryId", true, g."IsSeatMapped", true, l."GalleryBlockId", true, b."IsSeatMapped", true,
       l."Id", true, l."IsSeatMapped", true, 1, l."SeatingCapacity", v.price, l."HasSeats", l."Seats", now(),'seed',true,false
FROM (VALUES (1,1,3000),(1,2,2000),(1,3,500),(1,4,200),(1,5,2500),(1,6,400),(1,7,2500),(1,8,400),
             (2,1,1500),(2,2,1000),(2,3,300),(2,4,100),(2,5,1200),(2,6,250),(2,7,1200),(2,8,250)) AS v(prog,lvl,price)
JOIN "BlockLevels" l ON l."Id"=v.lvl JOIN "VenueGalleries" g ON g."Id"=l."VenueGalleryId" JOIN "GalleryBlocks" b ON b."Id"=l."GalleryBlockId"
ON CONFLICT ("Id") DO NOTHING;

-- ---- matches (public EventId is a GUID: Booking/Ticketing store it as uuid) ------------------------------
--  1 Test, 5 days, Mirpur (multi-segment) | 2 ODI at Mirpur, LIVE TODAY | 3 ODI Chattogram | 4 T20I Sylhet, draft (unpublished)
--  5 BPL Mirpur | 6 BPL Chattogram | 7 BPL Sylhet (limited availability)
INSERT INTO "Events" ("Id","EventId","Name","ProgramId","VenueId","StartDateTime","EndDateTime","EventCoverImage","IsPublished","IsVatInclusive","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,'11111111-1111-4111-8111-000000000001','Bangladesh vs India - Test (5 days)',1,1,now() + interval '20 days', now() + interval '24 days 8 hours','etp-local/seed/events/e1.jpg',true,false,now(),'seed',true,false),
 (2,'11111111-1111-4111-8111-000000000002','Bangladesh vs India - 1st ODI',1,1,now() - interval '1 hour', now() + interval '7 hours','etp-local/seed/events/e2.jpg',true,false,now(),'seed',true,false),
 (3,'11111111-1111-4111-8111-000000000003','Bangladesh vs India - 2nd ODI',1,2,now() + interval '3 days', now() + interval '3 days 8 hours','etp-local/seed/events/e3.jpg',true,false,now(),'seed',true,false),
 (4,'11111111-1111-4111-8111-000000000004','Bangladesh vs India - 1st T20I (draft)',1,3,now() + interval '14 days', now() + interval '14 days 5 hours','etp-local/seed/events/e4.jpg',false,false,now(),'seed',true,false),
 (5,'11111111-1111-4111-8111-000000000005','BPL - Dhaka Capitals vs Chattogram Challengers',2,1,now() + interval '30 days', now() + interval '30 days 5 hours','etp-local/seed/events/e5.jpg',true,true,now(),'seed',true,false),
 (6,'11111111-1111-4111-8111-000000000006','BPL - Rangpur Riders vs Sylhet Strikers',2,2,now() + interval '32 days', now() + interval '32 days 5 hours','etp-local/seed/events/e6.jpg',true,true,now(),'seed',true,false),
 (7,'11111111-1111-4111-8111-000000000007','BPL - Sylhet Strikers vs Dhaka Capitals',2,3,now() + interval '34 days', now() + interval '34 days 5 hours','etp-local/seed/events/e7.jpg',true,true,now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

-- match rules come from the program settings
INSERT INTO "EventSettings" ("Id","EventId","ProgramId","LimitedAvailabilityThreshold","AllowableMaximumOrderPerUser","AllowableMaximumSeatPerOrder","TicketSellingStartFromHour","TicketSellingStopFromHour","TicketAvailableFromHour",
  "TicketNumberPrefix","Vat","IsVatPercentage","ServiceCharge","IsServiceChargePercentage","IsVatInclusive","PaymentGateway","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
SELECT e."Id", e."Id", e."ProgramId", ps."LimitedAvailabilityThreshold", ps."AllowableMaximumOrderPerUser", ps."AllowableMaximumSeatPerOrder", ps."TicketSellingStartFromHour", ps."TicketSellingStopFromHour", ps."TicketAvailableFromHour",
       ps."TicketNumberPrefix", ps."Vat", ps."IsVatPercentage", ps."ServiceCharge", ps."IsServiceChargePercentage", ps."IsVatInclusive", ps."PaymentGateway", now(),'seed',true,false
FROM "Events" e JOIN "ProgramSettings" ps ON ps."ProgramId"=e."ProgramId" WHERE e."Id" < 100
ON CONFLICT ("Id") DO NOTHING;

-- segments: the Test has one segment per day (a multi-segment ticket); every other match has one
INSERT INTO "EventSegments" ("Id","EventId","SegmentId","Name","SegmentType","StartDateTime","EndDateTime","Team1Id","Team2Id","BannerImage","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
SELECT d, 1, 'SEG-E1-D' || d, 'Test - Day ' || d, 'Sport', now() + interval '20 days' + (d-1) * interval '1 day', now() + interval '20 days 8 hours' + (d-1) * interval '1 day', 1, 2, 'etp-local/seed/segments/test.jpg', now(),'seed',true,false
FROM generate_series(1,5) d
ON CONFLICT ("Id") DO NOTHING;
INSERT INTO "EventSegments" ("Id","EventId","SegmentId","Name","SegmentType","StartDateTime","EndDateTime","Team1Id","Team2Id","BannerImage","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
SELECT 4 + e."Id", e."Id", 'SEG-E' || e."Id" || '-1', e."Name", 'Sport', e."StartDateTime", e."EndDateTime", t.t1, t.t2, 'etp-local/seed/segments/e' || e."Id" || '.jpg', now(),'seed',true,false
FROM "Events" e JOIN (VALUES (2,1,2),(3,1,2),(4,1,2),(5,3,4),(6,5,6),(7,6,3)) AS t(ev,t1,t2) ON t.ev=e."Id"
ON CONFLICT ("Id") DO NOTHING;

-- price/capacity of every level of the match's ground (Id = match * 10 + level)
INSERT INTO "EventVenueDetails" ("Id","ProgramId","EventId","VenueId","VenueGallaryId","IsGalleryActive","IsSeatMappedInGallery","IsGallerySellable","GalleryBlockId","IsBlockActive","IsSeatMappedInBlock","IsBlockSellable",
  "BlockLevelId","IsLevelActive","IsSeatMappedInLevel","IsLevelSellable","CurrencyId","SeatingCapacity","PricePerSeat","IsPublish","HasSeats","Seats","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
SELECT e."Id"*10 + p."BlockLevelId", e."ProgramId", e."Id", p."VenueId", p."VenueGallaryId", true, p."IsSeatMappedInGallery", true, p."GalleryBlockId", true, p."IsSeatMappedInBlock", true,
       p."BlockLevelId", true, p."IsSeatMappedInLevel", true, p."CurrencyId", p."SeatingCapacity", p."PricePerSeat", e."IsPublished", p."HasSeats", p."Seats", now(),'seed',true,false
FROM "Events" e JOIN "ProgramVenueDetails" p ON p."ProgramId"=e."ProgramId" AND p."VenueId"=e."VenueId"
WHERE e."Id" < 100
ON CONFLICT ("Id") DO NOTHING;

-- ---- promotions ----------------------------------------------------------------------------------------
INSERT INTO "Discounts" ("Id","Name","DiscountType","DiscountValue","Status","StartDateTime","EndDateTime","IsPublished","ProgramId","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,'ODI early bird 10% (Pavilion)','Percentage',10,'Active',now() - interval '5 days', now() + interval '20 days',true,1,now(),'seed',true,false),
 (2,'Flat 100 off (ended)','FixedAmount',100,'Expired',now() - interval '40 days', now() - interval '10 days',true,1,now(),'seed',true,false),
 (3,'BPL launch 15% (upcoming)','Percentage',15,'Upcoming',now() + interval '10 days', now() + interval '40 days',true,2,now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

-- discount 1 applies to the 1st ODI (event 2), Pavilion gallery (1) of Mirpur (venue 1)
INSERT INTO "DiscountAssigns" ("Id","DiscountId","AssignType","ProgramId","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,'Gallery',1,now(),'seed',true,false) ON CONFLICT ("Id") DO NOTHING;
INSERT INTO "DiscountVenueEventGallery" ("Id","DiscountAssignId","VenueId","EventId","GalleryId","VenueEventGalleryName","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,1,2,1,'Sher-e-Bangla National Cricket Stadium - Bangladesh vs India - 1st ODI - Pavilion',now(),'seed',true,false) ON CONFLICT ("Id") DO NOTHING;
INSERT INTO "DiscountAssignEvent" ("DiscountAssignId","EventsId") VALUES (1,2) ON CONFLICT DO NOTHING;
INSERT INTO "DiscountAssignVenueGallery" ("DiscountAssignId","GalleriesId") VALUES (1,1) ON CONFLICT DO NOTHING;

INSERT INTO "PromoCodes" ("Id","Code","Name","DiscountType","DiscountAppliedTo","DiscountValue","TotalUsageLimit","LimitPerUser","Status","StartDateTime","EndDateTime","IsPublished","ProgramId","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,'BCBWELCOME10','Welcome 10%','Percentage','BasePrice',10,100,2,'Active',now() - interval '5 days', now() + interval '60 days',true,1,now(),'seed',true,false),
 (2,'BPLFLAT100','BPL flat 100 off','FixedAmount','DiscountedPrice',100,50,1,'Active',now() - interval '1 days', now() + interval '70 days',true,2,now(),'seed',true,false),
 (3,'OLDCODE','Expired code','Percentage','BasePrice',5,10,1,'Expired',now() - interval '60 days', now() - interval '30 days',true,1,now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

-- BCBWELCOME10 applies to the 2nd ODI (event 3), Pavilion (gallery 4) at Chattogram (venue 2)
INSERT INTO "PromoCodeAssigns" ("Id","PromoCodeId","AssignType","ProgramId","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,'Event',1,now(),'seed',true,false) ON CONFLICT ("Id") DO NOTHING;
INSERT INTO "PromoCodeVenueEventGallery" ("Id","PromoCodeAssignId","VenueId","EventId","GalleryId","VenueEventGalleryName","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,2,3,4,'Zahur Ahmed Chowdhury Stadium - Bangladesh vs India - 2nd ODI - Pavilion',now(),'seed',true,false) ON CONFLICT ("Id") DO NOTHING;
INSERT INTO "EventPromoCodeAssign" ("EventsId","PromoCodeAssignId") VALUES (3,1) ON CONFLICT DO NOTHING;
INSERT INTO "PromoCodeAssignVenueGallery" ("GalleriesId","PromoCodeAssignId") VALUES (4,1) ON CONFLICT DO NOTHING;

-- ---- landing page (public endpoint /event/api/v1/landing-page-image/public returns the published rows) ----
INSERT INTO "LandingPageImage" ("Id","ProgramId","Title","Description","ActionUrl","ImageUrl","Type","ThumbnailUrl","DisplayOrder","IsPublished","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,'Bangladesh vs India Series','Test, ODIs and T20Is - book your seats','https://etp.local/events','etp-local/seed/landing/hero-series.jpg','Hero','etp-local/seed/landing/hero-series-t.jpg',1,true,now(),'seed',true,false),
 (2,2,'Bangladesh Premier League','Franchise cricket returns','https://etp.local/events','etp-local/seed/landing/hero-bpl.jpg','Hero','etp-local/seed/landing/hero-bpl-t.jpg',2,true,now(),'seed',true,false),
 (3,null,'Title Sponsor',null,null,'etp-local/seed/landing/sponsor1.png','Sponsors',null,1,true,now(),'seed',true,false),
 (4,null,'Match-day notice','Tickets are non-refundable and non-transferable.',null,'etp-local/seed/landing/notice.png','Notice',null,1,true,now(),'seed',true,false),
 (5,null,'How do I get my ticket?','After payment, download it from My Tickets.',null,'etp-local/seed/landing/faq.png','FAQ',null,1,true,now(),'seed',true,false),
 (6,null,'Draft banner (unpublished)',null,null,'etp-local/seed/landing/draft.jpg','Hero',null,9,false,now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

COMMIT;
