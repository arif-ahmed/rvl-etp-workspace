import { test, expect } from '@playwright/test';

test.describe('my tickets @tickets', () => {
  test('seeded orders are listed in the bookings table', async ({ page }) => {
    await page.goto('/en/tickets');

    await expect(page.getByRole('heading', { name: 'My Tickets' })).toBeVisible({ timeout: 30_000 });
    // "Upcoming events" is the default tab; the seed includes past matches too.
    await page.getByRole('tab', { name: 'All events' }).click();

    await expect(page.locator('[mat-row]').first()).toBeVisible();
    await expect(page.getByRole('button', { name: 'View Details' }).first()).toBeVisible();
  });

  test('upcoming tab shows orders or the empty state', async ({ page }) => {
    await page.goto('/en/tickets');
    await page.getByRole('tab', { name: 'Upcoming events' }).click();

    // Give the bookings API time to respond; either data or the empty state
    // must eventually render.
    await expect(page.locator('[mat-row]').first().or(page.getByText('No Ticket!'))).toBeVisible({
      timeout: 20_000,
    });
  });

  test('ticket details page opens from the list', async ({ page }) => {
    await page.goto('/en/tickets');
    await page.getByRole('tab', { name: 'All events' }).click();

    // Seed data includes Cancelled/Pending orders whose View Details is
    // disabled; pick the first *enabled* one.
    const viewButton = page
      .locator('button:has-text("View Details"):not([disabled])')
      .first();
    await expect(viewButton).toBeVisible({ timeout: 30_000 });
    await viewButton.click();

    await expect(page).toHaveURL(/\/en\/tickets\/ticket-details\//);
    await expect(page.getByRole('heading', { name: 'Ticket Details' })).toBeVisible();
  });
});
