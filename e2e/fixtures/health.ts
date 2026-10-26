import { env } from './env';

async function reachable(url: string, timeoutMs = 5_000): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    const res = await fetch(url, { signal: controller.signal });
    clearTimeout(timer);
    return res.status < 500;
  } catch {
    return false;
  }
}

/**
 * Returns a human-readable message when a required local service is down,
 * or null when everything the user-portal suite needs is up.
 */
export async function globalSetupError(): Promise<string | null> {
  const checks: Array<{ name: string; url: string; hint: string }> = [
    {
      name: `user portal (${env.userPortalUrl})`,
      url: env.userPortalUrl,
      hint: 'pwsh ./scripts/Setup-UserPortal.ps1 -Start',
    },
    {
      name: `Event service (${env.eventApi})`,
      url: `${env.eventApi}/health`,
      hint: 'dotnet run --project aspire/Etp.AppHost',
    },
    {
      name: `Booking service (${env.bookingApi})`,
      url: `${env.bookingApi}/health`,
      hint: 'dotnet run --project aspire/Etp.AppHost',
    },
    {
      name: `mock-identity (${env.mockIdentity})`,
      url: `${env.mockIdentity}/__dev/health`,
      hint: 'node mock-identity/server.js',
    },
    {
      name: `tsp-mock (${env.tspMock})`,
      url: `${env.tspMock}/auth`,
      hint: 'node tsp-mock/server.js',
    },
  ];

  const results = await Promise.all(checks.map((c) => reachable(c.url).then((ok) => ({ ...c, ok }))));
  const down = results.filter((r) => !r.ok);
  if (down.length === 0) return null;

  const lines = down.map((d) => `  - ${d.name} is not reachable  ->  ${d.hint}`);
  return [
    'The ETP local stack is not fully running. Start what is missing:',
    ...lines,
    '  (seed data if needed: pwsh ./scripts/Seed-EtpData.ps1 — see docs/local-dev.md)',
  ].join('\n');
}
