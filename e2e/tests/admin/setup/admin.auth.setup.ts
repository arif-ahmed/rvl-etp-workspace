import { test as setup, expect } from '@playwright/test';
import path from 'node:path';
import { env } from '../../../fixtures/env';

const ADMIN_STATE = path.join(__dirname, '..', '..', '..', 'playwright', '.auth', 'admin.json');

/**
 * Phase 2 scaffold. The admin portal signs in with Cognito + 2FA; the second
 * factor is served by mock-identity (fixed OTP, see docs/admin-portal-local.md).
 * Enable with E2E_RUN_ADMIN=1 (the admin projects are only registered then).
 */
setup('authenticate as the seeded admin', async ({ page }) => {
  test.skip(process.env.E2E_RUN_ADMIN !== '1', 'Phase 2: set E2E_RUN_ADMIN=1 and start the admin portal');

  await page.goto('/en/auth');

  await page.locator('input[formcontrolname="phone"]').fill(env.adminPhone);
  await page.locator('input[formcontrolname="password"]').fill(env.adminPassword);
  await page.getByRole('button', { name: 'Login' }).click();

  // 2FA: mock-identity always accepts env.mockOtp.
  await expect(page.getByText(/verification code|otp/i).first()).toBeVisible({ timeout: 30_000 });
  for (let i = 0; i < env.adminOtp.length; i++) {
    await page.locator(`#digit-${i}`).fill(env.adminOtp[i]);
  }
  await page.getByRole('button', { name: /verify|submit|next/i }).click();

  await expect(page.locator('app-layout, app-dashboard, nav').first()).toBeVisible({ timeout: 30_000 });

  await page.context().storageState({ path: ADMIN_STATE });
});
