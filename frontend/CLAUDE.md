# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the Next.js frontend for "Watches" — a Bluesky watch-collection gallery. It displays posts collected by the listener service: gallery views (all posts and per-handle), individual post pages with a pricing widget and Reddit discussion card, classifier-driven brand stats/filtering, and RSS feeds. Design language is warm paper-and-ink minimalism with a bronze accent.

Never hardcode secrets (passwords, API keys, tokens) in any file — see the Security Policy in the root CLAUDE.md. Use environment variables.

## Development Commands

- `npm run dev` - Start development server on port 42420 (hard-coded in the dev script)
- `npm run build` - Build for production
- `npm run start` - Start production server (respects PORT env var, default 3000)

(No lint script — this project doesn't use ESLint.)

## Architecture & Data Flow

### Core Data Structure
The application centers around the `Post` type (defined in `lib/redis.ts`) which represents a Bluesky post with associated metadata. Each post can have multiple images, and the system creates separate entries for each image (identified by URI + image index). `lib/redis.ts` also defines `WatchMeta` (classifier output) and `WatchStats` (brand aggregates).

### Data Sources
- **Redis**: Primary data store. Posts live in the `all-doodles:posts` list, with `post:<uri>` keys for direct lookup and `handle:<handle>:posts` URI lists per author (`getPosts` supports both the new URI format and the legacy numeric-index format). Classifier state is in `__doodles:watch-meta` / `__doodles:watch-canonical`; widget overrides and caches in other `__doodles:*` keys.
- **eBay Browse API**: `lib/ebay.ts` — recent-listings search for the pricing widget (24h Redis cache)
- **Reddit archives**: `lib/reddit.ts` — Arctic Shift primary / PullPush fallback for the Reddit card (24h Redis cache)
- **External Images**: Served from `cdn.bsky.app` and `bsky.social` (configured in `next.config.js`)

### Key Architecture Patterns

**Multi-Image Post Handling**: When a Bluesky post contains multiple images, each gets a separate `Post` entry with URIs like `at://...post/ID#image0`, `at://...post/ID#image1`. The `lib/utils.ts` functions handle parsing these URIs for routing and grouping (`groupPostsByBaseUri`).

**Hero Overrides**: `__doodles:hero-overrides` (Redis hash, basePostId → image index) reorders a multi-image post's images so a chosen image leads on gallery cards. Post detail pages keep the original order.

**Theme System**: CSS custom properties in `styles/globals.css` define light/dark themes applied via `data-theme` attribute. The `ThemeContext` manages state and localStorage persistence. Dark is the default.

**RSS Generation**: Dynamic RSS feed at `/rss.xml` using `getServerSideProps` to fetch and format data server-side. Public URLs point at `https://ryanswatches.com`.

## Routing Structure

- `/` - Main gallery, all posts (server-rendered with client-side refresh, paginated 50/page)
- `/[handle]` - Per-user gallery with a dominant hero card on page 1
- `/post/[id]` - Individual post pages where `[id]` is the extracted post ID + optional image index
- `/[handle]/post/[id]` - User-scoped post pages
- `/rss.xml` - RSS feed endpoint (server-generated XML, `?handle=` supported)

API routes (all rate-limited, CORS-restricted to ryanswatches.com in production):
- `/api/posts` - Posts with `?handle=`, `?brand=`, and `?paginate=true&page=&pageSize=` params
- `/api/config` - Deployment config (hashtag, site title, primary handle) for the masthead
- `/api/custom-users` - All handles that have posted (from `handles:all`)
- `/api/watch-stats` - Classifier aggregates (unique watches, brands, per-brand counts)
- `/api/pricing?postId=` - Pricing widget data (eBay + manufacturer price)
- `/api/reddit?postId=` - Reddit card data (503 when `REDDIT_CARD_ENABLED` is off)

## Styling Approach

**Design System**: Warm paper-and-ink minimalism — cream (`#f7f5f0`) / near-black (`#0c0c0c`) surfaces, bronze accent (`#8b6634` light / `#c89456` dark), hairline borders. Theme-aware via CSS custom properties.

**Component Styling**: CSS Modules for scoped styles. Key modules:
- `Home.module.css` - Gallery pages
- `WatchCard.module.css` - Gallery cards
- `Post.module.css` - Individual post pages
- `Pricing.module.css` / `Reddit.module.css` / `Stats.module.css` / `Pagination.module.css` - Widgets

**Typography**: Google Fonts 'Schibsted Grotesk' (body/UI) and 'Lato' (accents).

## Important Implementation Details

**Hydration Safety**: Individual post pages use client-side mounting detection to avoid server/client date formatting mismatches.

**Image Optimization**: Next.js Image component with remote patterns configured for Bluesky CDN domains.

**Rich Text**: The `RichText` component renders post text using Bluesky `facets` (byte-offset indexed) so inline URLs, hashtags, and mentions are full-length and clickable.

**Error Handling**: Redis connection errors gracefully handled in API routes with appropriate HTTP status codes.

**Performance**: RSS feed cached for 1 hour, gallery auto-refreshes every 5 minutes on the client, eBay/Reddit responses cached 24h in Redis.

## Testing Policy
**IMPORTANT**: Do not run tests, builds, or any validation commands unless explicitly requested in the prompt. The user will handle all testing and provide feedback on any errors or changes needed.
