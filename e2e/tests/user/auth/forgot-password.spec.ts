import { test, expect } from '@playwright/test';
import { env } from '../../../fixtures/env';

/**
 * Resets the seeded customer's password to the same value, so the local stack
 * stays in its documented state (login `1700000011` / `Passw0rd!23`).
 */
test.describe('forgot password @auth @reset', () => {
  // /en/auth/* is UnAuthGuard-protected: signed-in users are redirected home.
  test.use({ storageState: { cookies: [], origins: [] } });

  test('user can reset the password via SMS OTP and sign in again', async ({ page }) => {
    await page.goto('/en/auth/phone-reset-password');
    await page.locator('input[formcontrolname="phone"]').fill(env.userPhone);
    await page.getByRole('button', { name: 'Reset Password' }).click();

    // OTP + new password on one page.
    await expect(page.getByText('Please check your Phone!')).toBeVisible();
    for (let i = 0; i < env.mockOtp.length; i++) {
      await page.locator(`#digit-${i}`).fill(env.mockOtp[i]);
    }
    await page.locator('input[formcontrolname="password"]').fill(env.userPassword);
    await page.locator('input[formcontrolname="confirmPassword"]').fill(env.userPassword);
    await page.getByRole('button', { name: 'Submit' }).click();

    await expect(page.getByText('Password Reset Successful!')).toBeVisible({ timeout: 30_000 });

    // The (unchanged) password works.
    await page.goto('/en/auth/login');
    await page.locator('input[formcontrolname="phone"]').fill(env.userPhone);
    await page.locator('input[formcontrolname="password"]').fill(env.userPassword);
    await page.getByRole('button', { name: 'Next' }).click();
    await expect(page.locator('a', { hasText: 'My Tickets' }).first()).toBeVisible({ timeout: 30_000 });
  });

  test('unknown phone is rejected @negative', async ({ page }) => {
    await page.goto('/en/auth/phone-reset-password');
    await page.locator('input[formcontrolname="phone"]').fill('1999999999');

    // The portal banner only matches a 'user_not_found' error string, but
    // mock-identity reports `phone_number_not_found` (docs/identity-mock-local.md
    // §5 case 7) — assert the documented API rejection instead.
    const resetResponse = page.waitForResponse(
      (res) => res.url().includes('/otp/password-reset-request') && res.request().method() === 'POST',
    );
    await page.getByRole('button', { name: 'Reset Password' }).click();
    const response = await resetResponse;

    expect(response.status()).toBe(404);
    expect((await response.json()).status_message).toBe('phone_number_not_found');
  });
});
