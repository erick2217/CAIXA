import sharp from "sharp";
import { mkdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";

const publicDir = resolve("public");
const sourcePath = resolve(publicDir, "icons/monogram.svg");
const sourceSvg = await readFile(sourcePath, "utf8");
const maskableSvg = sourceSvg
  .replace('r="220"', 'r="176"')
  .replace('stroke-width="8"', 'stroke-width="7"')
  .replace('font-size="176"', 'font-size="140"')
  .replace('letter-spacing="-12"', 'letter-spacing="-10"');

await mkdir(publicDir, { recursive: true });

const outputs = [
  ["pwa-192x192.png", sourceSvg, 192],
  ["pwa-512x512.png", sourceSvg, 512],
  ["pwa-maskable-512x512.png", maskableSvg, 512],
  ["apple-touch-icon.png", sourceSvg, 180],
];

await Promise.all(
  outputs.map(([filename, svg, size]) =>
    sharp(Buffer.from(svg))
      .resize(size, size)
      .png()
      .toFile(resolve(publicDir, filename)),
  ),
);
