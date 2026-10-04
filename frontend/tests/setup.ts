import { afterAll } from 'vitest';
import { assertTestRedisUrl } from './redis-guard';

// Hard stop before any test file loads if REDIS_URL is not DB 15.
assertTestRedisUrl(process.env.REDIS_URL);

afterAll(async () => {
  // Each test file gets its own module registry (vitest isolates), hence its
  // own singleton client; close it so the worker can exit promptly.
  const { getRedisClient } = await import('../lib/redis');
  try {
    await getRedisClient().quit();
  } catch {
    // already closed
  }
});
