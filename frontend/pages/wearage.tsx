import React, { useEffect, useMemo, useState } from 'react';
import Head from 'next/head';
import Link from 'next/link';
import { format } from 'date-fns';
import ShareList, { ShareRow } from '../components/ShareList';
import { getWearageData } from '../lib/wear';
import type { WearageData, WatchInfo } from '../lib/wear';
import type { WearageSummary } from '../lib/wearage';
import { useTheme } from '../contexts/ThemeContext';
import homeStyles from '../styles/Home.module.css';
import styles from '../styles/Wearage.module.css';

interface WearageProps {
  siteTitle: string;
  data: WearageData | null;
}

type WindowKey = 'all' | '30';

const WINDOW_LABELS: Record<WindowKey, string> = {
  all: 'All time',
  '30': 'Last 30 days',
};

function watchName(info: WatchInfo | undefined, id: string): string {
  return info ? `${info.brand} ${info.model}`.trim() : id;
}

function thumbOf(info: WatchInfo | undefined): string | null {
  return info ? info.thumbnailUrl ?? info.imageUrl : null;
}

function pctText(share: number): string {
  return `${Number((share * 100).toFixed(1))}%`;
}

function buildWatchRows(summary: WearageSummary, watches: Record<string, WatchInfo>): ShareRow[] {
  return summary.shares
    .filter(s => s.ms > 0)
    .map(s => ({
      id: s.watchId,
      name: watchName(watches[s.watchId], s.watchId),
      thumbnailUrl: thumbOf(watches[s.watchId]),
      share: s.share,
      wears: s.wears,
      lastWornAt: s.lastWornAt,
    }));
}

function buildBrandRows(summary: WearageSummary, watches: Record<string, WatchInfo>): ShareRow[] {
  interface Acc {
    ms: number;
    wears: number;
    lastWornAt: string | null;
    watchCount: number;
    topMs: number;
    thumbnailUrl: string | null;
  }
  const byBrand = new Map<string, Acc>();
  for (const s of summary.shares) {
    if (s.ms <= 0) continue;
    const info = watches[s.watchId];
    const brand = info?.brand || 'Unknown';
    const acc =
      byBrand.get(brand) ??
      { ms: 0, wears: 0, lastWornAt: null, watchCount: 0, topMs: -1, thumbnailUrl: null };
    acc.ms += s.ms;
    acc.wears += s.wears;
    acc.watchCount += 1;
    if (s.lastWornAt && (!acc.lastWornAt || s.lastWornAt > acc.lastWornAt)) {
      acc.lastWornAt = s.lastWornAt;
    }
    if (s.ms > acc.topMs) {
      acc.topMs = s.ms;
      acc.thumbnailUrl = thumbOf(info);
    }
    byBrand.set(brand, acc);
  }
  return Array.from(byBrand.entries())
    .sort((a, b) => b[1].ms - a[1].ms || a[0].localeCompare(b[0]))
    .map(([brand, acc]) => ({
      id: brand,
      name: brand,
      sub: `${acc.watchCount} ${acc.watchCount === 1 ? 'watch' : 'watches'}`,
      thumbnailUrl: acc.thumbnailUrl,
      share: summary.totalMs > 0 ? acc.ms / summary.totalMs : 0,
      wears: acc.wears,
      lastWornAt: acc.lastWornAt,
    }));
}

export default function Wearage({ siteTitle, data }: WearageProps) {
  const { theme, toggleTheme } = useTheme();
  const [windowKey, setWindowKey] = useState<WindowKey>('all');
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  const summary = data ? (windowKey === 'all' ? data.allTime : data.last30Days) : null;

  const watchRows = useMemo(
    () => (data && summary ? buildWatchRows(summary, data.watches) : []),
    [data, summary],
  );
  const brandRows = useMemo(
    () => (data && summary ? buildBrandRows(summary, data.watches) : []),
    [data, summary],
  );

  const wears = summary ? summary.shares.reduce((n, s) => n + s.wears, 0) : 0;
  const watchesWorn = summary ? summary.shares.filter(s => s.ms > 0).length : 0;
  const canonicalCount = data ? Object.keys(data.watches).length : 0;
  const unworn = Math.max(0, canonicalCount - watchRows.length);
  const top = summary && summary.shares.length > 0 && summary.shares[0].ms > 0 ? summary.shares[0] : null;

  let updated = '';
  if (mounted && data) {
    const d = new Date(data.generatedAt);
    if (!Number.isNaN(d.getTime())) updated = format(d, 'MMM d, h:mm a');
  }

  return (
    <>
      <Head>
        <title>{`Wearage · ${siteTitle}`}</title>
        <meta name="description" content="Which watches actually get wrist time." />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
      </Head>

      <main className={homeStyles.main}>
        <div className={homeStyles.topButtons}>
          <a
            href="https://github.com/rpj/watches"
            target="_blank"
            rel="noopener noreferrer"
            className={homeStyles.githubButton}
            aria-label="View source on GitHub"
          >
            <svg viewBox="0 0 24 24" fill="currentColor" width="20" height="20">
              <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.30.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
            </svg>
          </a>
          {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
          <a href="/rss.xml" className={homeStyles.rssButton} aria-label="RSS Feed">
            <svg viewBox="-271 273 256 256" fill="currentColor" width="18" height="18">
              <path d="M-271,360v48.9c31.9,0,62.1,12.6,84.7,35.2c22.6,22.6,35.1,52.8,35.1,84.8v0.1h49.1c0-46.6-19-88.7-49.6-119.4C-182.2,379-224.4,360.1-271,360z"/>
              <path d="M-237,460.9c-9.4,0-17.8,3.8-24,10s-10,14.6-10,24c0,9.3,3.8,17.7,10,23.9c6.2,6.1,14.6,9.9,24,9.9s17.8-3.7,24-9.9s10-14.6,10-23.9c0-9.4-3.8-17.8-10-24C-219.2,464.7-227.6,460.9-237,460.9z"/>
              <path d="M-90.1,348.1c-46.3-46.4-110.2-75.1-180.8-75.1v48.9C-156.8,322-64.1,414.9-64,529h49C-15,458.4-43.7,394.5-90.1,348.1z"/>
            </svg>
          </a>
          <button
            onClick={toggleTheme}
            className={homeStyles.themeToggle}
            aria-label={`Switch to ${theme === 'light' ? 'dark' : 'light'} mode`}
          >
            {theme === 'light' ? (
              <svg viewBox="0 0 24 24" fill="currentColor" width="16" height="16">
                <circle cx="12" cy="12" r="8" fill="currentColor" />
              </svg>
            ) : (
              <svg viewBox="0 0 24 24" fill="currentColor" width="16" height="16">
                <circle cx="12" cy="12" r="8" fill="none" stroke="currentColor" strokeWidth="2"/>
              </svg>
            )}
          </button>
        </div>

        <header className={homeStyles.header}>
          <div className={styles.nav}>
            <Link href="/" className={homeStyles.backButton} aria-label="Back to gallery">
              ← Gallery
            </Link>
          </div>
          <h1 className={`${homeStyles.title} ${styles.pageTitle}`}>
            <Link href="/">{siteTitle}</Link>
          </h1>
          <p className={styles.kicker}>Wearage</p>
        </header>

        {!data || !summary ? (
          <div className={homeStyles.error}>Unable to load wearage</div>
        ) : (
          <div className={styles.content}>
            <div className={styles.toggleRow}>
              <div className={styles.toggle} role="group" aria-label="Time window">
                {(['all', '30'] as const).map(key => (
                  <button
                    key={key}
                    type="button"
                    className={`${styles.toggleButton} ${windowKey === key ? styles.active : ''}`}
                    aria-pressed={windowKey === key}
                    onClick={() => setWindowKey(key)}
                  >
                    {WINDOW_LABELS[key]}
                  </button>
                ))}
              </div>
            </div>

            <section className={styles.hero} aria-label="Top watch">
              <p className={styles.heroFigure}>{top ? pctText(top.share) : '—'}</p>
              <p className={styles.heroName}>
                {top ? watchName(data.watches[top.watchId], top.watchId) : 'Nothing logged yet'}
              </p>
              {top && (
                <p className={styles.heroCaption}>
                  of awake wrist-time · {WINDOW_LABELS[windowKey]}
                </p>
              )}
            </section>

            <div className={styles.numbers}>
              <span>
                <span><strong>{summary.daysTracked}</strong> Days tracked</span>
                <span className={styles.dot} aria-hidden="true">·</span>
                <span><strong>{wears}</strong> Wears</span>
                <span className={styles.dot} aria-hidden="true">·</span>
                <span><strong>{watchesWorn}</strong> Watches worn</span>
              </span>
            </div>

            <ShareList
              title="Share of wrist time"
              ariaLabel="Share of wrist time by watch"
              rows={watchRows}
            />
            {unworn > 0 && (
              <p className={styles.collapsed}>
                {unworn} {unworn === 1 ? 'watch' : 'watches'} with no wrist time yet
              </p>
            )}

            <div className={styles.gap} aria-hidden="true" />

            <ShareList title="By brand" ariaLabel="Share of wrist time by brand" rows={brandRows} />

            <footer className={styles.method}>
              <p>
                Each watch is credited from the moment it&rsquo;s logged until the next log. At the
                end of every day ({data.config.timeZone}) {data.config.sleepHours} hours come off
                whichever watch is on the wrist, since nobody wears a watch to bed. Shares are of
                what remains: awake wrist-time, never hours.
              </p>
              <p className={styles.updated}>{updated && `Updated ${updated}`}</p>
            </footer>

            <div className={styles.footer}>
              <Link href="/" className={homeStyles.userLink}>
                ← Back to gallery
              </Link>
            </div>
          </div>
        )}
      </main>
    </>
  );
}

export async function getServerSideProps() {
  const siteTitle =
    (process.env.SITE_TITLE && process.env.SITE_TITLE.trim()) ||
    (process.env.HASHTAG_TO_WATCH ?? '').trim();

  let data: WearageData | null = null;
  try {
    data = await getWearageData();
  } catch (e) {
    console.error('SSR getWearageData failed:', e);
  }

  return { props: { siteTitle, data } };
}
