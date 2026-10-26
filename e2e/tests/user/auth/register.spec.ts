import { test, expect } from '@playwright/test';
import { env, makeTestUser } from '../../../fixtures/env';

/** Fills the six OTP digit inputs (#digit-0 … #digit-5) — mock-identity OTP is fixed. */
async function fillOtp(page: import('@playwright/test').Page, otp: string) {
  for (let i = 0; i < otp.length; i++) {
    await page.locator(`#digit-${i}`).fill(otp[i]);
  }
}

test.describe('registration @auth @register', () => {
  // /en/auth/* is UnAuthGuard-protected: signed-in users are redirected home.
  test.use({ storageState: { cookies: [], origins: [] } });

  test('new user can register with SMS OTP and sign in', async ({ page }) => {
    const user = makeTestUser('register');

    await page.goto('/en/auth/register');
    await page.locator('input[formcontrolname="name"]').fill(user.name);
    await page.locator('input[formcontrolname="email"]').fill(user.email);
    await page.locator('input[formcontrolname="phone"]').fill(user.phoneUi);
    await page.locator('mat-checkbox input').check();
    await page.getByRole('button', { name: 'Next' }).click();

    // Email verification, an interstitial, then phone verification — all
    // accept the fixed mock-identity OTP.
    await expect(page.getByText('Please check your email!')).toBeVisible({ timeout: 30_000 });
    await fillOtp(page, env.mockOtp);
    await page.getByRole('button', { name: 'Next' }).click();

    await expect(page.getByText('Email Verified Successfully!')).toBeVisible({ timeout: 30_000 });
    await page.getByRole('button', { name: 'Next' }).click();

    await expect(page.getByText('Please check your Phone!')).toBeVisible({ timeout: 30_000 });
    await fillOtp(page, env.mockOtp);
    await page.getByRole('button', { name: 'Next' }).click();

    await expect(page.getByText('Phone Number Verified Successfully!')).toBeVisible({ timeout: 30_000 });
    await page.getByRole('button', { name: 'Next' }).click();

    // Set password step.
    await expect(page.getByText('Set your password')).toBeVisible();
    await page.locator('input[formcontrolname="password"]').fill(user.password);
    await page.locator('input[formcontrolname="confirmPassword"]').fill(user.password);
    await page.getByRole('button', { name: 'Next' }).click();

    // Back at login with a success banner; the new user can sign in.
    await expect(page).toHaveURL(/\/auth\/login/, { timeout: 30_000 });
    await page.locator('input[formcontrolname="phone"]').fill(user.phoneUi);
    await page.locator('input[formcontrolname="password"]').fill(user.password);
    await page.getByRole('button', { name: 'Next' }).click();
    await expect(page.locator('a', { hasText: 'My Tickets' }).first()).toBeVisible({ timeout: 30_000 });
  });

  test('registering an existing phone is rejected @negative', async ({ page }) => {
    await page.goto('/en/auth/register');
    await page.locator('input[formcontrolname="name"]').fill('Duplicate User');
    await page.locator('input[formcontrolname="email"]').fill('duplicate@etp.local');
    await page.locator('input[formcontrolname="phone"]').fill(env.userPhone);
    await page.locator('mat-checkbox input').check();
    await page.getByRole('button', { name: 'Next' }).click();

    await expect(page.getByText('User already exists!')).toBeVisible();
  });
});
