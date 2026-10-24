import React from 'react';
import Image from 'next/image';
import Link from 'next/link';
import styles from '../styles/Wearage.module.css';

export interface ShareRow {
  id: string;
  name: string;
  sub?: string;
  /** Where the name links (a watch's post page, a brand's gallery filter). */
  href?: string;
  thumbnailUrl: string | null;
  /** 0..1 */
  share: number;
  wears: number;
}

interface ShareListProps {
  title: string;
  rows: ShareRow[];
  ariaLabel: string;
}

function pct(share: number): string {
  return (share * 100).toFixed(1);
}

export default function ShareList({ title, rows, ariaLabel }: ShareListProps) {
  return (
    <section className={styles.shareList} aria-label={ariaLabel}>
      <h2 className={styles.listTitle}>{title}</h2>
      {rows.length === 0 ? (
        <p className={styles.muted}>Nothing logged in this window yet.</p>
      ) : (
        <table className={styles.table}>
          <thead className={styles.visuallyHidden}>
            <tr>
              <th scope="col">Watch</th>
              <th scope="col">Share</th>
              <th scope="col">Wears</th>
            </tr>
          </thead>
          <tbody>
            {rows.map(row => {
              const p = pct(row.share);
              return (
                <tr
                  key={row.id}
                  className={styles.row}
                  title={`${row.name} · ${p}% · ${row.wears} ${row.wears === 1 ? 'wear' : 'wears'}`}
                >
                  <td className={styles.watchCell}>
                    <div className={styles.watchInner}>
                      {row.thumbnailUrl ? (
                        <Image
                          src={row.thumbnailUrl}
                          alt=""
                          width={40}
                          height={40}
                          className={styles.thumb}
                        />
                      ) : (
                        <span className={styles.fallback} aria-hidden="true">
                          {row.name.charAt(0).toUpperCase()}
                        </span>
                      )}
                      <span className={styles.nameBlock}>
                        {row.href ? (
                          <Link href={row.href} className={`${styles.name} ${styles.nameLink}`}>
                            {row.name}
                          </Link>
                        ) : (
                          <span className={styles.name}>{row.name}</span>
                        )}
                        {row.sub && <span className={styles.sub}>{row.sub}</span>}
                      </span>
                    </div>
                  </td>
                  <td className={styles.barCell}>
                    <div className={styles.barInner}>
                      <div className={styles.track}>
                        <div
                          className={styles.fill}
                          style={{ width: `${row.share * 100}%` }}
                          role="img"
                          aria-label={`${row.name}: ${p}% of wrist time`}
                        />
                      </div>
                      <span className={styles.value}>{p}%</span>
                    </div>
                  </td>
                  <td className={styles.wearsCell}>{row.wears}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </section>
  );
}
