# RVL AWS Access Handover — Summary

Quick reference covering AWS root, admin, and database access status for the RVL/GOBCB handover.

**Account:** `329599633826` ·

---

## 5. AWS Root Access

**Status:** Done

Root email `gitadmin@reliefvalidation.com.bd` is owned and controlled by RVL.

> Note: this account is also the management account of an AWS Organization hosting two other unrelated client accounts (ONEID, TicketBangla) plus Dipon Group/NBR resources — root control extends to those as well, worth keeping in mind for future changes.

## 6. AWS Admin Access

**Status:** Done

Admin access can also be granted/revoked directly from the Root account going forward.

Currently holding `AdministratorAccess`:
- `mahafuz.aziz@dipon.com.bd` (Mahafuz Aziz)
- `saadmankarim-rvl` (Saadman Karim)

## 7. Database Access — Stage Environment

**Status:** Done

Stage DB is publicly reachable over the internet but restricted to a whitelisted IP network (security group allowlist).

| Field | Value |
|---|---|
| Host | `etp-development-rds-postgresql.c9ygs42smo7d.ap-southeast-1.rds.amazonaws.com` |
| Port | `5432` |
| Database | `etp_staging` |
| User | `eticketingplatformuser` |
| Password | via SSM Parameter Store: `staging/admin-service/appsettings` |

## 8. Database Access — Production Environment

**Status:** Done

Production DB is **not** publicly accessible — network-restricted to the VPC. To connect, a bastion jump server needs to be configured.

| Field | Value |
|---|---|
| Host | `etp-production-proxy.proxy-c9ygs42smo7d.ap-southeast-1.rds.amazonaws.com` |
| Port | `5432` |
| Database | `etp_production` |
| User | `etp_production` |
| Password | via SSM Parameter Store: `/rvl/prod/admin-service-appsettings` |

---

