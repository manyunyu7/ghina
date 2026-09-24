#!/usr/bin/env node
// Unit tests for the pure tasks module (docs/tasks.md) and transaction photo helpers
// (docs/transaction-photos.md). No server/DB needed:
//
//   node scripts/test-tasks.mjs
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createJiti } from "jiti";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const jiti = createJiti(import.meta.url, { alias: { "@": join(root, "src") } });
const t = await jiti.import(join(root, "src/lib/tasks.ts"));
const ph = await jiti.import(join(root, "src/lib/photos.ts"));

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
const ok = (schema, v) => schema.safeParse(v).success;
const err = (schema, v) => {
  const r = schema.safeParse(v);
  return r.success ? null : r.error.issues[0].message;
};

console.log("constants");
check("bucket order fire, want, should", eq(t.BUCKET_IDS, ["fire", "want", "should"]));
check("bucket colors", eq(t.BUCKETS.map((b) => b.color), ["#FF4B4B", "#CE82FF", "#1CB0F6"]));
check("bucket XP 10/8/5", eq(t.BUCKETS.map((b) => b.xp), [10, 8, 5]) && t.bucketXp("should") === 5);
check("daily XP cap 20, 60 notifications", t.TASK_XP_DAILY_CAP === 20 && t.MAX_TASK_NOTIFICATIONS === 60);
check("notification title", t.taskNotificationTitle("KERJA", "fire", "Kirim revisi client A") === "[KERJA-FIRE] Kirim revisi client A");

console.log("date helpers");
check("isoWeekday Mon=1", t.isoWeekday("2026-09-21") === 1 && t.isoWeekday("2026-09-27") === 7);
check("addDaysKey across month/year", t.addDaysKey("2026-12-31", 1) === "2027-01-01" && t.addDaysKey("2026-03-01", -1) === "2026-02-28");
check("daysInMonth leap", t.daysInMonth(2028, 2) === 29 && t.daysInMonth(2026, 2) === 28 && t.daysInMonth(2026, 4) === 30);
{
  const c = t.localClock(new Date("2026-09-24T17:30:00Z"), "Asia/Jakarta");
  check("localClock in Asia/Jakarta", eq(c, { date: "2026-09-25", time: "00:30", weekday: 5 }), c);
}

console.log("recurrence: nextDueDate");
const nd = (rule, due) => t.nextDueDate({ interval: 1, ...rule }, due);
check("daily +1", nd({ freq: "daily" }, "2026-09-24") === "2026-09-25");
check("daily every 3 days across month", nd({ freq: "daily", interval: 3 }, "2026-09-29") === "2026-10-02");
check("weekly default weekday = same weekday next week", nd({ freq: "weekly" }, "2026-09-24") === "2026-10-01");
check("weekly Mon/Wed/Fri from Mon → Wed", nd({ freq: "weekly", weekdays: [1, 3, 5] }, "2026-09-21") === "2026-09-23");
check("weekly Mon/Wed/Fri from Fri → next Mon", nd({ freq: "weekly", weekdays: [5, 1, 3] }, "2026-09-25") === "2026-09-28");
check("weekly every 2 weeks Tue/Thu from Thu → Tue in 2 weeks", nd({ freq: "weekly", interval: 2, weekdays: [2, 4] }, "2026-09-24") === "2026-10-06");
check("weekly every 2 weeks Tue/Thu from Tue → Thu same week", nd({ freq: "weekly", interval: 2, weekdays: [2, 4] }, "2026-09-22") === "2026-09-24");
check("weekly Sunday → next Sunday", nd({ freq: "weekly", weekdays: [7] }, "2026-09-27") === "2026-10-04");
check("monthly default day", nd({ freq: "monthly" }, "2026-09-15") === "2026-10-15");
check("monthly 31 clamps to 30 (Sep→Oct is 31 ok)", nd({ freq: "monthly", monthDay: 31 }, "2026-08-31") === "2026-09-30");
check("monthly 31 from Jan 31 → Feb 28", nd({ freq: "monthly", monthDay: 31 }, "2026-01-31") === "2026-02-28");
check("monthly 31 from Feb 28 (clamped) → Mar 31, no drift", nd({ freq: "monthly", monthDay: 31 }, "2026-02-28") === "2026-03-31");
check("monthly 29 leap year Feb", nd({ freq: "monthly", monthDay: 29 }, "2028-01-29") === "2028-02-29");
check("monthly monthDay later in same month", nd({ freq: "monthly", monthDay: 20 }, "2026-09-05") === "2026-09-20");
check("monthly every 3 months across year", nd({ freq: "monthly", interval: 3, monthDay: 10 }, "2026-11-10") === "2027-02-10");
check("monthly every 12 months", nd({ freq: "monthly", interval: 12 }, "2026-02-28") === "2027-02-28");

console.log("recurrence: nextOccurrence");
const base = {
  id: "task1", seriesId: null, areaId: "a1", title: "Bayar listrik", note: "PLN", bucket: "fire", dueDate: "2026-01-31",
  dueTime: "09:00", remindBefore: 30, recurrence: { freq: "monthly", interval: 1 }, sortOrder: 3, amount: 250000,
  walletId: "w1", categoryId: "c1", transactionId: "tx1", done: true,
};
const n1 = t.nextOccurrence(base);
check("next id = <seriesId>_<YYYYMMDD> (series = first id)", n1?.id === "task1_20260228", n1?.id);
check("next copies fields, undone, no transaction",
  n1.data.title === "Bayar listrik" && n1.data.dueTime === "09:00" && n1.data.remindBefore === 30 && n1.data.bucket === "fire" &&
  n1.data.amount === 250000 && n1.data.walletId === "w1" && n1.data.categoryId === "c1" && n1.data.transactionId === null &&
  n1.data.done === false && n1.data.doneAt === null && n1.data.seriesId === "task1" && n1.data.sortOrder === 3, n1.data);
check("next materializes monthDay (31) → no drift", eq(n1.data.recurrence, { freq: "monthly", interval: 1, monthDay: 31 }));
const n2 = t.nextOccurrence({ ...base, ...n1.data, id: n1.id });
check("second next keeps seriesId and returns to 31", n2.id === "task1_20260331" && n2.data.seriesId === "task1", n2.id);
check("deterministic: same input → same id", t.nextOccurrence(base).id === n1.id);
check("recurrence as JSON string works", t.nextOccurrence({ ...base, recurrence: JSON.stringify({ freq: "daily", interval: 2 }) })?.id === "task1_20260202");
check("one-off → null", t.nextOccurrence({ ...base, recurrence: null }) === null);
check("no due date → null", t.nextOccurrence({ ...base, dueDate: null }) === null);
check("occurrenceId", t.occurrenceId("abc", "2026-09-01") === "abc_20260901");

console.log("status helpers");
const tk = (o) => ({ bucket: "want", done: false, dueDate: null, dueTime: null, ...o });
check("mepet: WANT due today", t.isMepet(tk({ dueDate: "2026-09-24" }), "2026-09-24"));
check("mepet: WANT due tomorrow", t.isMepet(tk({ dueDate: "2026-09-25" }), "2026-09-24"));
check("not mepet: in 2 days", !t.isMepet(tk({ dueDate: "2026-09-26" }), "2026-09-24"));
check("not mepet: FIRE / done / overdue / no date",
  !t.isMepet(tk({ bucket: "fire", dueDate: "2026-09-24" }), "2026-09-24") && !t.isMepet(tk({ done: true, dueDate: "2026-09-24" }), "2026-09-24") &&
  !t.isMepet(tk({ dueDate: "2026-09-23" }), "2026-09-24") && !t.isMepet(tk({}), "2026-09-24"));
const now = { date: "2026-09-24", time: "10:00", weekday: 4 };
check("overdue: yesterday", t.isOverdue(tk({ dueDate: "2026-09-23" }), now));
check("overdue: today 09:59", t.isOverdue(tk({ dueDate: "2026-09-24", dueTime: "09:59" }), now));
check("not overdue: today 10:00 / today no time / done / none",
  !t.isOverdue(tk({ dueDate: "2026-09-24", dueTime: "10:00" }), now) && !t.isOverdue(tk({ dueDate: "2026-09-24" }), now) &&
  !t.isOverdue(tk({ dueDate: "2026-09-01", done: true }), now) && !t.isOverdue(tk({}), now));

console.log("focus mode");
const work = { id: "w", archived: false, schedule: { days: [1, 2, 3, 4, 5], start: "09:00", end: "17:00" } };
const life = { id: "l", archived: false, schedule: null };
const kuliah = { id: "k", archived: false, schedule: JSON.stringify({ days: [6], start: "08:00", end: "12:00" }) };
const old = { id: "o", archived: true, schedule: null };
const areas = [work, life, kuliah, old];
const ids = (xs) => xs.map((a) => a.id);
check("Thu 10:00 → Kerjaan", eq(ids(t.focusAreas(areas, now)), ["w"]));
check("Thu 17:00 (end exclusive) → unscheduled", eq(ids(t.focusAreas(areas, { ...now, time: "17:00" })), ["l"]));
check("Sat 09:00 → Kuliah (JSON string schedule)", eq(ids(t.focusAreas(areas, { date: "2026-09-26", time: "09:00", weekday: 6 })), ["k"]));
check("Sun → unscheduled non-archived", eq(ids(t.focusAreas(areas, { date: "2026-09-27", time: "09:00", weekday: 7 })), ["l"]));
check("archived scheduled area never focus", eq(ids(t.focusAreas([{ ...work, archived: true }, life], now)), ["l"]));

console.log("schemas");
check("schedule ok, days deduped/sorted", eq(t.areaScheduleSchema.parse({ days: [5, 1, 1], start: "09:00", end: "17:00" }).days, [1, 5]));
check("schedule start ≥ end rejected", !ok(t.areaScheduleSchema, { days: [1], start: "17:00", end: "09:00" }));
check("schedule bad day / empty / bad time rejected",
  !ok(t.areaScheduleSchema, { days: [8], start: "09:00", end: "10:00" }) && !ok(t.areaScheduleSchema, { days: [], start: "09:00", end: "10:00" }) &&
  !ok(t.areaScheduleSchema, { days: [1], start: "9:00", end: "10:00" }) && !ok(t.areaScheduleSchema, { days: [1], start: "09:00", end: "24:00" }));
const area = (o) => ({ name: "Kuliah", code: "KULIAH", color: "#123456", icon: "graduation-cap", schedule: null, sortOrder: 2, archived: false, ...o });
check("area ok", ok(t.taskAreaSchema, area({})));
check("area code uppercased", t.taskAreaSchema.parse(area({ code: " kul1 " })).code === "KUL1");
check("area code >8 / symbols rejected", !ok(t.taskAreaSchema, area({ code: "TOOLONGXX" })) && !ok(t.taskAreaSchema, area({ code: "A-B" })) && !ok(t.taskAreaSchema, area({ code: "" })));
check("area name >40 rejected", !ok(t.taskAreaSchema, area({ name: "x".repeat(41) })));
check("area unknown icon rejected", !ok(t.taskAreaSchema, area({ icon: "rocket" })));
check("area defaults", eq(t.taskAreaSchema.parse({ name: "X", code: "X" }), { name: "X", code: "X", color: "#58CC02", icon: "briefcase", schedule: null, sortOrder: 0, archived: false }));

const task = (o) => ({ areaId: "a1", title: "Do it", ...o });
const p = t.taskSchema.parse(task({}));
check("task defaults", p.bucket === "want" && p.done === false && p.doneAt === null && p.sortOrder === 0 && p.recurrence === null && p.note === null, p);
check("task title required / ≤200", !ok(t.taskSchema, task({ title: " " })) && !ok(t.taskSchema, task({ title: "x".repeat(201) })));
check("task note ≤2000, blank → null", !ok(t.taskSchema, task({ note: "x".repeat(2001) })) && t.taskSchema.parse(task({ note: "  " })).note === null);
check("task unknown bucket rejected", !ok(t.taskSchema, task({ bucket: "later" })));
check("task bad date rejected", !ok(t.taskSchema, task({ dueDate: "2026-02-30" })));
check("task dueTime without dueDate rejected", err(t.taskSchema, task({ dueTime: "09:00" })) === "A due time needs a due date");
check("task recurrence without dueDate rejected", err(t.taskSchema, task({ recurrence: { freq: "daily", interval: 1 } })) === "A recurring task needs a due date");
check("task remindBefore negative / fractional rejected", !ok(t.taskSchema, task({ remindBefore: -1 })) && !ok(t.taskSchema, task({ remindBefore: 1.5 })));
check("task amount ≤ 0 rejected", !ok(t.taskSchema, task({ amount: 0 })));
check("task recurrence weekdays on daily rejected", !ok(t.taskSchema, task({ dueDate: "2026-09-24", recurrence: { freq: "daily", interval: 1, weekdays: [1] } })));
check("task recurrence interval 0 / 366 rejected",
  !ok(t.taskSchema, task({ dueDate: "2026-09-24", recurrence: { freq: "daily", interval: 0 } })) &&
  !ok(t.taskSchema, task({ dueDate: "2026-09-24", recurrence: { freq: "daily", interval: 366 } })));
check("task recurrence defaults materialized",
  eq(t.taskSchema.parse(task({ dueDate: "2026-09-24", recurrence: { freq: "weekly" } })).recurrence, { freq: "weekly", interval: 1, weekdays: [4] }));
check("task doneAt without offset rejected", !ok(t.taskSchema, task({ done: true, doneAt: "2026-09-24T10:00:00" })));
check("task done without doneAt → stamped", t.taskSchema.parse(task({ done: true })).doneAt instanceof Date);
check("task undone drops doneAt", t.taskSchema.parse(task({ done: false, doneAt: "2026-09-24T10:00:00Z" })).doneAt === null);
check("task seriesId too long rejected", !ok(t.taskSchema, task({ seriesId: "x".repeat(56) })));
check("task '' ids → null", t.taskSchema.parse(task({ walletId: "", categoryId: "", transactionId: "" })).walletId === null);

console.log("ordering / defaults");
check("compareTasks bucket then sortOrder",
  eq([{ bucket: "should", sortOrder: 0 }, { bucket: "fire", sortOrder: 2 }, { bucket: "fire", sortOrder: 1 }].sort(t.compareTasks).map((x) => x.bucket + x.sortOrder), ["fire1", "fire2", "should0"]));
check("sortOrderBetween", t.sortOrderBetween(1, 2) === 1.5 && t.sortOrderBetween(null, 2) === 1 && t.sortOrderBetween(3, null) === 4 && t.sortOrderBetween() === 0);
const defs = t.defaultAreas("u123");
check("default area ids deterministic", eq(defs.map((a) => a.id), ["area-kerjaan-u123", "area-life-u123"]));
check("default Kerjaan", defs[0].code === "KERJA" && defs[0].color === "#1CB0F6" && defs[0].icon === "briefcase" && eq(defs[0].schedule, { days: [1, 2, 3, 4, 5], start: "09:00", end: "17:00" }));
check("default Keseharian", defs[1].code === "LIFE" && defs[1].color === "#58CC02" && defs[1].icon === "home" && defs[1].schedule === null);
check("default areas pass the schema", defs.every((d) => ok(t.taskAreaSchema, d)));

console.log("photos");
check("photos ok", eq(ph.photosSchema.parse(["/uploads/a.jpg", "/uploads/b-1.png"]), ["/uploads/a.jpg", "/uploads/b-1.png"]));
check("photos deduped", eq(ph.photosSchema.parse(["/uploads/a.jpg", "/uploads/a.jpg"]), ["/uploads/a.jpg"]));
check("photos max 5", !ok(ph.photosSchema, ["a", "b", "c", "d", "e", "f"].map((x) => `/uploads/${x}.jpg`)) && ok(ph.photosSchema, ["a", "b", "c", "d", "e"].map((x) => `/uploads/${x}.jpg`)));
check("photos traversal / absolute URL rejected",
  !ok(ph.photosSchema, ["/uploads/../.env"]) && !ok(ph.photosSchema, ["https://x.com/a.jpg"]) && !ok(ph.photosSchema, ["/uploads/.."]));
check("photos not an array rejected", !ok(ph.photosSchema, "/uploads/a.jpg"));
check("parsePhotos lenient", eq(ph.parsePhotos('["/uploads/a.jpg","../x",3]'), ["/uploads/a.jpg"]) && eq(ph.parsePhotos("nope"), []) && eq(ph.parsePhotos(null), []));
check("serializePhotos", ph.serializePhotos(["/uploads/a.jpg"]) === '["/uploads/a.jpg"]' && ph.serializePhotos([]) === "[]");
check("removedPhotos", eq(ph.removedPhotos(["/uploads/a.jpg", "/uploads/b.jpg"], ["/uploads/b.jpg", "/uploads/c.jpg"]), ["/uploads/a.jpg"]));

console.log("upload type sniffing");
{
  const b = (...xs) => Uint8Array.from(xs.flatMap((x) => (typeof x === "string" ? [...x].map((c) => c.charCodeAt(0)) : [x])));
  const ftyp = (brand) => b(0, 0, 0, 0x18, "ftyp", brand, 0, 0, 0, 0);
  check("JPEG", ph.sniffImageType(b(0xff, 0xd8, 0xff, 0xe0, 0, 0x10)) === "jpg");
  check("PNG", ph.sniffImageType(b(0x89, "PNG", 0x0d, 0x0a, 0x1a, 0x0a, 0, 0)) === "png");
  check("GIF87a/89a", ph.sniffImageType(b("GIF87a", 1)) === "gif" && ph.sniffImageType(b("GIF89a", 1)) === "gif");
  check("WebP", ph.sniffImageType(b("RIFF", 0, 0, 0, 0, "WEBPVP8 ")) === "webp");
  check("RIFF but not WebP (WAV) → null", ph.sniffImageType(b("RIFF", 0, 0, 0, 0, "WAVEfmt ")) === null);
  check("HEIC brands", ["heic", "heix", "hevc"].every((x) => ph.sniffImageType(ftyp(x)) === "heic"));
  check("HEIF brands", ["mif1", "msf1", "heif"].every((x) => ph.sniffImageType(ftyp(x)) === "heif"));
  check("AVIF / MP4 → null", ph.sniffImageType(ftyp("avif")) === null && ph.sniffImageType(ftyp("isom")) === null);
  check("SVG / HTML / text / empty / truncated → null",
    ph.sniffImageType(b('<svg xmlns="http://www.w3.org/2000/svg"/>')) === null &&
    ph.sniffImageType(b("<?xml version='1.0'?><svg/>")) === null &&
    ph.sniffImageType(b("<html></html>")) === null && ph.sniffImageType(b("hello")) === null &&
    ph.sniffImageType(new Uint8Array()) === null && ph.sniffImageType(b(0xff, 0xd8)) === null && ph.sniffImageType(b(0x89, "PN")) === null);
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
