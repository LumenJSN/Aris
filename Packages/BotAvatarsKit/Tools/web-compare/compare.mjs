/* Side-by-side stills of the web renderer and the Swift port, with a
   difference metric per pair.

     BOT_AVATARS_UPSTREAM=/path/to/Libraries.dev@bfb396b \
     OUT=/path/to/fabric-compare node compare.mjs [shading] [yaw]

   The web side is the upstream source itself (packages/bot-avatars/src),
   bundled with Bun and drawn in Chrome (Playwright, channel "chrome") at a
   device pixel ratio of 2; the Swift side is the botavatar-still tool,
   built in release. Both draw the rest pose of the same type, size and
   body colour on the same backdrop. The body colour is the Swift port's
   palette colour at the default saturation (shade(color, 0, 0.25)) on
   both sides, so the pair differs by the material, not the palette. */

import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const here = dirname(fileURLToPath(import.meta.url));
const pkg = resolve(here, '../..');
const upstream = process.env.BOT_AVATARS_UPSTREAM;
const out = process.env.OUT;
if (!upstream || !out) {
  console.error('set BOT_AVATARS_UPSTREAM (a Libraries.dev checkout at bfb396b) and OUT (the output folder)');
  process.exit(2);
}
const shading = process.argv[2] ?? 'fabric';
/* the head turned by this many radians (the rest pose's own when 0) */
const YAW = Number(process.argv[3] ?? 0);
const tag = YAW ? `${shading}-yaw${YAW}` : shading;
const SIZE = 96;
const DPR = 2;
const TYPES = ['clover', 'cat', 'cloud', 'blob'];
const SCHEMES = { dark: [17, 17, 19], light: [245, 245, 247] };
/* the Swift port's palette (BotAvatarTypes.swift) */
const PALETTE = { clover: '#35B8FF', cat: '#F4D28B', cloud: '#CFD5E4', blob: '#2FCB7A' };

mkdirSync(out, { recursive: true });
const build = join(out, '.build');
mkdirSync(build, { recursive: true });

/* the web page's script: the upstream renderer, bundled */
const src = join(upstream, 'packages/bot-avatars/src');
const entry = join(build, 'entry.ts');
writeFileSync(
  entry,
  `import { draw, OVERSCAN } from ${JSON.stringify(join(src, 'draw.ts'))};
import { restPose } from ${JSON.stringify(join(src, 'engine.ts'))};
import { SHAPE_PATHS } from ${JSON.stringify(join(src, 'shapes.ts'))};
import { botAvatarPresets } from ${JSON.stringify(join(src, 'presets.ts'))};
import { autoInk, shade } from ${JSON.stringify(join(src, 'color.ts'))};
(window as any).bodyColor = (hex: string) => shade(hex, 0, 0.25);
(window as any).renderAvatar = (o: { type: string; size: number; shading: string; color: string; dpr: number; yaw: number }) => {
  const preset = (botAvatarPresets as any)[o.type];
  const n = Math.round(o.size * OVERSCAN * o.dpr);
  const c = document.createElement('canvas');
  c.width = c.height = n;
  const g = c.getContext('2d')!;
  g.setTransform(o.dpr, 0, 0, o.dpr, 0, 0);
  draw(g, o.size, { ...restPose('default'), yaw: o.yaw }, {
    path: new Path2D((SHAPE_PATHS as any)[o.type]),
    face: preset.face, faceX: preset.faceX, faceY: preset.faceY, faceScale: preset.faceScale,
    color: o.color, ink: autoInk(o.color), shading: o.shading as any,
    typeKey: o.type, still: true, dpr: o.dpr,
  });
  return c.toDataURL('image/png');
};
`
);
const bundle = join(build, 'page.js');
execFileSync('bun', ['build', entry, '--outfile', bundle, '--target', 'browser'], { stdio: 'inherit' });

/* the Swift side's tool */
execFileSync('swift', ['build', '-c', 'release', '--product', 'botavatar-still'], { cwd: pkg, stdio: 'inherit' });
const still = join(pkg, '.build/release/botavatar-still');

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ deviceScaleFactor: DPR });
await page.setContent('<!doctype html><html><body style="margin:0"></body></html>');
await page.addScriptTag({ content: readFileSync(bundle, 'utf8') });

/* composite onto a backdrop, compare, lay out side by side — in the page */
await page.addScriptTag({
  content: `
  const load = (url) => new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = no; i.src = url; });
  window.onBackdrop = async (url, rgb) => {
    const img = await load(url);
    const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
    const g = c.getContext('2d'); g.fillStyle = 'rgb(' + rgb.join(',') + ')'; g.fillRect(0, 0, c.width, c.height); g.drawImage(img, 0, 0);
    return c.toDataURL('image/png');
  };
  window.compare = async (webUrl, swiftUrl, rgb, label) => {
    const [a, b] = await Promise.all([load(webUrl), load(swiftUrl)]);
    const w = a.width, h = a.height;
    const px = (img) => { const c = document.createElement('canvas'); c.width = w; c.height = h; const g = c.getContext('2d'); g.drawImage(img, 0, 0); return g.getImageData(0, 0, w, h).data; };
    const A = px(a), B = px(b);
    let n = 0, nb = 0; const sum = [0, 0, 0], sumB = [0, 0, 0];
    const diff = new ImageData(w, h);
    for (let i = 0; i < w * h * 4; i += 4) {
      let body = false;
      for (let ch = 0; ch < 3; ch++) {
        const d = Math.abs(A[i + ch] - B[i + ch]);
        sum[ch] += d;
        if (Math.abs(A[i + ch] - rgb[ch]) > 2 || Math.abs(B[i + ch] - rgb[ch]) > 2) body = true;
        diff.data[i + ch] = Math.min(255, d * 4);
      }
      diff.data[i + 3] = 255;
      n++;
      if (body) { nb++; for (let ch = 0; ch < 3; ch++) sumB[ch] += Math.abs(A[i + ch] - B[i + ch]); }
    }
    const mad = sum.map((s) => s / n), madBody = sumB.map((s) => s / Math.max(1, nb));
    const pad = 28, c = document.createElement('canvas'); c.width = 3 * w; c.height = h + pad;
    const g = c.getContext('2d');
    g.fillStyle = 'rgb(' + rgb.join(',') + ')'; g.fillRect(0, 0, c.width, c.height);
    g.drawImage(a, 0, pad); g.drawImage(b, w, pad);
    const d = document.createElement('canvas'); d.width = w; d.height = h; d.getContext('2d').putImageData(diff, 0, 0);
    g.drawImage(d, 2 * w, pad);
    g.fillStyle = rgb[0] < 128 ? '#ddd' : '#222'; g.font = '13px -apple-system, Helvetica, sans-serif';
    g.fillText('web  ' + label, 6, 18); g.fillText('swift', w + 6, 18); g.fillText('|diff| x4', 2 * w + 6, 18);
    return { mad, madBody, bodyPixels: nb, sideBySide: c.toDataURL('image/png') };
  };`,
});

const png = (url) => Buffer.from(url.split(',')[1], 'base64');
const rows = [];
for (const type of TYPES) {
  const color = await page.evaluate((hex) => window.bodyColor(hex), PALETTE[type]);
  const raw = await page.evaluate((o) => window.renderAvatar(o), { type, size: SIZE, shading, color, dpr: DPR, yaw: YAW });
  for (const [scheme, rgb] of Object.entries(SCHEMES)) {
    const web = await page.evaluate(([u, c]) => window.onBackdrop(u, c), [raw, rgb]);
    const webPath = join(out, `web-${tag}-${type}-${scheme}.png`);
    writeFileSync(webPath, png(web));
    const swiftPath = join(out, `swift-${tag}-${type}-${scheme}.png`);
    execFileSync(still, [type, String(SIZE), shading, scheme, swiftPath, color, String(YAW)]);
    const swift = 'data:image/png;base64,' + readFileSync(swiftPath).toString('base64');
    const r = await page.evaluate(([a, b, c, l]) => window.compare(a, b, c, l), [web, swift, rgb, `${type} ${scheme}`]);
    const sidePath = join(out, `side-${tag}-${type}-${scheme}.png`);
    writeFileSync(sidePath, png(r.sideBySide));
    rows.push({ type, scheme, color, mad: r.mad, madBody: r.madBody, bodyPixels: r.bodyPixels, web: webPath, swift: swiftPath, side: sidePath });
    console.log(`${type.padEnd(7)} ${scheme.padEnd(5)}  MAD r/g/b ${r.mad.map((v) => v.toFixed(2)).join(' / ')}   on the avatar ${r.madBody.map((v) => v.toFixed(2)).join(' / ')}  (${r.bodyPixels} px)`);
  }
}
await browser.close();
writeFileSync(join(out, `metrics-${tag}.json`), JSON.stringify({ shading, yaw: YAW, size: SIZE, dpr: DPR, rows }, null, 2));
