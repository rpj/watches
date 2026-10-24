import { describe, it, expect } from 'vitest';
import {
  computeWearage,
  localDayStart,
  nextLocalDayStart,
  localDaysBetween,
  zoneOffsetMs,
} from '../lib/wearage';
import type { WearEvent } from '../lib/wear';

const TZ = 'America/Los_Angeles';
const HOUR = 3_600_000;

function ev(id: string, watchId: string, wornAt: string): WearEvent {
  return { id, watchId, wornAt, source: 'app', recordedAt: wornAt };
}
const at = (iso: string) => new Date(iso);
const ms = (iso: string) => Date.parse(iso);

describe('local day math (America/Los_Angeles)', () => {
  it('finds local midnight for a PDT instant', () => {
    expect(localDayStart(ms('2026-10-24T12:00:00-07:00'), TZ)).toBe(ms('2026-10-24T00:00:00-07:00'));
    expect(localDayStart(ms('2026-10-24T00:00:00-07:00'), TZ)).toBe(ms('2026-10-24T00:00:00-07:00'));
    // 23:30 PDT on the 23rd is already the 24th in UTC; the local day must win.
    expect(localDayStart(ms('2026-10-23T23:30:00-07:00'), TZ)).toBe(ms('2026-10-23T00:00:00-07:00'));
  });

  it('handles the fall-back day (2026-11-01, 25 hours) and spring-forward day (2026-03-08, 23 hours)', () => {
    const fallBackStart = localDayStart(ms('2026-11-01T12:00:00-08:00'), TZ);
    expect(fallBackStart).toBe(ms('2026-11-01T00:00:00-07:00'));
    expect(nextLocalDayStart(fallBackStart, TZ) - fallBackStart).toBe(25 * HOUR);

    const springStart = localDayStart(ms('2026-03-08T12:00:00-07:00'), TZ);
    expect(springStart).toBe(ms('2026-03-08T00:00:00-08:00'));
    expect(nextLocalDayStart(springStart, TZ) - springStart).toBe(23 * HOUR);

    const ordinary = localDayStart(ms('2026-10-22T12:00:00-07:00'), TZ);
    expect(nextLocalDayStart(ordinary, TZ) - ordinary).toBe(24 * HOUR);
  });

  it('reports offsets on both sides of the DST change', () => {
    expect(zoneOffsetMs(ms('2026-10-31T12:00:00-07:00'), TZ)).toBe(-7 * HOUR);
    expect(zoneOffsetMs(ms('2026-11-02T12:00:00-08:00'), TZ)).toBe(-8 * HOUR);
  });

  it('counts inclusive local days', () => {
    expect(localDaysBetween(ms('2026-10-22T08:00:00-07:00'), ms('2026-10-24T12:00:00-07:00'), TZ)).toBe(3);
    expect(localDaysBetween(ms('2026-10-22T08:00:00-07:00'), ms('2026-10-22T09:00:00-07:00'), TZ)).toBe(1);
    expect(localDaysBetween(ms('2026-10-22T08:00:00-07:00'), ms('2026-10-22T07:00:00-07:00'), TZ)).toBe(0);
  });
});

describe('computeWearage', () => {
  const base = { timeZone: TZ, sleepHours: 7 };

  it('is empty with no events', () => {
    const s = computeWearage([], { ...base, now: at('2026-10-24T12:00:00-07:00') });
    expect(s).toEqual({ totalMs: 0, daysTracked: 0, firstEventAt: null, shares: [] });
  });

  it('credits a single watch across completed days minus sleep, and the partial day in full', () => {
    const s = computeWearage(
      [ev('e1', 'A', '2026-10-22T08:00:00-07:00')],
      { ...base, now: at('2026-10-24T12:00:00-07:00') }
    );
    // Oct 22: 16h − 7 = 9h; Oct 23: 24h − 7 = 17h; Oct 24 (partial): 12h.
    expect(s.totalMs).toBe(38 * HOUR);
    expect(s.daysTracked).toBe(3);
    expect(s.firstEventAt).toBe('2026-10-22T08:00:00-07:00');
    expect(s.shares).toEqual([
      { watchId: 'A', ms: 38 * HOUR, share: 1, wears: 1, lastWornAt: '2026-10-22T08:00:00-07:00' },
    ]);
  });

  it('splits a mid-day switch and deducts sleep only from the watch on at midnight', () => {
    const s = computeWearage(
      [ev('e1', 'A', '2026-10-22T08:00:00-07:00'), ev('e2', 'B', '2026-10-22T14:00:00-07:00')],
      { ...base, now: at('2026-10-23T00:00:00-07:00') }
    );
    // A: 6h untouched. B: 10h − 7 = 3h.
    expect(s.shares.map(x => [x.watchId, x.ms / HOUR])).toEqual([['A', 6], ['B', 3]]);
    expect(s.totalMs).toBe(9 * HOUR);
    expect(s.shares[0].share).toBeCloseTo(6 / 9, 12);
    expect(s.shares[1].share).toBeCloseTo(3 / 9, 12);
  });

  it('clamps a late switch to zero without spilling the deduction backwards', () => {
    const s = computeWearage(
      [ev('e1', 'A', '2026-10-22T08:00:00-07:00'), ev('e2', 'B', '2026-10-22T23:30:00-07:00')],
      { ...base, now: at('2026-10-23T00:00:00-07:00') }
    );
    const byId = Object.fromEntries(s.shares.map(x => [x.watchId, x]));
    expect(byId.A.ms).toBe(15.5 * HOUR);
    expect(byId.B.ms).toBe(0);
    expect(byId.B.wears).toBe(1);
    expect(byId.A.share).toBe(1);
    expect(byId.B.share).toBe(0);
  });

  it('clips to the window: earlier events still define the wearer, but only in-window time and wears count', () => {
    const s = computeWearage(
      [ev('e1', 'A', '2026-10-20T08:00:00-07:00'), ev('e2', 'B', '2026-10-23T10:00:00-07:00')],
      { ...base, now: at('2026-10-23T12:00:00-07:00'), since: at('2026-10-22T00:00:00-07:00') }
    );
    const byId = Object.fromEntries(s.shares.map(x => [x.watchId, x]));
    // A: Oct 22 full (24 − 7 = 17h) + Oct 23 00:00→10:00 (10h, but A hands over before midnight so no deduction) = 27h.
    expect(byId.A.ms).toBe(27 * HOUR);
    expect(byId.A.wears).toBe(0);
    expect(byId.A.lastWornAt).toBeNull();
    // B: 10:00→12:00 on the partial day.
    expect(byId.B.ms).toBe(2 * HOUR);
    expect(byId.B.wears).toBe(1);
    expect(s.daysTracked).toBe(2);
  });

  it('deducts exactly sleepHours on the 25-hour fall-back day', () => {
    const s = computeWearage(
      [ev('e1', 'A', '2026-10-31T12:00:00-07:00')],
      { ...base, now: at('2026-11-02T00:00:00-08:00') }
    );
    // Oct 31: 12h − 7 = 5h. Nov 1: 25h − 7 = 18h.
    expect(s.shares[0].ms).toBe(23 * HOUR);
    expect(s.daysTracked).toBe(2);
  });

  it('shares sum to one and sort by time then wears', () => {
    const s = computeWearage(
      [
        ev('e1', 'A', '2026-10-20T08:00:00-07:00'),
        ev('e2', 'B', '2026-10-21T08:00:00-07:00'),
        ev('e3', 'C', '2026-10-21T20:00:00-07:00'),
        ev('e4', 'B', '2026-10-22T08:00:00-07:00'),
      ],
      { ...base, now: at('2026-10-23T12:00:00-07:00') }
    );
    const sum = s.shares.reduce((acc, x) => acc + x.share, 0);
    expect(Math.abs(sum - 1)).toBeLessThan(1e-9);
    expect(s.shares.map(x => x.watchId)).toEqual(['B', 'A', 'C']);
    expect(s.shares.find(x => x.watchId === 'B')?.wears).toBe(2);
  });

  it('ignores unparseable and future events', () => {
    const s = computeWearage(
      [ev('bad', 'Z', 'not a date'), ev('future', 'Y', '2027-01-01T00:00:00-08:00'), ev('e1', 'A', '2026-10-23T08:00:00-07:00')],
      { ...base, now: at('2026-10-23T12:00:00-07:00') }
    );
    expect(s.shares.map(x => x.watchId)).toEqual(['A']);
    expect(s.totalMs).toBe(4 * HOUR);
  });

  it('honours sleepHours = 0', () => {
    const s = computeWearage(
      [ev('e1', 'A', '2026-10-22T00:00:00-07:00')],
      { ...base, sleepHours: 0, now: at('2026-10-24T00:00:00-07:00') }
    );
    expect(s.totalMs).toBe(48 * HOUR);
  });
});
