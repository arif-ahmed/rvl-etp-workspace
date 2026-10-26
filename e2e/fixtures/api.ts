import type { APIRequestContext, Page } from '@playwright/test';
import { env, type TestUser } from './env';

/**
 * Helpers for the workspace-owned mocks and test-friendly backend endpoints.
 * Nothing here touches a submodule; these are the same local endpoints
 * documented in docs/identity-mock-local.md and docs/local-dev.md §7.1.
 */

/** Creates a real user in the Floci `etp-user` pool via mock-identity. */
export async function registerUserViaIdentity(request: APIRequestContext, user: TestUser): Promise<void> {
  const base = env.mockIdentity;
  const post = (path: string, data: unknown) =>
    request.post(`${base}${path}`, { data, failOnStatusCode: true });

  const cached = await (await post('/user/register-cached', {
    name: user.name,
    email: user.email,
    phone: user.phoneApi,
    dob: '1990-01-01',
    address: 'Dhaka',
  })).json();

  const userId = cached?.data?.user_id;
  if (!userId) throw new Error(`register-cached did not return a user_id: ${JSON.stringify(cached)}`);

  await post('/otp/send-otp', { type: 'sms', destination: user.phoneApi });
  await post('/otp/verify-otp', { type: 'sms', destination: user.phoneApi, otp: env.mockOtp });
  await post('/user/register', { user_id: userId, password: user.password });
}

/**
 * Marks an order Paid and triggers ticket generation, without a real payment
 * gateway. This is the Booking service's own test bypass endpoint
 * (`payment-status-bypass`); it responds with a redirect, which we do not follow.
 */
export async function bypassPayment(request: APIRequestContext, orderPublicId: string): Promise<number> {
  const res = await request.get(
    `${env.bookingApi}/api/v1/user-booking-order/payment-status-bypass`,
    { params: { rawData: orderPublicId }, maxRedirects: 0, failOnStatusCode: false },
  );
  return res.status();
}

/**
 * Fills NID/address/DOB for the signed-in user via mock-identity, so the
 * portal's "Complete your profile first!" gate before ticket purchase passes
 * (isProfileCompleted requires address + dob + verification_id).
 */
export async function completeProfile(page: Page): Promise<void> {
  const token = await page.evaluate(() => {
    const key = Object.keys(localStorage).find((k) => k.endsWith('.accessToken'));
    return key ? localStorage.getItem(key) : null;
  });
  if (!token) throw new Error('no Amplify accessToken in localStorage — is the user signed in?');

  const res = await page.request.put(`${env.mockIdentity}/user/my-profile`, {
    headers: { Authorization: `Bearer ${token}` },
    data: {
      verification_type: 'nid',
      verification_id: '1990887766554',
      address: 'Dhaka',
      dob: '1990-01-01',
    },
  });
  if (!res.ok()) throw new Error(`PUT my-profile failed: ${res.status()} ${await res.text()}`);
}
