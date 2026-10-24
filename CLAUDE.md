# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Watches is the full-stack engine behind **Ryan's Watches**: a Bluesky-powered watch-collection gallery. A Node.js listener polls Bluesky for posts with the configured hashtag (`HASHTAG_TO_WATCH`, required), a Claude-powered classifier identifies each watch (brand/model, dedup of follow-on posts), and a Next.js frontend renders the gallery with per-brand stats/filtering and a per-watch pricing widget (eBay + manufacturer JSON-LD). Redis stores everything; Docker Compose orchestrates. A SwiftUI iOS app in `./ios-app/` ("Wrist") logs which watch is being worn via the authenticated `/api/wear/*` routes; see `ios-app/PLAN.md` and `ios-app/API.md`.

Originally built as "Daily Doodles" for daily-art aggregation; the `all-doodles:` / `__doodles:` Redis key prefixes are a historical artifact of that era. Don't rename them and don't read meaning into them.

## Security Policy

**Never hardcode secrets in any file.** No passwords, API keys, tokens, session blobs, or credentialed connection strings in source, scripts, one-off tools, docs, or committed log/output files. Read credentials from environment variables — or CLI arguments for one-off tools. `.env` is gitignored and stays that way; `.env.example` contains placeholders only. If you find a committed secret, remove it AND flag it to the user as compromised (it lives in git history; it must be rotated, not just deleted).

## Development Commands

### Root Level
```bash
# Start all services in production
docker-compose up -d

# Setup environment
cp .env.example .env
# Edit .env: Bluesky credentials, HASHTAG_TO_WATCH (required), ANTHROPIC_API_KEY
```

### Listener Service (./listener/)
```bash
npm run start              # Unified listener: poll + inline classification + price refresh
npm run backfill           # Import hardcoded historical posts (run once)
npm run backfill-facets    # Re-fetch rich-text facets for legacy posts
npm run classify-existing  # Classify un-classified posts (Claude calls)
npm run apply-overrides    # Apply manual overrides + rebuild canonical + refresh prices
npm run set-override       # npm run set-override -- <postId> <field> <value>  (search_query/product_url)
npm run fetch-prices       # Refresh manufacturer prices from product_url overrides
npm run watch-stats        # Read-only classifier output summary
npm run clear-redis        # Wipe stored data (destructive)
```

### Frontend (./frontend/)
```bash
npm run dev           # Development server on port 42420 (hard-coded in the dev script)
npm run build         # Production build
npm run start         # Production server (respects PORT env var, default 3000)
npm test              # vitest; integration tests hit Redis logical DB 15 only (guarded)
npm run typecheck     # tsc --noEmit
```

There is no lint script — this project intentionally does not use ESLint.

### Initial Setup Workflow
1. `cp .env.example .env` and configure credentials + `HASHTAG_TO_WATCH`
2. `cd listener && REDIS_URL=redis://localhost:6379 npm run backfill` (optional, run once)
3. `docker-compose up -d` OR run services individually for development
4. `cd listener && npm run classify-existing` to bootstrap classification for backfilled posts

## Architecture

### Service Architecture
- **Listener**: Polls Bluesky every ~5 minutes (batches of 100, max 20 batches/cycle) for posts with the configured hashtag, optionally restricted to `HANDLES_TO_WATCH`. Stores one Post entry per image in a unified Redis store, runs the watch classifier inline on each new post (shells out to `claude -p`; fail-soft if unavailable), and refreshes manufacturer product prices on a throttled cadence.
- **Frontend**: Next.js pages router. `/` all posts (with the last watch on the wrist), `/[handle]` per-user gallery with hero card, `/post/[id]` and `/[handle]/post/[id]` post pages with the pricing widget, `/rss.xml`, `/wearage` (wear-time shares). Server-rendered with 5-minute client auto-refresh, pagination (50/page), and `?brand=` filtering driven by classifier meta.
- **Redis**: Single source of truth — posts, per-handle indices, classifier output, overrides, widget caches, sessions. There is **no per-user prefix fanout**; that was the old design and has been removed.

### Key Data Structure
```typescript
type Post = {
  uri: string,           // "at://did/app.bsky.feed.post/id#imageN"
  authorHandle: string,
  authorDisplayName: string,
  text: string,          // Bluesky display text (inline URLs may be truncated)
  imageUrls: string[],   // Single image per entry
  createdAt: string,
  postUrl: string,
  facets?: Facet[],      // Bluesky rich-text facets — used by the post page to render full inline URLs / hashtags / mentions as clickable links
}
```

### Multi-Image Handling
Posts with multiple images are split into separate `Post` entries with URIs like `at://...#image0`, `at://...#image1`. This enables individual image routing and display. Bluesky "Gallery" embeds (posts with more than 4 images) are handled the same way.

### Redis Keys
- `all-doodles:posts` — list of Post JSON (one per image, newest first)
- `post:<uri>` — Post JSON keyed by image URI (direct lookup)
- `handle:<handle>:posts` — list of image URIs per author; `handles:all` — set of all authors
- `all-doodles:processed-uris` — dedup set; `all-doodles:last-seen-post` — search cursor
- `all-posts:saved-session` — Bluesky session persistence
- `__doodles:watch-meta` / `watch-canonical` / `watch-overrides` / `product-prices` / `hero-overrides` — classifier + widget state (see README for full semantics)
- `__doodles:ebay-pricing:*` — 24h eBay response cache
- `__doodles:wear-events` (hash eventId → wear event) / `__doodles:wear-timeline` (zset by worn-at ms) — wear API state; see `ios-app/API.md`

### Styling System
Warm paper-and-ink minimalism: cream / near-black surfaces with a bronze accent (`#8b6634` light / `#c89456` dark) and hairline borders. CSS custom properties for theming, CSS Modules for component scoping. Fonts: 'Schibsted Grotesk' (body/UI) and 'Lato' (accents). Dark theme is the default.

## Environment Variables
- `BLUESKY_IDENT` / `BLUESKY_PASS` - Bluesky credentials (required)
- `HASHTAG_TO_WATCH` - Hashtag to monitor, include the # prefix (required — the listener exits fatally without it; no default)
- `ANTHROPIC_API_KEY` - Required for the inline watch classifier; without it classification fails-soft (posts still stored)
- `REDIS_URL` - Redis connection string (default: redis://localhost:6379)
- `POLLING_FREQ_SECONDS` - Listener polling interval (default: 300)
- `PRICE_REFRESH_FREQ_SECONDS` - Manufacturer price-refresh cadence via JSON-LD scrape (default: 21600 = 6h). See README "Pricing Overrides".
- `HANDLES_TO_WATCH` - Comma-separated handle allow-list. First handle is the deployment owner on the gallery; setting it also enables multi-image grouping on gallery cards.
- `SITE_TITLE` - Masthead wordmark; falls back to the hashtag when unset
- `WATCH_CLASSIFIER_MODEL` - Claude model for the classifier (default: sonnet)
- `EBAY_CLIENT_ID`, `EBAY_CLIENT_SECRET`, `EBAY_ENV` - eBay Browse API for the pricing widget (`EBAY_ENV`: production|sandbox, default sandbox)
- `WEAR_API_TOKEN` - Bearer token for `/api/wear/*` (iOS app). Unset = wear API disabled (503). Read per-request, never logged.
- `WEAR_TIMEZONE` / `WEAR_SLEEP_HOURS` - Local day zone (default America/Los_Angeles) and nightly deduction hours (default 7) for the wearage page; see README "On the site".
- `PORT` - Frontend production port (default: 3000). The dev server is hard-coded to 42420.

## Docker Configuration
Uses `network_mode: 'host'` for both services. Services auto-restart unless manually stopped. Environment variables sourced from host `.env` file. The listener image bundles the `claude` CLI (pinned, autoupdater disabled) for inline classification.

## Testing Policy
**IMPORTANT**: Do not run tests, builds, or any validation commands unless explicitly requested in the prompt. The user will handle all testing and provide feedback on any errors or changes needed. Exception: the wear API / iOS work (`frontend/tests`, `ios-app/WristCore`) has an explicit standing OK to run `npm test`, `npm run typecheck`, and `swift test` (in Docker) against Redis DB 15.
