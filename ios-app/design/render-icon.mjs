#!/usr/bin/env node
/**
 * Wrist app icon: art-deco variants built as SVG and rasterised with the
 * frontend's `sharp` (no extra dependencies).
 *
 *   node render-icon.mjs            # writes icon-{a,b,c}.svg + .png (1024) + -preview.png (256)
 *   node render-icon.mjs --install b   # copies variant b into the asset catalog as AppIcon.png
 *
 * Palette is the site's dark theme: near-black field, bronze accent, muted
 * hairlines. No text, no gradients; iOS masks the corners itself.
 */
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { writeFileSync, readFileSync } from 'node:fs';

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(here, '..', '..', 'frontend', 'package.json'));
const sharp = require('sharp');

const BG = '#0c0c0c';
const BRONZE = '#c89456';
const BRONZE_DIM = '#8b6634';
const MUTED = '#8a857d';
const INK = '#f0ece5';

const S = 1024;
const C = S / 2;

/** Point at polar (deg clockwise from 12 o'clock, radius) around (cx, cy). */
function polar(cx, cy, deg, r) {
  const rad = (deg * Math.PI) / 180;
  return [cx + Math.sin(rad) * r, cy - Math.cos(rad) * r];
}
const f = n => n.toFixed(1);

/** Shared dial: ring, inner hairline, 12 indices, 10:08 hands, centre pip. */
function dial(cx, cy, r, { ring = 12, hands = true } = {}) {
  let out = '';
  out += `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${BG}" stroke="${BRONZE}" stroke-width="${ring}"/>`;
  out += `<circle cx="${cx}" cy="${cy}" r="${r - 38}" fill="none" stroke="${MUTED}" stroke-width="2" opacity="0.7"/>`;
  for (let i = 0; i < 12; i++) {
    const major = i % 3 === 0;
    const [x1, y1] = polar(cx, cy, i * 30, r - (major ? 80 : 68));
    const [x2, y2] = polar(cx, cy, i * 30, r - 48);
    out += `<line x1="${f(x1)}" y1="${f(y1)}" x2="${f(x2)}" y2="${f(y2)}" stroke="${major ? BRONZE : MUTED}" stroke-width="${major ? 9 : 5}" stroke-linecap="round"/>`;
  }
  if (hands) {
    // 10:08 — the classic catalogue pose.
    const [hx, hy] = polar(cx, cy, 300, r * 0.48);
    const [mx, my] = polar(cx, cy, 48, r * 0.72);
    out += `<line x1="${cx}" y1="${cy}" x2="${f(hx)}" y2="${f(hy)}" stroke="${BRONZE}" stroke-width="16" stroke-linecap="round"/>`;
    out += `<line x1="${cx}" y1="${cy}" x2="${f(mx)}" y2="${f(my)}" stroke="${BRONZE}" stroke-width="11" stroke-linecap="round"/>`;
    out += `<circle cx="${cx}" cy="${cy}" r="15" fill="${BG}" stroke="${BRONZE}" stroke-width="7"/>`;
  }
  return out;
}

/** Stepped crown at 3 o'clock. */
function crown(cx, cy, r) {
  const x = cx + r + 6;
  return (
    `<rect x="${x}" y="${cy - 30}" width="34" height="60" rx="4" fill="${BRONZE}"/>` +
    `<rect x="${x + 34}" y="${cy - 18}" width="16" height="36" rx="3" fill="${BRONZE_DIM}"/>`
  );
}

function svg(body) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${S} ${S}">` +
    `<rect width="${S}" height="${S}" fill="${BG}"/>${body}</svg>`;
}

// --- Variant A: sunburst behind the dial -----------------------------------
function variantA() {
  const cy = 548;
  const r = 282;
  let rays = '';
  for (let deg = -82; deg <= 82; deg += 10.25) {
    const long = Math.round((deg + 82) / 10.25) % 2 === 0;
    const [x1, y1] = polar(C, cy, deg, r + 34);
    const [x2, y2] = polar(C, cy, deg, r + (long ? 178 : 118));
    rays += `<line x1="${f(x1)}" y1="${f(y1)}" x2="${f(x2)}" y2="${f(y2)}" stroke="${BRONZE_DIM}" stroke-width="6" stroke-linecap="round"/>`;
  }
  // Two stepped baseline bars under the dial: the deco plinth.
  const plinth =
    `<rect x="${C - 250}" y="${cy + r + 44}" width="500" height="8" fill="${BRONZE_DIM}"/>` +
    `<rect x="${C - 170}" y="${cy + r + 70}" width="340" height="6" fill="${MUTED}" opacity="0.8"/>`;
  return svg(rays + plinth + dial(C, cy, r) + crown(C, cy, r));
}

// --- Variant B: stepped frame with fluting ----------------------------------
function variantB() {
  const cy = C;
  const r = 262;
  // Stepped (ziggurat) frame: an octagon-ish outline with notched corners.
  const o = 118, n = 56; // outer inset, notch size
  const frame = [
    [o + n, o], [S - o - n, o], [S - o - n, o + n / 2], [S - o - n / 2, o + n / 2], [S - o - n / 2, o + n], [S - o, o + n],
    [S - o, S - o - n], [S - o - n / 2, S - o - n], [S - o - n / 2, S - o - n / 2], [S - o - n, S - o - n / 2], [S - o - n, S - o],
    [o + n, S - o], [o + n, S - o - n / 2], [o + n / 2, S - o - n / 2], [o + n / 2, S - o - n], [o, S - o - n],
    [o, o + n], [o + n / 2, o + n], [o + n / 2, o + n / 2], [o + n, o + n / 2],
  ].map(([x, y]) => `${x},${y}`).join(' ');
  const outline = `<polygon points="${frame}" fill="none" stroke="${BRONZE_DIM}" stroke-width="6" stroke-linejoin="miter"/>`;
  // Fluting: vertical hairlines either side of the dial.
  let flutes = '';
  for (const dx of [-412, -386, -360, 360, 386, 412]) {
    flutes += `<line x1="${C + dx}" y1="${cy - 150}" x2="${C + dx}" y2="${cy + 150}" stroke="${MUTED}" stroke-width="3" opacity="0.8"/>`;
  }
  // Chevron bars top and bottom.
  const bars =
    `<rect x="${C - 120}" y="${o + 40}" width="240" height="7" fill="${BRONZE}"/>` +
    `<rect x="${C - 120}" y="${S - o - 47}" width="240" height="7" fill="${BRONZE}"/>`;
  return svg(outline + flutes + bars + dial(C, cy, r) + crown(C, cy, r));
}

// --- Variant C: rising fan below a floating dial ----------------------------
function variantC() {
  const cy = 470;
  const r = 240;
  const fx = C, fy = 905;
  let fan = '';
  for (let rr = 190; rr <= 560; rr += 62) {
    // Only the part of each arc that is above the dial's lower edge is drawn; the
    // arcs read as a sunrise behind the watch.
    fan += `<path d="M ${fx - rr} ${fy} A ${rr} ${rr} 0 0 1 ${fx + rr} ${fy}" fill="none" stroke="${rr % 124 === 66 ? BRONZE_DIM : MUTED}" stroke-width="${rr % 124 === 66 ? 6 : 3}" opacity="0.85"/>`;
  }
  const horizon = `<rect x="${fx - 560}" y="${fy - 3}" width="1120" height="6" fill="${BRONZE_DIM}"/>`;
  const clip = `<defs><clipPath id="sky"><rect x="0" y="0" width="${S}" height="${fy}"/></clipPath></defs>`;
  return svg(clip + `<g clip-path="url(#sky)">${fan}</g>` + horizon + dial(C, cy, r, { ring: 11 }) + crown(C, cy, r));
}

const variants = { a: variantA, b: variantB, c: variantC };

async function render(key) {
  const body = variants[key]();
  const svgPath = join(here, `icon-${key}.svg`);
  writeFileSync(svgPath, body);
  const png = await sharp(Buffer.from(body), { density: 144 }).resize(S, S).png().toBuffer();
  writeFileSync(join(here, `icon-${key}.png`), png);
  const preview = await sharp(png).resize(256, 256).png().toBuffer();
  writeFileSync(join(here, `icon-${key}-preview.png`), preview);
  return png;
}

const args = process.argv.slice(2);
const installIdx = args.indexOf('--install');
if (installIdx >= 0) {
  const key = args[installIdx + 1];
  if (!variants[key]) {
    console.error(`unknown variant "${key}"; choose one of ${Object.keys(variants).join(', ')}`);
    process.exit(1);
  }
  const png = await render(key);
  const setDir = join(here, '..', 'Wrist', 'Assets.xcassets', 'AppIcon.appiconset');
  writeFileSync(join(setDir, 'AppIcon.png'), png);
  const contentsPath = join(setDir, 'Contents.json');
  const contents = JSON.parse(readFileSync(contentsPath, 'utf8'));
  contents.images = contents.images.map(img => ({ ...img, filename: 'AppIcon.png' }));
  writeFileSync(contentsPath, JSON.stringify(contents, null, 2) + '\n');
  console.log(`installed variant ${key} → ${join(setDir, 'AppIcon.png')}`);
} else {
  for (const key of Object.keys(variants)) {
    await render(key);
    console.log(`rendered icon-${key}.svg / .png / -preview.png`);
  }
}
