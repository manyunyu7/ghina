#!/usr/bin/env node
// Unit tests for the pure notes module (docs/notes.md), upload type sniffing
// (src/lib/media.ts) and the SSRF-safe link title fetcher (src/lib/link-titles.ts,
// against local HTTP servers). No Next server / DB needed:
//
//   node scripts/test-notes.mjs
import http from "node:http";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createJiti } from "jiti";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const jiti = createJiti(import.meta.url, { alias: { "@": join(root, "src") } });
const n = await jiti.import(join(root, "src/lib/notes.ts"));
const media = await jiti.import(join(root, "src/lib/media.ts"));
const lt = await jiti.import(join(root, "src/lib/link-titles.ts"));

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
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const parse = (v) => n.noteSchema.safeParse(v);
const err = (schema, v) => {
  const r = schema.safeParse(v);
  return r.success ? null : r.error.issues[0].message;
};

console.log("note schema");
{
  const r = parse({});
  check("empty note → defaults", r.success && eq(r.data, {
    title: null, body: "", checklist: [], labels: [], color: null, pinned: false, archived: false, photos: [], audio: [], links: [],
    source: null, linkedTaskId: null, linkedContentId: null, linkedTransactionId: null,
  }), r.data ?? r.error?.issues);
  const full = parse({
    title: "  Belanja\nbulanan  ",
    body: "Beli **beras**\r\nlihat https://toko.id/beras.",
    checklist: [{ id: "a", text: " telur ", done: true }, { id: "b", text: "" }],
    labels: ["l1", "l1", "l2"],
    color: "yellow",
    pinned: true,
    photos: ["/uploads/abc.jpg", "/uploads/abc.jpg"],
    audio: [{ url: "/uploads/v1.m4a", durationSec: 12.5, transcript: "  halo  " }],
    links: [{ url: "https://x.id/a", title: "A" }],
    source: "share",
    linkedTaskId: "",
  });
  check("full note parses", full.success, full.error?.issues);
  const d = full.data;
  check("title one line + trimmed", d.title === "Belanja bulanan", d.title);
  check("body CRLF → LF, not trimmed", d.body === "Beli **beras**\nlihat https://toko.id/beras.", d.body);
  check("checklist text trimmed, done default false", eq(d.checklist, [{ id: "a", text: "telur", done: true }, { id: "b", text: "", done: false }]));
  check("labels deduped", eq(d.labels, ["l1", "l2"]));
  check("photos deduped", eq(d.photos, ["/uploads/abc.jpg"]));
  check("transcript trimmed", d.audio[0].transcript === "halo");
  check("body URL appended to links (trailing '.' dropped)", eq(d.links, [{ url: "https://x.id/a", title: "A" }, { url: "https://toko.id/beras", title: null }]), d.links);
  check("'' link id → null", d.linkedTaskId === null);
  check("unknown source → null", parse({ source: "widget" }).data?.source === null);
  check("control chars dropped from body", parse({ body: "a\u0000b\u0007c\td" }).data?.body === "abc\td");
}
check("title > 200 → error", /Judul terlalu panjang/.test(err(n.noteSchema, { title: "x".repeat(201) })));
check("body 50 000 ok, 50 001 → error", parse({ body: "x".repeat(50000) }).success && !parse({ body: "x".repeat(50001) }).success);
check("color not in palette → error", err(n.noteSchema, { color: "#ff0000" }) === "Warna catatan tidak valid");
check("checklist 200 ok, 201 → error", parse({ checklist: Array.from({ length: 200 }, (_, i) => ({ id: `i${i}`, text: "x" })) }).success &&
  /Maksimal 200/.test(err(n.noteSchema, { checklist: Array.from({ length: 201 }, (_, i) => ({ id: `i${i}`, text: "x" })) })));
check("checklist duplicate ids → error", /duplikat/.test(err(n.noteSchema, { checklist: [{ id: "a", text: "1" }, { id: "a", text: "2" }] })));
check("checklist bad id → error", !parse({ checklist: [{ id: "a b", text: "1" }] }).success);
check("checklist as JSON string → error", !parse({ checklist: "[]" }).success);
check("11 photos → error", /Maksimal 10 foto/.test(err(n.noteSchema, { photos: Array.from({ length: 11 }, (_, i) => `/uploads/p${i}.png`) })));
check("photo must be an image upload path", !parse({ photos: ["/uploads/a.m4a"] }).success && !parse({ photos: ["/uploads/../x.png"] }).success && !parse({ photos: ["https://evil/a.png"] }).success);
check("audio must be an audio upload path", !parse({ audio: [{ url: "/uploads/a.png", durationSec: 1 }] }).success);
check("audio > 10 min (+10 s) → error", !parse({ audio: [{ url: "/uploads/a.m4a", durationSec: 611 }] }).success && parse({ audio: [{ url: "/uploads/a.m4a", durationSec: 605 }] }).success);
check("6 clips → error", !parse({ audio: Array.from({ length: 6 }, (_, i) => ({ url: `/uploads/a${i}.m4a`, durationSec: 1 })) }).success);
check("duplicate clip url kept once", parse({ audio: [{ url: "/uploads/a.m4a", durationSec: 1 }, { url: "/uploads/a.m4a", durationSec: 2 }] }).data?.audio.length === 1);
check("21 links → error", !parse({ links: Array.from({ length: 21 }, (_, i) => ({ url: `https://x.id/${i}` })) }).success);
check("javascript: link → error", !parse({ links: [{ url: "javascript:alert(1)" }] }).success);
check("link with credentials → error", !parse({ links: [{ url: "https://u:p@x.id/" }] }).success);
check("21 labels → error", !parse({ labels: Array.from({ length: 21 }, (_, i) => `l${i}`) }).success);
{
  const body = Array.from({ length: 25 }, (_, i) => `https://b.id/${i}`).join(" ");
  const d = parse({ body, links: [{ url: "https://shared.id/", title: "S" }] }).data;
  check("body URLs capped so links ≤ 20 (sent first)", d.links.length === 20 && d.links[0].url === "https://shared.id/", d.links.length);
}

console.log("URL extraction");
check("markdown link + parens + punctuation", eq(
  n.extractUrls("Lihat [ini](https://a.id/x) dan (https://b.id/y), juga https://c.id/z?q=1&r=2! https://wiki.id/Foo_(bar)."),
  ["https://a.id/x", "https://b.id/y", "https://c.id/z?q=1&r=2", "https://wiki.id/Foo_(bar)"],
), n.extractUrls("Lihat [ini](https://a.id/x) dan (https://b.id/y), juga https://c.id/z?q=1&r=2! https://wiki.id/Foo_(bar)."));
check("dedupe, order of appearance", eq(n.extractUrls("https://a.id https://b.id https://a.id"), ["https://a.id", "https://b.id"]));
check("ignores non-http and bare domains", eq(n.extractUrls("ftp://x.id www.y.id mailto:a@b.id"), []));
check("mergeLinks keeps stored titles", eq(
  n.mergeLinks([{ url: "https://a.id", title: null }], "https://b.id", [{ url: "https://a.id", title: "A" }, { url: "https://b.id", title: "B" }]),
  [{ url: "https://a.id", title: "A" }, { url: "https://b.id", title: "B" }],
));

console.log("labels");
check("label schema: trimmed, default color", eq(n.noteLabelSchema.parse({ name: "  Kerjaan " }), { name: "Kerjaan", color: "#58CC02", pinnedTab: false, sortOrder: 0 }));
check("label name 1–30", !n.noteLabelSchema.safeParse({ name: "  " }).success && !n.noteLabelSchema.safeParse({ name: "x".repeat(31) }).success);
check("label name taken case-insensitively", n.labelNameTaken([{ id: "a", name: "Ide Konten" }], "ide konten") && !n.labelNameTaken([{ id: "a", name: "Ide Konten" }], "IDE KONTEN", "a"));
check("stripLabel removes the id, keeps order", eq(n.stripLabel(["a", "b", "c"], "b"), ["a", "c"]));
check("default label", eq(n.defaultNoteLabel("u1"), { id: "label-ide-konten-u1", name: "Ide Konten", color: "#CE82FF", pinnedTab: true, sortOrder: 0 }) && n.ideaLabelId("u1") === "label-ide-konten-u1");

console.log("stored column parsing (lenient)");
check("bad JSON → []", eq(n.parseChecklist("{oops"), []) && eq(n.parseLinks(null), []) && eq(n.parseLabelIds(""), []));
check("invalid entries dropped", eq(n.parseImageList('["/uploads/a.png","/etc/passwd",5]'), ["/uploads/a.png"]));
check("audio parse", eq(n.parseAudio('[{"url":"/uploads/a.ogg","durationSec":3}]'), [{ url: "/uploads/a.ogg", durationSec: 3, transcript: null }]));

console.log("search / titles / sorting");
{
  const note = { title: "Resep", body: "Nasi **goreng**", checklist: [{ id: "a", text: "Kecap manis", done: false }], audio: [{ url: "/uploads/a.m4a", durationSec: 1, transcript: "pakai telur" }], links: [{ url: "https://x.id", title: "Dapur Umami" }] };
  check("search title/body/checklist/transcript/link title", ["resep", "GORENG", "kecap", "telur", "umami", "nasi kecap"].every((q) => n.noteMatches(note, q)) && !n.noteMatches(note, "sate"));
  check("empty query matches", n.noteMatches(note, "  "));
}
check("firstLine strips markdown", n.firstLine("\n\n## **Ide** [video](https://x.id) baru\nlain") === "Ide video baru");
check("noteDisplayTitle fallbacks", n.noteDisplayTitle({ title: null, body: "", checklist: [{ id: "a", text: "Beli susu", done: false }] }) === "Beli susu" && n.noteDisplayTitle({ title: null, body: "" }) === "Catatan");
check("bodyExcerpt", n.bodyExcerpt("# Judul\n- satu\n- dua\n\n> kutip") === "Judul\nsatu\ndua\nkutip");
{
  const a = { pinned: false, updatedAt: "2026-09-24T10:00:00Z" }, b = { pinned: true, updatedAt: "2026-09-01T00:00:00Z" }, c = { pinned: false, updatedAt: "2026-09-24T11:00:00Z" };
  check("compareNotes: pinned first then newest", eq([a, b, c].sort(n.compareNotes), [b, c, a]));
}

console.log("amount parsing (→ Transaksi)");
const amounts = [
  ["Bayar listrik Rp 250.000", 250000],
  ["Rp1.250.000,50 untuk servis", 1250000.5],
  ["Rp 25rb parkir", 25000],
  ["jajan Rp. 15k", 15000],
  ["beli hp 1,5jt", 1500000],
  ["total 125000", 125000],
  ["total 125.000 tgl 12/09/2026 jam 10:30", 125000],
  ["Rp 10.000 dan Rp 20.000", null],
  ["Rp 10.000 lalu Rp10.000 lagi", 10000],
  ["2 kali 3 buah", null],
  ["tanggal 2026-09-12", null],
  ["beli 3 barang 45000 dan 60000", null],
];
for (const [text, want] of amounts) check(`parseAmount(${JSON.stringify(text)}) = ${want}`, n.parseAmount(text) === want, n.parseAmount(text));

console.log("upload sniffing (image + audio)");
{
  const b = (arr, pad = 16) => Uint8Array.from([...arr, ...Array(pad).fill(0)]);
  const ascii = (s) => [...s].map((c) => c.charCodeAt(0));
  const ftyp = (brand) => b([0, 0, 0, 0x20, ...ascii("ftyp"), ...ascii(brand)]);
  check("m4a (M4A brand)", media.sniffAudioType(ftyp("M4A ")) === "m4a");
  check("mp4 audio (isom/mp42) → m4a", media.sniffAudioType(ftyp("isom")) === "m4a" && media.sniffAudioType(ftyp("mp42")) === "m4a");
  check("HEIC stays an image, not audio", media.sniffMediaType(ftyp("heic"))?.kind === "image" && media.sniffAudioType(ftyp("heic")) === null);
  check("ADTS AAC", media.sniffAudioType(b([0xff, 0xf1, 0x50, 0x80])) === "aac");
  check("MP3 with ID3", media.sniffAudioType(b(ascii("ID3\u0004"))) === "mp3");
  check("MP3 frame sync", media.sniffAudioType(b([0xff, 0xfb, 0x90, 0x64])) === "mp3");
  check("Ogg (Opus)", media.sniffAudioType(b([...ascii("OggS"), 0, 2])) === "ogg");
  check("WebM (EBML)", media.sniffAudioType(b([0x1a, 0x45, 0xdf, 0xa3])) === "webm");
  check("JPEG is not audio", media.sniffAudioType(b([0xff, 0xd8, 0xff, 0xe0])) === null && media.sniffMediaType(b([0xff, 0xd8, 0xff, 0xe0]))?.kind === "image");
  check("text/HTML/SVG rejected", [ascii("hello world"), ascii("<html><script>"), ascii("<svg onload=x>")].every((x) => media.sniffMediaType(b(x)) === null));
  check("RIFF WAVE not accepted", media.sniffMediaType(b([...ascii("RIFF"), 0, 0, 0, 0, ...ascii("WAVE")])) === null);
  check("upload path regexes", media.AUDIO_UPLOAD_RE.test("/uploads/abc-1.m4a") && !media.AUDIO_UPLOAD_RE.test("/uploads/abc.png") && media.IMAGE_UPLOAD_RE.test("/uploads/a.heic") && !media.IMAGE_UPLOAD_RE.test("/uploads/a.svg"));
  check("audio limit 20 MB, image 5 MB", media.MAX_AUDIO_BYTES === 20 * 1024 * 1024 && media.MAX_BYTES_BY_KIND.image === 5 * 1024 * 1024);
}

console.log("link titles: address policy");
for (const ip of ["127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1", "169.254.169.254", "100.64.0.1", "0.0.0.0", "224.0.0.1", "255.255.255.255", "198.18.0.1",
  "::1", "::", "fe80::1", "fc00::1", "fd00:ec2::254", "ff02::1", "::ffff:127.0.0.1", "::ffff:7f00:1", "::ffff:169.254.169.254", "64:ff9b::a9fe:a9fe", "64:ff9b:1::a9fe:a9fe", "64:ff9b:1:ab00:7f::1", "2002:7f00:1::", "2001:db8::1", "::127.0.0.1"]) {
  check(`blocked ${ip}`, !lt.isPublicAddress(ip));
}
for (const ip of ["93.184.216.34", "1.1.1.1", "8.8.8.8", "172.32.0.1", "2606:4700:4700::1111", "::ffff:8.8.8.8", "2a00:1450:4001::200e"]) {
  check(`public ${ip}`, lt.isPublicAddress(ip));
}
check("not an IP → not public", !lt.isPublicAddress("localhost") && !lt.isPublicAddress("1.2.3"));

console.log("link titles: HTML parsing");
check("og:title preferred, entities decoded", lt.extractTitle('<title>T</title><meta content="Kopi &amp; Teh &#x2014; Enak" property="og:title">') === "Kopi & Teh — Enak");
check("<title> fallback, whitespace collapsed", lt.extractTitle("<head><title>\n  Halo\n  Dunia </title></head>") === "Halo Dunia");
check("no title → null", lt.extractTitle("<p>x</p>") === null);
check("long title capped at 300", lt.extractTitle(`<title>${"a".repeat(400)}</title>`).length === 300);

console.log("link titles: fetch (local servers)");
{
  const big = "<html><head>" + "<!-- pad -->".repeat(40000) + "<title>Too far</title></head></html>";
  const server = http.createServer((req, res) => {
    const u = new URL(req.url, "http://x");
    const port = server.address().port;
    switch (u.pathname) {
      case "/ok":
        res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
        return res.end('<html><head><meta property="og:title" content="Halaman OK"><title>fallback</title></head><body>…</body></html>');
      case "/latin1":
        res.writeHead(200, { "content-type": "text/html; charset=iso-8859-1" });
        return res.end(Buffer.from("<title>Caf\xe9</title>", "latin1"));
      case "/json":
        res.writeHead(200, { "content-type": "application/json" });
        return res.end('{"title":"no"}');
      case "/404":
        res.writeHead(404, { "content-type": "text/html" });
        return res.end("<title>Not found</title>");
      case "/slow":
        res.writeHead(200, { "content-type": "text/html" });
        res.write("<html><head>");
        return setTimeout(() => res.end("<title>late</title>"), 1500);
      case "/big":
        res.writeHead(200, { "content-type": "text/html" });
        return res.end(big);
      case "/redir":
        res.writeHead(302, { location: `http://127.0.0.1:${port}/ok` });
        return res.end();
      case "/loop":
        res.writeHead(302, { location: "/loop" });
        return res.end();
      case "/to-metadata":
        res.writeHead(301, { location: "http://169.254.169.254/latest/meta-data/" });
        return res.end();
      case "/to-private-name":
        res.writeHead(302, { location: `http://localhost:${port}/ok` });
        return res.end();
      case "/to-other-loopback":
        res.writeHead(302, { location: `http://127.0.0.2:${port}/ok` });
        return res.end();
      case "/to-ftp":
        res.writeHead(302, { location: "ftp://example.com/" });
        return res.end();
      default:
        res.writeHead(404);
        res.end();
    }
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${server.address().port}`;
  // The test server lives on 127.0.0.1 — only this exact address is let through here.
  const allowTest = { isAllowedAddress: (ip) => ip === "127.0.0.1" || lt.isPublicAddress(ip) };
  const title = async (path, opts = allowTest) => {
    try {
      return { title: await lt.fetchPageTitle(/^[a-z]+:/.test(path) ? path : base + path, opts) };
    } catch (e) {
      return { error: e.message };
    }
  };
  let r = await title("/ok");
  check("fetches og:title", r.title === "Halaman OK", r);
  r = await title("/latin1");
  check("decodes the declared charset", r.title === "Café", r);
  r = await title("/json");
  check("non-HTML → error", !!r.error, r);
  r = await title("/404");
  check("HTTP error → error", /HTTP 404/.test(r.error ?? ""), r);
  const t0 = Date.now();
  r = await title("/slow", { ...allowTest, timeoutMs: 500 });
  check("timeout honoured", !!r.error && Date.now() - t0 < 1400, { ...r, ms: Date.now() - t0 });
  r = await title("/big");
  check("reads at most 256 KB (title beyond → null)", r.title === null && !r.error, r);
  r = await title("/redir");
  check("follows a redirect to an allowed host", r.title === "Halaman OK", r);
  r = await title("/loop");
  check("redirect loop stops after 3 hops", /Too many redirects/.test(r.error ?? ""), r);
  r = await title("/to-metadata");
  check("redirect to 169.254.169.254 → blocked", /Blocked/.test(r.error ?? ""), r);
  r = await title("/to-other-loopback");
  check("redirect to another loopback address → blocked", /Blocked/.test(r.error ?? ""), r);
  r = await title("/to-private-name");
  check("redirect to a name resolving to loopback (localhost) → blocked unless 127.0.0.1", !r.error || /Blocked/.test(r.error), r);
  r = await title("/to-ftp");
  check("redirect to ftp: → error", /http/.test(r.error ?? ""), r);
  // Default policy (production): the local server itself is unreachable.
  for (const u of [`${base}/ok`, `http://localhost:${server.address().port}/ok`, `http://[::1]:${server.address().port}/ok`, "http://169.254.169.254/", "http://10.0.0.1/", "http://0x7f.1/", "http://2130706433/"]) {
    r = await title(u, {});
    check(`default policy blocks ${u}`, !!r.error && r.title === undefined, r);
  }
  r = await title("file:///etc/passwd", {});
  check("file: URL → error", /Only http/.test(r.error ?? ""), r);
  r = await title("http://user:pw@example.com/", {});
  check("credentials in URL → error", /Credentials/.test(r.error ?? ""), r);
  lt.clearLinkTitleCache();
  let hits = 0;
  const counting = { isAllowedAddress: (ip) => { hits++; return allowTest.isAllowedAddress(ip); } };
  const g1 = await lt.getLinkTitle(`${base}/ok`, counting);
  const before = hits;
  const g2 = await lt.getLinkTitle(`${base}/ok`, counting);
  check("getLinkTitle caches per URL", g1 === "Halaman OK" && g2 === g1 && hits === before, { g1, g2, hits, before });
  check("getLinkTitle never throws (blocked → null)", (await lt.getLinkTitle("http://127.0.0.1:1/")) === null);
  server.close();
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
