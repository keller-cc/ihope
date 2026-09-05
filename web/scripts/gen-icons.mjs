/**
 * Export brand icons as rounded squares (transparent corners).
 * Browser chrome cannot CSS-round favicons — radius must be baked in.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import sharp from 'sharp'
import pngToIco from 'png-to-ico'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const publicDir = path.join(__dirname, '..', 'public')
const src = path.join(publicDir, 'mmexport1571484547096.webp')

/** Apple-ish continuous corner ≈ 22% of side. */
const CORNER_RATIO = 0.22

const meta = await sharp(src).metadata()
const w = meta.width ?? 1080
const h = meta.height ?? 962
const side = Math.min(w, h)
const left = Math.floor((w - side) / 2)
const top = Math.floor((h - side) / 2)

const squareBuf = await sharp(src)
  .extract({ left, top, width: side, height: side })
  .resize(1024, 1024, { fit: 'cover' })
  .sharpen({ sigma: 0.4 })
  .png()
  .toBuffer()

function roundMaskSvg(size) {
  const r = Math.max(1, Math.round(size * CORNER_RATIO))
  return Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}">` +
      `<rect width="${size}" height="${size}" rx="${r}" ry="${r}" fill="#fff"/>` +
      `</svg>`,
  )
}

/** Rounded square PNG with transparent outside. */
async function roundedPng(size) {
  const resized = await sharp(squareBuf).resize(size, size).ensureAlpha().png().toBuffer()
  const mask = await sharp(roundMaskSvg(size)).png().toBuffer()
  return sharp(resized)
    .composite([{ input: mask, blend: 'dest-in' }])
    .png({ compressionLevel: 9 })
    .toBuffer()
}

const writes = [
  ['favicon-16.png', await roundedPng(16)],
  ['favicon-32.png', await roundedPng(32)],
  ['favicon-48.png', await roundedPng(48)],
  ['apple-touch-icon-180.png', await roundedPng(180)],
  ['icon-192.png', await roundedPng(192)],
  ['icon-512.png', await roundedPng(512)],
  ['icon-maskable-512.png', await roundedPng(512)],
]

for (const [name, buf] of writes) {
  await fs.promises.writeFile(path.join(publicDir, name), buf)
  console.log('wrote', name, buf.length)
}

const ico = await pngToIco([
  path.join(publicDir, 'favicon-16.png'),
  path.join(publicDir, 'favicon-32.png'),
  path.join(publicDir, 'favicon-48.png'),
])
await fs.promises.writeFile(path.join(publicDir, 'favicon.ico'), ico)
console.log('wrote favicon.ico', ico.length)
console.log('done')
