-- 04-checker-issues-push: gate staff + match-day scans, user issues, device tokens, activity log.
-- psql variables: :user_sub (User pool +8801700000011), :checker_sub (TicketChecker pool +8801700000021), :admin_sub (Admin pool +8801700000001)
SET search_path = etp;
BEGIN;

-- gates per match (EntryGateId = the BlockLevelEntryGates Id the gate belongs to; names match the Tickets.EntryGates text)
INSERT INTO "TicketCheckerGates" ("Id","ProgramId","EventId","VenueId","EntryGateName","EntryGateId","BlockLevelEntryGatesId","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,1,2,1,'Gate 1','1',1,now(),'seed',true,false),   -- 1st ODI, Pavilion
 (2,1,2,1,'Gate 5','3',3,now(),'seed',true,false),   -- 1st ODI, Grand Stand
 (3,1,2,1,'Gate 7','4',4,now(),'seed',true,false),   -- 1st ODI, Student Enclosure
 (4,1,3,2,'Gate A','5',5,now(),'seed',true,false),   -- 2nd ODI, Pavilion
 (5,2,5,1,'Gate 5','3',3,now(),'seed',true,false)    -- BPL Mirpur, Grand Stand
ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "TicketCheckerGateUsers" ("Id","TicketCheckerGateId","UserId","Name","IsDownloadEnable","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE
SELECT g."Id", g."Id", :'checker_sub', 'Local Ticket Checker', true, now(),'seed',true,false FROM "TicketCheckerGates" g WHERE g."Id" < 100
ON CONFLICT ("Id") DO NOTHING;

-- match day of the 1st ODI: ticket 1 enters at Gate 1 and is scanned again (EntryCount 2 = duplicate attempt);
-- a Grand Stand ticket is let in manually at Gate 5
INSERT INTO "CheckedTickets" ("Id","EventLongId","EventId","TicketCheckerGateId","TicketCheckerGateName","TicketCheckerId","TicketCheckerName","TicketNumber","EntryCount","IsManualEntry","EntryTime","CreatedAt","CreatedBy","IsActive","IsDeleted") OVERRIDING SYSTEM VALUE VALUES
 (1,2,'11111111-1111-4111-8111-000000000002','1','Gate 1',:'checker_sub','Local Ticket Checker','BDI-L-000001',1,false,now() - interval '30 minutes',now(),'seed',true,false),
 (2,2,'11111111-1111-4111-8111-000000000002','1','Gate 1',:'checker_sub','Local Ticket Checker','BDI-L-000001',2,false,now() - interval '20 minutes',now(),'seed',true,false),
 (3,2,'11111111-1111-4111-8111-000000000002','2','Gate 5',:'checker_sub','Local Ticket Checker','BDI-L-000003',1,true,now() - interval '10 minutes',now(),'seed',true,false)
ON CONFLICT ("Id") DO NOTHING;

-- user issues raised against 1st ODI orders (Status Open | Resolved)
INSERT INTO "ReportedIssues" ("Id","EventId","ProgramId","IssueNumber","OrderNumber","OrderDate","PublicOrderId","Description","Status","Feedback","ResolvedAt","ResolvedBy","CreatedAt","CreatedBy") OVERRIDING SYSTEM VALUE VALUES
 (1,2,1,'ISS-LOCAL-0001','ORD-LOCAL-0002',now() - interval '5 minutes','44444444-4444-4444-8444-000000000002','Money was deducted but the order is still pending.','Open',null,null,null,now() - interval '4 minutes',:'user_sub'),
 (2,2,1,'ISS-LOCAL-0002','ORD-LOCAL-0005',now() - interval '2 hours','44444444-4444-4444-8444-000000000005','I cancelled by mistake, please help.','Resolved','Thanks, refund issued.',now() - interval '30 minutes',:'admin_sub',now() - interval '90 minutes',:'user_sub')
ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "ReportedIssueChatMessages" ("Id","ReportedIssueId","ProgramId","SenderType","SenderId","SenderName","Message","IsRead","CreatedAt","CreatedBy") OVERRIDING SYSTEM VALUE VALUES
 (1,1,1,'User',:'user_sub','Local User','Money was deducted but the order is still pending.',true,now() - interval '4 minutes',:'user_sub'),
 (2,1,1,'Admin',:'admin_sub','Local Admin','We are checking with the payment gateway.',false,now() - interval '2 minutes',:'admin_sub'),
 (3,2,1,'User',:'user_sub','Local User','I cancelled by mistake, please help.',true,now() - interval '90 minutes',:'user_sub'),
 (4,2,1,'Admin',:'admin_sub','Local Admin','Refund issued, sorry for the trouble.',true,now() - interval '30 minutes',:'admin_sub')
ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "UserDeviceTokens" ("Id","UserId","FcmToken","OsType","UpdatedAt","CreatedAt") OVERRIDING SYSTEM VALUE VALUES
 (1,:'user_sub','seed-fcm-token-android-0001','Android',now(),now()),
 (2,:'user_sub','seed-fcm-token-ios-0001','iOS',now(),now())
ON CONFLICT ("Id") DO NOTHING;

INSERT INTO "ActivityLogs" ("Id","ServiceName","EntityName","EntityId","Action","NewValues","TransactionId","Timestamp","UserId","IpAddress") OVERRIDING SYSTEM VALUE VALUES
 (1,'Admin','Event','2','Create','{"Name":"Bangladesh vs India - 1st ODI"}','seed-tx-0001',now() - interval '10 days',:'admin_sub','127.0.0.1'),
 (2,'Booking','UserBookingOrder','1','Create','{"OrderNumber":"ORD-LOCAL-0001"}','seed-tx-0002',now() - interval '2 days',:'user_sub','127.0.0.1')
ON CONFLICT ("Id") DO NOTHING;

-- bump every identity sequence to at least 99 so rows created later through the APIs get Ids >= 100 and never collide with the seed
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT c.table_name, c.column_name, pg_get_serial_sequence('etp."'||c.table_name||'"', c.column_name) AS seq
           FROM information_schema.columns c
           WHERE c.table_schema='etp' AND c.is_identity='YES' LOOP
    IF r.seq IS NOT NULL THEN
      EXECUTE format('SELECT setval(%L, GREATEST((SELECT COALESCE(MAX(%I),0) FROM etp.%I), 99), true)', r.seq, r.column_name, r.table_name);
    END IF;
  END LOOP;
END $$;

COMMIT;
