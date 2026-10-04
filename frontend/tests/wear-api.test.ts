import { beforeEach, describe, expect, it } from 'vitest';
import watchesHandler from '../pages/api/wear/watches';
import eventsHandler from '../pages/api/wear/events';
import eventByIdHandler from '../pages/api/wear/events/[id]';
import { callApi } from './helpers';
import { EVENTS, IMAGE, seedCollection, WATCH_CITIZEN, WATCH_KURONO, WATCH_SKAGEN } from './fixtures';

const WATCH_KEYS = [
  'brand', 'id', 'imageUrl', 'lastWornAt', 'model', 'postCount', 'postUrl', 'thumbnailUrl', 'wearCount',
];

async function postAll() {
  for (const e of EVENTS) {
    await callApi(eventsHandler, { method: 'POST', body: e });
  }
}

beforeEach(async () => {
  await seedCollection();
});

describe('auth on every route', () => {
  const routes = [
    ['watches', watchesHandler, 'GET', {}],
    ['events', eventsHandler, 'GET', {}],
    ['events/[id]', eventByIdHandler, 'DELETE', { id: EVENTS[0].id }],
  ] as const;

  for (const [name, handler, method, query] of routes) {
    it(`${name}: 401 without a token`, async () => {
      const r = await callApi(handler, { method, query: { ...query }, token: null });
      expect(r.status).toBe(401);
    });
    it(`${name}: 401 with a wrong token`, async () => {
      const r = await callApi(handler, { method, query: { ...query }, token: 'wrong-token' });
      expect(r.status).toBe(401);
    });
    it(`${name}: 503 when the server token is unset`, async () => {
      const saved = process.env.WEAR_API_TOKEN;
      delete process.env.WEAR_API_TOKEN;
      try {
        const r = await callApi(handler, { method, query: { ...query } });
        expect(r.status).toBe(503);
      } finally {
        if (saved !== undefined) process.env.WEAR_API_TOKEN = saved;
      }
    });
  }
});

describe('GET /api/wear/watches', () => {
  it('returns the collection with no events', async () => {
    const r = await callApi(watchesHandler);
    expect(r.status).toBe(200);
    const body = r.json();
    expect(Object.keys(body).sort()).toEqual(['current', 'generatedAt', 'watches'].sort());
    expect(Number.isNaN(Date.parse(body.generatedAt))).toBe(false);
    expect(body.watches.map((w: any) => w.id)).toEqual([WATCH_CITIZEN, WATCH_KURONO, WATCH_SKAGEN]);
    for (const w of body.watches) {
      expect(Object.keys(w).sort()).toEqual(WATCH_KEYS);
    }
    const skagen = body.watches.find((w: any) => w.id === WATCH_SKAGEN);
    expect(skagen.imageUrl).toBe(IMAGE.skagenOne);
    expect(body.current).toBeNull();
    expect(String(r.header('x-ratelimit-limit'))).toBe('60');
  });

  it('rejects POST with 405', async () => {
    const r = await callApi(watchesHandler, { method: 'POST', body: {} });
    expect(r.status).toBe(405);
  });
});

describe('GET /api/wear/events', () => {
  it('returns an empty list', async () => {
    const r = await callApi(eventsHandler);
    expect(r.status).toBe(200);
    expect(r.json()).toEqual({ events: [] });
  });

  it('rejects invalid limits', async () => {
    expect((await callApi(eventsHandler, { query: { limit: '0' } })).status).toBe(400);
    expect((await callApi(eventsHandler, { query: { limit: 'abc' } })).status).toBe(400);
  });

  it('honours limit', async () => {
    await postAll();
    const r = await callApi(eventsHandler, { query: { limit: '2' } });
    expect(r.status).toBe(200);
    expect(r.json().events).toHaveLength(2);
  });
});

describe('POST /api/wear/events', () => {
  it('records events idempotently and updates the watches view', async () => {
    for (const e of EVENTS) {
      const r = await callApi(eventsHandler, { method: 'POST', body: e });
      expect(r.status).toBe(201);
      const body = r.json();
      expect(body.created).toBe(true);
      expect(typeof body.event.recordedAt).toBe('string');
    }

    const again = await callApi(eventsHandler, { method: 'POST', body: EVENTS[0] });
    expect(again.status).toBe(200);
    expect(again.json().created).toBe(false);

    const view = (await callApi(watchesHandler)).json();
    const byId = (id: string) => view.watches.find((w: any) => w.id === id);
    expect(byId(WATCH_CITIZEN).wearCount).toBe(2);
    expect(byId(WATCH_KURONO).wearCount).toBe(1);
    expect(byId(WATCH_SKAGEN).wearCount).toBe(0);
    expect(view.current.id).toBe(EVENTS[1].id);
    expect(byId(WATCH_CITIZEN).lastWornAt).toBe(EVENTS[2].wornAt);
  });

  it('rejects an empty object', async () => {
    expect((await callApi(eventsHandler, { method: 'POST', body: {} })).status).toBe(400);
  });

  it('rejects malformed JSON', async () => {
    const r = await callApi(eventsHandler, { method: 'POST', body: '{not json' });
    expect(r.status).toBe(400);
  });

  it('rejects an unknown watchId', async () => {
    const r = await callApi(eventsHandler, { method: 'POST', body: { ...EVENTS[0], watchId: 'nosuchwatch' } });
    expect(r.status).toBe(400);
    expect(r.json().error).toContain('watchId');
  });

  it('rejects an unknown source', async () => {
    const r = await callApi(eventsHandler, { method: 'POST', body: { ...EVENTS[0], source: 'siri' } });
    expect(r.status).toBe(400);
  });

  it('rejects a wornAt more than 24h in the future', async () => {
    const wornAt = new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString();
    const r = await callApi(eventsHandler, { method: 'POST', body: { ...EVENTS[0], wornAt } });
    expect(r.status).toBe(400);
  });

  it('rejects an id that fails the pattern', async () => {
    const r = await callApi(eventsHandler, { method: 'POST', body: { ...EVENTS[0], id: 'short' } });
    expect(r.status).toBe(400);
  });

  it('rejects PUT with 405', async () => {
    const r = await callApi(eventsHandler, { method: 'PUT', body: EVENTS[0] });
    expect(r.status).toBe(405);
  });
});

describe('DELETE /api/wear/events/[id]', () => {
  beforeEach(postAll);

  it('deletes once, then 404s', async () => {
    const first = await callApi(eventByIdHandler, { method: 'DELETE', query: { id: EVENTS[1].id } });
    expect(first.status).toBe(204);
    expect(first.text()).toBe('');

    const second = await callApi(eventByIdHandler, { method: 'DELETE', query: { id: EVENTS[1].id } });
    expect(second.status).toBe(404);
    expect(second.json()).toEqual({ error: 'Not found' });
  });

  it('rejects an invalid id', async () => {
    const r = await callApi(eventByIdHandler, { method: 'DELETE', query: { id: 'bad id!' } });
    expect(r.status).toBe(400);
  });

  it('rejects GET with 405', async () => {
    const r = await callApi(eventByIdHandler, { method: 'GET', query: { id: EVENTS[1].id } });
    expect(r.status).toBe(405);
  });

  it('moves current to the next most recent wear', async () => {
    await callApi(eventByIdHandler, { method: 'DELETE', query: { id: EVENTS[1].id } });
    const view = (await callApi(watchesHandler)).json();
    expect(view.current.id).toBe(EVENTS[2].id);
  });
});
