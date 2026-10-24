import React from 'react';
import Image from 'next/image';
import styles from '../styles/Wearage.module.css';

export interface ShareRow {
  id: string;
  name: string;
  sub?: string;
  thumbnailUrl: string | null;
  /** 0..1 */
  share: number;
  wears: number;
  lastWornAt: string | null;
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
                  title={`${row.name} · ${p}% · ${row.wears} wears · last ${row.lastWornAt ?? 'never'}`}
                >
                  <td className={styles.watchCell}>
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
                      <span className={styles.name}>{row.name}</span>
                      {row.sub && <span className={styles.sub}>{row.sub}</span>}
                    </span>
                  </td>
                  <td className={styles.barCell}>
                    <div className={styles.track}>
                      <div
                        className={styles.fill}
                        style={{ width: `${row.share * 100}%` }}
                        role="img"
                        aria-label={`${row.name}: ${p}% of wrist time`}
                      />
                    </div>
                    <span className={styles.value}>{p}%</span>
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
