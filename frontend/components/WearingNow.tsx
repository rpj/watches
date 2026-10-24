import React from 'react';
import Image from 'next/image';
import Link from 'next/link';
import type { WearingNow as WearingNowData } from '../lib/wear';
import styles from '../styles/WearingNow.module.css';

interface WearingNowProps {
  wearing: WearingNowData | null;
}

/**
 * "Last on the wrist": the most recently logged watch. Deliberately no
 * timestamp and never a bare-wrist state; the server already skips those.
 */
export default function WearingNow({ wearing }: WearingNowProps) {
  if (!wearing) {
    return null;
  }

  const { watch } = wearing;
  const thumb = watch.thumbnailUrl ?? watch.imageUrl;
  const name = `${watch.brand} ${watch.model}`.trim();

  return (
    <section className={styles.wearing} aria-label="Last on the wrist">
      {thumb ? (
        <Image
          src={thumb}
          alt=""
          aria-label={name}
          width={28}
          height={28}
          className={styles.thumb}
        />
      ) : (
        <span className={styles.fallback} aria-label={name} role="img">
          {watch.brand.charAt(0).toUpperCase()}
        </span>
      )}
      <span className={styles.label}>Last on the wrist</span>
      <Link
        href={`/post/${encodeURIComponent(watch.id)}?ref=${encodeURIComponent('/')}`}
        className={styles.name}
      >
        {name}
      </Link>
      <Link href="/wearage" className={styles.more}>
        wearage &rarr;
      </Link>
    </section>
  );
}
