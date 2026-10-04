import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { NextApiResponse } from 'next';
import type { MockResponse } from 'node-mocks-http';
import { requireWearToken, tokensMatch } from '../lib/wear-auth';
import { mockApi, TEST_TOKEN } from './helpers';

describe('tokensMatch', () => {
  it('accepts equal tokens', () => {
    expect(tokensMatch('abc123', 'abc123')).toBe(true);
  });
  it('rejects same-length different tokens', () => {
    expect(tokensMatch('abc123', 'abc124')).toBe(false);
  });
  it('rejects different lengths', () => {
    expect(tokensMatch('abc', 'abcd')).toBe(false);
  });
  it('handles empty strings', () => {
    expect(tokensMatch('', 'x')).toBe(false);
    expect(tokensMatch('', '')).toBe(true);
  });
});

describe('requireWearToken', () => {
  let saved: string | undefined;

  beforeEach(() => {
    saved = process.env.WEAR_API_TOKEN;
  });
  afterEach(() => {
    if (saved === undefined) delete process.env.WEAR_API_TOKEN;
    else process.env.WEAR_API_TOKEN = saved;
  });

  it('returns 503 when the env var is unset', () => {
    delete process.env.WEAR_API_TOKEN;
    const { req, res } = mockApi();
    expect(requireWearToken(req, res)).toBe(false);
    expect(res._getStatusCode()).toBe(503);
    expect(res._getJSONData()).toEqual({ error: 'Wear API disabled' });
  });

  it('returns 503 when the env var is whitespace', () => {
    process.env.WEAR_API_TOKEN = '   ';
    const { req, res } = mockApi();
    expect(requireWearToken(req, res)).toBe(false);
    expect(res._getStatusCode()).toBe(503);
  });

  it('returns 401 with WWW-Authenticate when no header is sent', () => {
    process.env.WEAR_API_TOKEN = TEST_TOKEN;
    const { req, res } = mockApi({ token: null });
    expect(requireWearToken(req, res)).toBe(false);
    expect(res._getStatusCode()).toBe(401);
    expect(res._getJSONData()).toEqual({ error: 'Unauthorized' });
    expect(res.getHeader('www-authenticate')).toBeTruthy();
  });

  it('returns 401 for a non-Bearer scheme', () => {
    process.env.WEAR_API_TOKEN = TEST_TOKEN;
    const { req, res } = mockApi({ token: null, headers: { authorization: 'Basic abc' } });
    expect(requireWearToken(req, res)).toBe(false);
    expect(res._getStatusCode()).toBe(401);
  });

  it('returns 401 for a wrong token', () => {
    process.env.WEAR_API_TOKEN = TEST_TOKEN;
    const { req, res } = mockApi({ token: 'wrong-token' });
    expect(requireWearToken(req, res)).toBe(false);
    expect(res._getStatusCode()).toBe(401);
  });

  it('returns true and leaves the response untouched for the correct token', () => {
    process.env.WEAR_API_TOKEN = TEST_TOKEN;
    const { req, res } = mockApi();
    expect(requireWearToken(req, res)).toBe(true);
    expect((res as unknown as MockResponse<NextApiResponse>)._isEndCalled()).toBe(false);
  });
});
