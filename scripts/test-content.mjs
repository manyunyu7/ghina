#!/usr/bin/env node
// Unit tests for the pure content-planner module (docs/content.md). No server/DB needed:
//
//   node scripts/test-content.mjs
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createJiti } from "jiti";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const jiti = createJiti(import.meta.url, { alias: { "@": join(root, "src") } });
const c = await jiti.import(join(root, "src/lib/content.ts"));

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
const err = (schema, v) => {
  const r = schema.safeParse(v);
  return r.success ? null : r.error.issues[0].message;
};

console.log("platform registry");
check("8 platforms in order", eq(c.PLATFORM_IDS, ["instagram", "tiktok", "youtube", "x", "threads", "linkedin", "facebook", "other"]));
check("every platform has label/short/color/icon", c.PLATFORMS.every((p) => p.label && p.short && /^#[0-9A-F]{6}$/i.test(p.color) && p.icon));
check("profile URL: @ stripped + encoded", c.platformUrl(c.platformInfo("instagram").profileUrl, "@ghina.id") === "https://www.instagram.com/ghina.id/" &&
  c.platformUrl(c.platformInfo("tiktok").profileUrl, "a b") === "https://www.tiktok.com/@a%20b");
check("other has no URL", c.platformUrl(c.platformInfo("other").profileUrl, "x") === null);
check("unknown platform → other", c.platformInfo("myspace").id === "other");
check("platformLabel / short for other", c.platformLabel({ platform: "other", platformName: "Pinterest" }) === "Pinterest" && c.platformShort({ platform: "other", platformName: "Pinterest" }) === "PINT" && c.platformShort({ platform: "other", platformName: "!!" }) === "LAIN");
check("notification title [IG-TAYANG]", c.postNotificationTitle({ platform: "instagram" }, "Tips hemat") === "[IG-TAYANG] Tips hemat");

console.log("stages");
check("stage order", eq(c.STAGE_IDS, ["ide", "naskah", "produksi", "siap", "terjadwal", "tayang"]));
check("stage XP ide→naskah 3, →tayang 10, ide→tayang sum, backwards 0",
  c.stageXp("ide", "naskah") === 3 && c.stageXp("terjadwal", "tayang") === 10 && c.stageXp("ide", "tayang") === 28 && c.stageXp("tayang", "ide") === 0);
const P = (...s) => s.map((status) => ({ status }));
check("autoStage: no posts → unchanged", c.autoStage("naskah", []) === "naskah");
check("autoStage: a scheduled post → terjadwal", c.autoStage("produksi", P("draft", "scheduled")) === "terjadwal");
check("autoStage: scheduled but user moved further (tayang) → stays", c.autoStage("tayang", P("scheduled")) === "tayang");
check("autoStage: all non-skipped posted → tayang", c.autoStage("terjadwal", P("posted", "skipped", "posted")) === "tayang");
check("autoStage: one posted one draft → unchanged", c.autoStage("siap", P("posted", "draft")) === "siap");
check("autoStage: one posted one scheduled → terjadwal", c.autoStage("siap", P("posted", "scheduled")) === "terjadwal");
check("autoStage: all skipped → unchanged", c.autoStage("siap", P("skipped", "skipped")) === "siap");
check("autoStage: never backwards", c.autoStage("tayang", P("draft")) === "tayang");
check("autoStage: unknown stage treated as ide", c.autoStage("weird", P("scheduled")) === "terjadwal");

console.log("account schema");
{
  const a = c.socialAccountSchema.parse({ platform: "instagram", handle: " @ghina ", platformName: "ignored", targetPerWeek: 3 });
  check("defaults: color per platform, platformName null for built-ins", a.color === "#E1306C" && a.platformName === null && a.handle === "@ghina" && a.targetPerWeek === 3 && a.archived === false && a.sortOrder === 0, a);
  check("targetPerWeek 0 → null", c.socialAccountSchema.parse({ platform: "x", handle: "a", targetPerWeek: 0 }).targetPerWeek === null);
  check("other needs platformName", /nama platform/.test(err(c.socialAccountSchema, { platform: "other", handle: "a" }) ?? ""));
  check("other with name ok", c.socialAccountSchema.parse({ platform: "other", platformName: "Pinterest", handle: "a" }).platformName === "Pinterest");
  check("unknown platform / long handle / bad target → error",
    !c.socialAccountSchema.safeParse({ platform: "myspace", handle: "a" }).success &&
    !c.socialAccountSchema.safeParse({ platform: "x", handle: "a".repeat(61) }).success &&
    !c.socialAccountSchema.safeParse({ platform: "x", handle: "a", targetPerWeek: 51 }).success &&
    !c.socialAccountSchema.safeParse({ platform: "x", handle: "a", targetPerWeek: 1.5 }).success);
  check("custom color kept", c.socialAccountSchema.parse({ platform: "x", handle: "a", color: "#123456" }).color === "#123456");
}

console.log("item schema");
{
  const it = c.contentItemSchema.parse({ title: "  Review\nHP  " });
  check("defaults", eq(it, { title: "Review HP", stage: "ide", format: null, pillar: null, idea: "", noteId: null, checklist: [], photos: [], assetLinks: [], sponsor: null }), it);
  const full = c.contentItemSchema.parse({
    title: "Endorse kopi",
    stage: "produksi",
    format: "reel",
    pillar: " Promo ",
    idea: "# Hook\r\nCoba kopi",
    checklist: [{ id: "c1", text: "Rekam" }],
    photos: ["/uploads/t.jpg"],
    assetLinks: [{ url: "https://drive.google.com/x", label: " Draft " }, { url: "https://canva.com/y" }],
    sponsor: { brand: " Kopi Kita ", amount: 1500000, currency: "idr", due: "2026-10-01" },
  });
  check("full item", full.pillar === "Promo" && full.idea === "# Hook\nCoba kopi" && eq(full.assetLinks, [{ url: "https://drive.google.com/x", label: "Draft" }, { url: "https://canva.com/y", label: null }]), full);
  check("sponsor normalized", eq(full.sponsor, { brand: "Kopi Kita", amount: 1500000, currency: "IDR", due: "2026-10-01", paid: false, transactionId: null }), full.sponsor);
  check("bad stage/format → error", !c.contentItemSchema.safeParse({ title: "a", stage: "done" }).success && !c.contentItemSchema.safeParse({ title: "a", format: "tweet" }).success);
  check("blank title → error", err(c.contentItemSchema, { title: "  " }) === "Judul wajib diisi");
  check("sponsor: negative amount / bad due / bad currency → error",
    !c.contentItemSchema.safeParse({ title: "a", sponsor: { brand: "b", amount: -1 } }).success &&
    !c.contentItemSchema.safeParse({ title: "a", sponsor: { brand: "b", amount: 1, due: "2026-02-30" } }).success &&
    !c.contentItemSchema.safeParse({ title: "a", sponsor: { brand: "b", amount: 1, currency: "RUPIAH" } }).success);
  check("sponsor barter (amount 0) ok", c.contentItemSchema.safeParse({ title: "a", sponsor: { brand: "b", amount: 0 } }).success);
  check("sponsor as JSON string → error", !c.contentItemSchema.safeParse({ title: "a", sponsor: '{"brand":"b"}' }).success);
  check("assetLinks: javascript: → error, 21 → error",
    !c.contentItemSchema.safeParse({ title: "a", assetLinks: [{ url: "javascript:1" }] }).success &&
    !c.contentItemSchema.safeParse({ title: "a", assetLinks: Array.from({ length: 21 }, (_, i) => ({ url: `https://x.id/${i}` })) }).success);
  check("11 photos / audio path as photo → error",
    !c.contentItemSchema.safeParse({ title: "a", photos: Array.from({ length: 11 }, (_, i) => `/uploads/p${i}.png`) }).success &&
    !c.contentItemSchema.safeParse({ title: "a", photos: ["/uploads/a.m4a"] }).success);
}

console.log("post schema");
{
  const base = { contentId: "c", accountId: "a" };
  const p = c.contentPostSchema.parse(base);
  check("defaults", p.status === "draft" && p.caption === "" && p.hashtags === "" && p.scheduledAt === null && p.postedAt === null && p.url === null && eq(p.metrics, {}) && p.metricsAt === null, p);
  check("scheduled needs scheduledAt", /butuh waktu/.test(err(c.contentPostSchema, { ...base, status: "scheduled" }) ?? ""));
  const s = c.contentPostSchema.parse({ ...base, status: "scheduled", scheduledAt: "2026-09-25T12:00:00+07:00" });
  check("scheduledAt with offset → Date", s.scheduledAt instanceof Date && s.scheduledAt.toISOString() === "2026-09-25T05:00:00.000Z");
  check("scheduledAt without offset → error", !c.contentPostSchema.safeParse({ ...base, scheduledAt: "2026-09-25T12:00:00" }).success);
  const posted = c.contentPostSchema.parse({ ...base, status: "posted" });
  check("posted without postedAt → stamped now", posted.postedAt instanceof Date && Math.abs(posted.postedAt - Date.now()) < 2000);
  check("postedAt dropped when not posted", c.contentPostSchema.parse({ ...base, status: "draft", postedAt: "2026-09-01T00:00:00Z" }).postedAt === null);
  check("metrics: unknown keys dropped, null = not entered", eq(c.contentPostSchema.parse({ ...base, metrics: { views: 100, likes: null, foo: 3 } }).metrics, { views: 100 }));
  check("metrics: negative / fractional → error", !c.contentPostSchema.safeParse({ ...base, metrics: { views: -1 } }).success && !c.contentPostSchema.safeParse({ ...base, metrics: { likes: 1.5 } }).success);
  check("url must be http(s)", !c.contentPostSchema.safeParse({ ...base, url: "javascript:alert(1)" }).success && c.contentPostSchema.parse({ ...base, url: " https://instagram.com/p/x " }).url === "https://instagram.com/p/x" && c.contentPostSchema.parse({ ...base, url: "" }).url === null);
  check("caption 5000 ok / 5001 error; hashtags ≤ 1000",
    c.contentPostSchema.safeParse({ ...base, caption: "x".repeat(5000) }).success && !c.contentPostSchema.safeParse({ ...base, caption: "x".repeat(5001) }).success &&
    !c.contentPostSchema.safeParse({ ...base, hashtags: "#".repeat(1001) }).success);
  check("remindBefore 0–10080 int", c.contentPostSchema.safeParse({ ...base, remindBefore: 0 }).success && !c.contentPostSchema.safeParse({ ...base, remindBefore: 10081 }).success);
  check("unknown status → error", !c.contentPostSchema.safeParse({ ...base, status: "live" }).success);
}

console.log("pillars");
{
  const d = c.defaultPillars("u1");
  check("default pillars (deterministic ids, order)", eq(d.map((p) => [p.id, p.name, p.sortOrder]), [
    ["pillar-edukasi-u1", "Edukasi", 0], ["pillar-hiburan-u1", "Hiburan", 1], ["pillar-promo-u1", "Promo", 2], ["pillar-bts-u1", "Behind the scene", 3], ["pillar-personal-u1", "Personal", 4],
  ]));
  check("pillar name taken case-insensitively", c.pillarNameTaken(d, "edukasi") && !c.pillarNameTaken(d, "EDUKASI", "pillar-edukasi-u1") && !c.pillarNameTaken(d, "Tutorial"));
  check("pillar schema 1–30", !c.contentPillarSchema.safeParse({ name: "" }).success && !c.contentPillarSchema.safeParse({ name: "x".repeat(31) }).success && c.contentPillarSchema.parse({ name: " Tips " }).name === "Tips");
}

console.log("weeks / slots / consistency");
check("weekStart Monday", c.weekStart("2026-09-24") === "2026-09-21" && c.weekStart("2026-09-21") === "2026-09-21" && c.weekStart("2026-09-27") === "2026-09-21");
check("weeksInRange", eq(c.weeksInRange("2026-09-24", "2026-10-05"), ["2026-09-21", "2026-09-28", "2026-10-05"]));
check("localParts Asia/Jakarta", eq(c.localParts("2026-09-24T17:30:00Z"), { date: "2026-09-25", hour: 0, weekday: 5 }));
{
  const accounts = [{ id: "ig", targetPerWeek: 3 }, { id: "tt", targetPerWeek: null }, { id: "old", targetPerWeek: 1, archived: true }];
  const posts = [
    { id: "1", accountId: "ig", status: "posted", scheduledAt: "2026-09-20T03:00:00Z", postedAt: "2026-09-21T03:00:00Z" }, // posted Mon (scheduled prev Sun)
    { id: "2", accountId: "ig", status: "scheduled", scheduledAt: "2026-09-26T05:00:00Z", postedAt: null },
    { id: "3", accountId: "ig", status: "skipped", scheduledAt: "2026-09-23T05:00:00Z", postedAt: null },
    { id: "4", accountId: "ig", status: "scheduled", scheduledAt: "2026-09-27T18:00:00Z", postedAt: null }, // Mon 01:00 WIB → next week
    { id: "5", accountId: "tt", status: "draft", scheduledAt: "2026-09-22T05:00:00Z", postedAt: null },
  ];
  const slots = c.weekSlots(accounts, posts, "2026-09-21");
  check("weekSlots: IG planned 2/3 (skipped + next-week excluded), posted 1, empty 1", eq(slots[0], { accountId: "ig", target: 3, planned: 2, posted: 1, empty: 1, met: false }), slots[0]);
  check("weekSlots: no target → empty/met null; archived skipped", eq(slots[1], { accountId: "tt", target: null, planned: 1, posted: 0, empty: null, met: null }) && slots.length === 2, slots);
  check("postTime: posted → postedAt, else scheduledAt", c.postTime(posts[0]).toISOString() === "2026-09-21T03:00:00.000Z" && c.postTime(posts[1]).toISOString() === "2026-09-26T05:00:00.000Z");
}
{
  const weeks = ["2026-08-31", "2026-09-07", "2026-09-14", "2026-09-21"];
  const counts = new Map([["2026-08-31", 3], ["2026-09-07", 1], ["2026-09-14", 3]]);
  check("consistency: met 2, longest 1, current 1 (in-progress week not met ignored)",
    eq(c.consistency(counts, 3, weeks, "2026-09-21"), { weeksMet: 2, weeks: 4, longestStreak: 1, currentStreak: 1 }), c.consistency(counts, 3, weeks, "2026-09-21"));
  check("consistency: a past unmet last week breaks the current streak", c.consistency(counts, 3, weeks).currentStreak === 0);
  const all = new Map(weeks.map((w) => [w, 2]));
  check("consistency: 4 weeks met → streak 4", eq(c.consistency(all, 2, weeks, "2026-09-21"), { weeksMet: 4, weeks: 4, longestStreak: 4, currentStreak: 4 }));
  check("consistency: no target → zeros", c.consistency(all, null, weeks).weeksMet === 0);
  check("postedPerWeek by local postedAt", eq([...c.postedPerWeek([
    { id: "1", accountId: "a", status: "posted", scheduledAt: null, postedAt: "2026-09-20T18:00:00Z" }, // Mon 01:00 WIB
    { id: "2", accountId: "a", status: "posted", scheduledAt: null, postedAt: "2026-09-20T16:00:00Z" }, // Sun 23:00 WIB
    { id: "3", accountId: "a", status: "scheduled", scheduledAt: "2026-09-22T00:00:00Z", postedAt: null },
  ], "a")], [["2026-09-21", 1], ["2026-09-14", 1]]));
}

console.log("metrics");
check("engagement / rate", c.engagement({ likes: 10, comments: 2, shares: 3, saves: 5, views: 100 }) === 20 && c.engagementRate({ likes: 10, views: 100 }) === 0.1 && c.engagementRate({ likes: 1 }) === null);
check("metrics prompt after 3 days without metrics", c.needsMetricsPrompt({ status: "posted", postedAt: "2026-09-20T00:00:00Z" }, new Date("2026-09-23T00:00:00Z")) &&
  !c.needsMetricsPrompt({ status: "posted", postedAt: "2026-09-21T00:00:00Z" }, new Date("2026-09-23T00:00:00Z")) &&
  !c.needsMetricsPrompt({ status: "posted", postedAt: "2026-09-01T00:00:00Z", metricsAt: "2026-09-05T00:00:00Z" }) &&
  !c.needsMetricsPrompt({ status: "scheduled", postedAt: null }));
check("captionWithHashtags", c.captionWithHashtags({ caption: "Halo\n", hashtags: " #a #b " }) === "Halo\n\n#a #b" && c.captionWithHashtags({ caption: "", hashtags: "#a" }) === "#a");

console.log("report");
{
  const accounts = [{ id: "ig", targetPerWeek: 2 }, { id: "tt", targetPerWeek: null }];
  const items = [
    { id: "i1", title: "Tips A", pillar: "Edukasi", format: "reel" },
    { id: "i2", title: "Promo B", pillar: "Promo", format: "post" },
    { id: "i3", title: "Vlog C", pillar: null, format: "video" },
  ];
  const posts = [
    { id: "p1", contentId: "i1", accountId: "ig", status: "posted", scheduledAt: null, postedAt: "2026-09-01T12:00:00Z", metrics: { views: 1000, likes: 100, comments: 10 } }, // Tue 19 WIB
    { id: "p2", contentId: "i2", accountId: "ig", status: "posted", scheduledAt: null, postedAt: "2026-09-03T12:00:00Z", metrics: { views: 500, likes: 5 } }, // Thu 19
    { id: "p3", contentId: "i1", accountId: "tt", status: "posted", scheduledAt: null, postedAt: "2026-09-08T02:00:00Z", metrics: { views: 5000, likes: 50, shares: 30 } }, // Tue 09
    { id: "p4", contentId: "i3", accountId: "ig", status: "posted", scheduledAt: null, postedAt: "2026-09-09T12:00:00Z", metrics: {} }, // Wed 19
    { id: "p5", contentId: "i3", accountId: "tt", status: "scheduled", scheduledAt: "2026-09-10T12:00:00Z", postedAt: null, metrics: {} },
    { id: "p6", contentId: "i2", accountId: "ig", status: "posted", scheduledAt: null, postedAt: "2026-08-20T12:00:00Z", metrics: { views: 99999 } }, // out of range
  ];
  const r = c.buildContentReport({ from: "2026-08-31", to: "2026-09-13", accounts, items, posts, today: "2026-09-13" });
  check("full weeks in range", eq(r.weeks, ["2026-08-31", "2026-09-07"]) && r.days === 14, r.weeks);
  check("fullWeeksInRange skips partial edge weeks", eq(c.fullWeeksInRange("2026-09-01", "2026-09-21"), ["2026-09-07", "2026-09-14"]));
  check("totals", eq(r.totals, { posted: 4, scheduled: 1, skipped: 0, views: 6500, engagement: 195 }), r.totals);
  const ig = r.accounts.find((a) => a.accountId === "ig");
  check("IG: 3 posted of 4 expected, 1 week met, current streak 1 (in-progress week unmet doesn't break it)", ig.posted === 3 && ig.expected === 4 && ig.ratio === 0.75 && ig.weeksMet === 1 && ig.longestStreak === 1 && ig.currentStreak === 1, ig);
  check("TT: no target", r.accounts.find((a) => a.accountId === "tt").expected === null);
  check("best by views: p3, p1, p2 (no-views p4 excluded)", eq(r.bestByViews.map((b) => b.postId), ["p3", "p1", "p2"]) && r.bestByViews[0].title === "Tips A");
  check("best by engagement: p1 (110), p3 (80), p2 (5)", eq(r.bestByEngagement.map((b) => [b.postId, b.engagement]), [["p1", 110], ["p3", 80], ["p2", 5]]));
  const edu = r.byPillar.find((g) => g.key === "Edukasi");
  check("by pillar: Edukasi 2 posts, avg views 3000, avg engagement 95", edu.posts === 2 && edu.avgViews === 3000 && edu.avgEngagement === 95, edu);
  const none = r.byPillar.find((g) => g.key === "");
  check("by pillar: no pillar group with no metrics → nulls", none.posts === 1 && none.withMetrics === 0 && none.avgViews === null, none);
  check("by format keys", eq(r.byFormat.map((g) => g.key).sort(), ["post", "reel", "video"]));
  check("by weekday (local): Tue 2, Wed 1, Thu 1", eq(r.byWeekday.map((g) => [g.key, g.posts]), [["2", 2], ["3", 1], ["4", 1]]), r.byWeekday);
  check("by hour (local WIB): 9 → 1, 19 → 3", eq(r.byHour.map((g) => [g.key, g.posts]), [["9", 1], ["19", 3]]), r.byHour);
  check("pillar balance shares sum to 1", Math.abs(r.pillarBalance.reduce((s, x) => s + x.share, 0) - 1) < 1e-9 && r.pillarBalance.find((x) => x.key === "Edukasi").share === 0.5);
}

console.log("sponsorship");
{
  const s = c.sponsorSummary({
    items: [
      { id: "i1", title: "Kopi", sponsor: { brand: "Kopi Kita", amount: 1000000, currency: "IDR", due: "2026-09-10", paid: true, transactionId: "t1" }, createdAt: "2026-08-01T00:00:00Z" },
      { id: "i2", title: "Sepatu", sponsor: { brand: "Lari", amount: 500000, currency: "IDR", due: "2026-10-05", paid: true, transactionId: null }, createdAt: "2026-08-01T00:00:00Z" },
      { id: "i3", title: "Skincare", sponsor: { brand: "Glow", amount: 750000, currency: "IDR", due: "2026-09-01", paid: false, transactionId: null }, createdAt: "2026-08-01T00:00:00Z" },
      { id: "i4", title: "Tas", sponsor: { brand: "Bag", amount: 200000, currency: "IDR", due: null, paid: false, transactionId: null }, createdAt: "2026-08-01T00:00:00Z" },
      { id: "i5", title: "Tanpa sponsor", sponsor: null, createdAt: "2026-08-01T00:00:00Z" },
    ],
    posts: [{ contentId: "i1", accountId: "ig" }, { contentId: "i1", accountId: "tt" }, { contentId: "i2", accountId: "ig" }],
    transactionDates: new Map([["t1", "2026-08-31T20:00:00Z"]]), // Sep 1 WIB
    today: "2026-09-24",
  });
  check("by month: tx date (local) else due", eq(s.byMonth, [{ month: "2026-09", amount: 1000000, count: 1 }, { month: "2026-10", amount: 500000, count: 1 }]), s.byMonth);
  check("by account: split equally across the item's accounts", eq(s.byAccount, [{ accountId: "ig", amount: 1000000 }, { accountId: "tt", amount: 500000 }]), s.byAccount);
  check("unpaid: soonest due first, overdue flag, no-due last", eq(s.unpaid.map((u) => [u.contentId, u.overdue]), [["i3", true], ["i4", false]]), s.unpaid);
  check("income note", c.sponsorTransactionNote("Kopi Kita") === "Endorse Kopi Kita");
}

console.log("stored column parsing (lenient)");
check("parseSponsor bad → null", c.parseSponsor("{bad") === null && c.parseSponsor(null) === null && c.parseSponsor('{"brand":"x"}') === null);
check("parseSponsor ok", c.parseSponsor('{"brand":"B","amount":5,"currency":"IDR","due":null,"paid":true,"transactionId":"t"}')?.transactionId === "t");
check("parseMetrics bad → {}", eq(c.parseMetrics("oops"), {}) && eq(c.parseMetrics('{"views":3,"x":1}'), { views: 3 }));
check("parseAssetLinks drops invalid entries", eq(c.parseAssetLinks('[{"url":"https://a.id"},{"url":"javascript:x"}]'), [{ url: "https://a.id", label: null }]));

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
