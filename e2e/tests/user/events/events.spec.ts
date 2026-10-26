import { test, expect } from '@playwright/test';
import { bookableEventCard } from '../../../fixtures/user/portal';

test.describe('events @events', () => {
  test('home page shows the seeded events section', async ({ page }) => {
    await page.goto('/en');

    await expect(page.getByText('Available and Upcoming Events')).toBeVisible({ timeout: 30_000 });
    // Cards render inside @defer blocks with a skeleton delay — wait for one.
    await expect(page.locator('app-event-card-homepage').first()).toBeVisible();
  });

  test('all-events list shows seeded events and filters entry point', async ({ page }) => {
    await page.goto('/en/events');

    await expect(page.getByRole('heading', { name: 'All Events' })).toBeVisible({ timeout: 30_000 });
    await expect(page.getByRole('button', { name: 'Filter' })).toBeVisible();
    await expect(page.locator('app-event-card-homepage').first()).toBeVisible();
  });

  test('opening a bookable event shows detail and purchase CTA', async ({ page }) => {
    await page.goto('/en/events');

    // Seed data marks bookable events "Limited Availability" / "Available Now".
    const availableCard = bookableEventCard(page);
    await expect(availableCard).toBeVisible({ timeout: 30_000 });

    const eventName = (await availableCard.locator('h2').first().innerText()).trim();
    await availableCard.locator('h2').first().click();

    await expect(page).toHaveURL(/\/en\/events\/[^/]+$/);
    await expect(page.locator('h2', { hasText: eventName }).first()).toBeVisible();
    await expect(page.getByRole('button', { name: 'Buy Tickets Now' })).toBeEnabled();
  });
});
