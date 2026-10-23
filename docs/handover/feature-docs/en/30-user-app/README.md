# 30 · User App

Features started by customers in the Flutter user app (`rvl-gobcb-user-app`), User Cognito pool.

[Back to contents](../README.md)

## Sign-in and access

- [X-06 Customer registration](../60-cross-cutting/X-06-user-registration.md)
- [X-07 Customer login with phone and password](../60-cross-cutting/X-07-user-password-login.md)
- [X-08 OneID single sign-on](../60-cross-cutting/X-08-oneid-sso.md)
- [X-09 Customer forgot/reset password](../60-cross-cutting/X-09-user-forgot-password.md)
- [X-10 Customer change password, logout and token attach](../60-cross-cutting/X-10-user-session.md)
- [X-11 Delete account and app force-update](../60-cross-cutting/X-11-delete-account-force-update.md)
- [X-14 Authorization layer 1: pool schemes and policies](../60-cross-cutting/X-14-authz-pool-policies.md)

## Features in this section

| ID | Feature | Purpose |
|---|---|---|
| U-01 | [Splash, version gate and onboarding](U-01-splash-onboarding.md) | Start-up: env check, force-update check, onboarding, session restore. |
| U-02 | [Home and browse events](U-02-home-browse-events.md) | Home content, event list and event details in the app. |
| U-03 | [Information pages (pricing, gallery, contact)](U-03-info-pages.md) | Ticket pricing, gallery and contact screens. |
| U-04 | [Seat selection and promo code](U-04-seat-selection-promo.md) | Choose seats/quantity, see discounts, apply a promo code. |
| U-05 | [Booking and WebView payment](U-05-booking-webview-payment.md) | Create the order and pay in an in-app WebView; success is detected from the URL. |
| U-06 | [My bookings and tickets](U-06-my-bookings-tickets.md) | Order list, booking details, ticket actions (holder edit, download, share, OneID sync). |
| U-07 | [Profile and settings](U-07-profile-settings.md) | Profile view/update, language, logout and delete-account entry. |
| U-08 | [Report an issue and support chat](U-08-issues-chat.md) | Raise issues and exchange messages with support. |
| U-09 | [Push device-token registration](U-09-device-token.md) | Register/refresh the FCM token of the device with the PushNotification service. |
| U-10 | [Receiving push notifications](U-10-push-receipt.md) | How the app receives and opens push messages (event published, ticket generated). |
