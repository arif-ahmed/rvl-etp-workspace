import { defineConfig, devices } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

// Minimal .env loader (no dependency): e2e/.env, if present, feeds the
// process.env values below — see .env.example for the supported keys.
const envPath = path.join(__dirname, '.env');
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (match && !(match[1] in process.env) && match[2] !== '') process.env[match[1]] = match[2];
  }
}

// Screenshot toggle: set E2E_SCREENSHOT=on to capture every test; default is failures only.
const screenshotMode = process.env.E2E_SCREENSHOT === 'on' ? 'on' : 'only-on-failure';
const runAdmin = process.env.E2E_RUN_ADMIN === '1';

const userPortalUrl = process.env.E2E_USER_PORTAL_URL ?? 'http://localhost:4201';
const adminPortalUrl = process.env.E2E_ADMIN_PORTAL_URL ?? 'http://localhost:4200';

const AUTH_DIR = path.join(__dirname, 'playwright', '.auth');
const USER_STATE = path.join(AUTH_DIR, 'user.json');
const ADMIN_STATE = path.join(AUTH_DIR, 'admin.json');

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  timeout: 90_000, // Floci SRP logins and first-load @defer blocks can be slow on a busy stack
  retries: 1,
  workers: process.env.CI ? 2 : undefined,
  reporter: [['list'], ['html', { open: 'never' }]],
  globalSetup: './global-setup.ts',
  use: {
    viewport: { width: 1366, height: 850 },
    screenshot: screenshotMode as 'on' | 'only-on-failure',
    trace: 'on-first-retry',
    actionTimeout: 15_000,
    navigationTimeout: 30_000,
  },
  expect: { timeout: 10_000 },
  projects: [
    // Phase 1: user portal (http://localhost:4201)
    {
      name: 'user-setup',
      testMatch: /tests[/\\]user[/\\]setup[/\\].*\.ts$/,
      use: { baseURL: userPortalUrl },
    },
    {
      name: 'user',
      dependencies: ['user-setup'],
      testIgnore: /tests[/\\].*[/\\]setup[/\\].*\.ts$/,
      testMatch: /tests[/\\]user[/\\].*\.spec\.ts$/,
      use: {
        baseURL: userPortalUrl,
        storageState: USER_STATE,
      },
    },
    // Phase 2: admin portal (http://localhost:4200) — enable with E2E_RUN_ADMIN=1
    ...(runAdmin
      ? [
          {
            name: 'admin-setup',
            testMatch: /tests[/\\]admin[/\\]setup[/\\].*\.ts$/,
            use: { baseURL: adminPortalUrl },
          },
          {
            name: 'admin',
            dependencies: ['admin-setup'],
            testIgnore: /tests[/\\].*[/\\]setup[/\\].*\.ts$/,
            testMatch: /tests[/\\]admin[/\\].*\.spec\.ts$/,
            use: {
              baseURL: adminPortalUrl,
              storageState: ADMIN_STATE,
            },
          },
        ]
      : []),
  ],
});
