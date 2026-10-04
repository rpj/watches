/**
 * Canonical fixture set for the wear API. Mirrors the "Fixtures" section of
 * ios-app/API.md exactly; the Swift tests use the same data, so change both
 * together.
 */
import { getRedisClient, type Post, type WatchMeta, type CanonicalEntry } from '../lib/redis';
import { assertTestRedisUrl } from './redis-guard';

export const DID = 'did:plc:ep6hd5cp5gxj6pifezbar6nc';
export const HANDLE = 'ryanswatches.com';
const CDN = `https://cdn.bsky.app/img/feed_fullsize/plain/${DID}`;

export const WATCH_CITIZEN = '3m2uvdvq7622g';
export const WATCH_SKAGEN = '3m2uxrekinc2e';
export const WATCH_KURONO = '3mwz3ctxxnc26';
export const POST_CITIZEN_FOLLOWON = '3m3followon001';

/** Oldest first, exactly as stored in __doodles:watch-canonical. */
export const CANONICAL: CanonicalEntry[] = [
  { post_id: WATCH_CITIZEN, brand: 'Citizen', model: 'Eco Drive E110-K16750' },
  { post_id: WATCH_SKAGEN, brand: 'Skagen', model: '233LTMN Quartz' },
  { post_id: WATCH_KURONO, brand: 'Kurono', model: 'Malachite' },
];

export const IMAGE = {
  citizen: `${CDN}/bafkreicitizenaaaa`,
  skagenZero: `${CDN}/bafkreiskagenzero`,
  skagenOne: `${CDN}/bafkreiskagenone`,
  kurono: `${CDN}/bafkreikuronomalachite`,
  citizenBand: `${CDN}/bafkreicitizenband`,
} as const;

function post(basePostId: string, imageIndex: number, imageUrl: string, dayOffset: number, text: string): Post {
  const createdAt = new Date(Date.UTC(2026, 4, 1 + dayOffset)).toISOString(); // 2026-05-01 + offset
  return {
    uri: `at://${DID}/app.bsky.feed.post/${basePostId}#image${imageIndex}`,
    authorHandle: HANDLE,
    authorDisplayName: "Ryan's Watches",
    text,
    imageUrls: [imageUrl],
    createdAt,
    postUrl: `https://bsky.app/profile/${HANDLE}/post/${basePostId}`,
  };
}

/** Chronological order (oldest first). Stored newest-first in Redis via LPUSH. */
export const POSTS: Post[] = [
  post(WATCH_CITIZEN, 0, IMAGE.citizen, 0, 'Citizen Eco Drive #RyansWatches'),
  post(WATCH_SKAGEN, 0, IMAGE.skagenZero, 1, 'Skagen 233LTMN #RyansWatches'),
  post(WATCH_SKAGEN, 1, IMAGE.skagenOne, 1, 'Skagen 233LTMN #RyansWatches'),
  post(WATCH_KURONO, 0, IMAGE.kurono, 2, 'Kurono Malachite #RyansWatches'),
  post(POST_CITIZEN_FOLLOWON, 0, IMAGE.citizenBand, 3, 'New strap on the Citizen #RyansWatches'),
];

export const META: Record<string, WatchMeta> = {
  [WATCH_CITIZEN]: { kind: 'unique-watch', brand: 'Citizen', model: 'Eco Drive E110-K16750', references_post_id: null, confidence: 0.95, classified_at: '2026-05-04T00:19:19.968Z' },
  [WATCH_SKAGEN]: { kind: 'unique-watch', brand: 'Skagen', model: '233LTMN Quartz', references_post_id: null, confidence: 0.9, classified_at: '2026-05-04T00:19:19.968Z' },
  [WATCH_KURONO]: { kind: 'unique-watch', brand: 'Kurono', model: 'Malachite', references_post_id: null, confidence: 0.97, classified_at: '2026-10-04T00:00:00.000Z' },
  [POST_CITIZEN_FOLLOWON]: { kind: 'follow-on', brand: 'Citizen', model: 'Eco Drive E110-K16750', references_post_id: WATCH_CITIZEN, confidence: 0.8, classified_at: '2026-05-06T00:00:00.000Z' },
};

export const HERO_OVERRIDES: Record<string, string> = {
  [WATCH_SKAGEN]: '1',
};

/** Events in the order API.md says to insert them. */
export const EVENTS = [
  { id: '11111111-1111-4111-8111-111111111111', watchId: WATCH_CITIZEN, wornAt: '2026-10-01T08:00:00-07:00', source: 'app' as const },
  { id: '22222222-2222-4222-8222-222222222222', watchId: WATCH_KURONO, wornAt: '2026-10-03T08:05:00-07:00', source: 'notification' as const },
  { id: '33333333-3333-4333-8333-333333333333', watchId: WATCH_CITIZEN, wornAt: '2026-10-02T07:58:00-07:00', source: 'widget' as const },
];

/** Wipe DB 15 (and only DB 15). */
export async function resetDb(): Promise<void> {
  assertTestRedisUrl(process.env.REDIS_URL);
  await getRedisClient().flushdb();
}

/** Flush, then write canonical + posts + meta + hero overrides. Leaves wear keys empty. */
export async function seedCollection(): Promise<void> {
  await resetDb();
  const client = getRedisClient();
  const pipe = client.pipeline();

  for (const entry of CANONICAL) {
    pipe.rpush('__doodles:watch-canonical', JSON.stringify(entry));
  }
  // all-doodles:posts is LPUSH'd by the listener, so push oldest first to end up newest-first.
  for (const p of POSTS) {
    pipe.lpush('all-doodles:posts', JSON.stringify(p));
    pipe.set(`post:${p.uri}`, JSON.stringify(p));
    pipe.rpush(`handle:${HANDLE}:posts`, p.uri);
  }
  pipe.sadd('handles:all', HANDLE);
  for (const [id, meta] of Object.entries(META)) {
    pipe.hset('__doodles:watch-meta', id, JSON.stringify(meta));
  }
  for (const [id, idx] of Object.entries(HERO_OVERRIDES)) {
    pipe.hset('__doodles:hero-overrides', id, idx);
  }
  await pipe.exec();
}
