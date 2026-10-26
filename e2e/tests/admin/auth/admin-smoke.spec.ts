import { test, expect } from '@playwright/test';

/**
 * Phase 2 placeholder — the admin suite (event/venue/program management,
 * promo codes, and the cross-portal ticket lifecycle) will live here.
 * Every admin test carries a feature tag (@admin-events, @promo, ...) and the
 * cross-portal flows use @ticket-lifecycle.
 */
test.fixme('admin dashboard loads', async ({ page }) => {
  await page.goto('/en');
  await expect(page.locator('app-dashboard, app-layout').first()).toBeVisible();
});
