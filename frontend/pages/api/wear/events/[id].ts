import type { NextApiRequest, NextApiResponse } from 'next';
import { rateLimit, runMiddleware } from '../../../../lib/api-middleware';
import { requireWearToken } from '../../../../lib/wear-auth';
import { deleteWearEvent, EVENT_ID_PATTERN } from '../../../../lib/wear';

const limiter = rateLimit({ windowMs: 60 * 1000, maxRequests: 60 });

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  await runMiddleware(req, res, limiter);
  if (!requireWearToken(req, res)) return;

  if (req.method !== 'DELETE') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const id = req.query.id;
  if (typeof id !== 'string' || !EVENT_ID_PATTERN.test(id)) {
    return res.status(400).json({ error: 'Invalid event id' });
  }

  try {
    const deleted = await deleteWearEvent(id);
    if (!deleted) {
      return res.status(404).json({ error: 'Not found' });
    }
    res.status(204).end();
  } catch (error) {
    console.error('wear/events/[id]:', error);
    res.status(500).json({ error: 'Failed to delete wear event' });
  }
}
