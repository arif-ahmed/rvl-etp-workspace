// Central config for the E2E suite. Every value can be overridden via
// environment variables (see .env.example for the full list and defaults).

function num(url: string | undefined, fallback: string) {
  return url ?? fallback;
}

export const env = {
  userPortalUrl: num(process.env.E2E_USER_PORTAL_URL, 'http://localhost:4201'),
  adminPortalUrl: num(process.env.E2E_ADMIN_PORTAL_URL, 'http://localhost:4200'),
  eventApi: num(process.env.E2E_EVENT_URL, 'http://localhost:5103'),
  bookingApi: num(process.env.E2E_BOOKING_URL, 'http://localhost:5102'),
  mockIdentity: num(process.env.E2E_MOCK_IDENTITY_URL, 'http://localhost:5120'),
  tspMock: num(process.env.E2E_TSP_MOCK_URL, 'http://localhost:5130'),

  // Seeded customer (user pool). The portal login form takes the 10 digits
  // after +880 and rebuilds the full number itself.
  userPhone: process.env.E2E_USER_PHONE ?? '1700000011',
  userPassword: process.env.E2E_USER_PASSWORD ?? 'Passw0rd!23',

  // Seeded admin (admin pool, 2FA) and the fixed mock-identity OTP.
  adminPhone: process.env.E2E_ADMIN_PHONE ?? '1700000001',
  adminPassword: process.env.E2E_ADMIN_PASSWORD ?? 'Passw0rd!23',
  adminOtp: process.env.E2E_ADMIN_OTP ?? '123456',
  mockOtp: process.env.E2E_MOCK_OTP ?? '123456',
};

export type TestUser = {
  name: string;
  email: string;
  /** 11 digits with leading 0, as the identity API expects (e.g. 01712345678). */
  phoneApi: string;
  /** 10 digits starting with 1, as the portal login form expects. */
  phoneUi: string;
  password: string;
};

/** A unique customer per run, so booking tests never collide with seed data or each other. */
export function makeTestUser(prefix = 'e2e'): TestUser {
  // 9 digits → phoneUi is a full 10-digit number ("1XXXXXXXXX", the portal
  // prepends +880), phoneApi is the 11-digit form ("01XXXXXXXXX") the
  // identity API expects.
  const tail = String(Date.now() % 1_000_000_000).padStart(9, '0');
  return {
    name: `${prefix} Test User`,
    email: `${prefix}.${tail}@etp.local`,
    phoneApi: `01${tail}`,
    phoneUi: `1${tail}`,
    password: 'Passw0rd!23',
  };
}
