import { createHash, timingSafeEqual } from 'crypto';
import type { NextApiRequest, NextApiResponse } from 'next';

function digest(value: string): Buffer {
  return createHash('sha256').update(value, 'utf8').digest();
}

/** Constant-time comparison: both sides are hashed so lengths always match. */
export function tokensMatch(presented: string, expected: string): boolean {
  return timingSafeEqual(digest(presented), digest(expected));
}

/**
 * Gate for the wear API. Reads WEAR_API_TOKEN on every call (never cached).
 * Writes the error response and returns false when the request must stop.
 */
export function requireWearToken(req: NextApiRequest, res: NextApiResponse): boolean {
  const expected = process.env.WEAR_API_TOKEN;
  if (!expected || !expected.trim()) {
    res.status(503).json({ error: 'Wear API disabled' });
    return false;
  }

  const raw = req.headers.authorization;
  const header = Array.isArray(raw) ? raw[0] : raw;
  const match = typeof header === 'string' ? /^Bearer\s+(\S+)$/i.exec(header) : null;

  if (!match || !tokensMatch(match[1], expected)) {
    res.setHeader('WWW-Authenticate', 'Bearer realm="wear"');
    res.status(401).json({ error: 'Unauthorized' });
    return false;
  }
  return true;
}
