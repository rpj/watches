# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the listener service for "Watches" — a Bluesky watch-collection gallery. It polls Bluesky for posts with the configured hashtag (`HASHTAG_TO_WATCH`, required), stores them in Redis, and classifies each post inline via a Claude-powered watch classifier. Sibling components:

1. **Listener Service** (this directory, Node.js/TypeScript) - Polls Bluesky, stores posts, classifies watches, refreshes manufacturer prices
2. **Frontend** (../frontend, Next.js/React) - Gallery web interface
3. **Redis** - Data storage for posts, classifier output, and session management
4. **Docker Compose** - Orchestrates all services

Never hardcode secrets (passwords, API keys, tokens) in any file — see the Security Policy in the root CLAUDE.md. Use environment variables, or CLI arguments for one-off tools.

## Development Commands

### Listener Service
- `npm run start` - Start the main listener service
- `npm run backfill` - Import hardcoded list of existing posts
- `npm run backfill-facets` - Re-fetch Bluesky `facets` for legacy posts so the post page can render full URLs / clickable hashtags / mentions. Idempotent; supports `--dry-run` and `--force`.
- `npm run classify-existing` - Walk every stored post chronologically and run the watch classifier (see `watch-classifier/`) to populate `__doodles:watch-meta` and `__doodles:watch-canonical`. Idempotent; supports `--dry-run` and `--force`. Requires the `claude` CLI on PATH.
- `npm run apply-overrides` - Apply manual classification overrides from `__doodles:watch-overrides` and rebuild the canonical list. Pure Redis + (if any override carries `product_url`) immediate fetches against those manufacturer pages to refresh `__doodles:product-prices`. No Claude calls. Supports `--dry-run`.
- `npm run set-override -- <postId> <field> <value>` - Set a single partial-override field (`search_query` or `product_url`) on one post and apply it inline (writes to `__doodles:watch-meta` + fetches the product price). Skips canonical rebuild — only safe for the partial-override allow-list. Empty value clears the field.
- `npm run fetch-prices` - Refresh `__doodles:product-prices` by re-fetching every `product_url` in `watch-meta` and extracting JSON-LD `Product.offers.price`. Supports `--post=<basePostId>`. Listener also runs this on its own cadence (`PRICE_REFRESH_FREQ_SECONDS`, default 6h).
- `npm run watch-stats` - Read-only summary of classifier output (totals, by-brand counts, low-confidence list with `--low-confidence`, "other" entries with `--list-other`).
- `npm run clear-redis` - Wipe stored data (destructive — dev resets only).

### Frontend (../frontend/)
- `npm run dev` - Development server on port 42420 (hard-coded in the dev script)
- `npm run build` - Production build
- `npm run start` - Production server (respects PORT env var, default 3000)

(No lint script — this project doesn't use ESLint.)

### Full Stack
- `docker-compose up -d` - Start all services in production
- `cd listener && REDIS_URL=redis://localhost:6379 npm run backfill` - Backfill existing posts

## Architecture & Data Flow

### Core Components

**Listener Service Architecture:**
- Uses `@atproto/api` to interact with Bluesky's AT Protocol
- Polls Bluesky search API every ~5 minutes (configurable via `POLLING_FREQ_SECONDS`), in batches of 100 posts, max 20 batches per cycle
- Requires `HASHTAG_TO_WATCH` (exits fatally if unset); verifies the hashtag appears in each post's text
- Optionally restricts collection to `HANDLES_TO_WATCH` (comma-separated allow-list)
- Maintains session persistence in Redis to avoid re-authentication
- Creates separate `Post` entries for each image in multi-image posts
- Uses Redis sets to track processed URIs and avoid duplicates
- Runs the watch classifier inline on each new post (`classify-post.ts` shells out to `claude -p`; fail-soft when unavailable)
- Refreshes manufacturer product prices on a throttled cadence from inside the polling loop

**Data Structure:**
```typescript
type Facet = {
  index: { byteStart: number; byteEnd: number };
  features: Array<
    | { $type: 'app.bsky.richtext.facet#link'; uri: string }
    | { $type: 'app.bsky.richtext.facet#tag'; tag: string }
    | { $type: 'app.bsky.richtext.facet#mention'; did: string }
  >;
};

type Post = {
  uri: string,           // Format: "at://did/app.bsky.feed.post/id#imageN"
  authorHandle: string,
  authorDisplayName: string,
  text: string,          // Bluesky's display form (URLs may be truncated to ~30 chars + …)
  imageUrls: string[],   // Single image per post in listener
  createdAt: string,
  postUrl: string,       // Bluesky web URL
  facets?: Facet[],      // Bluesky rich-text facets — full URIs for inline links, etc.
}
```

**Redis Keys (unified store — no per-user prefix fanout):**
- `all-doodles:posts` - List of serialized Post objects, newest first
- `post:<uri>` - Full Post JSON keyed by image URI
- `handle:<handle>:posts` - List of image URIs per author (reverse index)
- `handles:all` - Set of every author handle seen
- `all-doodles:processed-uris` - Set of processed post/image URIs
- `all-doodles:last-seen-post` - URI of most recent processed post (search optimization)
- `all-posts:saved-session` - Bluesky session data for persistence
- `__doodles:watch-meta`, `__doodles:watch-canonical`, `__doodles:watch-overrides`, `__doodles:product-prices` - Classifier + pricing state (see root README)

### Key Processing Logic

**Multi-Image Handling:** Posts with multiple images get split into separate entries with URIs like `at://...#image0`, `at://...#image1`. This allows individual images to be displayed and referenced independently.

**Image Extraction:** Supports multiple Bluesky embed types:
- `app.bsky.embed.images#view` - Direct image embeds
- `app.bsky.embed.gallery#view` - Gallery embeds (posts with more than 4 images)
- `app.bsky.embed.recordWithMedia#view` - Quote posts with media (images or gallery only)
- Videos are skipped — we don't collect video thumbnails

**NSFW Filtering:** Posts with #nsfw / #noindex / #no-index tags or a `sexual` content label are skipped.

**Backfill Process:** The `backfill.ts` script processes hardcoded post URLs to import pre-hashtag posts. It clears existing data and rebuilds from scratch.

**Polling Strategy:** Searches in batches until finding the last seen post, with safety limits to prevent infinite loops. On first run, only processes the latest batch.

## Environment Variables

Required:
- `BLUESKY_IDENT` - Bluesky username/handle
- `BLUESKY_PASS` - Bluesky app password
- `HASHTAG_TO_WATCH` - Hashtag to monitor, include the # prefix. No default — the listener exits fatally without it.
- `ANTHROPIC_API_KEY` - For the inline watch classifier (`claude -p`). Without it, classification fails-soft: posts are still stored, no `watch-meta` written.

Optional:
- `REDIS_URL` - Redis connection string (defaults to `redis://localhost:6379`)
- `POLLING_FREQ_SECONDS` - Polling interval (default: 300)
- `PRICE_REFRESH_FREQ_SECONDS` - Manufacturer product-page price-refresh cadence (default: 21600 = 6h). The listener calls `refreshAllProductPrices` from inside the polling loop, throttled via `__doodles:product-prices:last-refresh`. Only does work if any `__doodles:watch-overrides` entries carry a `product_url`.
- `HANDLES_TO_WATCH` - Comma-separated allow-list of Bluesky handles; when set, only those authors' posts are collected
- `WATCH_CLASSIFIER_MODEL` - Claude model for the classifier (default: `sonnet`)

## Development Workflow

1. Set up `.env` file with Bluesky credentials and `HASHTAG_TO_WATCH`
2. Start Redis (via Docker Compose or standalone)
3. Run backfill to import existing posts: `cd listener && REDIS_URL=redis://localhost:6379 npm run backfill`
4. Start listener service: `npm run start`
5. Start frontend in development mode: `cd ../frontend && npm run dev`

## Docker Deployment

The `docker-compose.yml` uses `network_mode: 'host'` for both services, with environment variables passed from the host `.env` file. Services restart automatically unless stopped manually. The listener image bundles the `claude` CLI (pinned version, autoupdater disabled) so inline classification works in-container.

## Testing Policy
**IMPORTANT**: Do not run tests, builds, or any validation commands unless explicitly requested in the prompt. The user will handle all testing and provide feedback on any errors or changes needed.
