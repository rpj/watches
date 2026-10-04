import type { NextApiRequest, NextApiResponse } from 'next';
import { rateLimit, runMiddleware } from '../../../lib/api-middleware';
import { requireWearToken } from '../../../lib/wear-auth';
import { listWearEvents, parseLimit, recordWear, validateWearEventInput } from '../../../lib/wear';

export const config = { api: { bodyParser: { sizeLimit: '8kb' } } };

const limiter = rateLimit({ windowMs: 60 * 1000, maxRequests: 60 });

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  await runMiddleware(req, res, limiter);
  if (!requireWearToken(req, res)) return;

  if (req.method !== 'GET' && req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    if (req.method === 'GET') {
      const limit = parseLimit(req.query.limit);
      if (!limit.ok) {
        return res.status(400).json({ error: limit.error });
      }
      const events = await listWearEvents(limit.value);
      return res.status(200).json({ events });
    }

    let body: unknown = req.body;
    if (typeof body === 'string') {
      try {
        body = JSON.parse(body);
      } catch {
        return res.status(400).json({ error: 'Body must be valid JSON' });
      }
    }

    const input = validateWearEventInput(body);
    if (!input.ok) {
      return res.status(400).json({ error: input.error });
    }

    const result = await recordWear(input.value);
    if (!result.ok) {
      return res.status(400).json({ error: result.error });
    }
    if (result.created) {
      return res.status(201).json({ event: result.event, created: true });
    }
    return res.status(200).json({ event: result.event, created: false });
  } catch (error) {
    console.error('wear/events:', error);
    res.status(500).json({ error: 'Failed to process wear events' });
  }
}
