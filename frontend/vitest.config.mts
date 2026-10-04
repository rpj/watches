import { defineConfig } from 'vitest/config';

// Integration tests talk to a real Redis, but ONLY logical DB 15. DB 0 holds
// production data on the deployment host. `tests/setup.ts` refuses to run if
// REDIS_URL points anywhere else. Override the host with WEAR_TEST_REDIS_URL
// (keep the `/15`).
const redisUrl = process.env.WEAR_TEST_REDIS_URL || 'redis://localhost:6379/15';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    setupFiles: ['tests/setup.ts'],
    // Tests share one Redis DB and flush it between cases; never run files in parallel.
    fileParallelism: false,
    env: {
      REDIS_URL: redisUrl,
      // Test fixture only. Not a real credential.
      WEAR_API_TOKEN: 'test-token-not-a-secret',
      HANDLES_TO_WATCH: 'ryanswatches.com',
      HASHTAG_TO_WATCH: '#RyansWatches',
    },
  },
});
