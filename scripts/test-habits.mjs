#!/usr/bin/env node
// Unit tests for the pure habits module (docs/habits.md). No server/DB needed:
//
//   node scripts/test-habits.mjs
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createJiti } from "jiti";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const jiti = createJiti(import.meta.url, { alias: { "@": join(root, "src") } });
const h = await jiti.import(join(root, "src/lib/habits.ts"));

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
const done = (date, value = 1) => ({ date, type: "done", value });
const skip = (date) => ({ date, type: "skip", value: null });
const relapse = (date, value = 1, extra = {}) => ({ date, type: "relapse", value, ...extra });
const urge = (date, value = 1, extra = {}) => ({ date, type: "urge", value, ...extra });

// 2026-09-21 is a Monday; "today" in most tests is Friday 2026-09-25.
const TODAY = "2026-09-25";
const daily = { kind: "build", schedule: { type: "daily" }, target: { type: "check" }, startDate: "2026-09-01" };

console.log("constants");
check("milestones list", eq(h.QUIT_MILESTONES, [1, 3, 7, 14, 21, 30, 40, 60, 90, 120, 180, 270, 365]));
check("XP constants", h.HABIT_XP.buildMet === 5 && h.HABIT_XP.buildMetDailyCap === 10 && h.HABIT_XP.quitCleanCheckIn === 3 &&
  h.HABIT_XP.urgeResisted === 5 && h.HABIT_XP.urgeResistedDailyCap === 5 && h.HABIT_XP.quitMilestoneBonus[365] === 365);
check("trigger presets", eq(h.TRIGGER_PRESETS, ["bosan", "stres", "sendirian", "malam", "medsos", "capek"]));
check("daysBetween", h.daysBetween("2026-09-01", "2026-09-25") === 24 && h.daysBetween("2026-12-31", "2027-01-01") === 1);
check("todayKey in Asia/Jakarta", h.todayKey(new Date("2026-09-24T17:30:00Z")) === "2026-09-25");

console.log("schemas");
{
  const x = h.habitSchema.parse({ name: "  Minum\nair ", startDate: "2026-09-01", target: { type: "count", goal: 8, unit: " gelas " }, reminders: ["21:30", "07:00", "07:00"] });
  check("habit defaults + cleaning", x.name === "Minum air" && x.kind === "build" && x.color === "#58CC02" && eq(x.schedule, { type: "daily" }) &&
    eq(x.target, { type: "count", goal: 8, unit: "gelas" }) && eq(x.reminders, ["07:00", "21:30"]) && x.private === false && x.why === null && x.sortOrder === 0, x);
  const q = h.habitSchema.parse({ name: "Rokok", kind: "quit", startDate: "2026-09-01", schedule: { type: "perWeek", times: 3 }, target: { type: "duration", goal: 30 }, why: "  demi anak  " });
  check("quit habit forced daily + check", eq(q.schedule, { type: "daily" }) && eq(q.target, { type: "check" }) && q.why === "demi anak", q);
  check("count unit default 'kali'", h.habitSchema.parse({ name: "a", startDate: "2026-09-01", target: { type: "count", goal: 2 } }).target.unit === "kali");
  check("weekdays dedup + sorted", eq(h.habitSchema.parse({ name: "a", startDate: "2026-09-01", schedule: { type: "weekdays", days: [5, 1, 3, 1] } }).schedule, { type: "weekdays", days: [1, 3, 5] }));
  check("weekdays needs ≥ 1 day", /minimal satu hari/.test(err(h.habitSchema, { name: "a", startDate: "2026-09-01", schedule: { type: "weekdays", days: [] } }) ?? ""));
  check("perWeek 1–7", err(h.habitSchema, { name: "a", startDate: "2026-09-01", schedule: { type: "perWeek", times: 8 } }) !== null &&
    err(h.habitSchema, { name: "a", startDate: "2026-09-01", schedule: { type: "perWeek", times: 7 } }) === null);
  check("unknown schedule type rejected", err(h.habitSchema, { name: "a", startDate: "2026-09-01", schedule: { type: "monthly" } }) !== null);
  check("schedule as JSON string rejected", err(h.habitSchema, { name: "a", startDate: "2026-09-01", schedule: '{"type":"daily"}' }) !== null);
  check("duration goal 1–1440 integer", err(h.habitSchema, { name: "a", startDate: "2026-09-01", target: { type: "duration", goal: 1441 } }) !== null &&
    err(h.habitSchema, { name: "a", startDate: "2026-09-01", target: { type: "duration", goal: 1.5 } }) !== null);
  check("count goal ≤ 10000", err(h.habitSchema, { name: "a", startDate: "2026-09-01", target: { type: "count", goal: 10001 } }) !== null);
  check("name 1–60", err(h.habitSchema, { name: " ", startDate: "2026-09-01" }) === "Nama wajib diisi" && err(h.habitSchema, { name: "x".repeat(61), startDate: "2026-09-01" }) !== null);
  check("startDate required + real", err(h.habitSchema, { name: "a" }) !== null && err(h.habitSchema, { name: "a", startDate: "2026-02-30" }) !== null);
  check("≤ 5 reminders, HH:mm", err(h.habitSchema, { name: "a", startDate: "2026-09-01", reminders: ["1:00"] }) !== null &&
    err(h.habitSchema, { name: "a", startDate: "2026-09-01", reminders: ["01:00", "02:00", "03:00", "04:00", "05:00", "06:00"] }) !== null);
  check("why ≤ 500", err(h.habitSchema, { name: "a", startDate: "2026-09-01", why: "x".repeat(501) }) !== null);

  const l = h.habitLogSchema.parse({ habitId: "h1", date: "2026-09-25", type: "relapse", triggers: ["Stres", "stres", " malam ", ""], note: "  capek \r\n banget " });
  check("log triggers dedup case-insensitive, note cleaned", eq(l.triggers, ["Stres", "malam"]) && l.note === "capek \n banget" && l.value === null && l.at === null, l);
  check("triggers ≤ 10", err(h.habitLogSchema, { habitId: "h", date: "2026-09-25", type: "urge", triggers: Array.from({ length: 11 }, (_, i) => `t${i}`) }) !== null);
  check("triggers as JSON string rejected", err(h.habitLogSchema, { habitId: "h", date: "2026-09-25", type: "urge", triggers: "[]" }) !== null);
  check("bad log type", err(h.habitLogSchema, { habitId: "h", date: "2026-09-25", type: "maybe" }) !== null);
  check("at needs offset", err(h.habitLogSchema, { habitId: "h", date: "2026-09-25", type: "urge", at: "2026-09-25T10:00:00" }) !== null);
}

console.log("normalizeHabitLog");
{
  const base = (type, extra = {}) => h.habitLogSchema.parse({ habitId: "h", date: "2026-09-25", type, ...extra });
  const nb = (target, type, extra) => h.normalizeHabitLog({ kind: "build", target }, base(type, extra));
  const nq = (type, extra) => h.normalizeHabitLog({ kind: "quit", target: { type: "check" } }, base(type, extra));
  check("build check done → value 1", nb({ type: "check" }, "done", { value: 7 }).log.value === 1);
  check("build count done needs value", !nb({ type: "count", goal: 8, unit: "gelas" }, "done").ok && nb({ type: "count", goal: 8, unit: "gelas" }, "done", { value: 3 }).log.value === 3);
  check("build duration value integer", !nb({ type: "duration", goal: 30 }, "done", { value: 2.5 }).ok);
  check("build skip → value null, triggers dropped", (() => { const r = nb({ type: "check" }, "skip", { value: 3, triggers: ["x"] }); return r.ok && r.log.value === null && eq(r.log.triggers, []); })());
  check("build relapse/urge rejected", !nb({ type: "check" }, "relapse").ok && !nb({ type: "check" }, "urge").ok);
  check("quit skip rejected", !nq("skip").ok);
  check("quit done → value 1 (clean check-in)", nq("done", { value: 5 }).log.value === 1);
  check("quit relapse default 1, keeps triggers", (() => { const r = nq("relapse", { triggers: ["bosan"] }); return r.ok && r.log.value === 1 && eq(r.log.triggers, ["bosan"]); })());
  check("urge count integer ≥ 1", !nq("urge", { value: 0 }).ok && !nq("urge", { value: 1.5 }).ok && nq("urge", { value: 3 }).log.value === 3);
}

console.log("parse (lenient)");
check("parseHabitSchedule bad → daily", eq(h.parseHabitSchedule("nope"), { type: "daily" }) && eq(h.parseHabitSchedule('{"type":"perWeek","times":3}'), { type: "perWeek", times: 3 }));
check("parseHabitTarget bad → check", eq(h.parseHabitTarget('{"type":"count"}'), { type: "check" }));
check("parseReminders drops junk", eq(h.parseReminders('["07:00","x",5,"07:00"]'), ["07:00"]));
check("parseTriggers", eq(h.parseTriggers('["a","A","b"]'), ["a", "b"]) && eq(h.parseTriggers("oops"), []));

console.log("build streak: daily");
{
  const logs = [done("2026-09-20"), done("2026-09-21"), skip("2026-09-22"), done("2026-09-23"), done("2026-09-24")];
  const s = h.buildStreak(daily, logs, TODAY);
  check("skip neutral, today unmet doesn't break → 4", s.current === 4 && s.unit === "day" && s.periodMet === false, s);
  const s2 = h.buildStreak(daily, [...logs, done(TODAY)], TODAY);
  check("today met → 5", s2.current === 5 && s2.periodMet, s2);
  const s3 = h.buildStreak(daily, [done("2026-09-20"), done("2026-09-22"), done("2026-09-23"), done("2026-09-24")], TODAY);
  check("a missed day breaks (21st) → 3; longest 3", s3.current === 3 && s3.longest === 3, s3);
  const s4 = h.buildStreak(daily, [done("2026-09-10"), done("2026-09-11"), done("2026-09-12"), done("2026-09-13"), done("2026-09-24")], TODAY);
  check("longest from history (4), current 1", s4.current === 1 && s4.longest === 4, s4);
  const s5 = h.buildStreak(daily, [done("2026-09-23")], TODAY);
  check("yesterday missed → 0 (today pending doesn't save it)", s5.current === 0, s5);
  const s6 = h.buildStreak({ ...daily, startDate: "2026-09-24" }, [done("2026-09-24")], TODAY);
  check("days before startDate don't break", s6.current === 1, s6);
  const cnt = { ...daily, target: { type: "count", goal: 8, unit: "gelas" } };
  const s7 = h.buildStreak(cnt, [done("2026-09-23", 8), done("2026-09-24", 5), done(TODAY, 3)], TODAY);
  check("count: partial past day (5/8) is a miss; partial today pending → 0", s7.current === 0 && s7.longest === 1, s7);
  const s8 = h.buildStreak(cnt, [done("2026-09-23", 8), done("2026-09-24", 9), done(TODAY, 3)], TODAY);
  check("count: value ≥ goal met → 2", s8.current === 2, s8);
  check("future startDate → 0", h.buildStreak({ ...daily, startDate: "2026-10-01" }, [], TODAY).current === 0);
}

console.log("build streak: weekdays");
{
  const mwf = { ...daily, schedule: { type: "weekdays", days: [1, 3, 5] } };
  // Mon 14, Wed 16, Fri 18, Mon 21, Wed 23; today Fri 25 (pending)
  const logs = [done("2026-09-14"), done("2026-09-16"), done("2026-09-18"), done("2026-09-21"), done("2026-09-23")];
  const s = h.buildStreak(mwf, logs, TODAY);
  check("only scheduled days count; off days ignored → 5", s.current === 5, s);
  const s2 = h.buildStreak(mwf, [...logs, done("2026-09-22")], TODAY);
  check("done on an off day doesn't count", s2.current === 5, s2);
  const s3 = h.buildStreak(mwf, [done("2026-09-14"), done("2026-09-18"), done("2026-09-21"), done("2026-09-23")], TODAY);
  check("missed Wed 16 breaks → 3", s3.current === 3, s3);
  check("status off vs missed", h.buildDayStatus(mwf, h.indexLogs([]), "2026-09-22", TODAY) === "off" && h.buildDayStatus(mwf, h.indexLogs([]), "2026-09-23", TODAY) === "missed");
}

console.log("build streak: perWeek");
{
  const pw = { ...daily, schedule: { type: "perWeek", times: 3 }, startDate: "2026-08-31" };
  // weeks: 31 Aug, 7 Sep, 14 Sep, 21 Sep (current)
  const logs = [
    done("2026-08-31"), done("2026-09-02"), done("2026-09-04"),
    done("2026-09-07"), done("2026-09-08"), done("2026-09-09"),
    done("2026-09-14"), done("2026-09-16"), done("2026-09-19"),
    done("2026-09-22"),
  ];
  const s = h.buildStreak(pw, logs, TODAY);
  check("3 met weeks; current week not met yet doesn't break → 3 weeks", s.current === 3 && s.unit === "week" && !s.periodMet, s);
  const s2 = h.buildStreak(pw, [...logs, done("2026-09-23"), done("2026-09-24")], TODAY);
  check("current week met → 4", s2.current === 4 && s2.periodMet, s2);
  const s3 = h.buildStreak(pw, logs.filter((l) => l.date !== "2026-09-09"), TODAY);
  check("a missed week breaks → 1; longest 1", s3.current === 1 && s3.longest === 1, s3);
  // skip days reduce the available days: week of 7 Sep with 5 skips → need min(3, 2) = 2
  const s4 = h.buildStreak(pw, [...logs.filter((l) => l.date !== "2026-09-09"), skip("2026-09-09"), skip("2026-09-10"), skip("2026-09-11"), skip("2026-09-12"), skip("2026-09-13")], TODAY);
  check("skips lower the week's need (min(n, available))", s4.current === 3, s4);
  const w = h.weekStatus({ ...pw, startDate: "2026-09-25" }, h.indexLogs([done("2026-09-25"), done("2026-09-26")]), "2026-09-21", TODAY);
  check("partial first week: need = min(n, days since start)", w.need === 3 && w.met === 2 && w.status === "pending", w);
  const w2 = h.weekStatus({ ...pw, startDate: "2026-09-26" }, h.indexLogs([done("2026-09-26"), done("2026-09-27")]), "2026-09-21", "2026-09-28");
  check("start Sat → need 2, met", w2.need === 2 && w2.status === "met", w2);
}

console.log("quit streak");
{
  const q = { kind: "quit", schedule: { type: "daily" }, target: { type: "check" }, startDate: "2026-09-01" };
  const s = h.quitStreak(q, [], TODAY);
  check("no relapse: startDate..today inclusive = 25", s.current === 25 && s.longest === 25 && s.lastRelapse === null && s.segments.length === 1 && s.segments[0].ongoing, s);
  const s2 = h.quitStreak(q, [relapse("2026-09-10"), relapse("2026-09-20", 2)], TODAY);
  check("after relapse on 20th: 21..25 = 5; longest 9 (1..9)", s2.current === 5 && s2.longest === 9 && s2.lastRelapse === "2026-09-20", s2);
  check("segments", eq(s2.segments.map((x) => [x.start, x.end, x.days]), [["2026-09-01", "2026-09-09", 9], ["2026-09-11", "2026-09-19", 9], ["2026-09-21", TODAY, 5]]), s2.segments);
  const s3 = h.quitStreak(q, [relapse(TODAY)], TODAY);
  check("relapse today → 0, relapsedToday", s3.current === 0 && s3.relapsedToday && s3.longest === 24, s3);
  const s4 = h.quitStreak(q, [relapse("2026-08-20"), relapse("2026-09-30"), done(TODAY), urge(TODAY, 3)], TODAY);
  check("relapses before start / after today ignored; done/urge ignored", s4.current === 25, s4);
  check("future start → 0", h.quitStreak({ startDate: "2026-10-01" }, [], TODAY).current === 0);
  check("relapse value 0 ignored", h.quitStreak(q, [relapse("2026-09-20", 0)], TODAY).current === 25);
  check("cleanStreakBefore (relapse flow): 'sempat bersih 24 hari'", h.cleanStreakBefore(q, [relapse(TODAY)], TODAY) === 24);
  check("cleanStreakBefore after earlier relapse", h.cleanStreakBefore(q, [relapse("2026-09-20")], TODAY) === 4);
  check("start day itself: 1 day clean", h.quitStreak({ startDate: TODAY }, [], TODAY).current === 1);
}

console.log("milestones");
check("isQuitMilestone", h.isQuitMilestone(7) && h.isQuitMilestone(365) && !h.isQuitMilestone(8) && h.isQuitMilestone(400) && h.isQuitMilestone(500) && !h.isQuitMilestone(465));
check("nextQuitMilestone", h.nextQuitMilestone(0) === 1 && h.nextQuitMilestone(7) === 14 && h.nextQuitMilestone(365) === 400 && h.nextQuitMilestone(401) === 500);
check("quitMilestonesReached(410)", eq(h.quitMilestonesReached(410), [1, 3, 7, 14, 21, 30, 40, 60, 90, 120, 180, 270, 365, 400]));

console.log("completion rate");
{
  const r = h.completionRate(daily, [done("2026-09-20"), done("2026-09-21"), skip("2026-09-22"), done("2026-09-24")], "2026-09-19", TODAY, TODAY);
  // 19 missed, 20 met, 21 met, 22 skip (excluded), 23 missed, 24 met, 25 pending (excluded)
  check("daily: 3 met / 5 scheduled", r.met === 3 && r.total === 5 && Math.abs(r.rate - 0.6) < 1e-9, r);
  const r2 = h.completionRate(daily, [done(TODAY)], TODAY, TODAY, TODAY);
  check("today counts once met", r2.met === 1 && r2.total === 1);
  check("range before start → null", h.completionRate(daily, [], "2026-08-01", "2026-08-10", TODAY).rate === null);
  const pw = { ...daily, schedule: { type: "perWeek", times: 2 }, startDate: "2026-09-07" };
  const r3 = h.completionRate(pw, [done("2026-09-07"), done("2026-09-08"), done("2026-09-15")], "2026-09-07", TODAY, TODAY);
  check("perWeek: weeks met/judged (current week pending excluded)", r3.met === 1 && r3.total === 2, r3);
  const q = { kind: "quit", schedule: { type: "daily" }, target: { type: "check" }, startDate: "2026-09-16" };
  const r4 = h.completionRate(q, [relapse("2026-09-20")], "2026-09-01", TODAY, TODAY);
  check("quit: clean days / days since start", r4.met === 9 && r4.total === 10, r4);
}

console.log("skips + today");
{
  check("canSkip: max 2 per rolling 7 days", h.canSkip([skip("2026-09-20"), skip("2026-09-23")], TODAY) === false &&
    h.canSkip([skip("2026-09-18"), skip("2026-09-23")], TODAY) === true && h.canSkip([skip("2026-09-17"), skip("2026-09-30")], TODAY) === true &&
    h.canSkip([skip(TODAY), skip("2026-09-23")], TODAY) === true && h.canSkip([skip("2026-09-26"), skip("2026-09-27")], TODAY) === false);
  const t = h.habitToday({ ...daily, target: { type: "count", goal: 8, unit: "gelas" } }, [done(TODAY, 5)], TODAY);
  check("habitToday count progress", t.progress === 5 && t.goal === 8 && !t.met && t.scheduled, t);
  const q = { kind: "quit", schedule: { type: "daily" }, target: { type: "check" }, startDate: "2026-09-01" };
  const t2 = h.habitToday(q, [urge(TODAY, 2), done(TODAY)], TODAY);
  check("habitToday quit: urges + clean check-in, streak", t2.urges === 2 && t2.cleanCheckIn && t2.streak.current === 25 && !t2.met, t2);
  const t3 = h.habitToday({ ...daily, schedule: { type: "weekdays", days: [1] } }, [], TODAY);
  check("weekdays habit not scheduled on Friday", t3.scheduled === false);
}

console.log("insights");
{
  const q = { kind: "quit", schedule: { type: "daily" }, target: { type: "check" }, startDate: "2026-09-01" };
  const logs = [
    relapse("2026-09-18", 2, { at: "2026-09-18T15:30:00Z", triggers: ["malam", "Bosan"], note: "susah tidur" }), // Fri 22:30 WIB
    relapse("2026-09-21", 1, { at: "2026-09-21T16:00:00Z", triggers: ["bosan"] }), // Mon 23:00 WIB
    urge("2026-09-22", 3, { at: "2026-09-22T13:00:00Z", triggers: ["stres"] }), // Tue 20:00 WIB
    urge("2026-09-23", 1, { triggers: ["bosan"] }),
    done("2026-09-24"),
  ];
  const ins = h.habitInsights(q, logs, { from: "2026-09-15", to: TODAY, today: TODAY });
  check("relapse totals weighted by value", ins.relapses.total === 3 && ins.relapses.days === 2, ins.relapses);
  check("relapse by weekday (Mon=0): Fri 2, Mon 1", ins.relapses.byWeekday[4] === 2 && ins.relapses.byWeekday[0] === 1);
  check("relapse by hour in WIB: 22 → 2, 23 → 1", ins.relapses.byHour[22] === 2 && ins.relapses.byHour[23] === 1);
  check("urges: total 4, hour 20 → 3, unknown hour 1", ins.urges.total === 4 && ins.urges.byHour[20] === 3 && ins.urges.unknownHour === 1, ins.urges);
  check("top triggers merged case-insensitively", eq(ins.topTriggers, [{ tag: "Bosan", count: 4 }, { tag: "stres", count: 3 }, { tag: "malam", count: 2 }]), ins.topTriggers);
  check("journal", ins.journal.length === 1 && ins.journal[0].note === "susah tidur");
  check("heatmap quit statuses", ins.heatmap.length === 11 && ins.heatmap.find((d) => d.date === "2026-09-18").status === "relapse" &&
    ins.heatmap.find((d) => d.date === "2026-09-19").status === "clean" && ins.heatmap.find((d) => d.date === "2026-09-22").urges === 3);
  check("segments overlapping range", ins.segments.length === 3 && ins.segments[2].ongoing && ins.streak.current === 4, ins.segments);
  const ins2 = h.habitInsights(q, logs, { from: "2026-09-15", to: TODAY, today: TODAY, timeZone: "UTC" });
  check("timeZone option (UTC hours)", ins2.relapses.byHour[15] === 2);
  const bi = h.habitInsights(daily, [done("2026-09-24"), skip("2026-09-23")], { from: "2026-09-22", to: "2026-09-26", today: TODAY });
  check("build heatmap statuses", eq(bi.heatmap.map((d) => d.status), ["missed", "skip", "met", "pending", "future"]), bi.heatmap.map((d) => d.status));
}

check("maskedHabitName", h.maskedHabitName({ name: "PMO", private: true }) === "Kebiasaan pribadi" && h.maskedHabitName({ name: "Baca", private: false }) === "Baca");

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
