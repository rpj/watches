import type { NextApiRequest, NextApiResponse } from 'next';
import { rateLimit, runMiddleware } from '../../../lib/api-middleware';
import { requireWearToken } from '../../../lib/wear-auth';
import { listWearWatches } from '../../../lib/wear';

const limiter = rateLimit({ windowMs: 60 * 1000, maxRequests: 60 });

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  await runMiddleware(req, res, limiter);
  if (!requireWearToken(req, res)) return;

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { watches, current } = await listWearWatches();
    res.status(200).json({ watches, current, generatedAt: new Date().toISOString() });
  } catch (error) {
    console.error('wear/watches:', error);
    res.status(500).json({ error: 'Failed to fetch watches' });
  }
}
