import React, { useEffect, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { format, isToday } from 'date-fns';
import type { WearingNow as WearingNowData } from '../lib/wear';
import styles from '../styles/WearingNow.module.css';

interface WearingNowProps {
  wearing: WearingNowData | null;
}

export default function WearingNow({ wearing }: WearingNowProps) {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  if (!wearing) {
    return null;
  }

  const { watch, event } = wearing;
  // `watch` is null for the reserved "nothing on" entry: a bare wrist.
  const thumb = watch ? watch.thumbnailUrl ?? watch.imageUrl : null;
  const name = watch ? `${watch.brand} ${watch.model}`.trim() : 'Nothing right now';

  let since = '';
  if (mounted) {
    const worn = new Date(event.wornAt);
    if (!Number.isNaN(worn.getTime())) {
      since = isToday(worn) ? format(worn, 'h:mm a') : format(worn, 'MMM d');
    }
  }

  return (
    <section className={styles.wearing} aria-label="Currently wearing">
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
          {watch ? watch.brand.charAt(0).toUpperCase() : '–'}
        </span>
      )}
      <span className={styles.label}>On the wrist</span>
      {watch ? (
        <Link
          href={`/post/${encodeURIComponent(watch.id)}?ref=${encodeURIComponent('/')}`}
          className={styles.name}
        >
          {name}
        </Link>
      ) : (
        <span className={styles.name}>{name}</span>
      )}
      {since && <span className={styles.since}>&middot; since {since}</span>}
      <Link href="/wearage" className={styles.more}>
        wearage &rarr;
      </Link>
    </section>
  );
}
