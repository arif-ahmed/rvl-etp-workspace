# 20 · User Web Portal

Features started by customers in the Angular user portal (`rvl-gobcb-user-portal/ETP-Web`), User Cognito pool.

[Back to contents](../README.md)

## Sign-in and access

- [X-06 Customer registration](../60-cross-cutting/X-06-user-registration.md)
- [X-07 Customer login with phone and password](../60-cross-cutting/X-07-user-password-login.md)
- [X-08 OneID single sign-on](../60-cross-cutting/X-08-oneid-sso.md)
- [X-09 Customer forgot/reset password](../60-cross-cutting/X-09-user-forgot-password.md)
- [X-10 Customer change password, logout and token attach](../60-cross-cutting/X-10-user-session.md)
- [X-14 Authorization layer 1: pool schemes and policies](../60-cross-cutting/X-14-authz-pool-policies.md)

## Features in this section

| ID | Feature | Purpose |
|---|---|---|
| P-01 | [Home page content](P-01-home-content.md) | Banners, header/footer, notices and program list on the landing page. |
| P-02 | [Browse events and event details](P-02-browse-events.md) | Event lists and the event detail page. |
| P-03 | [Information pages (pricing, gallery, contact, policies)](P-03-info-pages.md) | Ticket-pricing, gallery, contact, terms, privacy, FAQ and ICC code pages. |
| P-04 | [Seat selection](P-04-seat-selection.md) | Stadium map, live availability, seat/quantity choice and automatic discount. |
| P-05 | [Apply promo code](P-05-apply-promo-code.md) | Validate a promo code before checkout and show the discount. |
| P-06 | [Booking order and online payment (DgePay)](P-06-booking-payment.md) | Create the order, lock capacity, pay through DgePay and handle the callback. |
| P-07 | [My bookings and generation status](P-07-my-bookings.md) | List the customer's orders and poll until tickets are generated. |
| P-08 | [Ticket generation request](P-08-ticket-generation-request.md) | Ask the platform to generate the tickets of a paid order. |
| P-09 | [Ticket details, holder info, download, share, invoice](P-09-ticket-details-downloads.md) | View tickets, edit the holder, download one/all, share a link, download the invoice. |
| P-10 | [Sync tickets to OneID wallet](P-10-oneid-ticket-sync.md) | Push a ticket or a whole order to the customer's OneID wallet. |
| P-11 | [Profile](P-11-profile.md) | View and update the customer profile. |
| P-12 | [Report an issue and chat with support](P-12-issues-chat.md) | Raise an issue about an order and chat with support in real time. |
| P-13 | [Language switch (EN/BN)](P-13-language-switch.md) | Switch the portal language through the `/:lang` route segment. |
