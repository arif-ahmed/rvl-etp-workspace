# 60 · Cross-cutting (authentication, authorization, platform services)

Concerns shared by many features: sign-in, access control, service-to-service calls, storage, messaging, logging, cache, configuration.

[Back to contents](../README.md)

## Features in this section

| ID | Feature | Purpose |
|---|---|---|
| X-01 | [Admin login (phone OTP + password)](X-01-admin-login.md) | Three-step admin sign-in: phone, SMS OTP, Cognito password. |
| X-02 | [Admin forgot password](X-02-admin-forgot-password.md) | Reset an admin password after an SMS OTP. |
| X-03 | [Admin change password and logout](X-03-admin-change-password-logout.md) | Change the password in Cognito; sign out and clear local state. |
| X-04 | [Admin session handling (token attach and refresh)](X-04-admin-session.md) | How the admin portal attaches, caches and refreshes tokens. |
| X-05 | [Staff account provisioning](X-05-admin-provisioning.md) | How admin, checker and agent accounts are created in Cognito by the Admin service. |
| X-06 | [Customer registration](X-06-user-registration.md) | Sign-up with email and phone OTP, then password; OneID alternative. |
| X-07 | [Customer login with phone and password](X-07-user-password-login.md) | User-pool sign-in in portal and app. |
| X-08 | [OneID single sign-on](X-08-oneid-sso.md) | Sign in through OneID federated by Cognito; auto-register on first login. |
| X-09 | [Customer forgot/reset password](X-09-user-forgot-password.md) | OTP-based password reset through the identity API. |
| X-10 | [Customer change password, logout and token attach](X-10-user-session.md) | Session handling in portal and app. |
| X-11 | [Delete account and app force-update](X-11-delete-account-force-update.md) | App-only account deletion and the minimum-version gate. |
| X-12 | [Checker login](X-12-checker-login.md) | TicketChecker-pool sign-in in the checker app. |
| X-13 | [Agent pool and offline-sold tickets](X-13-agent-pool.md) | Agent accounts and the only Agent API. |
| X-14 | [Authorization layer 1: pool schemes and policies](X-14-authz-pool-policies.md) | Which Cognito pool a token must come from, per endpoint. |
| X-15 | [Authorization layers 2–3: staff roles](X-15-authz-roles.md) | `custom:role` → role claims and `[Authorize(Roles=…)]`; role × endpoint matrix. |
| X-16 | [Authorization layer 4: program scope](X-16-authz-program-scope.md) | `X-Program-Id`, `custom:program_ids`, `[AuthorizeProgram]` and the EF query filter. |
| X-17 | [Client-side authorization (menus and guards)](X-17-authz-client-side.md) | What the portals hide or block per role; not a security boundary. |
| X-18 | [Endpoints without authorization](X-18-endpoints-without-auth.md) | Every endpoint reachable without a token, and why. |
| X-19 | [Service-to-service communication](X-19-service-to-service.md) | Typed HTTP clients with token forwarding, tokenless worker calls, and SQS. |
| X-20 | [File storage (S3, CloudFront)](X-20-file-storage.md) | Media and ticket buckets, folder layout, signed URLs and cookies. |
| X-21 | [Email (SES)](X-21-email-ses.md) | Where the platform sends email. |
| X-22 | [SMS and the external notification service](X-22-sms-notification.md) | SMS/OTP and notification calls to services outside the repos. |
| X-23 | [Push notifications (PushNotification service, Firebase)](X-23-push-firebase.md) | Device tokens, send APIs, queue and FCM. |
| X-24 | [Activity logging (audit trail)](X-24-activity-logging.md) | How entity changes are recorded across services. |
| X-25 | [Redis: cache, live capacity and locks](X-25-redis.md) | Key families, cache usage and RedLock distributed locks. |
| X-26 | [Configuration and secrets](X-26-configuration.md) | Where settings come from in AWS and locally; key reference. |
