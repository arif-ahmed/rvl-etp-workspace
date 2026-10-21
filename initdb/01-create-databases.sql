-- Runs once, on the first start with an empty etp-pgdata volume.
-- The repo itself never calls EnsureCreated/CREATE DATABASE — migrations only
-- create the schema inside an existing database, so the databases are made here.
-- Names are local-dev conventions; match them to the Database= values in your
-- user-secrets connection strings. Ticketing intentionally has no database of
-- its own: it shares Booking's (ConnectionStrings:Booking).

CREATE DATABASE etp_admin;
CREATE DATABASE etp_booking;
CREATE DATABASE etp_event;
CREATE DATABASE etp_ticketchecker;
CREATE DATABASE etp_pushnotification;
CREATE DATABASE etp_userissue;
