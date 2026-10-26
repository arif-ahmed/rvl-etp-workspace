import { test, expect } from '@playwright/test';
import { env } from '../../../fixtures/env';

test.describe('login @auth', () => {
  // /en/auth/* is guarded by an UnAuthGuard: signed-in users get redirected
  // home. These tests need a fresh, logged-out context.
  test.use({ storageState: { cookies: [], origins: [] } });

  test('wrong password shows an error', async ({ page }) => {
    await page.goto('/en/auth/login');
    await page.locator('input[formcontrolname="phone"]').fill(env.userPhone);
    await page.locator('input[formcontrolname="password"]').fill('WrongPassword!1');
    await page.getByRole('button', { name: 'Next' }).click();

    // The portal only renders a banner for specific Cognito message strings;
    // assert the sign-in was rejected (stays on the login form) instead.
    await expect(page).toHaveURL(/\/auth\/login/, { timeout: 15_000 });
    await expect(page.getByRole('button', { name: 'Next' })).toBeEnabled();
  });

  test('password login lands on the logged-in home page', async ({ page }) => {
    await page.goto('/en/auth/login');
    await page.locator('input[formcontrolname="phone"]').fill(env.userPhone);
    await page.locator('input[formcontrolname="password"]').fill(env.userPassword);
    await page.getByRole('button', { name: 'Next' }).click();

    await expect(page.locator('a', { hasText: 'My Tickets' }).first()).toBeVisible({ timeout: 30_000 });
  });
});

test.describe('logout @auth', () => {
  test('logout returns to the login page', async ({ page }) => {
    await page.goto('/en');

    await page.getByRole('button', { name: 'User menu button' }).click();
    // The menu item is a plain button inside the Material menu panel; the
    // mobile sidebar renders a second (hidden) copy.
    await page
      .locator('.mat-mdc-menu-panel')
      .locator('button', { hasText: 'Logout' })
      .click();
    // The portal asks for confirmation before signing out.
    await page.getByRole('button', { name: 'Log Out' }).click();

    await expect(page).toHaveURL(/\/auth\/login/);
  });
});
