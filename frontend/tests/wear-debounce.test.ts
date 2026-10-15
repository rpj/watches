import { describe, it, expect, beforeEach } from 'vitest';
import { recordWear, listWearWatches, listWearEvents, WEAR_DEBOUNCE_MS } from '../lib/wear';
import { seedCollection, WATCH_CITIZEN, WATCH_KURONO } from './fixtures';
import { callApi } from './helpers';
import eventsHandler from '../pages/api/wear/events';

const T0 = '2026-10-04T08:00:00-07:00';
const MINUTE = 60_000;

/** ISO timestamp `offsetMs` after T0 (UTC form; the server only compares instants). */
function at(offsetMs: number): string {
  return new Date(Date.parse(T0) + offsetMs).toISOString();
}

/** Ids must match EVENT_ID_PATTERN (8..64 chars of [A-Za-z0-9-]). */
const id = (n: number) => `debounce-${n}-aaaaaaaa`;

async function createdFlag(result: Awaited<ReturnType<typeof recordWear>>): Promise<boolean> {
  if (!result.ok) throw new Error(result.error);
  return result.created;
}

describe('recordWear double-tap collapse', () => {
  beforeEach(async () => {
    await seedCollection();
  });

  it('collapses a re-tap of the current watch inside the window', async () => {
    const first = await recordWear({ id: id(1), watchId: WATCH_CITIZEN, wornAt: T0, source: 'app' });
    expect(await createdFlag(first)).toBe(true);

    const second = await recordWear({ id: id(2), watchId: WATCH_CITIZEN, wornAt: at(5 * MINUTE), source: 'widget' });
    expect(second.ok).toBe(true);
    if (!second.ok || !first.ok) throw new Error('unreachable');
    expect(second.created).toBe(false);
    expect(second.event).toEqual(first.event);

    const { watches, current } = await listWearWatches();
    expect(watches.find(w => w.id === WATCH_CITIZEN)?.wearCount).toBe(1);
    expect(current?.id).toBe(id(1));
    expect(await listWearEvents()).toHaveLength(1);
  });

  it('logs again once the window has passed', async () => {
    await recordWear({ id: id(1), watchId: WATCH_CITIZEN, wornAt: T0, source: 'app' });
    const later = await recordWear({ id: id(2), watchId: WATCH_CITIZEN, wornAt: at(WEAR_DEBOUNCE_MS), source: 'app' });
    expect(await createdFlag(later)).toBe(true);
    expect(await listWearEvents()).toHaveLength(2);
  });

  it('logs a different watch inside the window, and the first watch again after switching', async () => {
    await recordWear({ id: id(1), watchId: WATCH_CITIZEN, wornAt: T0, source: 'app' });
    const kurono = await recordWear({ id: id(2), watchId: WATCH_KURONO, wornAt: at(1 * MINUTE), source: 'app' });
    expect(await createdFlag(kurono)).toBe(true);
    // Citizen is no longer current, so re-logging it is a real change.
    const back = await recordWear({ id: id(3), watchId: WATCH_CITIZEN, wornAt: at(2 * MINUTE), source: 'app' });
    expect(await createdFlag(back)).toBe(true);
    expect(await listWearEvents()).toHaveLength(3);
  });

  it('treats an earlier wornAt inside the window as a duplicate too (late offline flush)', async () => {
    await recordWear({ id: id(1), watchId: WATCH_CITIZEN, wornAt: T0, source: 'app' });
    const earlier = await recordWear({ id: id(2), watchId: WATCH_CITIZEN, wornAt: at(-3 * MINUTE), source: 'widget' });
    expect(await createdFlag(earlier)).toBe(false);
    expect(await listWearEvents()).toHaveLength(1);
  });

  it('still answers an explicit retry with the stored event, not the current one', async () => {
    const first = await recordWear({ id: id(1), watchId: WATCH_CITIZEN, wornAt: T0, source: 'app' });
    await recordWear({ id: id(2), watchId: WATCH_KURONO, wornAt: at(1 * MINUTE), source: 'app' });
    const retry = await recordWear({ id: id(1), watchId: WATCH_CITIZEN, wornAt: T0, source: 'app' });
    expect(retry.ok && !retry.created).toBe(true);
    if (!retry.ok || !first.ok) throw new Error('unreachable');
    expect(retry.event).toEqual(first.event);
    expect(await listWearEvents()).toHaveLength(2);
  });

  it('surfaces through POST /api/wear/events as 200 created:false with the current event', async () => {
    const first = await callApi(eventsHandler, {
      method: 'POST',
      body: { id: id(1), watchId: WATCH_CITIZEN, wornAt: T0, source: 'app' },
    });
    expect(first.status).toBe(201);

    const second = await callApi(eventsHandler, {
      method: 'POST',
      body: { id: id(2), watchId: WATCH_CITIZEN, wornAt: at(30_000), source: 'widget' },
    });
    expect(second.status).toBe(200);
    expect(second.json()).toEqual({ event: first.json().event, created: false });
  });
});
