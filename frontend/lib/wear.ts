import { getRedisClient, applyHeroOverrides } from './redis';
import type { Post, WatchMeta, CanonicalEntry } from './redis';
import { groupPostsByBaseUri } from './utils';

export const WEAR_EVENTS_KEY = '__doodles:wear-events';
export const WEAR_TIMELINE_KEY = '__doodles:wear-timeline';

const WATCH_META_KEY = '__doodles:watch-meta';
const WATCH_CANONICAL_KEY = '__doodles:watch-canonical';
const POSTS_KEY = 'all-doodles:posts';

export const WEAR_SOURCES = ['app', 'notification', 'widget', 'shortcut'] as const;
export type WearSource = (typeof WEAR_SOURCES)[number];

export interface WearEvent {
  id: string;
  watchId: string;
  wornAt: string;
  source: WearSource;
  recordedAt: string;
}

export interface WearWatch {
  id: string;
  brand: string;
  model: string;
  imageUrl: string | null;
  thumbnailUrl: string | null;
  postUrl: string;
  wearCount: number;
  lastWornAt: string | null;
  postCount: number;
}

export interface RankedWatch {
  watch: WearWatch;
  canonicalIndex: number;
}

export interface WearEventInput {
  id: string;
  watchId: string;
  wornAt: string;
  source: WearSource;
}

export type ValidationResult<T> = { ok: true; value: T } | { ok: false; error: string };

export const EVENT_ID_PATTERN = /^[A-Za-z0-9-]{8,64}$/;
export const MAX_FUTURE_MS = 24 * 60 * 60 * 1000;

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 500;

const BASE_ID_PATTERN = /\/app\.bsky\.feed\.post\/([^#]+)/;

function parseJson<T>(raw: string | null | undefined): T | null {
  if (!raw) return null;
  try {
    const v = JSON.parse(raw);
    return v && typeof v === 'object' ? (v as T) : null;
  } catch {
    return null;
  }
}

/**
 * Derive the Bluesky CDN thumbnail URL from a fullsize image URL. Returns the
 * input unchanged when the fullsize segment is absent, and null for null.
 */
export function thumbnailUrlFor(imageUrl: string | null): string | null {
  if (imageUrl === null) return null;
  return imageUrl.replace('/img/feed_fullsize/', '/img/feed_thumbnail/');
}

/**
 * Sort comparator for the wear picker: wearCount desc, postCount desc,
 * canonicalIndex desc (newer first), then brand and model ascending
 * (case-insensitive).
 */
export function compareWearWatches(a: RankedWatch, b: RankedWatch): number {
  return (
    b.watch.wearCount - a.watch.wearCount ||
    b.watch.postCount - a.watch.postCount ||
    b.canonicalIndex - a.canonicalIndex ||
    a.watch.brand.localeCompare(b.watch.brand, undefined, { sensitivity: 'base' }) ||
    a.watch.model.localeCompare(b.watch.model, undefined, { sensitivity: 'base' })
  );
}

/**
 * Validate a POST body for recording a wear. Unknown keys are dropped.
 * Existence of watchId is checked later by recordWear.
 */
export function validateWearEventInput(
  body: unknown,
  now: Date = new Date()
): ValidationResult<WearEventInput> {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return { ok: false, error: 'Body must be a JSON object' };
  }
  const b = body as Record<string, unknown>;

  if (typeof b.id !== 'string' || !EVENT_ID_PATTERN.test(b.id)) {
    return { ok: false, error: 'id must be 8-64 characters of letters, digits, or hyphens' };
  }
  if (typeof b.watchId !== 'string' || b.watchId.length === 0) {
    return { ok: false, error: 'watchId must be a non-empty string' };
  }
  if (typeof b.wornAt !== 'string') {
    return { ok: false, error: 'wornAt must be an ISO 8601 date' };
  }
  const wornMs = Date.parse(b.wornAt);
  if (Number.isNaN(wornMs)) {
    return { ok: false, error: 'wornAt must be an ISO 8601 date' };
  }
  if (wornMs > now.getTime() + MAX_FUTURE_MS) {
    return { ok: false, error: 'wornAt must not be more than 24 hours in the future' };
  }
  if (typeof b.source !== 'string' || !(WEAR_SOURCES as readonly string[]).includes(b.source)) {
    return { ok: false, error: `source must be one of: ${WEAR_SOURCES.join(', ')}` };
  }

  return {
    ok: true,
    value: {
      id: b.id,
      watchId: b.watchId,
      wornAt: b.wornAt,
      source: b.source as WearSource,
    },
  };
}

/**
 * Parse the `limit` query value: undefined gives 50; otherwise a number or
 * digit string that is an integer in 1..500.
 */
export function parseLimit(raw: unknown): ValidationResult<number> {
  const error = { ok: false as const, error: `limit must be an integer between 1 and ${MAX_LIMIT}` };
  if (raw === undefined) return { ok: true, value: DEFAULT_LIMIT };
  let n: number;
  if (typeof raw === 'number') {
    n = raw;
  } else if (typeof raw === 'string' && /^\d+$/.test(raw)) {
    n = Number(raw);
  } else {
    return error;
  }
  if (!Number.isInteger(n) || n < 1 || n > MAX_LIMIT) return error;
  return { ok: true, value: n };
}

function parseCanonical(rawList: string[]): CanonicalEntry[] {
  const out: CanonicalEntry[] = [];
  for (const raw of rawList) {
    const c = parseJson<CanonicalEntry>(raw);
    if (c && typeof c.post_id === 'string') out.push(c);
  }
  return out;
}

/**
 * Build the wear picker list (sorted) and the current wear event, deriving
 * all counts from the canonical list, posts, classifier meta, and wear keys.
 */
export async function listWearWatches(): Promise<{ watches: WearWatch[]; current: WearEvent | null }> {
  const client = getRedisClient();

  const [canonicalRaw, postsRaw, metaRaw, timelineRaw, eventsRaw] = await Promise.all([
    client.lrange(WATCH_CANONICAL_KEY, 0, -1),
    client.lrange(POSTS_KEY, 0, -1),
    client.hgetall(WATCH_META_KEY),
    client.zrevrange(WEAR_TIMELINE_KEY, 0, -1, 'WITHSCORES'),
    client.hgetall(WEAR_EVENTS_KEY),
  ]);

  const canonical = parseCanonical(canonicalRaw);

  const posts: Post[] = [];
  for (const raw of postsRaw) {
    const p = parseJson<Post>(raw);
    if (p && typeof p.uri === 'string' && Array.isArray(p.imageUrls)) posts.push(p);
  }
  const grouped = await applyHeroOverrides(client, groupPostsByBaseUri(posts));
  const postById = new Map<string, Post>();
  for (const p of grouped) {
    const m = p.uri.match(BASE_ID_PATTERN);
    if (m) postById.set(m[1], p);
  }

  const postCounts = new Map<string, number>();
  const bump = (id: string) => postCounts.set(id, (postCounts.get(id) ?? 0) + 1);
  for (const [id, raw] of Object.entries(metaRaw)) {
    const m = parseJson<WatchMeta>(raw);
    if (!m) continue;
    if (m.kind === 'unique-watch') bump(id);
    else if (m.kind === 'follow-on' && m.references_post_id) bump(m.references_post_id);
  }

  const wearCounts = new Map<string, number>();
  const lastWorn = new Map<string, string>();
  let current: WearEvent | null = null;
  // WITHSCORES output alternates member, score; highest score first.
  for (let i = 0; i < timelineRaw.length; i += 2) {
    const ev = parseJson<WearEvent>(eventsRaw[timelineRaw[i]]);
    if (!ev || typeof ev.watchId !== 'string') continue;
    if (current === null) current = ev;
    wearCounts.set(ev.watchId, (wearCounts.get(ev.watchId) ?? 0) + 1);
    if (!lastWorn.has(ev.watchId)) lastWorn.set(ev.watchId, ev.wornAt);
  }

  const firstHandle = (process.env.HANDLES_TO_WATCH ?? '').split(',')[0].trim() || '_';

  const ranked: RankedWatch[] = canonical.map((c, canonicalIndex) => {
    const post = postById.get(c.post_id);
    const imageUrl = post?.imageUrls[0] ?? null;
    return {
      canonicalIndex,
      watch: {
        id: c.post_id,
        brand: c.brand,
        model: c.model,
        imageUrl,
        thumbnailUrl: thumbnailUrlFor(imageUrl),
        postUrl: post?.postUrl ?? `https://bsky.app/profile/${firstHandle}/post/${c.post_id}`,
        wearCount: wearCounts.get(c.post_id) ?? 0,
        lastWornAt: lastWorn.get(c.post_id) ?? null,
        postCount: postCounts.get(c.post_id) ?? 0,
      },
    };
  });

  ranked.sort(compareWearWatches);
  return { watches: ranked.map(r => r.watch), current };
}

/**
 * Record a wear event idempotently. Returns created=false with the stored
 * event when the id already exists, or an error for an unknown watchId.
 */
export async function recordWear(
  input: WearEventInput,
  now: Date = new Date()
): Promise<{ ok: true; event: WearEvent; created: boolean } | { ok: false; error: string }> {
  const client = getRedisClient();

  const canonical = parseCanonical(await client.lrange(WATCH_CANONICAL_KEY, 0, -1));
  if (!canonical.some(c => c.post_id === input.watchId)) {
    return { ok: false, error: 'Unknown watchId' };
  }

  const event: WearEvent = { ...input, recordedAt: now.toISOString() };
  const added = await client.hsetnx(WEAR_EVENTS_KEY, input.id, JSON.stringify(event));
  if (added === 1) {
    await client.zadd(WEAR_TIMELINE_KEY, Date.parse(input.wornAt), input.id);
    return { ok: true, event, created: true };
  }

  const stored = parseJson<WearEvent>(await client.hget(WEAR_EVENTS_KEY, input.id));
  return { ok: true, event: stored ?? event, created: false };
}

/**
 * List wear events, newest wornAt first, up to `limit`.
 */
export async function listWearEvents(limit: number = DEFAULT_LIMIT): Promise<WearEvent[]> {
  const client = getRedisClient();
  const ids = await client.zrevrange(WEAR_TIMELINE_KEY, 0, limit - 1);
  if (ids.length === 0) return [];
  const raws = await client.hmget(WEAR_EVENTS_KEY, ...ids);
  const out: WearEvent[] = [];
  for (const raw of raws) {
    const ev = parseJson<WearEvent>(raw);
    if (ev) out.push(ev);
  }
  return out;
}

/**
 * Delete a wear event by id. Returns true if it existed.
 */
export async function deleteWearEvent(id: string): Promise<boolean> {
  const client = getRedisClient();
  const results = await client.pipeline().hdel(WEAR_EVENTS_KEY, id).zrem(WEAR_TIMELINE_KEY, id).exec();
  const hdel = results?.[0];
  return !!hdel && !hdel[0] && hdel[1] === 1;
}

/**
 * The event with the greatest wornAt, or null when none exist.
 */
export async function getCurrentWear(): Promise<WearEvent | null> {
  const client = getRedisClient();
  const [id] = await client.zrevrange(WEAR_TIMELINE_KEY, 0, 0);
  if (!id) return null;
  return parseJson<WearEvent>(await client.hget(WEAR_EVENTS_KEY, id));
}
