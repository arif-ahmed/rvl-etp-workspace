import { test, expect, type Page } from '@playwright/test';
import { env, makeTestUser } from '../../../fixtures/env';
import { registerUserViaIdentity, bypassPayment, completeProfile } from '../../../fixtures/api';
import { bookableEventCard } from '../../../fixtures/user/portal';

/** Material select by its mat-label text, picking the first enabled option. */
async function pickFirstOption(page: Page, label: string) {
  const field = page
    .locator('mat-form-field')
    .filter({ has: page.locator('mat-label', { hasText: label }) });
  await field.locator('mat-select').click();
  await page.locator('mat-option:not(.mat-mdc-option-disabled)').first().click();
}

/**
 * The flagship end-to-end purchase: a fresh user (created through
 * mock-identity, so no seed-data collisions) books a seat via the UI, the
 * order is marked Paid through the Booking service's payment bypass, and the
 * ticket-signing pipeline (tsp-mock) makes it appear in My Tickets.
 */
test.describe('book and pay @booking', () => {
  // The test signs in through the UI with its own fresh user, so it must not
  // inherit the project storageState (UnAuthGuard would redirect it home).
  test.use({ storageState: { cookies: [], origins: [] } });

  test('user books a seat, pays via bypass, and the ticket appears', async ({ page, request }) => {
    test.setTimeout(240_000); // ticket generation + signing can take a while

    const user = makeTestUser('booking');
    await registerUserViaIdentity(request, user);

    // Sign in through the UI (fresh user, no storageState).
    await page.goto('/en/auth/login');
    await page.locator('input[formcontrolname="phone"]').fill(user.phoneUi);
    await page.locator('input[formcontrolname="password"]').fill(user.password);
    await page.getByRole('button', { name: 'Next' }).click();
    await expect(page.locator('a', { hasText: 'My Tickets' }).first()).toBeVisible({ timeout: 30_000 });

    // The portal gates ticket purchase behind a completed profile
    // ("Ready to secure your tickets? Complete your profile first!") — fill
    // NID/address/DOB through mock-identity, then reload so it is picked up.
    await completeProfile(page);

    // Pick a bookable event and start the purchase.
    await page.goto('/en/events');
    const availableCard = bookableEventCard(page);
    await expect(availableCard).toBeVisible({ timeout: 30_000 });
    const eventName = (await availableCard.locator('h2').first().innerText()).trim();
    await availableCard.locator('h2').first().click();

    const buyButton = page.getByRole('button', { name: 'Buy Tickets Now' });
    await expect(buyButton).toBeEnabled();
    await buyButton.click();
    await expect(page).toHaveURL(/\/en\/tickets\/[^/]+\/seats/);

    // Seat selection: first available gallery/block/level, one ticket. Seats
    // are assigned automatically; the checkout button enables when ready.
    await pickFirstOption(page, 'Pick a Gallery');
    await pickFirstOption(page, 'Pick a Block');
    await pickFirstOption(page, 'Pick a Level');
    await pickFirstOption(page, 'Number of Ticket');

    // Ticket holder (required for checkout; the portal wants an 11-digit phone).
    await page.locator('input[placeholder="Enter name"]').fill(user.name);
    await page.locator('input[placeholder="Enter phone"]').fill(user.phoneApi);

    // Block the external payment gateway redirect; capture the created order.
    await page.route((url) => !url.hostname.includes('localhost'), (route) => route.abort());

    const confirmButton = page.getByRole('button', { name: 'Confirm and make payment' });
    await expect(confirmButton).toBeEnabled();
    await confirmButton.click();

    const modal = page.locator('mat-dialog-container');
    const orderResponse = page.waitForResponse(
      (res) => res.request().method() === 'POST' && res.url().includes('/user-booking-order'),
      { timeout: 120_000 }, // order + payment session creation can be slow locally
    );
    await modal.getByRole('button', { name: 'Continue' }).click();
    const response = await orderResponse;
    const body = await response.json().catch(() => ({}));
    if (!body.publicId) {
      if (response.status() === 400 && String(body?.title ?? '').includes('Simultaneous order')) {
        throw new Error(
          'Known local-stack issue: the Booking service rejected the order with ' +
            '"Simultaneous order is prohibited" — its distributed lock (user_booking:*) ' +
            'never reaches Redis, so no order can be created against the local stack. ' +
            'This is a backend/environment problem, not a test failure (see e2e/README.md).',
        );
      }
      throw new Error(`booking order creation failed: ${response.status()} ${JSON.stringify(body).slice(0, 400)}`);
    }

    // Simulate the gateway callback: mark Paid and kick off ticket generation.
    const bypassStatus = await bypassPayment(request, body.publicId);
    expect(bypassStatus, 'payment-status-bypass should redirect on success').toBeLessThan(400);

    // Ticket generation runs asynchronously (Ticketing service + tsp-mock);
    // poll My Tickets until the order shows up and becomes viewable.
    const orderRow = page.locator('[mat-row]', { hasText: eventName });
    await expect
      .poll(
        async () => {
          await page.goto('/en/tickets');
          await page.getByRole('tab', { name: 'All events' }).click();
          return orderRow.count();
        },
        { message: 'order should appear in My Tickets', timeout: 90_000, intervals: [5_000] },
      )
      .toBeGreaterThan(0);

    // View Details enables once the order is Paid/Requested/Generated.
    const viewDetails = orderRow.getByRole('button', { name: 'View Details' });
    await expect
      .poll(async () => viewDetails.isEnabled(), {
        message: 'View Details should enable (Paid/Generated)',
        timeout: 90_000,
        intervals: [5_000],
      })
      .toBe(true);

    await viewDetails.click();
    await expect(page).toHaveURL(/\/en\/tickets\/ticket-details\//);
    await expect(page.getByRole('heading', { name: 'Ticket Details' })).toBeVisible();
  });
});
