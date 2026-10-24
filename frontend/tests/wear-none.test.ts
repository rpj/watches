import { describe, it, expect, beforeEach } from 'vitest';
import { recordWear, listWearWatches, getWearingNow, NONE_WATCH_ID } from '../lib/wear';
import { computeWearage } from '../lib/wearage';
import type { WearEvent } from '../lib/wear';
import { seedCollection, EVENTS, WATCH_CITIZEN, WATCH_KURONO } from './fixtures';
import { callApi } from './helpers';
import eventsHandler from '../pages/api/wear/events';
import wearingHandler from '../pages/api/wearing';

const HOUR = 3_600_000;
const TZ = 'America/Los_Angeles';

function ev(id: string, watchId: string, wornAt: string): WearEvent {
  return { id, watchId, wornAt, source: 'app', recordedAt: wornAt };
}

describe('the reserved "nothing on" entry', () => {
  beforeEach(async () => {
    await seedCollection();
  });

  it('is accepted by recordWear without being canonical', async () => {
    const r = await recordWear({ id: 'nothing-0001-aaaa', watchId: NONE_WATCH_ID, wornAt: '2026-10-04T21:00:00-07:00', source: 'app' });
    expect(r.ok && r.created).toBe(true);
    const still = await recordWear({ id: 'nothing-0002-aaaa', watchId: 'not-a-watch', wornAt: '2026-10-04T21:01:00-07:00', source: 'app' });
    expect(still.ok).toBe(false);
  });

  it('becomes current but never appears in the watch list', async () => {
    await recordWear(EVENTS[1]);
    await recordWear({ id: 'nothing-0001-aaaa', watchId: NONE_WATCH_ID, wornAt: '2026-10-04T21:00:00-07:00', source: 'app' });
    const { watches, current } = await listWearWatches();
    expect(current?.watchId).toBe(NONE_WATCH_ID);
    expect(watches.map(w => w.id)).not.toContain(NONE_WATCH_ID);
    expect(watches.find(w => w.id === WATCH_KURONO)?.wearCount).toBe(1);
  });

  it('surfaces as watch: null from getWearingNow and /api/wearing', async () => {
    await recordWear({ id: 'nothing-0001-aaaa', watchId: NONE_WATCH_ID, wornAt: '2026-10-04T21:00:00-07:00', source: 'app' });
    const now = await getWearingNow();
    expect(now?.watch).toBeNull();
    expect(now?.event.watchId).toBe(NONE_WATCH_ID);
    const res = await callApi(wearingHandler, { token: null });
    expect(res.status).toBe(200);
    expect(res.json().wearing.watch).toBeNull();
  });

  it('is debounced like any other entry through the API', async () => {
    const first = await callApi(eventsHandler, {
      method: 'POST',
      body: { id: 'nothing-0001-aaaa', watchId: NONE_WATCH_ID, wornAt: '2026-10-04T21:00:00-07:00', source: 'app' },
    });
    expect(first.status).toBe(201);
    const second = await callApi(eventsHandler, {
      method: 'POST',
      body: { id: 'nothing-0002-aaaa', watchId: NONE_WATCH_ID, wornAt: '2026-10-04T21:03:00-07:00', source: 'widget' },
    });
    expect(second.status).toBe(200);
    expect(second.json().created).toBe(false);
  });
});

describe('computeWearage with a bare wrist', () => {
  const base = { timeZone: TZ, sleepHours: 7 };

  it('ends the previous watch credit and deducts nothing at midnight', () => {
    const s = computeWearage(
      [ev('e1', WATCH_CITIZEN, '2026-10-22T08:00:00-07:00'), ev('e2', NONE_WATCH_ID, '2026-10-22T18:00:00-07:00')],
      { ...base, now: new Date('2026-10-23T00:00:00-07:00') }
    );
    // Citizen 08:00→18:00 = 10h, untouched: the bare wrist is "on" at midnight, so no sleep deduction lands on a watch.
    expect(s.shares).toEqual([
      { watchId: WATCH_CITIZEN, ms: 10 * HOUR, share: 1, wears: 1, lastWornAt: '2026-10-22T08:00:00-07:00' },
    ]);
    expect(s.totalMs).toBe(10 * HOUR);
    expect(s.daysTracked).toBe(1);
  });

  it('is never listed and earns nothing across days', () => {
    const s = computeWearage(
      [ev('e1', NONE_WATCH_ID, '2026-10-20T08:00:00-07:00'), ev('e2', WATCH_KURONO, '2026-10-22T09:00:00-07:00')],
      { ...base, now: new Date('2026-10-22T12:00:00-07:00') }
    );
    expect(s.shares.map(x => x.watchId)).toEqual([WATCH_KURONO]);
    expect(s.shares[0].ms).toBe(3 * HOUR);
    expect(s.daysTracked).toBe(3);
  });
});
