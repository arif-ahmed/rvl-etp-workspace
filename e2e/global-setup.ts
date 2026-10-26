import { globalSetupError } from './fixtures/health';

/**
 * Fails fast — with the exact commands to start the stack — when the local
 * platform is not running. Better than cryptic timeouts in every test.
 */
export default async function () {
  const message = await globalSetupError();
  if (message) {
    console.error(`\n  ${message}\n`);
    throw new Error(message);
  }
}
