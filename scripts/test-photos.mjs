#!/usr/bin/env node
// Photo upload regression test (docs/transaction-photos.md) against a running server.
//
//   npx next dev -p 3100                       # in another terminal
//   node scripts/test-photos.mjs [baseUrl] [fixtureDir]
//
// Uploads what phones actually send — JPEG with an EXIF (APP1) header, JFIF JPEG,
// PNG screenshot, HEIC/HEIF (several ftyp brands), a 3 MB photo (over nginx's 1 MB
// default) — through /api/mobile/upload, checks the returned path is one the sync
// schema and the app accept, and that refusals come back as Indonesian 400s.
// With [fixtureDir], every file in it is uploaded too (e.g. real camera/gallery output).
// Throwaway users mobile-test-photo-*@example.test and their files are removed at the end.
import { readdir, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createJiti } from "jiti";

const BASE = process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:3100";
const FIXTURES = process.argv[3];
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const jiti = createJiti(import.meta.url, { alias: { "@": join(root, "src") } });

let passed = 0;
let failed = 0;
function check(name, cond, detail) {
  if (cond) {
    passed++;
    console.log(`  ok   ${name}`);
  } else {
    failed++;
    console.log(`  FAIL ${name}${detail !== undefined ? ` — ${JSON.stringify(detail)}` : ""}`);
  }
}

// Same pattern as the mobile app (mobile/lib/data/models/wire.dart `uploadPathRe`).
const MOBILE_UPLOAD_RE = /^\/uploads\/[A-Za-z0-9-]+\.[a-z]+$/;

const pad = (head, size) => {
  const b = Buffer.alloc(size, 0x20);
  Buffer.from(head).copy(b);
  return b;
};
const jpegExif = (size = 4000) => pad([0xff, 0xd8, 0xff, 0xe1, 0x1d, 0x5d, ...Buffer.from("Exif\0\0MM\0*")], size);
const jpegJfif = (size = 4000) => pad([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, ...Buffer.from("JFIF\0")], size);
const png = (size = 4000) => pad([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, ...Buffer.from("IHDR")], size);
const isobmff = (brand, size = 4000) => pad([0, 0, 0, 0x18, ...Buffer.from("ftyp"), ...Buffer.from(brand), 0, 0, 0, 0], size);

/** Every url this run uploaded (removed at the end). */
const uploaded = [];

async function upload(token, bytes, name, type = "application/octet-stream") {
  const form = new FormData();
  form.append("file", new File([bytes], name, { type }));
  const res = await fetch(`${BASE}/api/mobile/upload`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}` },
    body: form,
  });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    // not JSON
  }
  if (json?.url) uploaded.push(json.url);
  return { status: res.status, json };
}

const prefix = `mobile-test-photo-${Date.now()}`;
try {
  // Pure sniffing: what Android / iOS cameras and galleries produce.
  const { sniffImageType } = await jiti.import(join(root, "src/lib/photos.ts"));
  console.log("sniffImageType");
  check("JPEG with EXIF APP1 first → jpg", sniffImageType(jpegExif()) === "jpg");
  check("JFIF JPEG → jpg", sniffImageType(jpegJfif()) === "jpg");
  check("PNG → png", sniffImageType(png()) === "png");
  for (const b of ["heic", "heix", "hevc", "heim", "heis"]) check(`ftyp ${b} → heic`, sniffImageType(isobmff(b)) === "heic");
  for (const b of ["mif1", "msf1"]) check(`ftyp ${b} → heif`, sniffImageType(isobmff(b)) === "heif");
  check("AVIF is not accepted", sniffImageType(isobmff("avif")) === null);
  check("text is not an image", sniffImageType(Buffer.from("hello world")) === null);

  console.log("upload endpoint");
  const reg = await fetch(`${BASE}/api/mobile/auth/register`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: `${prefix}@example.test`, password: "rahasia123", name: "Photo QA" }),
  });
  const { token } = await reg.json();
  check("register throwaway user", typeof token === "string");

  const cases = [
    ["exif.jpg", jpegExif(), "jpg"],
    ["IMG_20260925.jpeg", jpegJfif(), "jpg"],
    ["scaled_1000001234.png", png(), "png"],
    ["camera.heic", isobmff("heic"), "heic"],
    ["gallery.heif", isobmff("mif1"), "heif"],
    // Mislabelled by the client (image_picker keeps the source name): bytes decide.
    ["scaled_photo.heic", jpegExif(), "jpg"],
    ["3mb.jpg", jpegExif(3 * 1024 * 1024), "jpg"],
  ];
  for (const [name, bytes, ext] of cases) {
    const r = await upload(token, bytes, name, "image/jpeg");
    const url = r.json?.url ?? "";
    check(
      `${name} (${Math.round(bytes.length / 1024)} KB) → .${ext}, accepted by the app and on disk`,
      r.status === 200 && url.endsWith(`.${ext}`) && MOBILE_UPLOAD_RE.test(url) && existsSync(join(root, "public", url)),
      r,
    );
  }

  let r = await upload(token, jpegExif(6 * 1024 * 1024), "big.jpg");
  check("6 MB photo → 400 in Indonesian", r.status === 400 && /terlalu besar/.test(r.json?.error ?? ""), r);
  r = await upload(token, Buffer.from("<svg xmlns='http://www.w3.org/2000/svg'/>"), "x.svg", "image/svg+xml");
  check("SVG → 400 in Indonesian", r.status === 400 && /bukan gambar|Unggah gambar/.test(r.json?.error ?? ""), r);

  if (FIXTURES) {
    console.log(`fixtures in ${FIXTURES}`);
    for (const f of (await readdir(FIXTURES)).filter((n) => /\.(jpe?g|png|webp|gif|hei[cf])$/i.test(n))) {
      const bytes = await readFile(join(FIXTURES, f));
      if (bytes.length > 5 * 1024 * 1024) continue; // the app compresses first
      const r2 = await upload(token, bytes, f);
      check(`${f} (${Math.round(bytes.length / 1024)} KB)`, r2.status === 200 && MOBILE_UPLOAD_RE.test(r2.json?.url ?? ""), r2);
    }
  }
} finally {
  // Deletes the users, then this run's files (no row references them).
  const { PrismaClient } = await import("@prisma/client");
  const prisma = new PrismaClient();
  try {
    await prisma.user.deleteMany({ where: { email: { startsWith: prefix, endsWith: "@example.test" } } });
  } finally {
    await prisma.$disconnect();
  }
  const { deleteUnreferencedUploads } = await jiti.import(join(root, "src/lib/uploads.ts"));
  await deleteUnreferencedUploads(uploaded);
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
