import type { NextApiRequest, NextApiResponse } from 'next';
import { getWearingNow, WearingNow } from '../../lib/wear';
import { rateLimit, cors, runMiddleware } from '../../lib/api-middleware';

/**
 * Public face of the wear data, used by the website's "On the wrist" card.
 * Unauthenticated by design (no requireWearToken); read-only.
 * The authenticated write/read routes live under /api/wear/*.
 */
const rateLimiter = rateLimit({
  windowMs: 60 * 1000,
  maxRequests: 100,
});

const corsMiddleware = cors({
  origin: process.env.NODE_ENV === 'production'
    ? ['https://ryanswatches.com', 'https://www.ryanswatches.com']
    : true,
  methods: ['GET', 'OPTIONS'],
  credentials: true,
});

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse<{ wearing: WearingNow | null } | { error: string }>
) {
  await runMiddleware(req, res, corsMiddleware);
  await runMiddleware(req, res, rateLimiter);

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const wearing = await getWearingNow();
    res.status(200).json({ wearing });
  } catch (error) {
    console.error('wearing:', error);
    res.status(500).json({ error: 'Failed to fetch wearing status' });
  }
}
