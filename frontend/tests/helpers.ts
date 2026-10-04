import { createMocks, type RequestMethod, type MockResponse } from 'node-mocks-http';
import type { NextApiRequest, NextApiResponse } from 'next';

/** Matches vitest.config.ts `test.env.WEAR_API_TOKEN`. Fixture only, not a credential. */
export const TEST_TOKEN = 'test-token-not-a-secret';

export type ApiHandler = (req: NextApiRequest, res: NextApiResponse) => Promise<unknown> | unknown;

export interface MockApiOptions {
  method?: RequestMethod;
  query?: Record<string, string | string[]>;
  body?: unknown;
  /** `undefined` → send TEST_TOKEN; `null` → send no Authorization header; string → send that token. */
  token?: string | null;
  headers?: Record<string, string>;
  /** Pin the client IP (rate-limit bucket). Defaults to a fresh IP per call so tests never trip the limiter by accident. */
  ip?: string;
}

let ipCounter = 0;
function freshIp(): string {
  ipCounter++;
  return `10.${(ipCounter >> 16) & 255}.${(ipCounter >> 8) & 255}.${ipCounter & 255}`;
}

/**
 * Build a Next API request/response pair. The rate limiter in
 * lib/api-middleware.ts reads `x-forwarded-for` and otherwise dereferences
 * `req.socket`, which node-mocks-http does not provide, so we always set the
 * header.
 */
export function mockApi(opts: MockApiOptions = {}) {
  const headers: Record<string, string> = {
    'x-forwarded-for': opts.ip ?? freshIp(),
    ...(opts.headers ?? {}),
  };
  if (opts.token !== null) {
    headers.authorization = `Bearer ${opts.token ?? TEST_TOKEN}`;
  }
  if (opts.body !== undefined && !headers['content-type']) {
    headers['content-type'] = 'application/json';
  }
  const { req, res } = createMocks({
    method: opts.method ?? 'GET',
    query: opts.query ?? {},
    body: opts.body as any,
    headers,
  });
  return {
    req: req as unknown as NextApiRequest,
    res: res as unknown as NextApiResponse & MockResponse<NextApiResponse>,
  };
}

export interface ApiResult {
  status: number;
  /** Parsed JSON body; throws if the body is empty or not JSON. */
  json: <T = any>() => T;
  /** Raw body text ('' for 204). */
  text: () => string;
  header: (name: string) => string | number | string[] | undefined;
}

/** Invoke a pages/api handler the way Next would and return a small result wrapper. */
export async function callApi(handler: ApiHandler, opts: MockApiOptions = {}): Promise<ApiResult> {
  const { req, res } = mockApi(opts);
  await handler(req, res);
  const mock = res as unknown as MockResponse<NextApiResponse>;
  return {
    status: mock._getStatusCode(),
    json: <T = any>() => mock._getJSONData() as T,
    text: () => mock._getData() as string,
    header: (name: string) => mock.getHeader(name),
  };
}
