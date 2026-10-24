import { beforeEach, describe, expect, it } from 'vitest';
import handler from '../pages/api/wearing';
import { recordWear } from '../lib/wear';
import { callApi } from './helpers';
import { EVENTS, IMAGE, seedCollection, WATCH_KURONO } from './fixtures';

beforeEach(async () => {
  await seedCollection();
});

describe('GET /api/wearing', () => {
  it('returns { wearing: null } with no events, and needs no auth', async () => {
    const r = await callApi(handler, { token: null });
    expect(r.status).toBe(200);
    expect(r.json()).toEqual({ wearing: null });
  });

  it('returns the last watch logged, without the event', async () => {
    await recordWear(EVENTS[1]);
    const r = await callApi(handler, { token: null });
    expect(r.status).toBe(200);
    const { wearing } = r.json();
    expect(wearing.watch).toEqual({
      id: WATCH_KURONO,
      brand: 'Kurono',
      model: 'Malachite',
      imageUrl: IMAGE.kurono,
      thumbnailUrl: IMAGE.kurono.replace('/feed_fullsize/', '/feed_thumbnail/'),
      postUrl: expect.stringContaining('/post/' + WATCH_KURONO),
    });
  });

  it('picks the latest wornAt, not the last inserted', async () => {
    for (const e of EVENTS) {
      await recordWear(e);
    }
    const r = await callApi(handler, { token: null });
    expect(r.status).toBe(200);
    expect(r.json().wearing.watch.id).toBe(WATCH_KURONO);
  });

  it('rejects non-GET methods with 405', async () => {
    const r = await callApi(handler, { method: 'POST', token: null });
    expect(r.status).toBe(405);
    expect(r.json()).toEqual({ error: 'Method not allowed' });
  });

  it('sets the rate-limit header to 100', async () => {
    const r = await callApi(handler, { token: null });
    expect(String(r.header('x-ratelimit-limit'))).toBe('100');
  });
});
