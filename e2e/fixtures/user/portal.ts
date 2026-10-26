import { type Locator, type Page } from '@playwright/test';

/**
 * Badges the portal shows for events that can currently be booked.
 * The seed data uses "Limited Availability" (never "Available Now"),
 * so accept both; Sold Out / Booking Closed / Coming Soon stay excluded.
 */
export const BOOKABLE_BADGE = /Available Now|Limited Availability/;

/** First event card on the list/home page that can be booked. */
export function bookableEventCard(page: Page): Locator {
  return page
    .locator('app-event-card-homepage')
    .filter({ hasText: BOOKABLE_BADGE })
    .first();
}
