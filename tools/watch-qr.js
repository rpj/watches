#!/usr/bin/env node
/**
 * watch-qr.js — generate a scannable QR code framed as a wristwatch.
 *
 * The scannable core stays a normal square QR (error-correction level H, so
 * ~30% of the code can be obscured and it still reads). Everything watch-shaped
 * — the round case, bezel, hour markers, lugs, strap, crown — is drawn *around*
 * that square so the composition reads as a watch while the code scans reliably.
 *
 * Usage:
 *   node watch-qr.js [options]
 *
 * Options:
 *   --url URL            Link the QR points to        (default https://ryanswatches.com)
 *   --out FILE           Output path. Extension picks the format: .svg -> SVG,
 *                        anything else (e.g. .png) -> PNG    (default watch-qr.png)
 *   --theme light|dark                                        (default light)
 *   --orientation vertical|horizontal                        (default vertical)
 *   --align left|center|right   Horizontal only: where the watch sits on the
 *                        card; straps run off the card edges (default center)
 *   --strap leather|rubber|nato|mesh|bracelet                (default leather)
 *   --title TEXT         Branding stamped on the strap  (default "RYAN'S WATCHES")
 *   --caption TEXT       Sub-line (default = the URL host)
 *   --width PX           PNG raster width in px                (default 1200)
 *   --no-verify          Skip the built-in scannability check (jsQR)
 */

const fs = require('fs');
const path = require('path');
const QRCode = require('qrcode');

// sharp/jsqr live in this package; fall back to the frontend's copy if needed.
function optionalDep(name) {
  try { return require(name); }
  catch { try { return require(path.join(__dirname, '..', 'frontend', 'node_modules', name)); } catch { return null; } }
}
const sharp = optionalDep('sharp');
const jsQR = optionalDep('jsqr');

// ---- args -----------------------------------------------------------------
function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const flag = (name) => process.argv.includes(`--${name}`);

const URL = arg('url', 'https://ryanswatches.com');
const OUT = arg('out', path.join(__dirname, 'watch-qr.png'));
const THEME = arg('theme', 'light');
const ORIENT = arg('orientation', 'vertical');
const ALIGN = arg('align', 'center');
const STRAP = arg('strap', 'leather');
const TITLE = arg('title', "RYAN'S WATCHES");
const CAPTION = arg('caption', URL.replace(/^https?:\/\//, '').replace(/\/$/, ''));
const PNG_WIDTH = parseInt(arg('width', '1200'), 10);
const VERIFY = !flag('no-verify');
const IS_SVG = /\.svg$/i.test(OUT);
const HORIZ = ORIENT === 'horizontal';

// ---- palette (mirrors frontend globals.css) --------------------------------
const themes = {
  light: {
    strap: '#8b6634', strapDark: '#6e4f24', stitch: '#f0e4cc',
    caseOuter: '#d8a468', caseInner: '#8b6634', bezel: '#3a352f',
    dial: '#f7f5f0', ink: '#1a1a1a', marker: '#d8a468', crown: '#c89456',
    titleColor: '#2a1c0e', titleHi: '#e8cfa0', page: '#ffffff',
  },
  dark: {
    strap: '#3a352f', strapDark: '#262320', stitch: '#c89456',
    caseOuter: '#c89456', caseInner: '#6e4f24', bezel: '#0c0c0c',
    dial: '#f0ece5', ink: '#141414', marker: '#d8a468', crown: '#d8a468',
    titleColor: '#f0e4cc', titleHi: '#000000', page: '#0c0c0c',
  },
};
const C = themes[THEME] || themes.light;

// ---- QR matrix -------------------------------------------------------------
const qr = QRCode.create(URL, { errorCorrectionLevel: 'H' });
const N = qr.modules.size;              // e.g. 29
const bits = qr.modules.data;           // row-major Uint8Array, 1 = dark
const dark = (r, c) => r >= 0 && c >= 0 && r < N && c < N && bits[r * N + c];
function inFinder(r, c) {                // 7x7 corner "eyes"
  const zone = (br, bc) => r >= br && r < br + 7 && c >= bc && c < bc + 7;
  return zone(0, 0) || zone(0, N - 7) || zone(N - 7, 0);
}

// ---- geometry --------------------------------------------------------------
const m = 13;                 // px per module
const qrPx = N * m;           // code size in px (no quiet zone)
const rDial = Math.ceil((qrPx / 2) * Math.SQRT2) + 26;  // dial contains the square
const rBezel = rDial + 46;
const rCase = rBezel + 10;
const strapHalf = Math.round(rCase * 0.58);   // half-width of the strap band
const strapTaper = 20;                        // narrowing toward a finished end
const strapEnd = 250;                         // finished-strap length past the case
const crownW = 34;
const OVERLAP = 50;                           // how far the strap tucks under the case

// Canvas + case placement depend on orientation/align.
// Vertical: portrait card, watch centred, finished straps top & bottom.
// Horizontal: landscape "card" — the watch stays upright on one half with its
// straps bleeding off the top & bottom edges, and branding fills the other half.
let W, H, cx, cy;
const SIDE = HORIZ ? (ALIGN === 'right' ? 'right' : 'left') : null;  // horizontal uses left/right
if (!HORIZ) {
  cx = rCase + 46;                                 // room for the crown on the right
  cy = rCase + strapEnd + 10;
  W = cx + rCase + 46 + crownW;
  H = cy + rCase + strapEnd + 10;
} else {
  const vBleed = 96;              // strap visible above/below before the top/bottom cut
  H = 2 * rCase + 2 * vBleed;
  cy = H / 2;
  const OPEN = 640, sidePad = 64;
  if (SIDE === 'right') { W = OPEN + 2 * rCase + crownW + sidePad; cx = OPEN + rCase; }
  else { cx = sidePad + rCase; W = cx + rCase + crownW + OPEN; }
}
const qx = cx - qrPx / 2, qy = cy - qrPx / 2;

// ---- svg helpers -----------------------------------------------------------
const parts = [];
const push = (s) => parts.push(s);
const f = (n) => (+n).toFixed(2);
const rr = (x, y, w, h, rad, fill, extra = '') =>
  `<rect x="${f(x)}" y="${f(y)}" width="${f(w)}" height="${f(h)}" rx="${f(rad)}" fill="${fill}" ${extra}/>`;

// ---- straps ----------------------------------------------------------------
// Each strap is drawn as a canonical band pointing "up" from the case, then
// rotated to the desired direction. Vertical watches get two finished straps
// (up/down); horizontal watches get two cut, full-bleed straps (left/right).
function bandPath(length, finished) {
  const nearY = cy - (rCase - OVERLAP), farY = nearY - length;
  const hn = strapHalf, hf = finished ? strapHalf - strapTaper : strapHalf;
  const xNL = cx - hn, xNR = cx + hn, xFL = cx - hf, xFR = cx + hf;
  if (finished) {
    const r = Math.min(30, hf);
    return `M${f(xNL)},${f(nearY)} L${f(xFL)},${f(farY + r)} Q${f(xFL)},${f(farY)} ${f(xFL + r)},${f(farY)} `
      + `L${f(xFR - r)},${f(farY)} Q${f(xFR)},${f(farY)} ${f(xFR)},${f(farY + r)} L${f(xNR)},${f(nearY)} Z`;
  }
  return `M${f(xNL)},${f(nearY)} L${f(xFL)},${f(farY)} L${f(xFR)},${f(farY)} L${f(xNR)},${f(nearY)} Z`;
}

function drawStrap(idx, dirDeg, length, finished) {
  const nearY = cy - (rCase - OVERLAP), farY = nearY - length;
  const clip = `sc${idx}`;
  const g = [];
  g.push(`<clipPath id="${clip}"><path d="${bandPath(length, finished)}"/></clipPath>`);

  if (STRAP === 'mesh' || STRAP === 'bracelet') {
    g.push(`<path d="${bandPath(length, finished)}" fill="url(#steelGrad)"/>`);
    g.push(`<g clip-path="url(#${clip})">`);
    if (STRAP === 'mesh') {
      g.push(rr(cx - strapHalf, farY, strapHalf * 2, length, 0, 'url(#meshPat)'));
    } else {                                   // bracelet: rows of three links
      const linkH = 32, gap = 4;
      for (let y = farY; y < nearY; y += linkH) {
        const h = Math.min(linkH - gap, nearY - y);
        g.push(rr(cx - strapHalf + 4, y, strapHalf * 0.62, h, 6, 'url(#steelGrad)', `stroke="#8a8f98" stroke-width="1"`));
        g.push(rr(cx - strapHalf * 0.34, y, strapHalf * 0.68, h, 6, 'url(#steelGrad)', `stroke="#8a8f98" stroke-width="1"`));
        g.push(rr(cx + strapHalf * 0.34 - 4, y, strapHalf * 0.62, h, 6, 'url(#steelGrad)', `stroke="#8a8f98" stroke-width="1"`));
      }
    }
    // brushed-steel edge highlights
    g.push(`<line x1="${f(cx - strapHalf + 3)}" y1="${f(farY)}" x2="${f(cx - strapHalf + 3)}" y2="${f(nearY)}" stroke="#ffffff" stroke-width="2" opacity="0.5"/>`);
    g.push(`<line x1="${f(cx + strapHalf - 3)}" y1="${f(farY)}" x2="${f(cx + strapHalf - 3)}" y2="${f(nearY)}" stroke="#000000" stroke-width="2" opacity="0.2"/>`);
    g.push(`</g>`);
  } else if (STRAP === 'nato') {
    g.push(`<path d="${bandPath(length, finished)}" fill="${C.strap}"/>`);
    g.push(`<g clip-path="url(#${clip})">`);
    // lengthwise stripes
    const stripe = (offx, w, col) => g.push(rr(cx + offx - w / 2, farY, w, length, 0, col));
    stripe(0, strapHalf * 0.5, C.strapDark);
    stripe(0, strapHalf * 0.18, C.stitch);
    // two steel keepers crossing the band
    for (const ky of [nearY - 34, nearY - 96]) {
      g.push(rr(cx - strapHalf - 4, ky, strapHalf * 2 + 8, 22, 5, 'url(#steelGrad)', `stroke="#8a8f98" stroke-width="1"`));
    }
    g.push(`</g>`);
  } else if (STRAP === 'rubber') {
    g.push(`<path d="${bandPath(length, finished)}" fill="${C.strapDark}"/>`);
    g.push(`<g clip-path="url(#${clip})">`);
    // matte with edge grooves + a centre channel
    for (const ox of [-strapHalf + 12, strapHalf - 12, 0]) {
      g.push(`<line x1="${f(cx + ox)}" y1="${f(farY + 8)}" x2="${f(cx + ox)}" y2="${f(nearY)}" stroke="#000000" stroke-width="3" opacity="0.22"/>`);
    }
    g.push(`</g>`);
  } else {                                     // leather (default)
    g.push(`<path d="${bandPath(length, finished)}" fill="url(#strapGrad)"/>`);
    g.push(`<g clip-path="url(#${clip})">`);
    for (const ox of [-(strapHalf - 22), strapHalf - 22]) {
      g.push(`<line x1="${f(cx + ox)}" y1="${f(farY + 14)}" x2="${f(cx + ox)}" y2="${f(nearY)}" stroke="${C.stitch}" stroke-width="4" stroke-dasharray="14 10" stroke-linecap="round" opacity="0.9"/>`);
    }
    g.push(`</g>`);
  }
  push(`<g transform="rotate(${dirDeg} ${f(cx)} ${f(cy)})">${g.join('')}</g>`);
}

// ---- build -----------------------------------------------------------------
push(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">`);
push(`<defs>
  <radialGradient id="caseGrad" cx="38%" cy="32%" r="80%">
    <stop offset="0%" stop-color="${C.caseOuter}"/><stop offset="60%" stop-color="${C.caseInner}"/><stop offset="100%" stop-color="${C.strapDark}"/>
  </radialGradient>
  <linearGradient id="strapGrad" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0%" stop-color="${C.strapDark}"/><stop offset="50%" stop-color="${C.strap}"/><stop offset="100%" stop-color="${C.strapDark}"/>
  </linearGradient>
  <linearGradient id="steelGrad" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0%" stop-color="#e8e8ec"/><stop offset="28%" stop-color="#b9bcc4"/><stop offset="52%" stop-color="#f2f2f5"/><stop offset="76%" stop-color="#9aa0aa"/><stop offset="100%" stop-color="#cfd3da"/>
  </linearGradient>
  <pattern id="meshPat" width="9" height="9" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
    <line x1="0" y1="0" x2="0" y2="9" stroke="#000000" stroke-width="2" opacity="0.16"/>
    <line x1="0" y1="0" x2="9" y2="0" stroke="#ffffff" stroke-width="2" opacity="0.28"/>
  </pattern>
</defs>`);

push(rr(0, 0, W, H, 0, C.page));

// straps (behind the case) — always run vertically (watch stays upright)
if (!HORIZ) {
  drawStrap(0, 0, strapEnd, true);       // up, finished end
  drawStrap(1, 180, strapEnd, true);     // down, finished end
} else {
  const lenUp = cy - (rCase - OVERLAP) + 40;         // bleed off the top edge
  const lenDown = (H - cy) - (rCase - OVERLAP) + 40; // bleed off the bottom edge
  drawStrap(0, 0, lenUp, false);
  drawStrap(1, 180, lenDown, false);
}

// crown at 3 o'clock
push(rr(cx + rCase - 4, cy - 26, crownW, 52, 10, 'url(#caseGrad)', `stroke="${C.bezel}" stroke-width="2"`));
for (let i = 0; i < 5; i++) {
  const gx = cx + rCase - 2 + i * (crownW / 5);
  push(`<line x1="${f(gx)}" y1="${f(cy - 22)}" x2="${f(gx)}" y2="${f(cy + 22)}" stroke="${C.bezel}" stroke-width="1.5" opacity="0.5"/>`);
}

// case + bezel + dial
push(`<circle cx="${f(cx)}" cy="${f(cy)}" r="${f(rCase)}" fill="url(#caseGrad)"/>`);
push(`<circle cx="${f(cx)}" cy="${f(cy)}" r="${f(rBezel)}" fill="${C.bezel}"/>`);
push(`<circle cx="${f(cx)}" cy="${f(cy)}" r="${f(rDial)}" fill="${C.dial}"/>`);

// hour markers on the bezel ring
for (let i = 0; i < 12; i++) {
  const a = (i / 12) * 2 * Math.PI - Math.PI / 2;
  const rMid = (rDial + rBezel) / 2, big = i % 3 === 0;
  const len = big ? 20 : 12, wdt = big ? 7 : 4;
  const x = cx + Math.cos(a) * rMid, y = cy + Math.sin(a) * rMid;
  push(`<g transform="translate(${f(x)} ${f(y)}) rotate(${f(a * 180 / Math.PI + 90)})">${rr(-wdt / 2, -len / 2, wdt, len, wdt / 2, C.marker)}</g>`);
}

// QR data modules as rounded squares (finder eyes drawn separately)
const rad = m * 0.32, side = m - 2 * rad;
let d = '';
for (let r = 0; r < N; r++) {
  for (let c = 0; c < N; c++) {
    if (!dark(r, c) || inFinder(r, c)) continue;
    const x = qx + c * m, y = qy + r * m;
    d += `M${f(x + rad)},${f(y)} h${f(side)} a${f(rad)},${f(rad)} 0 0 1 ${f(rad)},${f(rad)} v${f(side)} a${f(rad)},${f(rad)} 0 0 1 ${f(-rad)},${f(rad)} h${f(-side)} a${f(rad)},${f(rad)} 0 0 1 ${f(-rad)},${f(-rad)} v${f(-side)} a${f(rad)},${f(rad)} 0 0 1 ${f(rad)},${f(-rad)} z `;
  }
}
push(`<path d="${d}" fill="${C.ink}"/>`);

// finder eyes
function eye(br, bc) {
  const x = qx + bc * m, y = qy + br * m, s = 7 * m;
  push(rr(x, y, s, s, m * 1.1, C.ink));
  push(rr(x + m, y + m, 5 * m, 5 * m, m * 0.9, C.dial));
  push(rr(x + 2 * m, y + 2 * m, 3 * m, 3 * m, m * 0.7, C.ink));
}
eye(0, 0); eye(0, N - 7); eye(N - 7, 0);

// branding — stamped/debossed into the strap (dark glyph + soft highlight)
function stamped(text, x, y, size, spacing, anchor = 'middle') {
  const font = `font-family="Georgia, 'Times New Roman', serif" font-size="${size}" letter-spacing="${spacing}" font-weight="700" text-anchor="${anchor}"`;
  push(`<text x="${f(x)}" y="${f(y + 1.5)}" ${font} fill="${C.titleHi}" opacity="0.35">${text}</text>`);
  push(`<text x="${f(x)}" y="${f(y)}" ${font} fill="${C.titleColor}">${text}</text>`);
}
if (!HORIZ) {
  stamped(TITLE, cx, cy - rCase - strapEnd + 120, 34, 6);
  stamped(CAPTION, cx, cy + rCase + strapEnd - 96, 26, 3);
} else {
  // branding fills the open half of the card
  const ox = SIDE === 'left' ? (cx + rCase + crownW + W) / 2 : (cx - rCase) / 2;
  stamped(TITLE, ox, cy - 10, 42, 5);
  stamped(CAPTION, ox, cy + 42, 28, 3);
}

push(`</svg>`);
const svg = parts.join('\n');

// ---- output ----------------------------------------------------------------
async function main() {
  if (VERIFY && jsQR && sharp) {
    const { data, info } = await sharp(Buffer.from(svg)).resize({ width: 420 }).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    const res = jsQR(new Uint8ClampedArray(data), info.width, info.height);
    if (res && res.data === URL) console.log(`✓ scannable (decoded ${res.data})`);
    else console.warn(`⚠ scannability check ${res ? 'decoded a different value: ' + res.data : 'FAILED'} — inspect before printing`);
  }
  if (IS_SVG) {
    fs.writeFileSync(OUT, svg);
  } else {
    if (!sharp) { console.error('sharp not available — write to a .svg path or install sharp'); process.exit(1); }
    await sharp(Buffer.from(svg)).resize({ width: PNG_WIDTH }).png().toFile(OUT);
  }
  console.log(`Wrote ${OUT}  (${W}x${H}, ${ORIENT}${HORIZ ? '/' + ALIGN : ''}, strap=${STRAP}, theme=${THEME}, QR ${N}x${N} @ ECC-H)`);
}
main().catch((e) => { console.error(e); process.exit(1); });
