# Watches

The engine behind **Ryan's Watches** — a full-stack app that turns Bluesky
posts about watches into a collection gallery. A listener polls Bluesky for
posts with the configured hashtag, a Claude-powered classifier identifies
each watch (brand + model, deduplicating follow-on posts about the same
piece), and a Next.js frontend renders the gallery with per-brand stats and
filtering, a per-watch pricing widget (eBay listings + manufacturer MSRP),
and RSS feeds.

The hashtag is technically configurable (`HASHTAG_TO_WATCH`, required — the
listener exits without one), so the ingest pipeline could track anything.
But everything downstream of ingest — the classifier, canonical watch list,
pricing widget, brand stats — is watch-specific. This is a watch app.

**Naming note:** the project began life as "Daily Doodles", a daily-art
aggregator. The Redis key prefixes (`all-doodles:*`, `__doodles:*`) are a
historical artifact of that era, kept verbatim because renaming live data
buys nothing. Don't read meaning into them.

## Architecture

### Core Components
- **Listener Service** (Node.js/TypeScript) - Polls Bluesky every ~5 minutes for posts with the configured hashtag; classifies each new post inline via `claude -p`
- **Frontend** (Next.js/React) - Server-rendered gallery with auto-refresh, brand stats/filtering, pricing widget on post pages
- **Redis** - Single source of truth: posts, per-handle indices, classifier output, overrides, widget caches, session persistence
- **Docker Compose** - Service orchestration and deployment

### Data Flow
1. Listener polls the Bluesky search API for posts with the configured hashtag (optionally restricted to `HANDLES_TO_WATCH`)
2. Posts with images are stored in Redis — one `Post` entry per image — in a unified store (`all-doodles:posts` + per-URI keys + per-handle URI indices)
3. Each new post runs through the watch classifier (brand/model/kind), feeding the canonical unique-watch list and per-brand stats
4. Frontend serves galleries (all posts or per-handle), post pages with the pricing widget, and RSS feeds

## Quick Start

### Prerequisites
- Docker and Docker Compose
- Bluesky account with app password
- Anthropic API key (for the watch classifier; everything else works without it)

### Setup
1. **Environment Configuration**
   ```bash
   cp .env.example .env
   # Edit .env — required values:
   # BLUESKY_IDENT=your.handle.here
   # BLUESKY_PASS=your-app-password-here
   # HASHTAG_TO_WATCH=#YourTag        <- required, listener exits without it
   # ANTHROPIC_API_KEY=sk-ant-...     <- required for classification
   ```

2. **Import Existing Posts** (optional)
   ```bash
   cd listener
   npm install
   REDIS_URL=redis://localhost:6379 npm run backfill
   ```

3. **Start Services**
   ```bash
   docker-compose up -d
   ```

4. **Bootstrap classification for backfilled posts** (optional)
   ```bash
   cd listener && npm run classify-existing
   ```

5. **Access Application**
   - Frontend: http://localhost:3000 (or your configured PORT)
   - RSS Feed: http://localhost:3000/rss.xml

## Development

### Frontend (./frontend/)
```bash
npm install           # Install dependencies
npm run dev           # Development server on port 42420 (hard-coded in the dev script)
npm run build         # Production build
npm run start         # Production server (respects PORT env var, default 3000)
```

### Listener Service (./listener/)
```bash
npm install                 # Install dependencies
npm run start               # Start listener service
npm run backfill            # Import hardcoded historical posts
npm run backfill-facets     # Re-fetch facets (rich-text URIs/tags/mentions) for legacy posts
npm run classify-existing   # Run the watch classifier on un-classified posts (see below)
npm run apply-overrides     # Apply manual overrides + rebuild canonical + refresh product prices (no Claude calls)
npm run set-override        # Set a single partial-override field (search_query/product_url) on one post and apply it. `npm run set-override -- <postId> <field> <value>`
npm run fetch-prices        # Manually refresh manufacturer product prices for posts with `product_url` overrides
npm run watch-stats         # Read-only summary of classifier output
npm run clear-redis         # Wipe stored data (destructive — dev resets only)
```

**Backfilling rich text on legacy posts:**

The listener captures Bluesky's rich-text `facets` array on every new post,
which the post page uses to render full inline URLs / clickable hashtags /
mentions. Posts ingested before this feature was added store a truncated
text without facets. Run `npm run backfill-facets` once to re-fetch every
known post from Bluesky's public API and stamp the original facets onto
the stored Post record. Idempotent (only fetches posts missing the
field); add `--force` to re-fetch unconditionally; add `--dry-run` to
preview without writing.

**Watch classifier (`watch-classifier/SKILL.md`):**

Each post the listener stores is also fed through a Claude-powered
classifier that decides whether the post is a unique watch, a follow-on
("band upgrade", "wearing it again"), a family/collection shot, an event
post, or other; and extracts brand + model. Used to deduplicate fuzzy
plain-text descriptions and drive the per-brand stats / filter UI on the
gallery, plus the "First appeared →" link from a follow-on post back to
its canonical.

The skill lives at `listener/watch-classifier/SKILL.md` (version-controlled
in this repo) and is also symlinked from `~/.claude/skills/watch-classifier`
for interactive use. The listener calls `claude -p` non-interactively at
post-processing time and stores results in these Redis keys:

- `__doodles:watch-meta` — Hash, basePostId → JSON `{kind, brand, model, references_post_id, confidence, classified_at, search_query?, product_url?}`. The two optional fields are pricing-widget overrides; see "Pricing Overrides".
- `__doodles:watch-canonical` — List, oldest first, JSON `{post_id, brand, model}` for each unique watch. Drives the canonical-list context the classifier sees on subsequent posts (so post N+1 can be matched against post N's identified watches).
- `__doodles:watch-overrides` — Hash, basePostId → JSON (same shape as `watch-meta`). See the "Watch classification overrides" section below.
- `__doodles:product-prices` — Hash, basePostId → JSON `{value, currency, productUrl, productDomain, fetchedAt}`. Populated by the listener from `product_url` overrides; consumed by the per-post pricing widget. See "Pricing Overrides".

Bootstrap the classification for legacy posts with `cd listener && npm run classify-existing`. Inspect the output with `npm run watch-stats` (add `--low-confidence` to spot-check entries that need manual review).

Failure mode is fail-soft: if the `claude` CLI isn't available in the listener's environment (e.g. the Docker container without Claude Code installed), classification logs a warning and the listener keeps storing posts as before.

### Watch Classification Overrides

The classifier is good but not perfect — it's classifying fuzzy plain-text
prose. When it gets a post wrong, set a manual override. Overrides take
precedence over the LLM's output and persist across re-classifications.

**Storage:** `__doodles:watch-overrides` — Redis hash. Field is the base
post ID (the last segment of a Bluesky post URL, no `#image` suffix).
Value is a JSON blob with the same shape as `__doodles:watch-meta`:

```json
{
  "kind": "unique-watch" | "follow-on" | "family" | "event" | "other",
  "brand": "Tudor" | null,
  "model": "Black Bay 58" | null,
  "references_post_id": "3mxxxxxx" | null,
  "confidence": 1.0,
  "classified_at": "2026-04-25T00:00:00Z",
  "search_query": "Tudor Black Bay 58 39mm",
  "product_url": "https://www.tudorwatch.com/.../m79030n-0001"
}
```

`brand` and `model` are required when `kind` is `unique-watch` or
`follow-on`; null otherwise. `references_post_id` is required when `kind`
is `follow-on` (the base post ID of the canonical entry it follows up on);
null otherwise. `confidence` and `classified_at` are stamped by the
classifier; for hand-written overrides set `confidence: 1.0` and any
ISO-8601 timestamp.

`search_query` and `product_url` are both optional pricing overrides — see
the "Pricing Overrides" section below for what they do and how to set
them. Omit them entirely if you only need to correct the classifier output.

**Full vs. partial overrides.** An override JSON with `kind` set is a *full
override* — it replaces the classifier's meta wholesale. An override
JSON without `kind` (e.g. `{"search_query":"…"}`) is a *partial override*
— `apply-overrides` merges just the listed fields on top of the existing
meta. Partial overrides only patch the allow-listed fields (`search_query`,
`product_url`); unknown fields are ignored, and a partial
override against a post with no existing meta is skipped with a warning
(classify the post first via `classify-existing`).

Removing a partial override (`HDEL`) does *not* automatically clear the
fields it set in `__doodles:watch-meta`. To clear them, either set the
field explicitly to `null` (or empty string) and re-run `apply-overrides`,
or wipe the post's meta and re-classify.

**Set an override:**

```bash
# Mark a misclassified family post as event
redis-cli HSET __doodles:watch-overrides 3mkvhoxbbi22a '{
  "kind": "event",
  "brand": null,
  "model": null,
  "references_post_id": null,
  "confidence": 1.0,
  "classified_at": "2026-04-25T00:00:00Z"
}'

# Mark a misidentified follow-on as a new unique watch (variant of an
# existing canonical brand+line)
redis-cli HSET __doodles:watch-overrides 3mkxuccaxkc2j '{
  "kind": "unique-watch",
  "brand": "Brew",
  "model": "Metric PVD Black",
  "references_post_id": null,
  "confidence": 1.0,
  "classified_at": "2026-04-25T00:00:00Z"
}'
```

**Apply overrides:** an override sits dormant in Redis until the next
`classifyAndRecord` call — which only runs for new posts. To replay
overrides against the existing data:

```bash
cd listener
npm run apply-overrides
```

`apply-overrides` does three things — the first two are pure Redis (no
network), the third only runs if any override carries a `product_url`:

1. Copies every entry in `__doodles:watch-overrides` into
   `__doodles:watch-meta`, overwriting the classifier's prior output for
   those posts.
2. Rebuilds `__doodles:watch-canonical` from scratch — walks
   `all-doodles:posts` chronologically and re-derives the canonical list
   from the (now-overridden) meta. So a post previously classified as a
   canonical that's been overridden to `event` no longer appears in the
   canonical list, and a post overridden to `unique-watch` now does.
3. For every override carrying `product_url`, fetches the page and
   extracts the JSON-LD price into `__doodles:product-prices` so the
   per-post pricing widget renders immediately rather than waiting for
   the listener's next price-refresh tick (default 6h).

Run `npm run apply-overrides -- --dry-run` first if you want to preview.
Dry-run skips both the Redis writes *and* the product-page fetches.

**View, list, remove overrides:**

```bash
# All overrides
redis-cli HGETALL __doodles:watch-overrides

# A specific one
redis-cli HGET __doodles:watch-overrides 3mkvhoxbbi22a

# Remove (then re-run apply-overrides to revert that post to the
# classifier's output, OR run classify-existing -- --force to re-classify
# from scratch with the latest SKILL.md rules)
redis-cli HDEL __doodles:watch-overrides 3mkvhoxbbi22a
```

**When to override vs re-classify:** if it's a one-off the LLM got wrong,
override. If you've tightened the SKILL.md rules and want to see the new
output across the board, run `npm run classify-existing -- --force` — that
re-classifies every post from scratch (overrides remain in effect; they're
checked first on every classify call).

### Mental Model: Which Command, When?

| Command | What it does | Cost | When to use |
|---|---|---|---|
| `classify-existing` | Walks every post in `all-doodles:posts`, classifies any missing from `watch-meta`. Skips already-classified posts. | Tokens (Claude calls — Sonnet by default) | First-time bootstrap on a Redis with no prior classification, or after the listener was offline / running without `claude` and posts piled up un-classified. |
| `classify-existing -- --force` | Re-classifies **every** post from scratch. Clears the canonical list at start, rebuilds it incrementally. | Full corpus token cost | Only after editing `SKILL.md` and wanting a fresh corpus-wide pass. **Don't kill mid-run** — leaves canonical partial; recover with `apply-overrides`. |
| `apply-overrides` | Pure Redis + (if any override has `product_url`) network fetches to those manufacturer pages. Copies `watch-overrides` into `watch-meta`, rebuilds `watch-canonical` from existing meta by walking `all-doodles:posts` chronologically, and refreshes `__doodles:product-prices` for every override with a `product_url`. | Free in Redis-only mode; small egress when `product_url` is set | After setting / removing an override; also after any of the failure modes below. |
| `set-override` | One-shot per-post override setter. Merges a single field into the override JSON, applies it to `watch-meta`, and (for `product_url`) fetches the price inline. Skips the canonical rebuild — only supports the partial-override allow-list (`search_query`, `product_url`). | Free in Redis-only mode; one outbound HTTP request for `product_url` changes | The fastest path for the common pricing-override workflow (one field at a time). Use `apply-overrides` for full classification changes that need canonical rebuilt. |
| `fetch-prices` | Refreshes `__doodles:product-prices` by re-fetching every `product_url` in `watch-meta` and extracting JSON-LD `Product.offers.price`. Supports `--post=<basePostId>` to fetch one. | Free; just outbound HTTP | Manually re-fetch outside the listener's 6h cadence — e.g., after pasting a new product URL into an override and not wanting to wait. The listener does this automatically on its `PRICE_REFRESH_FREQ_SECONDS` schedule. |
| `watch-stats` | Read-only summary of classifier output. Flags: `--low-confidence`, `--list-other`. | Free | Sanity-check classifier output and find entries that need a manual override. |

**Overrides persist across all of the above** — they're consulted first on every `classifyAndRecord` call, and `apply-overrides` always re-applies them on top of meta. Setting an override is "sticky"; you can re-classify or rebuild canonical as much as you want without losing your manual corrections.

**Inline classification** runs synchronously inside `processPost` for every new post the listener captures — no scheduling needed. New posts go from Bluesky → listener → classified + meta + canonical entry, all in one polling cycle.

### Troubleshooting

**Symptom: gallery shows no Stats strip; `/api/watch-stats` returns `{uniqueCount: 0, brandCount: 0, byBrand: []}` even though "First appeared" links work and `/api/posts?brand=...` filters work.**

Diagnosis: `__doodles:watch-meta` is populated but `__doodles:watch-canonical` is empty. The Stats component renders nothing when `uniqueCount === 0`. The two API paths that DO work read meta directly and bypass the canonical list.

Common cause: a `classify-existing -- --force` run that was killed before it finished. The start of `--force` clears the canonical list and rebuilds it incrementally as it processes each post; an early kill leaves canonical at zero (or nearly so) while meta still has the prior good entries.

Fix: `cd listener && npm run apply-overrides` rebuilds canonical from existing meta in seconds. No Claude calls.

**Symptom: listener log shows "Watch classification failed" for every new post.**

The `claude` CLI isn't on PATH inside the listener container, or `ANTHROPIC_API_KEY` didn't propagate. The listener fail-soft path keeps storing posts; classification just stays empty until the deploy is fixed. See "Claude Code in the listener container" below.

### Claude Code in the listener container

The inline classifier shells out to `claude -p`. The listener Dockerfile installs `@anthropic-ai/claude-code` globally (pinned version) and sets `DISABLE_AUTOUPDATER=1` so the daemon doesn't pay the auto-update check on every invocation. `docker-compose.yml` propagates two env vars from the host:

- `ANTHROPIC_API_KEY` (required) — headless auth path. With this set, `claude -p` skips the OAuth/onboarding flow that would otherwise block the daemon. Set it in your shell or `.env` before `docker compose up`.
- `WATCH_CLASSIFIER_MODEL` (optional, defaults to `sonnet`) — which Claude model to call. Lets you swap to `haiku` for cheaper-but-noisier classification without rebuilding.

To validate the in-container setup, shell in and run a smoke test:

```bash
docker compose run --rm --entrypoint /bin/bash listener
# Inside the container:
which claude && claude --version
echo "$ANTHROPIC_API_KEY" | head -c 8 ; echo "…"
claude -p --output-format json --model sonnet \
  'Output JSON only, no fences: {"hello":"world"}'
```

If the JSON envelope comes back with a `result` field, the listener will classify cleanly on every new post.

### Pricing Overrides

The per-post pricing widget (the small card between the post text and the
images on `/post/[id]`) merges two data sources: eBay Browse API search
results, and a manufacturer product price extracted from a JSON-LD
`Product.offers.price` blob on a product page. Both can be steered per
post via two optional fields on a `__doodles:watch-overrides` entry.

#### `search_query` — fix eBay search precision

When the classifier's `brand` + `model` produces a noisy or empty eBay
search (common for microbrands or imprecise model names), set
`search_query` on the canonical's override to replace the default
`${brand} ${model}` query. Affects the widget for the canonical post and
all of its follow-ons.

Since `search_query` doesn't change the classification, write it as a
partial override (no `kind`) so it patches the existing meta instead of
replacing it. The shortest path is the `set-override` CLI, which writes
the override JSON and applies it in one step:

```bash
cd listener && npm run set-override -- 3m2v2gfa7as2w search_query \
  "PHILIPPE STARCK FOSSIL PH-5029 WATCH"
# Override updated: 3m2v2gfa7as2w.search_query = "..."
# Wrote __doodles:watch-meta: unique-watch Fossil PH-5029
#   search_query: "PHILIPPE STARCK FOSSIL PH-5029 WATCH"
```

Equivalent raw form, for when you want to script multi-field changes:

```bash
redis-cli --raw HSET __doodles:watch-overrides 3m2v2gfa7as2w \
  '{"search_query":"PHILIPPE STARCK FOSSIL PH-5029 WATCH"}'

cd listener && npm run apply-overrides
```

Note: the eBay response is cached in Redis for 24h per *effective* search
query, so a `search_query` change creates a new cache entry and the next
widget render fetches fresh data. The old cache entry expires on its own.

#### `product_url` — show the current manufacturer price

For watches still sold by the brand (microbrands, current production
flagships), set `product_url` to the manufacturer's product page. The
listener fetches the page on a cadence (default every 6h, see
`PRICE_REFRESH_FREQ_SECONDS`), extracts the price from JSON-LD
`Product.offers.price`, and stores it in `__doodles:product-prices`.

The widget then renders the current price + a link to the manufacturer
page alongside (or instead of) the eBay listings row. Works on any
e-commerce platform that emits the schema.org `Product` structured data
— Shopify, WooCommerce, and most custom storefronts do; we treat that
schema as a sanctioned data contract rather than parsing rendered HTML.

```bash
# Brew is a microbrand with very few eBay listings — point at their
# product page so the widget shows the current MSRP. Partial override
# preserves the classifier's brand/model/kind; only product_url is patched.
cd listener && npm run set-override -- 3mkxuccaxkc2j product_url \
  "https://brewwatches.com/products/metric-hp-1"
# Output:
#   Override updated: 3mkxuccaxkc2j.product_url = "..."
#   Wrote __doodles:watch-meta: unique-watch Brew Metric HP-1
#     product_url:  https://brewwatches.com/products/metric-hp-1
#   Fetching product price from ...
#     [price] USD 750 from brewwatches.com
```

The price fetch happens inline so you don't wait for the listener's 6h
refresh tick. To clear a previously-set product_url and drop the cached
price, pass an empty value:

```bash
cd listener && npm run set-override -- 3mkxuccaxkc2j product_url ""
#   Override updated: 3mkxuccaxkc2j.product_url = null
#   Cleared product-price cache entry for 3mkxuccaxkc2j
```

You can also set both fields together via the raw form when you need to
write multiple keys at once — the widget then shows the manufacturer
price *and* the eBay listings row when both return data:

```bash
redis-cli --raw HSET __doodles:watch-overrides 3mkxuccaxkc2j \
  '{"search_query":"Brew Metric HP-1", "product_url":"https://brewwatches.com/products/metric-hp-1"}'
cd listener && npm run apply-overrides
```

**Manual fetch (debugging):**

```bash
# Fetch all configured product URLs and refresh __doodles:product-prices
cd listener && npm run fetch-prices

# Fetch a single post
cd listener && npm run fetch-prices -- --post=3mkxuccaxkc2j

# Inspect stored prices
redis-cli HGETALL __doodles:product-prices

# Clear a stale price (e.g., product discontinued — the URL still works
# but the listed price is no longer relevant)
redis-cli HDEL __doodles:product-prices 3mkxuccaxkc2j
```

If a page has no parseable JSON-LD `Product` block, `fetch-prices` logs a
warning and writes nothing — any prior successful price remains in place
until you manually `HDEL` it.

**For follow-ons:** set `product_url` and `search_query` on the
*canonical* post's override, not on the follow-on. The widget on a
follow-on page resolves to the canonical's `basePostId` before looking
up overrides and prices, so one override entry covers the whole family.

### Tools (./tools/)
```bash
# Query specific post data and save to JSON file
npx ts-node query-post.ts <profile> <postId>

# Search for a post across the Redis store (posts, meta, overrides)
npx ts-node moderation.ts <postId>

# Delete a post everywhere (moderation)
npx ts-node moderation.ts <postId> --delete

# Rebuild the handle:*:posts reverse indices from all-doodles:posts
# (one-time migration helper; normally never needed). Connects to
# localhost:6379; pass the Redis password as the first arg if required.
npx ts-node build-reverse-index.ts [password]
```

### Watch-shaped QR code (`watch-qr.js`)

Generates a scannable QR code framed as a wristwatch — for print, packaging,
or a site hero. The scannable core stays a plain square QR at error-correction
level **H** (it tolerates ~30% obstruction), and the watch — round case, bezel,
hour markers, strap, crown — is drawn *around* it, so the whole thing reads as a
watch while still scanning reliably. Every run rasterises the result and decodes
it with a real QR reader (jsQR); it prints `✓ scannable` or warns before you
print something that won't scan.

```bash
cd tools

# Default: vertical watch, leather strap, light theme -> watch-qr.png
node watch-qr.js

# Horizontal "card": upright watch on one half, branding on the other,
# straps bleeding off the top & bottom edges (great for a banner / hero)
node watch-qr.js --orientation horizontal --align left  --out hero.png
node watch-qr.js --orientation horizontal --align right --theme dark

# Different strap, custom link and branding, larger raster
node watch-qr.js --strap mesh --url https://ryanswatches.com/ryanjoseph.dev \
                 --title "RYAN'S WATCHES" --caption "scan to browse" --width 2000

# SVG output (vector, crisp at any size) — chosen automatically by the extension
node watch-qr.js --out watch-qr.svg
```

**Options**

| Flag | Values | Default | Notes |
|------|--------|---------|-------|
| `--url` | any URL | `https://ryanswatches.com` | What the QR points to |
| `--out` | path | `watch-qr.png` | Format is picked from the extension: `.svg` → SVG, anything else → PNG |
| `--theme` | `light` \| `dark` | `light` | Matches the site's bronze-on-cream / bronze-on-black palette |
| `--orientation` | `vertical` \| `horizontal` | `vertical` | `vertical` = portrait, watch centred. `horizontal` = landscape card, watch on one half |
| `--align` | `left` \| `right` | `left` | Horizontal only: which half the watch sits on (branding fills the other) |
| `--strap` | `leather` \| `rubber` \| `nato` \| `mesh` \| `bracelet` | `leather` | Strap style |
| `--title` | text | `RYAN'S WATCHES` | Branding line |
| `--caption` | text | the URL's host | Sub-line |
| `--width` | px | `1200` | PNG raster width (ignored for SVG) |
| `--no-verify` | — | off | Skip the built-in scannability check |

Requires the `qrcode`, `sharp`, and `jsqr` packages (already in `tools/package.json`;
`npm install` in `tools/` if missing). Prefer SVG for print and PNG for the web.
Always test-scan the final asset with a couple of phones before sending it to print.

## Configuration

### Environment Variables

**Required:**
- `BLUESKY_IDENT` - Bluesky username/handle
- `BLUESKY_PASS` - Bluesky app password
- `HASHTAG_TO_WATCH` - Hashtag to monitor (include the # prefix). No default — the listener exits fatally without it, and the frontend's `/api/config` returns an error.
- `ANTHROPIC_API_KEY` - Required for the inline watch classifier. The listener calls `claude -p` per post; without this var, classification fails-soft (post still stored, no `watch-meta` entry written).

**Optional:**
- `REDIS_URL` - Redis connection string (default: `redis://localhost:6379`)
- `POLLING_FREQ_SECONDS` - Listener polling interval (default: 300)
- `PRICE_REFRESH_FREQ_SECONDS` - Cadence for refreshing manufacturer product prices via `fetch-prices` from inside the listener loop (default: 21600 = 6h). Only relevant if any `__doodles:watch-overrides` entries carry a `product_url`. The refresh runs after each polling tick that crosses the threshold, throttled via `__doodles:product-prices:last-refresh`.
- `EBAY_CLIENT_ID`, `EBAY_CLIENT_SECRET`, `EBAY_ENV` - eBay Browse API credentials for the pricing widget. `EBAY_ENV` is `production` or `sandbox` (default sandbox; sandbox returns synthetic data unsuitable for live).
- `HANDLES_TO_WATCH` - Comma-separated list of Bluesky handles to limit the collection to. First handle in the list is shown as the deployment owner on the gallery. Also enables multi-image grouping on gallery cards.
- `SITE_TITLE` - Human-readable wordmark for the gallery masthead (e.g. `Ryan's Watches`). Falls back to the hashtag itself when unset.
- `WATCH_CLASSIFIER_MODEL` - Claude model the watch classifier uses (default: `sonnet`). Set to `haiku` for cheaper / noisier classification.
- `WEAR_API_TOKEN` - Bearer token for the `/api/wear/*` endpoints used by the iOS app (see "Wear API & iOS app"). Unset = wear API disabled (503).
- `WEAR_TIMEZONE` - IANA zone defining local days for the wearage page's nightly deduction (default `America/Los_Angeles`).
- `WEAR_SLEEP_HOURS` - Hours deducted from the watch on the wrist at the end of each day (default `7`; `0` disables).
- `DISABLE_AUTOUPDATER` - Set to `1` in the listener container so `claude` doesn't run the auto-update check on every invocation. Already set in `listener/Dockerfile`.
- `PORT` - Frontend production server port (default: 3000). The dev server (`npm run dev`) runs on a hard-coded port 42420.

### Hero Image Overrides

Multi-image posts default to showing the first image (`#image0`) as the gallery
card preview. To feature a different image without changing the underlying post,
add an entry to the `__doodles:hero-overrides` Redis hash. The field is the base
post ID (the part after `app.bsky.feed.post/` in the URI, also the last segment
of the post URL on Bluesky); the value is the zero-based image index to feature.

```bash
# Use image1 (the second image) as the gallery preview for post 3mjve4rdk7k2c
redis-cli HSET __doodles:hero-overrides 3mjve4rdk7k2c 1

# Remove the override (revert to image0)
redis-cli HDEL __doodles:hero-overrides 3mjve4rdk7k2c

# List all current overrides
redis-cli HGETALL __doodles:hero-overrides
```

Effects:
- Applies to the gallery `/` and `/[handle]` pages — both the small preview cards
  and the dominant hero card on `/[handle]` page 1.
- The post detail page (`/post/[id]` and `/[handle]/post/[id]`) preserves the
  original image order regardless of overrides.
- An override index `<= 0`, non-numeric, or beyond the post's image count is
  silently ignored.

Changes take effect on the next gallery refresh — no service restart required.

## Wear API & iOS app

`ios-app/` contains **Wrist**, a single-purpose iOS app for logging which watch is on your wrist right now. It talks to a small authenticated API inside the frontend; the full wire contract is in [`ios-app/API.md`](ios-app/API.md) and the implementation plan in [`ios-app/PLAN.md`](ios-app/PLAN.md). Mac-side build/run instructions are in [`ios-app/README.md`](ios-app/README.md).

**Endpoints** (all require `Authorization: Bearer $WEAR_API_TOKEN`; 60 req/min per IP):

| Route | Purpose |
|---|---|
| `GET /api/wear/watches` | Every canonical watch with hero image, wear count, last worn, sorted most-worn first, plus the current wear event |
| `GET /api/wear/events?limit=50` | Recent wear events, newest first |
| `POST /api/wear/events` | Log a wear (`{id, watchId, wornAt, source}`; idempotent on `id`) |
| `DELETE /api/wear/events/{id}` | Undo a wear |

**Setup:** generate a token (`openssl rand -hex 32`), set `WEAR_API_TOKEN` in the deployment's `.env`, redeploy the frontend, then paste the same token into the app's setup screen. Leaving the variable unset disables the API entirely (every route returns 503).

**Tests:** `cd frontend && npm test` runs the vitest suite. Integration tests use a real Redis but only logical DB 15 (`redis://localhost:6379/15`) and refuse to start against any other DB; set `WEAR_TEST_REDIS_URL` to point at a different host (keep the `/15`).

### On the site: "On the wrist" and `/wearage`

The front page shows one line under the brand list with the watch currently on the wrist (public, read-only, fed by `GET /api/wearing`, refreshed every 5 minutes). `/wearage` breaks the history down by **share of awake wrist-time**, all-time and last 30 days, per watch and per brand.

Method: a watch is credited from the moment it is logged until the next log; at the end of every completed day (`WEAR_TIMEZONE`) `WEAR_SLEEP_HOURS` hours come off whichever watch is on the wrist; shares are of what remains. No hours are shown, only percentages. The math lives in `frontend/lib/wearage.ts` and is unit-tested.

## Data Structure

### Core Type
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
  uri: string;           // "at://did/app.bsky.feed.post/id#imageN"
  authorHandle: string;
  authorDisplayName: string;
  text: string;          // Bluesky display text — inline URLs may be truncated to ~30 chars
  imageUrls: string[];   // Single image per post entry
  createdAt: string;
  postUrl: string;       // Bluesky web URL
  facets?: Facet[];      // Bluesky rich-text facets — full URIs for inline links / tags / mentions, byte-offset indexed against `text`
}
```

### Multi-Image Handling
Posts with multiple images are split into separate `Post` entries:
- Original post: `at://did/app.bsky.feed.post/abc123`
- Image 1: `at://did/app.bsky.feed.post/abc123#image0`
- Image 2: `at://did/app.bsky.feed.post/abc123#image1`

This enables individual image routing and display. Gallery embeds (Bluesky
posts with more than 4 images) are supported the same way.

### Redis Structure

Storage is unified — every collected post lives in one store, with
per-handle index lists layered on top (there is no per-user prefix fanout;
handle filtering happens at ingest via `HANDLES_TO_WATCH` and at read time
via the `handle:*` indices):

**Post storage:**
- `all-doodles:posts` - List of serialized Post objects, newest first (one entry per image)
- `post:<uri>` - Full Post JSON keyed by image URI (direct lookup)
- `handle:<handle>:posts` - List of image URIs per author (reverse index)
- `handles:all` - Set of every author handle seen
- `all-doodles:processed-uris` - Set of processed post/image URIs (deduplication)
- `all-doodles:last-seen-post` - Most recent post URI (search optimization)
- `all-posts:saved-session` - Bluesky session data (authentication persistence)

**Classifier & widgets:**
- `__doodles:watch-meta` - Hash, basePostId → classifier output JSON
- `__doodles:watch-canonical` - List of unique watches, oldest first
- `__doodles:watch-overrides` - Hash of manual classification/widget overrides
- `__doodles:product-prices` - Hash of scraped manufacturer prices (+ `:last-refresh` throttle key)
- `__doodles:hero-overrides` - Hash mapping base post IDs to the gallery-preview image index (see [Hero Image Overrides](#hero-image-overrides))
- `__doodles:wear-events` - Hash, eventId → JSON wear event (which watch was put on, when, from which surface). Written by the wear API.
- `__doodles:wear-timeline` - Sorted set of wear event IDs scored by worn-at time; drives "currently wearing" and most-worn ordering.
- `__doodles:ebay-pricing:*` - 24h eBay response cache

## Frontend Features

### Routing
- `/` - All posts gallery, paginated (50/page), 5-minute auto-refresh
- `/[handle]` - User-specific gallery with a dominant hero card on page 1 (e.g., `/ryanjoseph.dev`)
- `/post/[id]` - Individual post pages with pricing widget, rich-text rendering, and back navigation
- `/[handle]/post/[id]` - User-scoped post pages
- `/rss.xml` - RSS feed, cached 1 hour (supports `?handle=` parameter)

### UI Features
- **Stats strip**: Unique-watch count, brand count, and per-brand filter chips driven by the classifier's canonical list
- **Brand filtering**: `?brand=` filtered galleries showing a brand's full timeline (canonicals + follow-ons)
- **"First appeared →"**: Follow-on posts link back to the canonical post for that watch
- **Theme System**: Light/dark mode toggle with localStorage persistence (dark is the default)
- **Auto-refresh**: Gallery updates every 5 minutes
- **Responsive Design**: Mobile-optimized layout

### Styling
- **Design Language**: Warm paper-and-ink minimalism — cream/near-black surfaces with a bronze accent (`#8b6634` light / `#c89456` dark), hairline borders
- **Typography**: Google Fonts 'Schibsted Grotesk' (body/UI) and 'Lato' (accents)
- **CSS Architecture**: CSS Modules with CSS custom properties for theming
- **Image Optimization**: Next.js Image component with Bluesky CDN support

## Listener Features

### Post Processing
- **Hashtag Detection**: Requires the configured hashtag in the post text
- **Handle Filtering**: When `HANDLES_TO_WATCH` is set, only those authors' posts are collected
- **Image Extraction**: Supports direct image embeds, gallery embeds (>4 images), and record-with-media embeds (videos skipped)
- **NSFW Filtering**: Skips posts with #nsfw / #noindex tags or sexual content labels
- **Deduplication**: Tracks processed URIs to prevent duplicates
- **Inline Classification**: Every stored post is classified (brand/model/kind) in the same polling cycle

### Session Management
- **Authentication**: Bluesky login with 2FA support
- **Session Persistence**: Saves auth tokens in Redis to avoid re-login
- **Rate Limit Handling**: Graceful handling of API limits

### Search Strategy
- **Incremental**: Searches from latest posts until finding the last seen post
- **Batch Processing**: 100 posts per search batch, maximum 20 batches per cycle
- **First Run**: Processes only the latest batch on initial run

## Deployment

### Docker Compose
```bash
# Production deployment
docker-compose up -d

# View logs
docker-compose logs -f listener
docker-compose logs -f frontend

# Stop services
docker-compose down
```

Both services use `network_mode: 'host'` and restart automatically unless
stopped. Environment variables are sourced from the host `.env` file.

### Manual Development
```bash
# Terminal 1: Start Redis
docker run -d -p 6379:6379 redis:alpine

# Terminal 2: Start listener
cd listener
npm install
npm run start

# Terminal 3: Start frontend (dev server on port 42420)
cd frontend
npm install
npm run dev
```

## API Reference

### Frontend API Endpoints
- `GET /api/posts` - All posts. Query params: `?handle=` (author filter), `?brand=` (classifier brand filter), `?paginate=true&page=1&pageSize=50` (paginated envelope instead of a bare array). Rate-limited (100 req/min).
- `GET /api/config` - Deployment config for the masthead: hashtag, site title, primary tracked handle
- `GET /api/custom-users` - Sorted list of every handle that has posted (from `handles:all`)
- `GET /api/watch-stats` - Classifier aggregates: unique-watch count, brand count, per-brand counts
- `GET /api/wearing` - The watch currently on the wrist: `{ wearing: { watch, event } | null }`. Public, read-only; rate-limited.
- `GET /api/pricing?postId=<basePostId>` - Pricing widget data: eBay listings summary + manufacturer price (24h cache)
- `GET /rss.xml` - RSS feed (all posts); `?handle=` for a user-specific feed

### Redis Commands
```bash
# View stored posts
redis-cli LRANGE all-doodles:posts 0 -1

# Check processed URIs
redis-cli SMEMBERS all-doodles:processed-uris

# View a single post by URI
redis-cli GET "post:at://did:plc:xxx/app.bsky.feed.post/yyy#image0"

# Posts by author
redis-cli LRANGE handle:ryanjoseph.dev:posts 0 -1

# All known authors
redis-cli SMEMBERS handles:all
```

## Troubleshooting

### Common Issues
- **Redis Connection**: Ensure Redis is running and `REDIS_URL` is correct
- **Listener exits immediately**: `HASHTAG_TO_WATCH` is unset — it's required
- **Bluesky Auth**: Verify `BLUESKY_IDENT` and `BLUESKY_PASS` are valid
- **2FA Required**: Listener will prompt for auth code during login
- **Missing Posts**: Run backfill script for historical posts
- **Image Loading**: Check Next.js remote patterns in `next.config.js`
- **No classification on new posts**: See "Claude Code in the listener container"

### Debugging
```bash
# Check Redis connectivity
redis-cli ping

# View all Redis keys
redis-cli KEYS "*posts*"

# Monitor listener logs
docker-compose logs -f listener
```

## License

This project is for educational and personal use. Bluesky content belongs to respective authors.
