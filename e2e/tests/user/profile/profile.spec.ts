import { test, expect } from '@playwright/test';

test.describe('profile @profile', () => {
  test('profile page shows the stub identity of the signed-in user', async ({ page }) => {
    await page.goto('/en/user-profile');

    await expect(page.getByRole('heading', { name: 'Profile', exact: true })).toBeVisible({ timeout: 30_000 });
    await expect(page.getByRole('tab', { name: 'Personal Information' })).toBeVisible();

    // The local mock-identity stub builds the profile from the token
    // (name "Local User") — see docs/identity-mock-local.md.
    const fullName = page.locator('input[formcontrolname="fullName"]');
    await expect(fullName).toBeVisible();
    await expect(fullName).not.toHaveValue('');
  });
});
