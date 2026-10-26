import { test as setup, expect } from '@playwright/test';
import path from 'node:path';
import { env } from '../../../fixtures/env';

const USER_STATE = path.join(__dirname, '..', '..', '..', 'playwright', '.auth', 'user.json');

/**
 * Logs in once through the real UI (Cognito SRP via Floci) and saves the
 * storage state. Every test in the `user` project reuses it — tokens live in
 * localStorage, which Playwright's storageState preserves per origin.
 */
setup('authenticate as the seeded customer', async ({ page }) => {
  await page.goto('/en/auth/login');

  await page.locator('input[formcontrolname="phone"]').fill(env.userPhone);
  await page.locator('input[formcontrolname="password"]').fill(env.userPassword);
  await page.getByRole('button', { name: 'Next' }).click();

  // Logged-in nav shows My Tickets; that is our proof of a valid session.
  const myTickets = page.locator('a', { hasText: 'My Tickets' });
  await expect(myTickets.first()).toBeVisible({ timeout: 30_000 });

  await page.context().storageState({ path: USER_STATE });
});
