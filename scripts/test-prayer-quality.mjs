#!/usr/bin/env node
// Unit tests for the pure prayer-quality module (docs/prayer-quality.md) and the
// ledger's balance-adjustment effect (docs/balance-adjustment.md). No server/DB needed:
//
//   node scripts/test-prayer-quality.mjs
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createJiti } from "jiti";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const jiti = createJiti(import.meta.url, { alias: { "@": join(root, "src") } });
const q = await jiti.import(join(root, "src/lib/prayer-quality.ts"));
const { effects, ledgerDeltas } = await jiti.import(join(root, "src/lib/ledger.ts"));
const { transactionSchema } = await jiti.import(join(root, "src/lib/schemas.ts"));
const { resolveRange } = await jiti.import(join(root, "src/app/(dashboard)/prayers/report/range.ts"));

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

const e = (date, prayer, status, extra = {}) => ({ date, prayer, status, qobliyah: false, badiyah: false, ...extra });
const full = (date, status) => q.FARDHU.map((p) => e(date, p.id, status));
const fields = (o) => ({ date: "2026-09-20", prayer: "subuh", status: "jamaah", qobliyah: false, badiyah: false, rakaat: null, prayedAt: null, note: null, ...o });

console.log("constants");
check("7 statuses in spec order", eq(q.STATUSES.map((s) => s.id), ["masjid", "jamaah", "ontime", "late", "qadha", "missed", "excused"]));
check("points 10/8/6/3/1/0/—", eq(q.STATUSES.map((s) => s.points), [10, 8, 6, 3, 1, 0, null]));
check("colors match spec", eq(q.STATUSES.map((s) => s.color), ["#1B7A2E", "#58CC02", "#1CB0F6", "#FFC800", "#FF9600", "#FF4B4B", "#CE82FF"]));
check("unfilled colors", q.UNFILLED.color === "#E5E5E5" && q.UNFILLED.colorDark === "#37464F");
check("8 prayer ids", eq(q.ALL_PRAYER_IDS, ["subuh", "dzuhur", "ashar", "maghrib", "isya", "dhuha", "tahajud", "witir"]));
check("quick status = jamaah", q.QUICK_STATUS === "jamaah");
check("rawatib table", eq(q.RAWATIB, {
  subuh: { qobliyah: true, badiyah: false }, dzuhur: { qobliyah: true, badiyah: true }, ashar: { qobliyah: false, badiyah: false },
  maghrib: { qobliyah: false, badiyah: true }, isya: { qobliyah: false, badiyah: true },
}));
check("rakaat options", eq(q.rakaatOptions("witir"), [1, 3, 5, 7, 9, 11]) && eq(q.rakaatOptions("dhuha"), [2, 4, 6, 8, 10, 12]));

console.log("validation");
check("valid fardhu", q.prayerEntryError(fields({})) === null);
check("unknown prayer", q.prayerEntryError(fields({ prayer: "jumat" })) !== null);
check("bad date 2026-02-30", q.prayerEntryError(fields({ date: "2026-02-30" })) !== null);
check("bad status", q.prayerEntryError(fields({ status: "done" })) !== null);
check("subuh qobliyah ok", q.prayerEntryError(fields({ qobliyah: true })) === null);
check("subuh ba'diyah rejected", q.prayerEntryError(fields({ badiyah: true })) !== null);
check("ashar rawatib rejected", q.prayerEntryError(fields({ prayer: "ashar", qobliyah: true })) !== null);
check("maghrib ba'diyah ok", q.prayerEntryError(fields({ prayer: "maghrib", badiyah: true })) === null);
check("rawatib with missed rejected", q.prayerEntryError(fields({ status: "missed", qobliyah: true })) !== null);
check("rawatib with excused rejected", q.prayerEntryError(fields({ status: "excused", qobliyah: true })) !== null);
check("rawatib with qadha ok", q.prayerEntryError(fields({ status: "qadha", qobliyah: true })) === null);
check("rakaat on fardhu rejected", q.prayerEntryError(fields({ rakaat: 2 })) !== null);
check("sunnah done ok", q.prayerEntryError(fields({ prayer: "dhuha", status: "done" })) === null);
check("sunnah non-done status rejected", q.prayerEntryError(fields({ prayer: "dhuha", status: "jamaah" })) !== null);
check("sunnah rawatib rejected", q.prayerEntryError(fields({ prayer: "tahajud", status: "done", qobliyah: true })) !== null);
check("dhuha 4 ok / 3 rejected / 14 rejected",
  q.prayerEntryError(fields({ prayer: "dhuha", status: "done", rakaat: 4 })) === null &&
  q.prayerEntryError(fields({ prayer: "dhuha", status: "done", rakaat: 3 })) !== null &&
  q.prayerEntryError(fields({ prayer: "dhuha", status: "done", rakaat: 14 })) !== null);
check("witir 3 ok / 2 rejected / 13 rejected",
  q.prayerEntryError(fields({ prayer: "witir", status: "done", rakaat: 3 })) === null &&
  q.prayerEntryError(fields({ prayer: "witir", status: "done", rakaat: 2 })) !== null &&
  q.prayerEntryError(fields({ prayer: "witir", status: "done", rakaat: 13 })) !== null);
check("note too long rejected", q.prayerEntryError(fields({ note: "x".repeat(501) })) !== null);

console.log("scoring");
const T = "2026-09-24";
let r = q.computeReport([], "2026-09-24", "2026-09-24", T);
check("empty today → score null, nothing counted", r.score === null && r.counted === 0);
r = q.computeReport([], "2026-09-23", "2026-09-24", T);
check("empty yesterday → 5 unfilled slots, score 0", r.counted === 5 && r.counts.unfilled === 5 && r.score === 0);
r = q.computeReport(full("2026-09-23", "masjid"), "2026-09-23", "2026-09-23", T);
check("all masjid → 100, 1 complete day", r.score === 100 && r.completeDays === 1);
r = q.computeReport(
  [e("2026-09-23", "subuh", "masjid"), e("2026-09-23", "dzuhur", "jamaah"), e("2026-09-23", "ashar", "ontime"), e("2026-09-23", "maghrib", "late"), e("2026-09-23", "isya", "missed")],
  "2026-09-23", "2026-09-23", T,
);
check("mixed day: (10+8+6+3+0)/50 = 54", r.score === 54 && r.points === 27, r);
check("mixed day not complete", r.completeDays === 0);
check("jamaah% = masjid+jamaah = 40", r.pct.jamaahAll === 40 && r.pct.masjid === 20 && r.pct.missed === 20);
r = q.computeReport([e(T, "subuh", "jamaah")], T, T, T);
check("today counts only recorded slots (8/10 → 80)", r.counted === 1 && r.score === 80);
r = q.computeReport([...full("2026-09-23", "excused")], "2026-09-23", "2026-09-23", T);
check("all excused → nothing counted, neutral day", r.counted === 0 && r.score === null && r.neutralDays === 1 && r.completeDays === 0 && r.counts.excused === 5);
r = q.computeReport([e("2026-09-23", "subuh", "jamaah"), e("2026-09-23", "dzuhur", "excused")], "2026-09-23", "2026-09-23", T);
check("excused excluded from slots; unfilled past slots count", r.counted === 4 && r.points === 8 && r.score === 20);
r = q.computeReport(full("2026-09-25", "masjid"), "2026-09-24", "2026-09-30", T);
check("future days ignored", r.counted === 0 && r.daysElapsed === 1);
r = q.computeReport([
  e("2026-09-23", "subuh", "jamaah", { qobliyah: true }),
  e("2026-09-23", "dzuhur", "late", { qobliyah: true, badiyah: true }),
  e("2026-09-23", "maghrib", "missed", { badiyah: true }), // invalid combo — not counted
  e("2026-09-23", "dhuha", "done", { rakaat: 4 }),
  e("2026-09-22", "dhuha", "done"),
  e("2026-09-23", "witir", "done"),
], "2026-09-22", "2026-09-23", T);
check("rawatib counted only on prayed rows", eq(r.rawatib, { qobliyah: 2, badiyah: 1, total: 3 }), r.rawatib);
check("sunnah counts", eq(r.sunnah, { dhuha: 2, tahajud: 0, witir: 1 }), r.sunnah);
check("sunnah rows never count as fardhu slots", r.counted === 10);

// Weakest / strongest
const wk = [
  ...full("2026-09-22", "masjid"),
  e("2026-09-23", "subuh", "late"), e("2026-09-23", "dzuhur", "masjid"), e("2026-09-23", "ashar", "missed"),
  e("2026-09-23", "maghrib", "masjid"), e("2026-09-23", "isya", "jamaah"),
];
r = q.computeReport(wk, "2026-09-22", "2026-09-23", T);
check("per-prayer scores", eq(r.perPrayer.map((b) => b.score), [65, 100, 50, 100, 90]), r.perPrayer.map((b) => b.score));
check("weakest = ashar (missed, lower score than subuh late)", r.weakest === "ashar", r.weakest);
check("strongest = dzuhur (first of the 100s)", r.strongest === "dzuhur", r.strongest);
r = q.computeReport(full("2026-09-23", "masjid"), "2026-09-23", "2026-09-23", T);
check("all equal → no weakest/strongest", r.weakest === null && r.strongest === null);

console.log("streak");
const streakEntries = [
  ...full("2026-09-20", "jamaah"),
  ...full("2026-09-21", "excused"), // neutral
  ...full("2026-09-22", "qadha"),
  ...full("2026-09-23", "late"),
  e(T, "subuh", "jamaah"), // today in progress
];
check("streak skips neutral day and incomplete today → 3", q.currentStreak(streakEntries, T) === 3, q.currentStreak(streakEntries, T));
check("complete today counts → 4", q.currentStreak([...streakEntries, ...full(T, "masjid")], T) === 4);
check("missed breaks streak", q.currentStreak([...full("2026-09-22", "jamaah"), ...full("2026-09-23", "missed")], T) === 0);
check("partial excused day with the rest prayed is neutral",
  q.dayState(new Map([["subuh", e("", "subuh", "jamaah")], ["dzuhur", e("", "dzuhur", "jamaah")], ["ashar", e("", "ashar", "excused")], ["maghrib", e("", "maghrib", "excused")], ["isya", e("", "isya", "excused")]])) === "neutral");

console.log("report ranges");
check("7 hari", eq(resolveRange({}, T), { preset: "7d", from: "2026-09-18", to: T }));
check("bulan ini", eq(resolveRange({ preset: "month" }, T), { preset: "month", from: "2026-09-01", to: "2026-09-30" }));
check("bulan lalu", eq(resolveRange({ preset: "lastmonth" }, T), { preset: "lastmonth", from: "2026-08-01", to: "2026-08-31" }));
check("3 bulan = 90 days", eq(resolveRange({ preset: "3m" }, T), { preset: "3m", from: "2026-06-27", to: T }));
check("custom swapped", eq(resolveRange({ from: "2026-09-10", to: "2026-09-01" }, T), { preset: "custom", from: "2026-09-01", to: "2026-09-10" }));
check("custom clamped to 366 days", resolveRange({ from: "2000-01-01", to: "2026-09-24" }, T).from === "2025-09-24");

console.log("ledger: adjustment");
check("adjustment +amount to wallet", eq(effects({ type: "adjustment", amount: 500, walletId: "A", toWalletId: null }), { A: 500 }));
check("negative adjustment", eq(effects({ type: "adjustment", amount: -250, walletId: "A", toWalletId: null }), { A: -250 }));
check("edit reverses old + applies new", eq(ledgerDeltas(
  { type: "adjustment", amount: 500, walletId: "A", toWalletId: null },
  { type: "adjustment", amount: -100, walletId: "A", toWalletId: null },
), { A: -600 }));
check("delete restores previous balance", eq(ledgerDeltas({ type: "adjustment", amount: -250, walletId: "A", toWalletId: null }, null), { A: 250 }));
const base = { walletId: "A", date: "2026-09-24" };
check("schema: adjustment negative ok", transactionSchema.safeParse({ ...base, type: "adjustment", amount: -5 }).success);
check("schema: adjustment 0 rejected", !transactionSchema.safeParse({ ...base, type: "adjustment", amount: 0 }).success);
check("schema: expense negative rejected", !transactionSchema.safeParse({ ...base, type: "expense", amount: -5 }).success);
check("schema: unknown type rejected", !transactionSchema.safeParse({ ...base, type: "gift", amount: 5 }).success);

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
