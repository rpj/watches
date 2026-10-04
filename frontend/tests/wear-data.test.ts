import { describe, it, expect, beforeEach } from 'vitest';
import {
  thumbnailUrlFor,
  compareWearWatches,
  validateWearEventInput,
  parseLimit,
  listWearWatches,
  recordWear,
  listWearEvents,
  deleteWearEvent,
  getCurrentWear,
  MAX_FUTURE_MS,
  type RankedWatch,
} from '../lib/wear';
import {
  seedCollection,
  CANONICAL,
  EVENTS,
  IMAGE,
  HANDLE,
  WATCH_CITIZEN,
  WATCH_SKAGEN,
  WATCH_KURONO,
} from './fixtures';

function ranked(
  id: string,
  canonicalIndex: number,
  over: Partial<RankedWatch['watch']> = {}
): RankedWatch {
  const c = CANONICAL.find(e => e.post_id === id)!;
  return {
    canonicalIndex,
    watch: {
      id,
      brand: c.brand,
      model: c.model,
      imageUrl: null,
      thumbnailUrl: null,
      postUrl: `https://bsky.app/profile/${HANDLE}/post/${id}`,
      wearCount: 0,
      lastWornAt: null,
      postCount: 1,
      ...over,
    },
  };
}

const NOW = new Date('2026-10-04T12:00:00.000Z');
const valid = EVENTS[0];

describe('thumbnailUrlFor', () => {
  it('swaps fullsize for thumbnail', () => {
    expect(thumbnailUrlFor(IMAGE.citizen)).toBe(IMAGE.citizen.replace('feed_fullsize', 'feed_thumbnail'));
  });
  it('leaves other URLs unchanged', () => {
    expect(thumbnailUrlFor('https://example.com/a.jpg')).toBe('https://example.com/a.jpg');
  });
  it('maps null to null', () => {
    expect(thumbnailUrlFor(null)).toBeNull();
  });
});

describe('compareWearWatches', () => {
  it('orders by wearCount desc', () => {
    const a = ranked(WATCH_CITIZEN, 0, { wearCount: 1 });
    const b = ranked(WATCH_KURONO, 2, { wearCount: 3, postCount: 0 });
    expect(compareWearWatches(a, b)).toBeGreaterThan(0);
    expect(compareWearWatches(b, a)).toBeLessThan(0);
  });
  it('orders by postCount desc when wearCount ties', () => {
    const a = ranked(WATCH_CITIZEN, 0, { postCount: 2 });
    const b = ranked(WATCH_KURONO, 2, { postCount: 1 });
    expect(compareWearWatches(a, b)).toBeLessThan(0);
  });
  it('orders by canonicalIndex desc when counts tie', () => {
    const a = ranked(WATCH_SKAGEN, 1);
    const b = ranked(WATCH_KURONO, 2);
    expect(compareWearWatches(a, b)).toBeGreaterThan(0);
    expect(compareWearWatches(b, a)).toBeLessThan(0);
  });
  it('orders by brand asc, case-insensitively, when index ties', () => {
    const a = ranked(WATCH_SKAGEN, 1, { brand: 'skagen' });
    const b = ranked(WATCH_KURONO, 1, { brand: 'Kurono' });
    expect(compareWearWatches(a, b)).toBeGreaterThan(0);
    expect(compareWearWatches(b, a)).toBeLessThan(0);
  });
  it('orders by model asc, case-insensitively, when brand ties', () => {
    const a = ranked(WATCH_SKAGEN, 1, { brand: 'Same', model: 'beta' });
    const b = ranked(WATCH_KURONO, 1, { brand: 'same', model: 'Alpha' });
    expect(compareWearWatches(a, b)).toBeGreaterThan(0);
    expect(compareWearWatches(b, a)).toBeLessThan(0);
  });
  it('matches API.md order with no events', () => {
    const list = [
      ranked(WATCH_SKAGEN, 1),
      ranked(WATCH_CITIZEN, 0, { postCount: 2 }),
      ranked(WATCH_KURONO, 2),
    ];
    expect(list.sort(compareWearWatches).map(r => r.watch.brand)).toEqual(['Citizen', 'Kurono', 'Skagen']);
  });
  it('matches API.md order with events', () => {
    const list = [
      ranked(WATCH_SKAGEN, 1, { wearCount: 0 }),
      ranked(WATCH_KURONO, 2, { wearCount: 1 }),
      ranked(WATCH_CITIZEN, 0, { wearCount: 2, postCount: 2 }),
    ];
    expect(list.sort(compareWearWatches).map(r => r.watch.brand)).toEqual(['Citizen', 'Kurono', 'Skagen']);
  });
});

describe('validateWearEventInput', () => {
  it('accepts a valid body and strips unknown keys', () => {
    const r = validateWearEventInput({ ...valid, extra: 'x', recordedAt: 'nope' }, NOW);
    expect(r).toEqual({ ok: true, value: valid });
  });
  it('rejects non-objects', () => {
    for (const body of [null, undefined, 'str', 5, [valid]]) {
      expect(validateWearEventInput(body, NOW).ok).toBe(false);
    }
  });
  it('rejects each missing field', () => {
    for (const key of ['id', 'watchId', 'wornAt', 'source'] as const) {
      const body: Record<string, unknown> = { ...valid };
      delete body[key];
      expect(validateWearEventInput(body, NOW).ok).toBe(false);
    }
  });
  it('rejects bad ids', () => {
    expect(validateWearEventInput({ ...valid, id: 'short' }, NOW).ok).toBe(false);
    expect(validateWearEventInput({ ...valid, id: 'has spaces here' }, NOW).ok).toBe(false);
    expect(validateWearEventInput({ ...valid, id: 'a'.repeat(65) }, NOW).ok).toBe(false);
    expect(validateWearEventInput({ ...valid, id: 'a'.repeat(64) }, NOW).ok).toBe(true);
  });
  it('rejects an empty watchId', () => {
    expect(validateWearEventInput({ ...valid, watchId: '' }, NOW).ok).toBe(false);
  });
  it('rejects unparseable wornAt', () => {
    const r = validateWearEventInput({ ...valid, wornAt: 'yesterday' }, NOW);
    expect(r).toEqual({ ok: false, error: 'wornAt must be an ISO 8601 date' });
  });
  it('rejects wornAt more than 24h ahead and accepts 23h', () => {
    const over = new Date(NOW.getTime() + MAX_FUTURE_MS + 60 * 60 * 1000).toISOString();
    const under = new Date(NOW.getTime() + 23 * 60 * 60 * 1000).toISOString();
    expect(validateWearEventInput({ ...valid, wornAt: over }, NOW).ok).toBe(false);
    expect(validateWearEventInput({ ...valid, wornAt: under }, NOW).ok).toBe(true);
  });
  it('rejects an unknown source', () => {
    expect(validateWearEventInput({ ...valid, source: 'carrier-pigeon' }, NOW).ok).toBe(false);
  });
});

describe('parseLimit', () => {
  it('defaults to 50', () => {
    expect(parseLimit(undefined)).toEqual({ ok: true, value: 50 });
  });
  it('accepts valid values', () => {
    expect(parseLimit('500')).toEqual({ ok: true, value: 500 });
    expect(parseLimit(10)).toEqual({ ok: true, value: 10 });
  });
  it('rejects invalid values', () => {
    for (const raw of ['0', '501', '1.5', 'abc', ['5']]) {
      expect(parseLimit(raw)).toEqual({ ok: false, error: 'limit must be an integer between 1 and 500' });
    }
  });
});

describe('wear data layer (redis)', () => {
  beforeEach(async () => {
    await seedCollection();
  });

  it('lists watches with no events', async () => {
    const { watches, current } = await listWearWatches();
    expect(watches.map(w => w.brand)).toEqual(['Citizen', 'Kurono', 'Skagen']);
    const skagen = watches.find(w => w.id === WATCH_SKAGEN)!;
    expect(skagen.imageUrl).toBe(IMAGE.skagenOne);
    for (const w of watches) {
      expect(w.thumbnailUrl).toContain('/img/feed_thumbnail/');
      expect(w.wearCount).toBe(0);
      expect(w.lastWornAt).toBeNull();
    }
    expect(watches[0].postUrl.endsWith(`/post/${WATCH_CITIZEN}`)).toBe(true);
    expect(watches.map(w => w.postCount)).toEqual([2, 1, 1]);
    expect(current).toBeNull();
  });

  describe('after recording events', () => {
    beforeEach(async () => {
      for (const e of EVENTS) {
        const r = await recordWear(e);
        expect(r.ok).toBe(true);
      }
    });

    it('orders by wear and reports current', async () => {
      const { watches, current } = await listWearWatches();
      expect(watches.map(w => w.brand)).toEqual(['Citizen', 'Kurono', 'Skagen']);
      expect(watches[0].wearCount).toBe(2);
      expect(watches[0].lastWornAt).toBe(EVENTS[2].wornAt);
      expect(watches[1].wearCount).toBe(1);
      expect(watches[2].wearCount).toBe(0);
      expect(current?.id).toBe(EVENTS[1].id);
    });

    it('is idempotent on duplicate ids', async () => {
      const first = (await listWearEvents()).find(e => e.id === EVENTS[0].id)!;
      const r = await recordWear({ ...EVENTS[0], watchId: WATCH_KURONO, source: 'shortcut' }, new Date('2030-01-01T00:00:00Z'));
      expect(r.ok).toBe(true);
      if (r.ok) {
        expect(r.created).toBe(false);
        expect(r.event).toEqual(first);
      }
      const { watches } = await listWearWatches();
      expect(watches.find(w => w.id === WATCH_CITIZEN)!.wearCount).toBe(2);
    });

    it('lists events newest wornAt first', async () => {
      expect((await listWearEvents()).map(e => e.id)).toEqual([EVENTS[1].id, EVENTS[2].id, EVENTS[0].id]);
      expect((await listWearEvents(2)).map(e => e.id)).toEqual([EVENTS[1].id, EVENTS[2].id]);
    });

    it('deletes events and updates derived state', async () => {
      expect(await deleteWearEvent(EVENTS[1].id)).toBe(true);
      expect(await deleteWearEvent(EVENTS[1].id)).toBe(false);
      expect((await getCurrentWear())?.id).toBe(EVENTS[2].id);
      const { watches } = await listWearWatches();
      expect(watches.find(w => w.id === WATCH_KURONO)!.wearCount).toBe(0);
    });
  });

  it('rejects an unknown watchId', async () => {
    const r = await recordWear({ ...EVENTS[0], watchId: 'doesnotexist' });
    expect(r.ok).toBe(false);
  });
});
