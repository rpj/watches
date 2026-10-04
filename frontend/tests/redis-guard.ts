/**
 * Safety guard: integration tests flush the database they run against.
 * Production data lives in logical DB 0 on the same Redis, so we refuse to
 * run unless REDIS_URL explicitly targets DB 15.
 */
export function assertTestRedisUrl(url: string | undefined): string {
  if (!url) {
    throw new Error('REDIS_URL is not set; tests require redis://<host>:<port>/15');
  }
  let db = '';
  try {
    db = new URL(url).pathname.replace(/^\//, '');
  } catch {
    throw new Error(`REDIS_URL "${url}" is not a valid URL`);
  }
  if (db !== '15') {
    throw new Error(
      `Refusing to run tests against REDIS_URL="${url}": tests flush the DB and must target logical DB 15 (e.g. redis://localhost:6379/15).`
    );
  }
  return url;
}
