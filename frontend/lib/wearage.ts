import type { WearEvent } from './wear';

/**
 * Reserved watchId meaning "no watch on the wrist". Logging it ends the
 * previous watch's credit without starting anyone else's. Never appears in
 * the watch list. Defined here (the pure module) so lib/wear.ts can re-export
 * it without a circular import.
 */
export const NONE_WATCH_ID = 'none';

/**
 * "Wearage": each watch's share of awake wrist-time.
 *
 * A watch is credited from the moment it is logged until the next log (the
 * latest log runs to `now`). At the end of every completed local day, up to
 * `sleepHours` hours are deducted from whichever watch is on the wrist at
 * midnight: a cheap, honest stand-in for "I never wear a watch at night".
 * Shares are of the resulting total, never raw hours.
 *
 * Pure: no Redis, no env. Local days come from `timeZone` via Intl.
 */

export interface WearageOptions {
  /** IANA zone used for day boundaries, e.g. "America/Los_Angeles". */
  timeZone: string;
  /** Hours deducted at the end of each completed day (0 disables). */
  sleepHours: number;
  now: Date;
  /** Only credit time at or after this instant (events before it still define who is wearing what). */
  since?: Date;
}

export interface WearageShare {
  watchId: string;
  /** Awake wrist-time credited in the window. */
  ms: number;
  /** ms / totalMs, 0 when totalMs is 0. */
  share: number;
  /** Events logged for this watch inside the window. */
  wears: number;
  lastWornAt: string | null;
}

export interface WearageSummary {
  totalMs: number;
  /** Local days from the first credited instant through `now`, inclusive. */
  daysTracked: number;
  firstEventAt: string | null;
  /** Sorted by ms desc, then wears desc, then watchId. */
  shares: WearageShare[];
}

const HOUR = 3_600_000;
const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(timeZone: string): Intl.DateTimeFormat {
  let f = formatters.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    formatters.set(timeZone, f);
  }
  return f;
}

interface LocalParts { year: number; month: number; day: number; hour: number; minute: number; second: number }

function localParts(ms: number, timeZone: string): LocalParts {
  const parts = formatter(timeZone).formatToParts(new Date(ms));
  const get = (type: string) => Number(parts.find(p => p.type === type)?.value ?? '0');
  return {
    year: get('year'),
    month: get('month'),
    day: get('day'),
    hour: get('hour') % 24,
    minute: get('minute'),
    second: get('second'),
  };
}

/** UTC offset of `timeZone` at instant `ms`, in milliseconds. */
export function zoneOffsetMs(ms: number, timeZone: string): number {
  const p = localParts(ms, timeZone);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return asUtc - Math.floor(ms / 1000) * 1000;
}

/** Instant of local midnight on the local day containing `ms`. DST-safe. */
export function localDayStart(ms: number, timeZone: string): number {
  const p = localParts(ms, timeZone);
  const wallMidnight = Date.UTC(p.year, p.month - 1, p.day);
  // First guess uses the offset at `ms`; if a DST change sits between
  // midnight and `ms`, the offset at the guess is the right one.
  let guess = wallMidnight - zoneOffsetMs(ms, timeZone);
  const corrected = wallMidnight - zoneOffsetMs(guess, timeZone);
  if (corrected !== guess) guess = corrected;
  return guess;
}

/** Instant of the next local midnight after the day containing `ms`. */
export function nextLocalDayStart(ms: number, timeZone: string): number {
  const start = localDayStart(ms, timeZone);
  // 30 h past midnight is always inside the following local day (days are 23..25 h).
  return localDayStart(start + 30 * HOUR, timeZone);
}

/** Whole local days from the day containing `fromMs` through the day containing `toMs`, inclusive. */
export function localDaysBetween(fromMs: number, toMs: number, timeZone: string): number {
  if (toMs < fromMs) return 0;
  let count = 0;
  let cursor = localDayStart(fromMs, timeZone);
  const last = localDayStart(toMs, timeZone);
  while (cursor <= last) {
    count++;
    cursor = nextLocalDayStart(cursor, timeZone);
  }
  return count;
}

export function computeWearage(events: WearEvent[], opts: WearageOptions): WearageSummary {
  const nowMs = opts.now.getTime();
  const sinceMs = opts.since ? opts.since.getTime() : Number.NEGATIVE_INFINITY;
  const sleepMs = Math.max(0, opts.sleepHours) * HOUR;
  const { timeZone } = opts;

  const timeline = events
    .map(e => ({ e, t: Date.parse(e.wornAt) }))
    .filter(x => Number.isFinite(x.t) && x.t <= nowMs)
    .sort((a, b) => a.t - b.t);

  const msByWatch = new Map<string, number>();
  const wearsByWatch = new Map<string, number>();
  const lastByWatch = new Map<string, { t: number; raw: string }>();
  let trackingStart: number | null = null;

  for (let i = 0; i < timeline.length; i++) {
    const { e, t } = timeline[i];
    const end = i + 1 < timeline.length ? timeline[i + 1].t : nowMs;
    const bare = e.watchId === NONE_WATCH_ID;

    if (t >= sinceMs && !bare) {
      wearsByWatch.set(e.watchId, (wearsByWatch.get(e.watchId) ?? 0) + 1);
      const prev = lastByWatch.get(e.watchId);
      if (!prev || t >= prev.t) lastByWatch.set(e.watchId, { t, raw: e.wornAt });
    }

    const s = Math.max(t, sinceMs);
    const eEnd = Math.min(end, nowMs);
    if (eEnd <= s) continue;
    if (trackingStart === null || s < trackingStart) trackingStart = s;
    // A bare-wrist interval still ends the previous watch's credit (handled by
    // `end` above) but earns nothing itself, and there is nothing to deduct.
    if (bare) continue;

    let dayStart = localDayStart(s, timeZone);
    while (dayStart < eEnd) {
      const dayEnd = nextLocalDayStart(dayStart, timeZone);
      const segStart = Math.max(s, dayStart);
      const segEnd = Math.min(eEnd, dayEnd);
      let credit = segEnd - segStart;
      // This watch is on the wrist at the end of a completed day: sleep comes off it.
      const completedDay = dayEnd <= nowMs;
      if (completedDay && eEnd >= dayEnd && sleepMs > 0) {
        credit = Math.max(0, credit - sleepMs);
      }
      msByWatch.set(e.watchId, (msByWatch.get(e.watchId) ?? 0) + credit);
      dayStart = dayEnd;
    }
  }

  const ids = new Set<string>([...msByWatch.keys(), ...wearsByWatch.keys()]);
  let totalMs = 0;
  for (const ms of msByWatch.values()) totalMs += ms;

  const shares: WearageShare[] = [...ids]
    .map(watchId => {
      const ms = msByWatch.get(watchId) ?? 0;
      return {
        watchId,
        ms,
        share: totalMs > 0 ? ms / totalMs : 0,
        wears: wearsByWatch.get(watchId) ?? 0,
        lastWornAt: lastByWatch.get(watchId)?.raw ?? null,
      };
    })
    .sort((a, b) => b.ms - a.ms || b.wears - a.wears || a.watchId.localeCompare(b.watchId));

  return {
    totalMs,
    // Through the last instant before `now`, so exactly-midnight `now` does not count an empty day.
    daysTracked: trackingStart === null ? 0 : localDaysBetween(trackingStart, Math.max(trackingStart, nowMs - 1), timeZone),
    firstEventAt: timeline.length > 0 ? timeline[0].e.wornAt : null,
    shares,
  };
}
