import { test, expect } from '@playwright/test';

/**
 * The fake OneID flow (dev-server proxy at /p/oneid) always signs in as the
 * seeded customer — see docs/user-portal-local.md §5. The popup auto-approves
 * and hands real Floci tokens back to the main page.
 */
test.describe('OneID wallet login @auth @oneid', () => {
  // /en/auth/login redirects signed-in users home (UnAuthGuard).
  test.use({ storageState: { cookies: [], origins: [] } });

  test('login with OneID Wallet signs in the seeded customer', async ({ page }) => {
    await page.goto('/en/auth/login');

    await page.getByRole('button', { name: 'Login with OneID Wallet' }).click();

    await expect(page.locator('a', { hasText: 'My Tickets' }).first()).toBeVisible({ timeout: 30_000 });
  });
});
