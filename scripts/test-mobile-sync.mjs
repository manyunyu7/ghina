#!/usr/bin/env node
// End-to-end test of the mobile API (docs/mobile-sync.md) against a running server.
//
//   npm run dev -- -p 3100          # in another terminal (or any running instance)
//   node scripts/test-mobile-sync.mjs [baseUrl]   # default http://localhost:3100
//
// Creates throwaway users (mobile-test-*@example.test) and deletes them at the end.
// Also exercises the web delete / reset helpers directly (via jiti) to confirm they
// write tombstones and rotate the sync epoch. Also covers tasks/areas and transaction photos.
import { randomUUID } from "node:crypto";
import http from "node:http";
import { existsSync } from "node:fs";
import { mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { PrismaClient } from "@prisma/client";
import { createJiti } from "jiti";

const BASE = process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:3100";
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const prisma = new PrismaClient();

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

async function api(method, path, { token, body, form } = {}) {
  const headers = {};
  if (token) headers.authorization = `Bearer ${token}`;
  let payload;
  if (form) payload = form;
  else if (body !== undefined) {
    headers["content-type"] = "application/json";
    payload = typeof body === "string" ? body : JSON.stringify(body);
  }
  const res = await fetch(BASE + path, { method, headers, body: payload });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    // not JSON
  }
  return { status: res.status, json, text };
}

const now = () => new Date().toISOString();
const ago = (ms) => new Date(Date.now() - ms).toISOString();
const mut = (entity, entityId, data, clientUpdatedAt = now()) => ({
  id: randomUUID(),
  entity,
  op: "upsert",
  entityId,
  data,
  clientUpdatedAt,
});
const del = (entity, entityId, clientUpdatedAt = now()) => ({
  id: randomUUID(),
  entity,
  op: "delete",
  entityId,
  clientUpdatedAt,
});
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const statuses = (r) => r.json?.results?.map((x) => x.status);
const byId = (rows, id) => rows.find((r) => r.id === id);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const createdEmails = [];
const resetCtx = {};

async function main() {
  console.log(`Testing ${BASE}`);
  const email = `mobile-test-${Date.now()}@example.test`;
  const emailB = `mobile-test-b-${Date.now()}@example.test`;
  createdEmails.push(email, emailB);

  // ---------- Auth ----------
  console.log("auth");
  let r = await api("POST", "/api/mobile/auth/register", { body: { name: "Tester", email, password: "short" } });
  check("register rejects short password (400)", r.status === 400, r.json);
  r = await api("POST", "/api/mobile/auth/register", { body: { name: "Tester", email, password: "password123" } });
  check("register → token + user", r.status === 200 && r.json.token && r.json.user.email === email, r.json);
  const user = r.json.user;
  check("user has syncEpoch", typeof user.syncEpoch === "string" && user.syncEpoch.length > 0);
  r = await api("POST", "/api/mobile/auth/register", { body: { name: "Tester", email, password: "password123" } });
  check("register duplicate email → 409", r.status === 409, r.json);
  r = await api("POST", "/api/mobile/auth/login", { body: { email, password: "wrongpass" } });
  check("login wrong password → 401", r.status === 401 && r.json.error, r.json);
  r = await api("POST", "/api/mobile/auth/login", { body: { email, password: "password123" } });
  check("login → token", r.status === 200 && r.json.token, r.json);
  const token = r.json.token;
  r = await api("POST", "/api/mobile/auth/login", { body: "{not json" });
  check("malformed JSON → 400", r.status === 400, r.json);

  r = await api("GET", "/api/mobile/me");
  check("me without token → 401 {error:unauthorized}", r.status === 401 && r.json?.error === "unauthorized", r.json);
  r = await api("GET", "/api/mobile/me", { token: token + "x" });
  check("me with bad token → 401", r.status === 401, r.json);
  r = await api("GET", "/api/mobile/sync", {});
  check("sync without token → 401 (not a /login redirect)", r.status === 401, r.status);
  r = await api("GET", "/api/mobile/me", { token });
  check("me → user", r.status === 200 && r.json.user.id === user.id, r.json);
  r = await api("PATCH", "/api/mobile/me", { token, body: { currency: "USD", name: "Tester 2" } });
  check("PATCH me", r.status === 200 && r.json.user.currency === "USD" && r.json.user.name === "Tester 2", r.json);
  r = await api("PATCH", "/api/mobile/me", { token, body: { currency: "XXX" } });
  check("PATCH me invalid currency → 400", r.status === 400, r.json);

  // ---------- Full pull ----------
  console.log("full pull");
  r = await api("GET", "/api/mobile/sync", { token });
  check("full pull ok", r.status === 200, r.json);
  const full = r.json;
  check("epoch matches user", full.epoch === user.syncEpoch, full.epoch);
  check("starter wallet present", full.changes.wallets.length === 1 && full.changes.wallets[0].name === "Cash");
  check("default categories present", full.changes.categories.length >= 10, full.changes.categories.length);
  check("all 17 entity keys present", Object.keys(full.changes).length === 17 &&
    ["taskAreas", "tasks", "noteLabels", "notes", "socialAccounts", "contentPillars", "contentItems", "contentPosts"].every((k) => Array.isArray(full.changes[k])), Object.keys(full.changes));
  {
    const areas = full.changes.taskAreas;
    const kerja = byId(areas, `area-kerjaan-${user.id}`);
    const life = byId(areas, `area-life-${user.id}`);
    check("first sync seeds default areas with deterministic ids", areas.length === 2 && kerja && life, areas);
    check("seeded Kerjaan: KERJA, schedule as JSON object",
      kerja?.code === "KERJA" && kerja.color === "#1CB0F6" && JSON.stringify(kerja.schedule) === '{"days":[1,2,3,4,5],"start":"09:00","end":"17:00"}', kerja);
    check("seeded Keseharian: LIFE, schedule null, home icon", life?.code === "LIFE" && life.schedule === null && life.icon === "home" && life.sortOrder === 1, life);
    check("area wire shape", kerja && ["id", "name", "code", "color", "icon", "schedule", "sortOrder", "archived", "createdAt", "updatedAt"].every((f) => f in kerja) && !("userId" in kerja), kerja);
    const again = (await api("GET", "/api/mobile/sync", { token })).json;
    check("second pull does not seed again", again.changes.taskAreas.length === 2, again.changes.taskAreas.length);
  }
  check("full pull has no tombstones", Array.isArray(full.deleted) && full.deleted.length === 0);
  check("serverTime ≈ now − 5s", Math.abs(Date.now() - 5000 - full.serverTime) < 3000, full.serverTime);
  const w0 = full.changes.wallets[0];
  check("wallet shape (numbers/bools/ISO dates, no userId)",
    typeof w0.balance === "number" && typeof w0.archived === "boolean" && /Z$/.test(w0.createdAt) && !("userId" in w0) && !("editedAt" in w0),
    w0);
  let cursor = full.serverTime;

  // ---------- Push creates ----------
  console.log("push creates");
  const W1 = randomUUID(), W2 = randomUUID(), C = randomUUID(), T1 = randomUUID(), T2 = randomUUID(), T3 = randomUUID();
  const P1 = randomUUID(), B1 = randomUUID(), H1 = randomUUID(), F1 = randomUUID(), S1 = randomUUID(), PL1 = randomUUID();
  const wallet = (name, balance) => ({ name, type: "bank", balance, currency: "IDR", color: "#6366f1", icon: "bank", archived: false });
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: {
      epoch: user.syncEpoch,
      mutations: [
        mut("wallets", W1, wallet("Main", 1000)),
        mut("wallets", W2, wallet("Savings", 0)),
        mut("categories", C, { name: "Test cat", type: "expense", color: "#ef4444", icon: "utensils" }),
        mut("transactions", T1, { walletId: W1, toWalletId: null, categoryId: C, type: "expense", amount: 100, note: "lunch", date: now() }),
        mut("transactions", T2, { walletId: W1, toWalletId: null, categoryId: null, type: "income", amount: 50, note: null, date: now() }),
        mut("transactions", T3, { walletId: W1, toWalletId: W2, categoryId: C, type: "transfer", amount: 300, note: "save", date: now() }),
        mut("prayers", P1, { date: "2026-09-23", prayer: "subuh" }),
        mut("budgets", B1, { categoryId: C, amount: 500000, month: 9, year: 2026 }),
        mut("health", H1, { date: now(), weight: 70.5, systolic: 120, diastolic: 80, pulse: 70, note: "am" }),
        mut("food", F1, { date: now(), name: "Nasi goreng", meal: "lunch", calories: 650.4, photoUrl: null, note: null }),
        mut("subscriptions", S1, { name: "Netflix", amount: 186000, currency: "IDR", cycle: "monthly", nextBilling: now(), categoryId: C, walletId: W1, color: "#ef4444", icon: "film", note: null, active: true }),
        mut("planned", PL1, { type: "expense", amount: 20000, note: "gift", categoryId: C, walletId: W2, date: now(), done: false }),
      ],
    },
  });
  check("push creates all applied", r.status === 200 && statuses(r).every((s) => s === "applied"), r.json);
  check("push serverTime present", typeof r.json.serverTime === "number");
  const renameAt = now(); // a client edit made after the create, before the edits below

  r = await api("GET", `/api/mobile/sync?since=${cursor}`, { token });
  let pull = r.json;
  check("incremental pull ok", r.status === 200, r.json);
  check("W1 balance = 1000 − 100 + 50 − 300 = 650", byId(pull.changes.wallets, W1)?.balance === 650, byId(pull.changes.wallets, W1));
  check("W2 balance = 300 (transfer in)", byId(pull.changes.wallets, W2)?.balance === 300, byId(pull.changes.wallets, W2));
  check("transfer carries no category", byId(pull.changes.transactions, T3)?.categoryId === null);
  check("transactions carry photos: [] by default (old clients)", Array.isArray(byId(pull.changes.transactions, T1)?.photos) && byId(pull.changes.transactions, T1).photos.length === 0, byId(pull.changes.transactions, T1));
  check("prayer pulled with updatedAt", !!byId(pull.changes.prayers, P1)?.updatedAt);
  check("food calories rounded to int", byId(pull.changes.food, F1)?.calories === 650);
  check("created rows keep client ids",
    [["transactions", T1], ["budgets", B1], ["health", H1], ["subscriptions", S1], ["planned", PL1], ["categories", C]].every(([e, id]) => byId(pull.changes[e], id)));
  // Let the 5 s cursor overlap pass, then take a cursor that is past all the creates.
  await sleep(5500);
  const cursor2 = (await api("GET", `/api/mobile/sync?since=${pull.serverTime}`, { token })).json.serverTime;

  // ---------- Edits / deletes ----------
  console.log("edit + delete");
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: {
      mutations: [
        mut("transactions", T1, { walletId: W1, toWalletId: null, categoryId: C, type: "expense", amount: 200, note: "lunch+", date: now() }),
        del("transactions", T2),
        // Wallet edited before those transactions on the client: still applies (editedAt-based LWW).
        mut("wallets", W1, { ...wallet("Main renamed", 999999), color: "#22c55e" }, renameAt),
      ],
    },
  });
  check("edit/delete/rename applied", JSON.stringify(statuses(r)) === '["applied","applied","applied"]', r.json);
  r = await api("GET", `/api/mobile/sync?since=${cursor2}`, { token });
  pull = r.json;
  const w1 = byId(pull.changes.wallets, W1);
  check("W1 balance = 650 − 100 (edit) − 50 (delete income) = 500", w1?.balance === 500, w1);
  check("wallet rename applied, balance on update ignored", w1?.name === "Main renamed" && w1?.color === "#22c55e", w1);
  check("edited tx in changes", byId(pull.changes.transactions, T1)?.amount === 200);
  check("tombstone for deleted tx", pull.deleted.some((d) => d.entity === "transactions" && d.id === T2 && /Z$/.test(d.deletedAt)), pull.deleted);
  check("unchanged rows not re-sent", pull.changes.prayers.length === 0 && pull.changes.health.length === 0, pull.changes.prayers);
  check("no id in both changes and deleted",
    !pull.deleted.some((d) => pull.changes[d.entity]?.some((row) => row.id === d.id)));

  // ---------- LWW / duplicates / validation ----------
  console.log("conflicts");
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: {
      mutations: [
        mut("transactions", T1, { walletId: W1, toWalletId: null, categoryId: C, type: "expense", amount: 1, note: "stale", date: now() }, ago(3600_000)),
        mut("prayers", randomUUID(), { date: "2026-09-23", prayer: "subuh" }),
        mut("budgets", randomUUID(), { categoryId: C, amount: 1, month: 9, year: 2026 }),
        mut("transactions", randomUUID(), { walletId: W1, type: "expense", amount: -5, date: now() }),
        mut("transactions", randomUUID(), { walletId: W1, toWalletId: W1, type: "transfer", amount: 5, date: now() }),
        mut("prayers", randomUUID(), { date: "2026-9-1", prayer: "subuh" }),
        { id: "bad-1", entity: "nope", op: "upsert", entityId: "x", clientUpdatedAt: now() },
        del("food", randomUUID()),
        mut("food", F1, { date: now(), name: "Nasi goreng", photoUrl: "/uploads/../../.env" }),
        mut("transactions", T2, { walletId: W1, type: "income", amount: 50, date: now() }, ago(3600_000)),
      ],
    },
  });
  const st = statuses(r);
  check("stale edit → skipped", st?.[0] === "skipped", r.json?.results?.[0]);
  check("duplicate prayer → duplicate", st?.[1] === "duplicate", r.json?.results?.[1]);
  check("duplicate budget → duplicate", st?.[2] === "duplicate", r.json?.results?.[2]);
  check("negative amount → rejected", st?.[3] === "rejected" && r.json.results[3].error, r.json?.results?.[3]);
  check("transfer to same wallet → rejected", st?.[4] === "rejected" && /differ/.test(r.json.results[4].error), r.json?.results?.[4]);
  check("bad prayer date → rejected", st?.[5] === "rejected", r.json?.results?.[5]);
  check("unknown entity → rejected (id echoed)", st?.[6] === "rejected" && r.json.results[6].id === "bad-1", r.json?.results?.[6]);
  check("delete of missing row → applied", st?.[7] === "applied", r.json?.results?.[7]);
  check("path-traversal photoUrl → rejected", st?.[8] === "rejected", r.json?.results?.[8]);
  check("re-create of row deleted later → skipped", st?.[9] === "skipped", r.json?.results?.[9]);
  const t1row = await prisma.transaction.findUnique({ where: { id: T1 } });
  check("skipped edit left server row alone", t1row?.amount === 200);
  const w1row = await prisma.wallet.findUnique({ where: { id: W1 } });
  check("rejected mutations did not move balances", w1row?.balance === 500, w1row?.balance);

  // ---------- Foreign ownership ----------
  console.log("ownership");
  r = await api("POST", "/api/mobile/auth/register", { body: { name: "Other", email: emailB, password: "password123" } });
  const tokenB = r.json.token;
  const userBId = r.json.user.id;
  r = await api("POST", "/api/mobile/sync", {
    token: tokenB,
    body: {
      mutations: [
        mut("wallets", W1, wallet("hijack", 0)),
        mut("transactions", randomUUID(), { walletId: W1, type: "expense", amount: 10, date: now() }),
        del("transactions", T1),
        mut("budgets", randomUUID(), { categoryId: C, amount: 10, month: 1, year: 2027 }),
      ],
    },
  });
  check("upsert of another user's wallet → rejected", statuses(r)?.[0] === "rejected", r.json?.results?.[0]);
  check("tx on another user's wallet → rejected", statuses(r)?.[1] === "rejected" && /Wallet not found/.test(r.json.results[1].error), r.json?.results?.[1]);
  check("delete of another user's tx → rejected", statuses(r)?.[2] === "rejected", r.json?.results?.[2]);
  check("budget on another user's category → rejected", statuses(r)?.[3] === "rejected", r.json?.results?.[3]);
  check("A's wallet untouched", (await prisma.wallet.findUnique({ where: { id: W1 } }))?.name === "Main renamed");

  // ---------- Upload ----------
  console.log("upload");
  const png = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
    "base64",
  );
  let form = new FormData();
  form.append("file", new Blob([png], { type: "image/png" }), "pixel.png");
  r = await api("POST", "/api/mobile/upload", { token, form });
  check("upload image → url", r.status === 200 && /^\/uploads\/[\w-]+\.png$/.test(r.json?.url), r.json);
  const photoUrl = r.json?.url;
  const img = await fetch(BASE + photoUrl);
  check("uploaded file is served", img.status === 200, img.status);
  form = new FormData();
  form.append("file", new Blob(["hello"], { type: "text/plain" }), "a.txt");
  r = await api("POST", "/api/mobile/upload", { token, form });
  check("upload non-image → 400", r.status === 400, r.json);
  // The type comes from the bytes, not the client's MIME type / name.
  const svg = '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"/>';
  for (const [body, type, name, label] of [
    [svg, "image/svg+xml", "x.svg", "SVG"],
    [svg, "image/png", "x.png", "SVG disguised as PNG"],
    ["<html><script>alert(1)</script></html>", "image/jpeg", "x.jpg", "HTML disguised as JPEG"],
  ]) {
    form = new FormData();
    form.append("file", new Blob([body], { type }), name);
    r = await api("POST", "/api/mobile/upload", { token, form });
    check(`upload ${label} → 400`, r.status === 400, r.json);
  }
  form = new FormData();
  form.append("file", new Blob([png], { type: "image/jpeg" }), "wrong.jpg");
  r = await api("POST", "/api/mobile/upload", { token, form });
  check("PNG bytes sent as image/jpeg → stored as .png", r.status === 200 && /\.png$/.test(r.json?.url), r.json);
  const sniffed = [r.json?.url];
  form = new FormData();
  form.append("file", new Blob([png], { type: "application/octet-stream" }), "blob");
  r = await api("POST", "/api/mobile/upload", { token, form });
  check("PNG bytes with a generic MIME type → accepted", r.status === 200 && /\.png$/.test(r.json?.url), r.json);
  sniffed.push(r.json?.url);
  for (const u of sniffed.filter(Boolean)) await rm(join(root, "public", u), { force: true });
  r = await api("POST", "/api/mobile/upload", { form: new FormData() });
  check("upload without token → 401", r.status === 401, r.json);
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: { mutations: [mut("food", F1, { date: now(), name: "Nasi goreng", meal: "lunch", calories: 650, photoUrl, note: "with photo" })] },
  });
  check("food upsert with photoUrl applied", statuses(r)?.[0] === "applied", r.json);

  // ---------- Cascades via sync ----------
  console.log("cascades");
  const cursor3 = Date.now() - 1000;
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [del("categories", C), del("wallets", W2), del("food", F1)] } });
  check("category + wallet + food delete applied", statuses(r)?.every((s) => s === "applied"), r.json);
  const photoGone = await fetch(BASE + photoUrl);
  check("deleted food's photo removed", photoGone.status === 404, photoGone.status);
  r = await api("GET", `/api/mobile/sync?since=${cursor3}`, { token });
  pull = r.json;
  const deleted = (e, id) => pull.deleted.some((d) => d.entity === e && d.id === id);
  check("category tombstone", deleted("categories", C));
  check("budget of category tombstoned", deleted("budgets", B1));
  check("wallet tombstone", deleted("wallets", W2));
  check("transfer into deleted wallet tombstoned", deleted("transactions", T3));
  check("tx categoryId nulled and re-sent", byId(pull.changes.transactions, T1)?.categoryId === null, byId(pull.changes.transactions, T1));
  const sub = byId(pull.changes.subscriptions, S1);
  check("subscription categoryId nulled", sub && sub.categoryId === null && sub.walletId === W1, sub);
  const pl = byId(pull.changes.planned, PL1);
  check("planned categoryId + walletId nulled", pl && pl.categoryId === null && pl.walletId === null, pl);
  check("W1 balance unchanged by cascade (500)", (await prisma.wallet.findUnique({ where: { id: W1 } }))?.balance === 500);

  // ---------- Prayer quality (docs/prayer-quality.md) ----------
  console.log("prayer quality");
  const P2 = randomUUID(), P3 = randomUUID(), P4 = randomUUID(), P5 = randomUUID();
  const prayerAt = "2026-09-20T05:10:00.000Z";
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: {
      mutations: [
        // Old client: date + prayer only → defaults.
        mut("prayers", P2, { date: "2026-09-20", prayer: "dzuhur" }),
        // New client: full fields.
        mut("prayers", P3, { date: "2026-09-20", prayer: "subuh", status: "masjid", qobliyah: true, badiyah: false, rakaat: null, prayedAt: prayerAt, note: "  di masjid  " }),
        mut("prayers", P4, { date: "2026-09-20", prayer: "dhuha", rakaat: 4 }),
        mut("prayers", P5, { date: "2026-09-20", prayer: "maghrib", status: "missed", qobliyah: false, badiyah: false }),
      ],
    },
  });
  check("prayer upserts (old + new clients) applied", JSON.stringify(statuses(r)) === '["applied","applied","applied","applied"]', r.json);
  let prow = await prisma.prayerEntry.findUnique({ where: { id: P2 } });
  check("old-client fardhu row defaults to ontime, no rawatib", prow?.status === "ontime" && !prow.qobliyah && !prow.badiyah && prow.rakaat === null);
  prow = await prisma.prayerEntry.findUnique({ where: { id: P3 } });
  check("new fields stored (status, qobliyah, prayedAt, trimmed note)",
    prow?.status === "masjid" && prow.qobliyah === true && prow.prayedAt?.toISOString() === prayerAt && prow.note === "di masjid", prow);
  prow = await prisma.prayerEntry.findUnique({ where: { id: P4 } });
  check("sunnah row defaults to done, rakaat kept", prow?.status === "done" && prow.rakaat === 4, prow);
  check("pre-existing prayer row reads as ontime", (await prisma.prayerEntry.findUnique({ where: { id: P1 } }))?.status === "ontime");

  // Old client re-pushing the row without the new fields keeps the stored quality.
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [mut("prayers", P3, { date: "2026-09-20", prayer: "subuh" })] } });
  prow = await prisma.prayerEntry.findUnique({ where: { id: P3 } });
  check("old-client update keeps status/rawatib/note", statuses(r)?.[0] === "applied" && prow?.status === "masjid" && prow.qobliyah && prow.note === "di masjid", prow);
  // Switching to missed while rawatib are ticked must be sent with rawatib cleared.
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: { mutations: [mut("prayers", P3, { date: "2026-09-20", prayer: "subuh", status: "missed" })] },
  });
  check("status → missed while stored qobliyah=true → rejected", statuses(r)?.[0] === "rejected", r.json);
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: { mutations: [mut("prayers", P3, { date: "2026-09-20", prayer: "subuh", status: "missed", qobliyah: false, prayedAt: null, note: "" })] },
  });
  prow = await prisma.prayerEntry.findUnique({ where: { id: P3 } });
  check("status → missed with rawatib cleared, null prayedAt/note", statuses(r)?.[0] === "applied" && prow?.status === "missed" && !prow.qobliyah && prow.prayedAt === null && prow.note === null, prow);

  const pbad = (data) => mut("prayers", randomUUID(), { date: "2026-09-21", ...data });
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: {
      mutations: [
        pbad({ prayer: "isya", status: "bogus" }),
        pbad({ prayer: "ashar", status: "jamaah", qobliyah: true }),
        pbad({ prayer: "subuh", status: "jamaah", badiyah: true }),
        pbad({ prayer: "dzuhur", status: "missed", qobliyah: true }),
        pbad({ prayer: "maghrib", status: "excused", badiyah: true }),
        pbad({ prayer: "dhuha", rakaat: 3 }),
        pbad({ prayer: "witir", rakaat: 2 }),
        pbad({ prayer: "tahajud", rakaat: 14 }),
        pbad({ prayer: "dhuha", status: "jamaah" }),
        pbad({ prayer: "isya", status: "jamaah", rakaat: 4 }),
        pbad({ prayer: "jumat" }),
        pbad({ prayer: "isya", prayedAt: "2026-09-21T19:00:00" }),
        pbad({ prayer: "tahajud", qobliyah: true }),
        pbad({ prayer: "witir", rakaat: 3, status: "done" }),
        pbad({ prayer: "dzuhur", status: "qadha", qobliyah: true, badiyah: true }),
        { ...pbad({ prayer: "isya", status: "excused" }), data: { date: "2026-02-30", prayer: "isya" } },
      ],
    },
  });
  const ps = statuses(r) ?? [];
  const expectReject = ["unknown status", "ashar qobliyah", "subuh ba'diyah", "rawatib + missed", "rawatib + excused",
    "dhuha 3 rakaat", "witir 2 rakaat", "tahajud 14 rakaat", "sunnah with fardhu status", "rakaat on fardhu",
    "unknown prayer id", "prayedAt without offset", "rawatib on sunnah"];
  expectReject.forEach((name, i) => check(`prayer ${name} → rejected`, ps[i] === "rejected" && r.json.results[i].error, r.json?.results?.[i]));
  check("witir 3 rakaat → applied", ps[13] === "applied", r.json?.results?.[13]);
  check("dzuhur qadha + both rawatib → applied", ps[14] === "applied", r.json?.results?.[14]);
  check("impossible date 2026-02-30 → rejected", ps[15] === "rejected", r.json?.results?.[15]);

  r = await api("GET", `/api/mobile/sync?since=${cursor2}`, { token });
  const pulledP3 = byId(r.json.changes.prayers, P3);
  const pulledP4 = byId(r.json.changes.prayers, P4);
  check("pulled prayer has all new wire fields",
    pulledP3 && ["status", "qobliyah", "badiyah", "rakaat", "prayedAt", "note"].every((f) => f in pulledP3) && pulledP4?.rakaat === 4 && pulledP4?.status === "done",
    pulledP3);

  // ---------- Balance adjustments (docs/balance-adjustment.md) ----------
  console.log("balance adjustments");
  const W3 = randomUUID(), A1 = randomUUID(), A2 = randomUUID();
  const bal = async (id) => (await prisma.wallet.findUnique({ where: { id } }))?.balance;
  const adj = (amount, extra = {}) => ({ walletId: W3, toWalletId: null, categoryId: null, type: "adjustment", amount, note: "Penyesuaian saldo", date: now(), ...extra });
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: { mutations: [mut("wallets", W3, wallet("Adjust me", 1000)), mut("transactions", A1, adj(500)), mut("transactions", A2, adj(-200))] },
  });
  check("adjustments applied", statuses(r)?.every((x) => x === "applied"), r.json);
  check("W3 = 1000 + 500 − 200 = 1300", (await bal(W3)) === 1300, await bal(W3));
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [mut("transactions", A1, adj(100))] } });
  check("edit adjustment +500 → +100: W3 = 900", statuses(r)?.[0] === "applied" && (await bal(W3)) === 900, await bal(W3));
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [del("transactions", A2)] } });
  check("delete −200 adjustment restores: W3 = 1100", statuses(r)?.[0] === "applied" && (await bal(W3)) === 1100, await bal(W3));
  const catInc = full.changes.categories.find((c) => c.type === "income");
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: {
      mutations: [
        mut("transactions", randomUUID(), adj(0)),
        mut("transactions", randomUUID(), adj(50, { categoryId: catInc.id })),
        mut("transactions", randomUUID(), adj(50, { toWalletId: W1 })),
        mut("transactions", randomUUID(), adj("abc")),
      ],
    },
  });
  check("adjustment amount 0 → rejected", statuses(r)?.[0] === "rejected", r.json?.results?.[0]);
  check("adjustment with category → rejected", statuses(r)?.[1] === "rejected" && /category/.test(r.json.results[1].error), r.json?.results?.[1]);
  check("adjustment with toWalletId → rejected", statuses(r)?.[2] === "rejected" && /destination/.test(r.json.results[2].error), r.json?.results?.[2]);
  check("adjustment non-numeric amount → rejected", statuses(r)?.[3] === "rejected", r.json?.results?.[3]);
  check("rejected adjustments did not move W3", (await bal(W3)) === 1100);
  r = await api("GET", `/api/mobile/sync?since=${cursor2}`, { token });
  const pa = byId(r.json.changes.transactions, A1);
  check("pulled adjustment keeps type + signed amount", pa?.type === "adjustment" && pa.amount === 100 && pa.categoryId === null && pa.toWalletId === null, pa);

  // Web wallet edit path (ledger helper the server action calls).
  {
    const jitiA = createJiti(import.meta.url, { alias: { "@": join(root, "src") } });
    const { adjustWalletBalance } = await jitiA.import(join(root, "src/lib/ledger.ts"));
    const t1 = await prisma.$transaction((db) => adjustWalletBalance(db, user.id, W3, 1250.5, { currency: "IDR", note: "cek kas" }));
    check("web edit 1100 → 1250.5 creates +150.5 adjustment", t1?.type === "adjustment" && t1.amount === 150.5 && (await bal(W3)) === 1250.5, t1);
    check("adjustment note default + user note", /^Penyesuaian saldo: .*1\.100.* → .*1\.25\d.* — cek kas$/.test(t1?.note ?? ""), t1?.note);
    const t2 = await prisma.$transaction((db) => adjustWalletBalance(db, user.id, W3, 1250.5 + 1e-9, { currency: "IDR" }));
    check("unchanged balance → no adjustment row", t2 === null);
    const t3 = await prisma.$transaction((db) => adjustWalletBalance(db, user.id, W3, 0, { currency: "IDR" }));
    check("web edit to 0 → negative adjustment", t3?.amount === -1250.5 && (await bal(W3)) === 0, t3);
    let threw = false;
    try {
      await prisma.$transaction((db) => adjustWalletBalance(db, user.id, W3 + "x", 5, { currency: "IDR" }));
    } catch {
      threw = true;
    }
    check("adjusting a foreign/missing wallet throws", threw);
    // Excluded from income/expense aggregates.
    const { getMonthlyTotals, monthRange } = await jitiA.import(join(root, "src/lib/queries.ts"));
    const d0 = new Date();
    const before = await getMonthlyTotals(user.id, monthRange(d0.getFullYear(), d0.getMonth() + 1));
    await prisma.$transaction((db) => adjustWalletBalance(db, user.id, W3, 999999, { currency: "IDR" }));
    const after = await getMonthlyTotals(user.id, monthRange(d0.getFullYear(), d0.getMonth() + 1));
    check("adjustments excluded from monthly income/expense totals", JSON.stringify(before) === JSON.stringify(after), { before, after });
  }

  // ---------- Task areas (docs/tasks.md) ----------
  console.log("task areas");
  const KERJA = `area-kerjaan-${user.id}`;
  const AR1 = randomUUID();
  const areaData = (o = {}) => ({ name: "Kuliah", code: "kuliah", color: "#123456", icon: "graduation-cap", schedule: { days: [6, 1, 1], start: "08:00", end: "12:00" }, sortOrder: 2, archived: false, ...o });
  const cursorT = Date.now() - 1000;
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: {
      mutations: [
        mut("taskAreas", AR1, areaData()),
        mut("taskAreas", randomUUID(), areaData({ name: "Other", code: "KULIAH" })),
        mut("taskAreas", randomUUID(), areaData({ code: "TOO-LONG!" })),
        mut("taskAreas", randomUUID(), areaData({ code: "OK1", schedule: { days: [1], start: "17:00", end: "09:00" } })),
        mut("taskAreas", randomUUID(), areaData({ code: "OK2", icon: "rocket" })),
        mut("taskAreas", randomUUID(), areaData({ code: "OK3", name: "" })),
        mut("taskAreas", randomUUID(), areaData({ code: "OK4", schedule: "{\"days\":[1]}" })),
      ],
    },
  });
  let ts = statuses(r) ?? [];
  check("area create applied", ts[0] === "applied", r.json?.results?.[0]);
  check("area with a code another id holds → duplicate", ts[1] === "duplicate", r.json?.results?.[1]);
  ["bad code", "schedule start ≥ end", "unknown icon", "empty name", "schedule as string"].forEach((n, i) =>
    check(`area ${n} → rejected`, ts[i + 2] === "rejected" && r.json.results[i + 2].error, r.json?.results?.[i + 2]));
  let arow = await prisma.taskArea.findUnique({ where: { id: AR1 } });
  check("area code stored uppercase, schedule normalized JSON", arow?.code === "KULIAH" && arow.schedule === '{"days":[1,6],"start":"08:00","end":"12:00"}', arow);
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [mut("taskAreas", AR1, areaData({ name: "Kuliah S2", schedule: null, archived: true }))] } });
  arow = await prisma.taskArea.findUnique({ where: { id: AR1 } });
  check("area update (rename, clear schedule, archive)", statuses(r)?.[0] === "applied" && arow?.name === "Kuliah S2" && arow.schedule === null && arow.archived, arow);
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [mut("taskAreas", KERJA, { name: "Kerjaan", code: "KERJA", color: "#1CB0F6", icon: "briefcase", schedule: { days: [1, 2, 3, 4, 5], start: "09:00", end: "17:00" }, sortOrder: 0, archived: false }, ago(3600_000))] } });
  check("device re-seeding the default area with an older timestamp → skipped (no duplicate)", statuses(r)?.[0] === "skipped" && (await prisma.taskArea.count({ where: { userId: user.id, code: "KERJA" } })) === 1, r.json);

  // ---------- Tasks ----------
  console.log("tasks");
  const TW = randomUUID(), TC = randomUUID(), TCI = randomUUID(), TK1 = randomUUID(), TK2 = randomUUID(), TXE = randomUUID();
  const taskData = (o = {}) => ({
    areaId: KERJA, title: "Bayar listrik", note: "  token PLN  ", bucket: "fire", dueDate: "2026-01-31", dueTime: "09:00", remindBefore: 30,
    recurrence: { freq: "monthly", interval: 1 }, seriesId: null, done: false, doneAt: null, sortOrder: 1.5, amount: 250000,
    walletId: TW, categoryId: TC, transactionId: null, ...o,
  });
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: {
      mutations: [
        mut("wallets", TW, wallet("Task wallet", 1_000_000)),
        mut("categories", TC, { name: "Listrik", type: "expense", color: "#ef4444", icon: "zap" }),
        mut("categories", TCI, { name: "Bonus", type: "income", color: "#22c55e", icon: "gift" }),
        mut("tasks", TK1, taskData()),
        mut("tasks", TK2, { areaId: AR1, title: "Baca jurnal" }),
      ],
    },
  });
  check("task creates applied (full + minimal)", statuses(r)?.every((x) => x === "applied"), r.json);
  let trow = await prisma.task.findUnique({ where: { id: TK1 } });
  check("recurring task: seriesId = own id, monthDay materialized, note trimmed",
    trow?.seriesId === TK1 && trow.recurrence === '{"freq":"monthly","interval":1,"monthDay":31}' && trow.note === "token PLN" && trow.sortOrder === 1.5, trow);
  trow = await prisma.task.findUnique({ where: { id: TK2 } });
  check("minimal task defaults (want, undone, no due)", trow?.bucket === "want" && !trow.done && trow.dueDate === null && trow.recurrence === null && trow.seriesId === null, trow);

  r = await api("POST", "/api/mobile/sync", {
    token,
    body: {
      mutations: [
        mut("tasks", randomUUID(), taskData({ areaId: randomUUID() })),
        mut("tasks", randomUUID(), taskData({ categoryId: TCI })),
        mut("tasks", randomUUID(), taskData({ dueDate: null, dueTime: "09:00", recurrence: null })),
        mut("tasks", randomUUID(), taskData({ dueDate: null, dueTime: null })),
        mut("tasks", randomUUID(), taskData({ bucket: "later" })),
        mut("tasks", randomUUID(), taskData({ title: "   " })),
        mut("tasks", randomUUID(), taskData({ dueDate: "2026-02-30" })),
        mut("tasks", randomUUID(), taskData({ recurrence: { freq: "daily", interval: 1, monthDay: 3 } })),
        mut("tasks", randomUUID(), taskData({ amount: -5 })),
        mut("tasks", randomUUID(), taskData({ transactionId: randomUUID() })),
        mut("tasks", randomUUID(), taskData({ walletId: W1 + "x" })),
        mut("tasks", randomUUID(), taskData({ recurrence: "{\"freq\":\"daily\"}" })),
        mut("tasks", randomUUID(), taskData({ done: true, doneAt: "2026-01-31T10:00:00" })),
        mut("tasks", randomUUID(), taskData({ remindBefore: 99999 })),
      ],
    },
  });
  ts = statuses(r) ?? [];
  ["unknown area", "income category", "dueTime without dueDate", "recurrence without dueDate", "unknown bucket", "blank title", "impossible date",
    "monthDay on daily rule", "negative amount", "unknown transaction", "unknown wallet", "recurrence as string", "doneAt without offset", "remindBefore > 7 days"]
    .forEach((n, i) => check(`task ${n} → rejected`, ts[i] === "rejected" && r.json.results[i].error, r.json?.results?.[i]));
  check("task unknown area → 'Area not found'", /Area not found/.test(r.json?.results?.[0]?.error ?? ""), r.json?.results?.[0]);

  // Complete a recurring occurrence offline with the money link: expense, done upsert, next occurrence.
  const doneAt = "2026-01-31T10:00:00.000Z";
  const NEXT = `${TK1}_20260228`;
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: {
      mutations: [
        mut("transactions", TXE, { walletId: TW, toWalletId: null, categoryId: TC, type: "expense", amount: 250000, note: "Bayar listrik", date: now(), photos: [] }),
        mut("tasks", TK1, taskData({ done: true, doneAt, transactionId: TXE, seriesId: TK1 })),
        mut("tasks", NEXT, taskData({ dueDate: "2026-02-28", seriesId: TK1, recurrence: { freq: "monthly", interval: 1, monthDay: 31 } })),
      ],
    },
  });
  check("complete: expense + done + next occurrence applied", statuses(r)?.every((x) => x === "applied"), r.json);
  trow = await prisma.task.findUnique({ where: { id: TK1 } });
  check("done task stores doneAt + transactionId", trow?.done && trow.doneAt?.toISOString() === doneAt && trow.transactionId === TXE, trow);
  check("expense moved the task wallet (1,000,000 − 250,000)", (await prisma.wallet.findUnique({ where: { id: TW } }))?.balance === 750000);
  // Device B completed the same occurrence offline, earlier → its next-occurrence upsert is skipped.
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: { mutations: [mut("tasks", NEXT, taskData({ dueDate: "2026-02-28", seriesId: TK1, note: "device B" }), ago(60_000))] },
  });
  check("same deterministic next id from another device (older) → skipped", statuses(r)?.[0] === "skipped", r.json);
  // …or newer → applied as an update of the same row.
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: { mutations: [mut("tasks", NEXT, taskData({ dueDate: "2026-02-28", seriesId: TK1, recurrence: { freq: "monthly", interval: 1, monthDay: 31 } }))] },
  });
  check("same next id (newer) → applied, still one row per occurrence",
    statuses(r)?.[0] === "applied" && (await prisma.task.count({ where: { seriesId: TK1 } })) === 2, r.json);
  r = await api("GET", `/api/mobile/sync?since=${cursorT}`, { token });
  const pt = byId(r.json.changes.tasks, TK1);
  check("task wire shape: recurrence object, doneAt ISO, all fields",
    pt && JSON.stringify(pt.recurrence) === '{"freq":"monthly","interval":1,"monthDay":31}' && pt.doneAt === doneAt && pt.done === true &&
    ["id", "areaId", "title", "note", "bucket", "dueDate", "dueTime", "remindBefore", "recurrence", "seriesId", "done", "doneAt", "sortOrder", "amount", "walletId", "categoryId", "transactionId", "createdAt", "updatedAt"].every((f) => f in pt) && !("userId" in pt),
    pt);
  check("pulled next occurrence", byId(r.json.changes.tasks, NEXT)?.dueDate === "2026-02-28");
  check("pulled areas include created area", byId(r.json.changes.taskAreas, AR1)?.code === "KULIAH");

  // Ownership: other user can't touch tasks/areas or use A's area.
  r = await api("POST", "/api/mobile/sync", {
    token: tokenB,
    body: { mutations: [mut("tasks", randomUUID(), taskData({ areaId: KERJA, walletId: null, categoryId: null })), mut("tasks", TK2, { areaId: KERJA, title: "hijack" }), del("taskAreas", AR1)] },
  });
  check("task in another user's area → rejected", statuses(r)?.[0] === "rejected", r.json?.results?.[0]);
  check("upsert/delete another user's task/area → rejected", statuses(r)?.[1] === "rejected" && statuses(r)?.[2] === "rejected", r.json);
  {
    // The delete helpers themselves are user-scoped (defense in depth, not just the callers).
    const jitiD = createJiti(import.meta.url, { alias: { "@": join(root, "src") } });
    const sd = await jitiD.import(join(root, "src/lib/sync-deletes.ts"));
    const tasksBefore = await prisma.task.count({ where: { userId: user.id } });
    const tombsBefore = await prisma.syncTombstone.count();
    const aWallet = await prisma.wallet.findFirst({ where: { userId: user.id } });
    const aCat = await prisma.category.findFirst({ where: { userId: user.id } });
    await prisma.$transaction((db) => sd.deleteTaskAreaCascade(db, userBId, AR1));
    await prisma.$transaction((db) => sd.deleteWalletCascade(db, userBId, aWallet.id));
    await prisma.$transaction((db) => sd.deleteCategoryCascade(db, userBId, aCat.id));
    await sd.deleteSynced(userBId, "tasks", TK2);
    await sd.deleteSynced(userBId, "taskAreas", AR1);
    check("cascade helpers with a foreign user id delete nothing, write no tombstone",
      (await prisma.taskArea.count({ where: { id: AR1 } })) === 1 && (await prisma.task.count({ where: { userId: user.id } })) === tasksBefore &&
      (await prisma.wallet.count({ where: { id: aWallet.id } })) === 1 && (await prisma.category.count({ where: { id: aCat.id } })) === 1 &&
      (await prisma.syncTombstone.count()) === tombsBefore);
  }

  // ---------- Task cascades ----------
  console.log("task cascades");
  const cursorC = Date.now() - 1000;
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [del("transactions", TXE)] } });
  trow = await prisma.task.findUnique({ where: { id: TK1 } });
  check("delete transaction → task.transactionId null", statuses(r)?.[0] === "applied" && trow?.transactionId === null, trow);
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [del("categories", TC), del("wallets", TW)] } });
  trow = await prisma.task.findUnique({ where: { id: TK1 } });
  check("delete category/wallet → task refs null", statuses(r)?.every((x) => x === "applied") && trow?.categoryId === null && trow.walletId === null, trow);
  r = await api("GET", `/api/mobile/sync?since=${cursorC}`, { token });
  const pc = byId(r.json.changes.tasks, TK1);
  check("nulled task re-sent in changes", pc && pc.transactionId === null && pc.walletId === null && pc.categoryId === null, pc);
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [del("taskAreas", AR1)] } });
  r = await api("GET", `/api/mobile/sync?since=${cursorC}`, { token });
  check("delete area → area + its tasks tombstoned",
    r.json.deleted.some((d) => d.entity === "taskAreas" && d.id === AR1) && r.json.deleted.some((d) => d.entity === "tasks" && d.id === TK2) &&
    (await prisma.task.count({ where: { id: TK2 } })) === 0, r.json.deleted);
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [mut("tasks", TK2, { areaId: KERJA, title: "zombie" }, ago(60_000))] } });
  check("stale upsert of cascaded-deleted task → skipped", statuses(r)?.[0] === "skipped", r.json);
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [del("tasks", NEXT)] } });
  check("task delete applied + tombstone", statuses(r)?.[0] === "applied" && (await prisma.syncTombstone.count({ where: { entity: "tasks", entityId: NEXT } })) === 1);

  // ---------- Transaction photos (docs/transaction-photos.md) ----------
  console.log("transaction photos");
  const upload = async () => {
    const f = new FormData();
    f.append("file", new Blob([png], { type: "image/png" }), "p.png");
    return (await api("POST", "/api/mobile/upload", { token, form: f })).json?.url;
  };
  const exists = async (u) => (await fetch(BASE + u)).status === 200;
  const [u1, u2, u3, u4] = [await upload(), await upload(), await upload(), await upload()];
  const TP = randomUUID(), TP2 = randomUUID(), TP3 = randomUUID();
  const txp = (photos, extra = {}) => ({ walletId: W1, toWalletId: null, categoryId: null, type: "expense", amount: 10, note: "struk", date: now(), ...(photos === undefined ? {} : { photos }), ...extra });
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [mut("transactions", TP, txp([u1, u2]))] } });
  check("tx with 2 photos applied", statuses(r)?.[0] === "applied", r.json);
  let prow2 = await prisma.transaction.findUnique({ where: { id: TP } });
  check("photos stored as JSON array", prow2?.photos === JSON.stringify([u1, u2]), prow2?.photos);
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [mut("transactions", TP, txp(undefined, { amount: 11 }))] } });
  prow2 = await prisma.transaction.findUnique({ where: { id: TP } });
  check("old client update without photos keeps them", statuses(r)?.[0] === "applied" && prow2?.photos === JSON.stringify([u1, u2]) && prow2.amount === 11, prow2);
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [mut("transactions", TP, txp([u2, u3]))] } });
  check("photo list change applied", statuses(r)?.[0] === "applied", r.json);
  check("removed photo file deleted, kept/new files stay", !(await exists(u1)) && (await exists(u2)) && (await exists(u3)));
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: {
      mutations: [
        mut("transactions", randomUUID(), txp(["a1", "a2", "a3", "a4", "a5", "a6"].map((n) => `/uploads/${n}.png`))),
        mut("transactions", randomUUID(), txp(["/uploads/../../.env"])),
        mut("transactions", randomUUID(), txp(u4)),
        mut("transactions", randomUUID(), txp(["https://evil.example/a.png"])),
        mut("transactions", TP, txp([u2, u3, "/uploads/a.png", "/uploads/b.png", "/uploads/c.png", "/uploads/d.png"])),
      ],
    },
  });
  ts = statuses(r) ?? [];
  ["more than 5 photos", "path traversal", "photos not an array", "absolute URL", "update to 6 photos"].forEach((n, i) =>
    check(`photos ${n} → rejected`, ts[i] === "rejected" && r.json.results[i].error, r.json?.results?.[i]));
  check("rejected photo updates deleted nothing", (await exists(u2)) && (await exists(u3)) && (await exists(u4)));
  // A duplicated transaction sharing a photo: deleting one keeps the file.
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [mut("transactions", TP2, txp([u3, u4]))] } });
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [del("transactions", TP)] } });
  check("delete tx → its unshared photo removed, shared one kept", statuses(r)?.[0] === "applied" && !(await exists(u2)) && (await exists(u3)));
  r = await api("GET", `/api/mobile/sync?since=${cursorC}`, { token });
  check("pulled photos is an array of URLs", JSON.stringify(byId(r.json.changes.transactions, TP2)?.photos) === JSON.stringify([u3, u4]), byId(r.json.changes.transactions, TP2));
  // Wallet delete cascade removes its transactions' photos.
  const WP = randomUUID();
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [mut("wallets", WP, wallet("Photo wallet", 0)), mut("transactions", TP3, txp([u4], { walletId: WP })), del("transactions", TP2)] } });
  check("TP2 deleted but u4 still used by TP3", statuses(r)?.every((x) => x === "applied") && !(await exists(u3)) && (await exists(u4)), r.json);
  r = await api("POST", "/api/mobile/sync", { token, body: { mutations: [del("wallets", WP)] } });
  check("wallet cascade delete removes its transactions' photos", statuses(r)?.[0] === "applied" && !(await exists(u4)));

  // ---------- Web task helpers (lib code the server actions call) ----------
  console.log("web task helpers");
  const jitiT = createJiti(import.meta.url, { alias: { "@": join(root, "src") } });
  const ts2 = await jitiT.import(join(root, "src/lib/tasks-server.ts"));
  check("ensureDefaultTaskAreas is a no-op when areas exist", (await ts2.ensureDefaultTaskAreas(prisma, user.id)) === 0);
  const series = await prisma.task.create({ data: { userId: user.id, areaId: KERJA, title: "Standup", dueDate: "2026-09-25", recurrence: '{"freq":"weekly","interval":1,"weekdays":[1,3,5]}', seriesId: null } });
  const n1 = await prisma.$transaction((db) => ts2.createNextOccurrence(db, user.id, series));
  const n1b = await prisma.$transaction((db) => ts2.createNextOccurrence(db, user.id, series));
  const nrow = await prisma.task.findUnique({ where: { id: n1 } });
  check("createNextOccurrence: Fri → Mon, deterministic, idempotent",
    n1 === `${series.id}_20260928` && n1b === n1 && nrow?.seriesId === series.id && !nrow.done && (await prisma.task.count({ where: { OR: [{ id: series.id }, { seriesId: series.id }] } })) === 2, nrow);
  let threw = null;
  try {
    await prisma.$transaction((db) => ts2.saveTask(db, user.id, randomUUID(), { areaId: KERJA, title: "x", categoryId: TCI }, false));
  } catch (e) {
    threw = e;
  }
  check("saveTask rejects an income category with TaskError", threw instanceof ts2.TaskError, threw?.message);

  // ---------- Web server actions (auth + next/cache stubbed) ----------
  console.log("web task + transaction actions");
  {
    const stubDir = await mkdtemp(join(tmpdir(), "ghina-stubs-"));
    await writeFile(join(stubDir, "auth.mjs"), "export async function requireUser() { return globalThis.__ghinaTestUser; }\n");
    await writeFile(join(stubDir, "cache.mjs"), "export function revalidatePath() {}\n");
    globalThis.__ghinaTestUser = await prisma.user.findUnique({ where: { id: user.id } });
    const jitiW = createJiti(import.meta.url, {
      alias: { "@/lib/auth-helpers": join(stubDir, "auth.mjs"), "next/cache": join(stubDir, "cache.mjs"), "@": join(root, "src") },
      moduleCache: false,
    });
    const ta = await jitiW.import(join(root, "src/app/(dashboard)/tasks/actions.ts"));
    const txa = await jitiW.import(join(root, "src/app/(dashboard)/transactions/actions.ts"));
    const wW = await prisma.wallet.create({ data: { userId: user.id, name: "Action wallet", balance: 500 } });
    const expCat = await prisma.category.findFirst({ where: { userId: user.id, type: "expense" } });

    let a = await ta.createTaskArea({ name: "Bisnis", code: "biz", schedule: { days: [6], start: "10:00", end: "14:00" } });
    check("action createTaskArea", a.ok && (await prisma.taskArea.findUnique({ where: { id: a.id } }))?.code === "BIZ", a);
    const areaId = a.id;
    a = await ta.createTaskArea({ name: "Dup", code: "BIZ" });
    check("action createTaskArea duplicate code → error", !a.ok && /already used/.test(a.error), a);
    a = await ta.updateTaskArea(areaId, { schedule: { days: [6], start: "14:00", end: "10:00" } });
    check("action updateTaskArea invalid schedule → error", !a.ok, a);
    a = await ta.updateTaskArea(areaId, { name: "Bisnis 2", archived: true });
    const ar = await prisma.taskArea.findUnique({ where: { id: areaId } });
    check("action updateTaskArea patch keeps other fields", a.ok && ar.name === "Bisnis 2" && ar.archived && ar.code === "BIZ" && ar.schedule !== null, ar);

    let c = await ta.createTask({ areaId, title: "Bayar hosting", bucket: "fire", dueDate: "2026-09-30", recurrence: { freq: "monthly", interval: 1 }, amount: 120, walletId: wW.id, categoryId: expCat.id });
    check("action createTask (recurring, money link)", c.ok, c);
    const tId = c.id;
    let tr = await prisma.task.findUnique({ where: { id: tId } });
    check("created task: seriesId = id, monthDay 30, sortOrder after last", tr?.seriesId === tId && tr.recurrence === '{"freq":"monthly","interval":1,"monthDay":30}' && tr.sortOrder === 0, tr);
    c = await ta.createTask({ areaId, title: "Second", bucket: "fire" });
    check("second task sorted after first", c.ok && (await prisma.task.findUnique({ where: { id: c.id } }))?.sortOrder === 1);
    const t2 = c.id;
    c = await ta.createTask({ areaId, title: "" });
    check("action createTask blank title → error", !c.ok && c.error, c);
    c = await ta.updateTask(tId, { dueTime: "08:00", remindBefore: 10 });
    tr = await prisma.task.findUnique({ where: { id: tId } });
    check("action updateTask patch", c.ok && tr.dueTime === "08:00" && tr.remindBefore === 10 && tr.title === "Bayar hosting" && tr.amount === 120, tr);

    c = await ta.completeTask(tId, { recordExpense: true });
    tr = await prisma.task.findUnique({ where: { id: tId } });
    check("action completeTask: done + next occurrence + expense", c.ok && tr.done && tr.doneAt && c.nextId === `${tId}_20261030` && c.transactionId && tr.transactionId === c.transactionId, c);
    const nx = await prisma.task.findUnique({ where: { id: `${tId}_20261030` } });
    check("next occurrence copies fields, undone, unlinked", nx && !nx.done && nx.dueTime === "08:00" && nx.amount === 120 && nx.transactionId === null && nx.seriesId === tId, nx);
    const etx = await prisma.transaction.findUnique({ where: { id: c.transactionId } });
    check("expense: amount/wallet/category/note from task, balance 500 → 380",
      etx?.type === "expense" && etx.amount === 120 && etx.categoryId === expCat.id && etx.note === "Bayar hosting" && (await prisma.wallet.findUnique({ where: { id: wW.id } })).balance === 380, etx);
    c = await ta.completeTask(tId, { recordExpense: true });
    check("completing again: no second expense / occurrence", c.ok && c.nextId === null && (await prisma.transaction.count({ where: { walletId: wW.id } })) === 1 && (await prisma.task.count({ where: { seriesId: tId } })) === 2, c);
    c = await ta.uncompleteTask(tId, { deleteExpense: true });
    tr = await prisma.task.findUnique({ where: { id: tId } });
    check("uncompleteTask + deleteExpense: undone, expense reversed, next kept",
      c.ok && !tr.done && tr.doneAt === null && tr.transactionId === null && (await prisma.wallet.findUnique({ where: { id: wW.id } })).balance === 500 && (await prisma.task.count({ where: { seriesId: tId } })) === 2, tr);
    c = await ta.completeTask(tId);
    check("re-complete without expense reuses the existing next occurrence", c.ok && c.nextId === `${tId}_20261030` && c.transactionId === null && (await prisma.task.count({ where: { seriesId: tId } })) === 2, c);
    c = await ta.completeTask(t2, { recordExpense: {} });
    check("completeTask with expense but no amount/wallet → error, task untouched", !c.ok && !(await prisma.task.findUnique({ where: { id: t2 } })).done, c);

    c = await ta.reorderTasks({ areaId: KERJA, bucket: "should" }, [t2, tId]);
    const [r1, r2] = [await prisma.task.findUnique({ where: { id: t2 } }), await prisma.task.findUnique({ where: { id: tId } })];
    check("reorderTasks moves into cell with index order", c.ok && r1.areaId === KERJA && r1.bucket === "should" && r1.sortOrder === 0 && r2.sortOrder === 1, [r1, r2]);
    c = await ta.reorderTasks({ areaId: KERJA, bucket: "should" }, [t2, randomUUID()]);
    check("reorderTasks with a foreign id → error", !c.ok);
    c = await ta.moveTask(t2, { bucket: "fire", sortOrder: 0.5 });
    check("moveTask", c.ok && (await prisma.task.findUnique({ where: { id: t2 } })).bucket === "fire");
    c = await ta.reorderTaskAreas([areaId, KERJA]);
    check("reorderTaskAreas", c.ok && (await prisma.taskArea.findUnique({ where: { id: areaId } })).sortOrder === 0 && (await prisma.taskArea.findUnique({ where: { id: KERJA } })).sortOrder === 1);
    c = await ta.deleteTask(t2);
    check("deleteTask tombstones", c.ok && (await prisma.syncTombstone.count({ where: { entity: "tasks", entityId: t2 } })) === 1);
    const t3 = (await ta.createTask({ areaId, title: "in area" })).id;
    c = await ta.deleteTaskArea(areaId);
    check("deleteTaskArea cascades tasks with tombstones", c.ok && (await prisma.task.count({ where: { id: t3 } })) === 0 && (await prisma.syncTombstone.count({ where: { entity: "tasks", entityId: t3 } })) === 1);
    c = await ta.ensureDefaultAreas();
    check("ensureDefaultAreas no-op when areas exist", c.ok && c.created === 0, c);

    // Transaction photos through the web form actions.
    const pngFile = (n) => new File([png], `${n}.png`, { type: "image/png" });
    const uploadsDir = join(root, "public");
    const onDisk = async (u) => existsSync(join(uploadsDir, u));
    const fd = (o, files = [], keep = null) => {
      const f = new FormData();
      for (const [k, v] of Object.entries(o)) f.append(k, v);
      for (const file of files) f.append("photos", file);
      if (keep) {
        f.append("photosManaged", "1");
        for (const u of keep) f.append("keepPhotos", u);
      }
      return f;
    };
    const base = { type: "expense", amount: "25", walletId: wW.id, date: "2026-09-24", note: "struk" };
    await txa.createTransaction(fd(base, [pngFile("a"), pngFile("b")]));
    let wtx = await prisma.transaction.findFirst({ where: { walletId: wW.id, note: "struk" } });
    const wp = JSON.parse(wtx.photos);
    check("web createTransaction saves 2 photos", wp.length === 2 && (await onDisk(wp[0])) && (await onDisk(wp[1])), wtx.photos);
    await txa.updateTransaction(fd({ ...base, id: wtx.id, amount: "30" }));
    wtx = await prisma.transaction.findUnique({ where: { id: wtx.id } });
    check("web update without photo UI keeps photos", wtx.amount === 30 && JSON.parse(wtx.photos).length === 2);
    await txa.updateTransaction(fd({ ...base, id: wtx.id }, [pngFile("c")], [wp[1], "/uploads/not-mine.png"]));
    wtx = await prisma.transaction.findUnique({ where: { id: wtx.id } });
    const wp2 = JSON.parse(wtx.photos);
    check("web update keep+add: [kept, new], foreign keep ignored, removed file deleted",
      wp2.length === 2 && wp2[0] === wp[1] && !(await onDisk(wp[0])) && (await onDisk(wp2[1])), wp2);
    let err = null;
    try {
      await txa.updateTransaction(fd({ ...base, id: wtx.id }, [1, 2, 3, 4].map((i) => pngFile(`x${i}`)), wp2));
    } catch (e) {
      err = e;
    }
    const filesNow = (await readdir(join(uploadsDir, "uploads"))).length;
    check("web update over 5 photos → throws, nothing changed", err && /At most 5/.test(err.message) && JSON.parse((await prisma.transaction.findUnique({ where: { id: wtx.id } })).photos).length === 2, err?.message);
    await txa.deleteTransaction(fd({ id: wtx.id }));
    check("web deleteTransaction removes photo files", !(await onDisk(wp2[0])) && !(await onDisk(wp2[1])) && (await readdir(join(uploadsDir, "uploads"))).length === filesNow - 2);
    await rm(stubDir, { recursive: true, force: true });
  }

  await notesAndContent({ user, token, tokenB, userBId, KERJA, W1, png, upload, exists });

  // Leave a wallet + photo transaction + linked task for the reset check below.
  const WR = randomUUID(), TR = randomUUID(), TKR = randomUUID();
  const uR = await upload();
  const uR2 = await upload(); // shared by the transaction and a note
  const NR = randomUUID(), IR = randomUUID();
  r = await api("POST", "/api/mobile/sync", {
    token,
    body: {
      mutations: [
        mut("wallets", WR, wallet("Reset me", 0)),
        mut("transactions", TR, txp([uR, uR2], { walletId: WR })),
        mut("tasks", TKR, { areaId: KERJA, title: "linked", walletId: WR, transactionId: TR, amount: 10 }),
        mut("notes", NR, { title: "struk", photos: [uR2], linkedTransactionId: TR }),
        mut("contentItems", IR, { title: "endorse", sponsor: { brand: "B", amount: 10, paid: true, transactionId: TR } }),
      ],
    },
  });
  check("reset fixture applied", statuses(r)?.every((x) => x === "applied"), r.json);
  resetCtx.taskId = TKR;
  resetCtx.photo = uR;
  resetCtx.sharedPhoto = uR2;
  resetCtx.noteId = NR;
  resetCtx.itemId = IR;

  // ---------- Web helpers (same code the server actions call) ----------
  console.log("web deletes / reset");
  const jiti = createJiti(import.meta.url, { alias: { "@": join(root, "src") } });
  const { deleteSynced, resetFinanceData } = await jiti.import(join(root, "src/lib/sync-deletes.ts"));
  const { createLedgerTransaction } = await jiti.import(join(root, "src/lib/ledger.ts"));
  const webWallet = await prisma.wallet.create({ data: { userId: user.id, name: "Web", balance: 100 } });
  const webTx = await prisma.$transaction((db) =>
    createLedgerTransaction(db, user.id, { walletId: webWallet.id, toWalletId: null, categoryId: null, type: "expense", amount: 40, note: null, date: new Date() }),
  );
  check("web ledger create moves balance", (await prisma.wallet.findUnique({ where: { id: webWallet.id } }))?.balance === 60);
  await deleteSynced(user.id, "transactions", webTx.id);
  check("web tx delete reverses balance", (await prisma.wallet.findUnique({ where: { id: webWallet.id } }))?.balance === 100);
  const prayer = await prisma.prayerEntry.create({ data: { userId: user.id, date: "2026-09-22", prayer: "isya" } });
  await deleteSynced(user.id, "prayers", prayer.id);
  await deleteSynced(user.id, "wallets", webWallet.id);
  const tombs = await prisma.syncTombstone.findMany({ where: { userId: user.id, entityId: { in: [webTx.id, prayer.id, webWallet.id] } } });
  check("web deletes write tombstones (tx, prayer, wallet)", tombs.length === 3, tombs.map((t) => t.entity));

  await resetFinanceData(user.id);
  const after = await prisma.user.findUnique({ where: { id: user.id } });
  check("reset rotates syncEpoch", after.syncEpoch !== user.syncEpoch);
  check("reset wiped wallets", (await prisma.wallet.count({ where: { userId: user.id } })) === 0);
  {
    const tr = await prisma.task.findUnique({ where: { id: resetCtx.taskId } });
    check("reset keeps tasks + areas, nulls wallet/category/transaction links",
      tr && tr.walletId === null && tr.categoryId === null && tr.transactionId === null && (await prisma.taskArea.count({ where: { userId: user.id } })) >= 2, tr);
    check("reset removed transaction photo files", (await fetch(BASE + resetCtx.photo)).status === 404);
    const nr = await prisma.note.findUnique({ where: { id: resetCtx.noteId } });
    const ir = await prisma.contentItem.findUnique({ where: { id: resetCtx.itemId } });
    check("reset keeps notes + content, nulls note/sponsor transaction links (paid kept)",
      nr && nr.linkedTransactionId === null && ir && JSON.parse(ir.sponsor).transactionId === null && JSON.parse(ir.sponsor).paid === true &&
      (await prisma.contentPillar.count({ where: { userId: user.id } })) > 0, { nr, ir });
    check("reset keeps a transaction photo a note still uses", (await fetch(BASE + resetCtx.sharedPhoto)).status === 200);
  }
  r = await api("POST", "/api/mobile/sync", { token, body: { epoch: user.syncEpoch, mutations: [mut("wallets", randomUUID(), wallet("zombie", 0))] } });
  check("push with old epoch → 409 + new epoch, nothing applied", r.status === 409 && r.json.epoch === after.syncEpoch, r.json);
  check("zombie wallet not created", (await prisma.wallet.count({ where: { userId: user.id } })) === 0);
  r = await api("GET", `/api/mobile/sync?since=${cursor3}`, { token });
  check("pull reports new epoch", r.json.epoch === after.syncEpoch);
}

// ---------- Notes + content planner (docs/notes.md, docs/content.md) ----------
async function notesAndContent({ user, token, tokenB, userBId, KERJA, W1, png, upload, exists }) {
  const push = async (mutations, tk = token) => api("POST", "/api/mobile/sync", { token: tk, body: { mutations } });
  const pullSince = async (c, tk = token) => (await api("GET", `/api/mobile/sync?since=${c}`, { token: tk })).json;
  const jitiL = createJiti(import.meta.url, { alias: { "@": join(root, "src") } });
  const ns = await jitiL.import(join(root, "src/lib/notes-server.ts"));
  const cs = await jitiL.import(join(root, "src/lib/content-server.ts"));
  const IDEA = `label-ide-konten-${user.id}`;
  let r;

  console.log("notes/content: seeding");
  r = await api("GET", "/api/mobile/sync", { token });
  const idea = byId(r.json.changes.noteLabels, IDEA);
  check("full pull seeds `Ide Konten` (deterministic id, pinned tab)", idea?.name === "Ide Konten" && idea.pinnedTab === true && r.json.changes.noteLabels.length === 1, r.json.changes.noteLabels);
  const pillarIds = ["edukasi", "hiburan", "promo", "bts", "personal"].map((k) => `pillar-${k}-${user.id}`);
  check("full pull seeds 5 default pillars (deterministic ids, order)",
    r.json.changes.contentPillars.length === 5 && pillarIds.every((id, i) => byId(r.json.changes.contentPillars, id)?.sortOrder === i) &&
    byId(r.json.changes.contentPillars, pillarIds[3]).name === "Behind the scene", r.json.changes.contentPillars);
  check("label/pillar wire shape", idea && eq(Object.keys(idea), ["id", "name", "color", "pinnedTab", "sortOrder", "createdAt", "updatedAt"]), idea);
  check("seeding is idempotent (helpers + second pull)",
    (await ns.ensureDefaultNoteLabel(prisma, user.id)) === 0 && (await cs.ensureDefaultContentPillars(prisma, user.id)) === 0 &&
    (await api("GET", "/api/mobile/sync", { token })).json.changes.contentPillars.length === 5 &&
    (await prisma.noteLabel.count({ where: { userId: user.id } })) === 1);
  r = await api("GET", "/api/mobile/sync", { token: tokenB });
  check("other user gets their own seeded label", byId(r.json.changes.noteLabels, `label-ide-konten-${userBId}`) && r.json.changes.noteLabels.length === 1);

  console.log("notes/content: uploads (audio)");
  const m4a = Buffer.concat([Buffer.from([0, 0, 0, 0x20]), Buffer.from("ftypM4A "), Buffer.alloc(256)]);
  const ogg = Buffer.concat([Buffer.from("OggS"), Buffer.alloc(256)]);
  const up = async (bytes, type, name) => {
    const f = new FormData();
    f.append("file", new Blob([bytes], { type }), name);
    return api("POST", "/api/mobile/upload", { token, form: f });
  };
  r = await up(m4a, "application/octet-stream", "rec");
  check("upload m4a (generic MIME) → .m4a, kind audio", r.status === 200 && /^\/uploads\/[\w-]+\.m4a$/.test(r.json?.url) && r.json.kind === "audio", r.json);
  const a1 = r.json?.url;
  r = await up(ogg, "audio/ogg", "v.opus");
  check("upload ogg/opus → .ogg", r.status === 200 && /\.ogg$/.test(r.json?.url), r.json);
  const a2 = r.json?.url;
  r = await up(png, "audio/mp4", "fake.m4a");
  check("image bytes sent as audio → stored as image (kind image)", r.status === 200 && /\.png$/.test(r.json?.url) && r.json.kind === "image", r.json);
  await rm(join(root, "public", r.json?.url ?? "/nope"), { force: true });
  r = await up("<html><script>alert(1)</script></html>", "audio/mp4", "x.m4a");
  check("HTML disguised as audio → 400", r.status === 400, r.json);
  r = await up(Buffer.concat([m4a, Buffer.alloc(21 * 1024 * 1024)]), "audio/mp4", "big.m4a");
  check("audio > 20 MB → 400", r.status === 400 && /20 MB/.test(r.json?.error ?? ""), r.json);
  r = await up(Buffer.concat([png, Buffer.alloc(6 * 1024 * 1024)]), "image/png", "big.png");
  check("image > 5 MB still → 400", r.status === 400 && /5 MB/.test(r.json?.error ?? ""), r.json);
  check("uploaded audio is served", await exists(a1));

  console.log("notes/content: labels + notes sync");
  const L1 = randomUUID(), N1 = randomUUID();
  r = await push([
    mut("noteLabels", L1, { name: "Kerjaan", color: "#1CB0F6", pinnedTab: true, sortOrder: 1 }),
    mut("noteLabels", randomUUID(), { name: " kerjaan " }),
    mut("noteLabels", randomUUID(), { name: "IDE konten" }),
    mut("noteLabels", randomUUID(), { name: "" }),
  ]);
  check("labels: created / case-insensitive duplicate ×2 / blank rejected", eq(statuses(r), ["applied", "duplicate", "duplicate", "rejected"]), r.json);
  const [p1, p2, p3] = [await upload(), await upload(), await upload()];
  const noteData = (extra = {}) => ({
    title: "Ide video",
    body: "Script di https://contoh.invalid/a dan [b](https://contoh.invalid/b).",
    checklist: [{ id: "c1", text: "Rekam", done: false }],
    labels: [L1, IDEA, "no-such-label"],
    color: "yellow",
    pinned: true,
    archived: false,
    photos: [p1, p2],
    audio: [{ url: a1, durationSec: 12.5, transcript: "halo" }, { url: a2, durationSec: 3 }],
    links: [],
    source: "quick",
    linkedTaskId: null,
    linkedContentId: null,
    linkedTransactionId: null,
    ...extra,
  });
  const cursorN = Date.now() - 1000;
  r = await push([mut("notes", N1, noteData())]);
  check("note upsert applied", statuses(r)?.[0] === "applied", r.json);
  let nrow = await prisma.note.findUnique({ where: { id: N1 } });
  check("unknown label id dropped, JSON columns stored as text", nrow?.labels === JSON.stringify([L1, IDEA]) && nrow.photos === JSON.stringify([p1, p2]), nrow);
  check("body URLs extracted into links", eq(JSON.parse(nrow.links), [{ url: "https://contoh.invalid/a", title: null }, { url: "https://contoh.invalid/b", title: null }]), nrow.links);
  let pn = byId((await pullSince(cursorN)).changes.notes, N1);
  const NOTE_FIELDS = ["id", "title", "body", "checklist", "labels", "color", "pinned", "archived", "photos", "audio", "links", "source", "linkedTaskId", "linkedContentId", "linkedTransactionId", "createdAt", "updatedAt"];
  check("note wire: exact fields (no userId/editedAt)", pn && eq(Object.keys(pn), NOTE_FIELDS), pn && Object.keys(pn));
  check("note wire: JSON fields as JSON values", Array.isArray(pn?.checklist) && Array.isArray(pn.labels) && Array.isArray(pn.photos) && eq(pn.audio[1], { url: a2, durationSec: 3, transcript: null }) && Array.isArray(pn.links) && pn.color === "yellow", pn);

  r = await push([
    mut("notes", randomUUID(), noteData({ checklist: "[]" })),
    mut("notes", randomUUID(), noteData({ photos: Array.from({ length: 11 }, (_, i) => `/uploads/x${i}.png`) })),
    mut("notes", randomUUID(), noteData({ photos: [a1] })),
    mut("notes", randomUUID(), noteData({ color: "#ff0000" })),
    mut("notes", randomUUID(), noteData({ audio: [{ url: a1, durationSec: 700 }] })),
    mut("notes", randomUUID(), noteData({ body: "x".repeat(50001) })),
    mut("notes", randomUUID(), noteData({ labels: "x" })),
    mut("notes", randomUUID(), noteData({ links: [{ url: "javascript:alert(1)" }] })),
    mut("notes", randomUUID(), noteData({ photos: ["/uploads/../../.env"] })),
  ]);
  ["checklist as string", "11 photos", "audio url as photo", "color outside palette", "clip > 10 min", "body > 50 000", "labels not array", "javascript: link", "path traversal"].forEach((name, i) =>
    check(`note ${name} → rejected`, statuses(r)?.[i] === "rejected" && r.json.results[i].error, r.json?.results?.[i]));
  check("rejected notes touched no files", (await exists(p1)) && (await exists(a1)));

  r = await push([mut("notes", N1, noteData({ photos: [p2], audio: [{ url: a1, durationSec: 12.5, transcript: "halo" }] }))]);
  check("note update dropping a photo + a clip deletes those files only", statuses(r)?.[0] === "applied" && !(await exists(p1)) && !(await exists(a2)) && (await exists(p2)) && (await exists(a1)));

  // Last-write-wins uses editedAt: a server-side title fill (links/updatedAt only) must not
  // make a device's edit — made before the fill, pushed after — lose.
  const editAt = new Date().toISOString();
  await sleep(30);
  await prisma.note.update({ where: { id: N1 }, data: { links: JSON.stringify([{ url: "https://contoh.invalid/a", title: "Judul A" }, { url: "https://contoh.invalid/b", title: null }]) } });
  r = await push([mut("notes", N1, noteData({ title: "Ide video v2", photos: [p2], audio: [{ url: a1, durationSec: 12.5 }] }), editAt)]);
  nrow = await prisma.note.findUnique({ where: { id: N1 } });
  check("edit older than a title fill (but newer than the last edit) still applies", statuses(r)?.[0] === "applied" && nrow.title === "Ide video v2", r.json);
  check("fetched link title kept when the client sends none", JSON.parse(nrow.links)[0].title === "Judul A", nrow.links);
  r = await push([mut("notes", N1, noteData({ title: "stale" }), ago(60_000))]);
  check("stale note edit → skipped", statuses(r)?.[0] === "skipped", r.json);

  // Background title fetch: the server never reaches a local address from a note link.
  {
    let hits = 0;
    const srv = http.createServer((req, res) => {
      hits++;
      res.writeHead(200, { "content-type": "text/html" });
      res.end("<title>Lokal</title>");
    });
    await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
    const url = `http://127.0.0.1:${srv.address().port}/page`;
    const N2 = randomUUID();
    r = await push([mut("notes", N2, { body: `cek ${url}` })]);
    await sleep(800);
    check("sync push of a note linking 127.0.0.1: server never fetched it (SSRF)", statuses(r)?.[0] === "applied" && hits === 0, hits);
    const n2before = await prisma.note.findUnique({ where: { id: N2 } });
    await sleep(20);
    const filled = await ns.refreshNoteLinkTitles(N2, { isAllowedAddress: (ip) => ip === "127.0.0.1" });
    const n2 = await prisma.note.findUnique({ where: { id: N2 } });
    check("refreshNoteLinkTitles fills titles, bumps updatedAt, not editedAt",
      filled === 1 && JSON.parse(n2.links)[0].title === "Lokal" && n2.editedAt.getTime() === n2before.editedAt.getTime() && n2.updatedAt > n2before.updatedAt, n2.links);
    srv.close();
  }

  // Ownership
  r = await push([
    mut("notes", N1, noteData()),
    del("notes", N1),
    mut("notes", randomUUID(), { title: "B", labels: [IDEA, L1], linkedTaskId: KERJA }),
    mut("noteLabels", L1, { name: "hijack" }),
  ], tokenB);
  check("other user: upsert/delete A's note → rejected", statuses(r)?.[0] === "rejected" && statuses(r)?.[1] === "rejected", r.json);
  const bNote = await prisma.note.findFirst({ where: { userId: userBId, title: "B" } });
  check("other user's note can't reference A's labels/rows (dropped/nulled)", statuses(r)?.[2] === "applied" && bNote?.labels === "[]" && bNote.linkedTaskId === null, bNote);
  check("other user: upsert A's label → rejected", statuses(r)?.[3] === "rejected");

  console.log("notes/content: content sync");
  const ACC1 = randomUUID(), ACC3 = randomUUID(), PIL1 = randomUUID(), ITEM1 = randomUUID(), ITEM2 = randomUUID(), POST1 = randomUUID(), POST2 = randomUUID();
  const cursorK = Date.now() - 1000;
  const sched = new Date(Date.now() + 86_400_000).toISOString();
  const itemData = (extra = {}) => ({
    title: "Review kopi",
    stage: "produksi",
    format: "reel",
    pillar: "Edukasi",
    idea: "# Hook\nKopi enak",
    noteId: N1,
    checklist: [{ id: "k1", text: "Rekam", done: true }],
    photos: [p3],
    assetLinks: [{ url: "https://drive.google.com/x", label: "Draft" }],
    sponsor: { brand: "Kopi Kita", amount: 1500000, currency: "IDR", due: "2026-10-01", paid: false, transactionId: null },
    ...extra,
  });
  const postData = (extra = {}) => ({ contentId: ITEM1, accountId: ACC1, caption: "Halo", hashtags: "#kopi", scheduledAt: sched, remindBefore: 30, status: "scheduled", postedAt: null, url: null, metrics: {}, metricsAt: null, ...extra });
  r = await push([
    mut("socialAccounts", ACC1, { platform: "instagram", handle: "@ghina", targetPerWeek: 3 }),
    mut("socialAccounts", randomUUID(), { platform: "other", handle: "x" }),
    mut("socialAccounts", ACC3, { platform: "tiktok", handle: "ghina", color: "#000000", sortOrder: 1 }),
    mut("contentPillars", PIL1, { name: "Tutorial", color: "#FF9600", sortOrder: 5 }),
    mut("contentPillars", randomUUID(), { name: "edukasi" }),
    mut("contentItems", ITEM1, itemData()),
    mut("contentItems", ITEM2, { title: "Tanpa catatan", noteId: "no-such-note", pillar: "tutorial" }),
    mut("contentPosts", POST1, postData()),
    mut("contentPosts", POST2, postData({ accountId: ACC3, status: "posted", postedAt: now(), url: "https://www.tiktok.com/@ghina/video/1", metrics: { views: 1000, likes: 50 }, metricsAt: now() })),
    mut("contentPosts", randomUUID(), postData({ contentId: "nope" })),
    mut("contentPosts", randomUUID(), postData({ scheduledAt: null })),
    mut("contentPosts", randomUUID(), postData({ metrics: '{"views":1}' })),
    mut("contentItems", randomUUID(), itemData({ sponsor: '{"brand":"x"}' })),
    mut("contentItems", randomUUID(), itemData({ stage: "done" })),
  ]);
  check("content creates", eq(statuses(r), ["applied", "rejected", "applied", "applied", "duplicate", "applied", "applied", "applied", "applied", "rejected", "rejected", "rejected", "rejected", "rejected"]), r.json?.results);
  let pk = await pullSince(cursorK);
  const acc = byId(pk.changes.socialAccounts, ACC1);
  check("account wire: default color, platformName null", acc?.color === "#E1306C" && acc.platformName === null && acc.targetPerWeek === 3 && eq(Object.keys(acc), ["id", "platform", "platformName", "handle", "color", "targetPerWeek", "archived", "sortOrder", "createdAt", "updatedAt"]), acc);
  const it = byId(pk.changes.contentItems, ITEM1);
  check("item wire: sponsor/checklist/assetLinks as JSON", it && eq(it.sponsor, { brand: "Kopi Kita", amount: 1500000, currency: "IDR", due: "2026-10-01", paid: false, transactionId: null }) && Array.isArray(it.checklist) && eq(it.assetLinks, [{ url: "https://drive.google.com/x", label: "Draft" }]) && it.noteId === N1, it);
  check("item with unknown noteId stored with noteId null", byId(pk.changes.contentItems, ITEM2)?.noteId === null);
  const po = byId(pk.changes.contentPosts, POST2);
  check("post wire: metrics object, dates ISO", po && eq(po.metrics, { views: 1000, likes: 50 }) && /Z$/.test(po.postedAt) && po.status === "posted", po);
  check("sync does not auto-advance the stage (client's job)", (await prisma.contentItem.findUnique({ where: { id: ITEM1 } })).stage === "produksi");
  r = await push([mut("contentPillars", pillarIds[0], { name: "Edukasi & Tips", color: "#1CB0F6", sortOrder: 0 })]);
  check("pillar rename via sync renames items' pillar", statuses(r)?.[0] === "applied" && (await prisma.contentItem.findUnique({ where: { id: ITEM1 } })).pillar === "Edukasi & Tips");
  r = await push([
    mut("contentPosts", randomUUID(), postData()),
    mut("socialAccounts", ACC1, { platform: "x", handle: "hijack" }),
    del("contentItems", ITEM1),
  ], tokenB);
  check("other user: post on A's item / edit A's account / delete A's item → rejected", eq(statuses(r), ["rejected", "rejected", "rejected"]), r.json);

  console.log("notes/content: cascades");
  const TKN = randomUUID(), TXN = randomUUID(), N3 = randomUUID();
  r = await push([
    mut("tasks", TKN, { areaId: KERJA, title: "dari catatan" }),
    mut("transactions", TXN, { walletId: W1, toWalletId: null, categoryId: null, type: "income", amount: 1500000, note: "Endorse", date: now() }),
    mut("notes", N1, noteData({ photos: [p2], audio: [{ url: a1, durationSec: 12.5 }], linkedTaskId: TKN, linkedTransactionId: TXN, linkedContentId: ITEM1 })),
    mut("contentItems", ITEM1, itemData({ pillar: "Edukasi & Tips", sponsor: { brand: "Kopi Kita", amount: 1500000, paid: true, transactionId: TXN } })),
    mut("notes", N3, { title: "linked to item", linkedContentId: ITEM1 }),
  ]);
  check("links set", statuses(r)?.every((x) => x === "applied") && (await prisma.note.findUnique({ where: { id: N1 } })).linkedTaskId === TKN, r.json);
  const cursorX = Date.now() - 1000;
  r = await push([del("tasks", TKN), del("transactions", TXN)]);
  nrow = await prisma.note.findUnique({ where: { id: N1 } });
  let irow = await prisma.contentItem.findUnique({ where: { id: ITEM1 } });
  check("delete task/transaction → note links null", statuses(r)?.every((x) => x === "applied") && nrow.linkedTaskId === null && nrow.linkedTransactionId === null && nrow.linkedContentId === ITEM1, nrow);
  check("delete transaction → sponsor.transactionId null, paid kept", eq(JSON.parse(irow.sponsor), { brand: "Kopi Kita", amount: 1500000, currency: "IDR", due: null, paid: true, transactionId: null }), irow.sponsor);
  pk = await pullSince(cursorX);
  check("nulled note + item re-sent in changes", byId(pk.changes.notes, N1)?.linkedTaskId === null && byId(pk.changes.contentItems, ITEM1)?.sponsor?.transactionId === null);
  r = await push([mut("contentItems", ITEM1, itemData({ sponsor: { brand: "Kopi Kita", amount: 1, paid: true, transactionId: TXN } }))]);
  check("stale sponsor.transactionId of a deleted tx → stored as null", statuses(r)?.[0] === "applied" && JSON.parse((await prisma.contentItem.findUnique({ where: { id: ITEM1 } })).sponsor).transactionId === null);
  const TXE = randomUUID();
  r = await push([
    mut("transactions", TXE, { walletId: W1, toWalletId: null, categoryId: null, type: "expense", amount: 5, note: null, date: now() }),
    mut("contentItems", ITEM1, itemData({ sponsor: { brand: "Kopi Kita", amount: 1, paid: true, transactionId: TXE } })),
  ]);
  check("sponsor.transactionId of an expense (not income) → stored as null", eq(statuses(r), ["applied", "applied"]) && JSON.parse((await prisma.contentItem.findUnique({ where: { id: ITEM1 } })).sponsor).transactionId === null, r.json);
  await push([del("transactions", TXE)]);

  r = await push([del("socialAccounts", ACC3)]);
  pk = await pullSince(cursorX);
  check("delete account → its posts tombstoned", statuses(r)?.[0] === "applied" && pk.deleted.some((d) => d.entity === "contentPosts" && d.id === POST2) && pk.deleted.some((d) => d.entity === "socialAccounts" && d.id === ACC3) && (await prisma.contentPost.count({ where: { id: POST2 } })) === 0);
  r = await push([mut("contentPosts", POST2, postData({ accountId: ACC3 }), ago(60_000))]);
  check("stale upsert of cascaded post → skipped", statuses(r)?.[0] === "skipped", r.json);
  r = await push([del("contentPillars", PIL1)]);
  check("delete pillar → items with it (case-insensitive) get pillar null", statuses(r)?.[0] === "applied" && (await prisma.contentItem.findUnique({ where: { id: ITEM2 } })).pillar === null);
  r = await push([del("notes", N1)]);
  irow = await prisma.contentItem.findUnique({ where: { id: ITEM1 } });
  check("delete note → item.noteId null, note files removed", statuses(r)?.[0] === "applied" && irow.noteId === null && !(await exists(p2)) && !(await exists(a1)), irow.noteId);
  r = await push([del("contentItems", ITEM1)]);
  pk = await pullSince(cursorX);
  check("delete item → posts tombstoned, notes' linkedContentId null, photo removed",
    statuses(r)?.[0] === "applied" && pk.deleted.some((d) => d.entity === "contentPosts" && d.id === POST1) && (await prisma.note.findUnique({ where: { id: N3 } })).linkedContentId === null &&
    byId(pk.changes.notes, N3)?.linkedContentId === null && !(await exists(p3)));
  check("tombstones for note, item, pillar, label-free", pk.deleted.some((d) => d.entity === "notes" && d.id === N1) && pk.deleted.some((d) => d.entity === "contentItems" && d.id === ITEM1) && pk.deleted.some((d) => d.entity === "contentPillars" && d.id === PIL1));

  // Label delete strips it from notes (they re-sync); a deleted default label isn't re-seeded.
  const N4 = randomUUID();
  await push([mut("noteLabels", L1, { name: "Kerjaan" }), mut("notes", N4, { title: "berlabel", labels: [L1, IDEA] })]);
  const cursorL = Date.now() - 1000;
  r = await push([del("noteLabels", L1), del("noteLabels", IDEA)]);
  pk = await pullSince(cursorL);
  check("delete label → stripped from notes, note re-sent", statuses(r)?.every((x) => x === "applied") && eq(byId(pk.changes.notes, N4)?.labels, []) && pk.deleted.some((d) => d.entity === "noteLabels" && d.id === L1), byId(pk.changes.notes, N4));
  check("deleted `Ide Konten` is not re-seeded", !pk.changes.noteLabels.some((l) => l.id === IDEA) && (await prisma.noteLabel.count({ where: { id: IDEA } })) === 0);
  r = await push([mut("noteLabels", IDEA, { name: "Ide Konten", color: "#CE82FF", pinnedTab: true, sortOrder: 0 })]);
  check("re-creating `Ide Konten` with a newer edit works", statuses(r)?.[0] === "applied");
  r = await push([mut("notes", randomUUID(), { labels: [L1] })]);
  check("note referencing a deleted label → label dropped", statuses(r)?.[0] === "applied");

  // A file shared by a note and a transaction survives deleting either one alone.
  const shared = await upload();
  const NS = randomUUID(), TXS = randomUUID();
  await push([
    mut("transactions", TXS, { walletId: W1, toWalletId: null, categoryId: null, type: "expense", amount: 1, note: null, date: now(), photos: [shared] }),
    mut("notes", NS, { title: "struk", photos: [shared], linkedTransactionId: TXS }),
  ]);
  await push([del("transactions", TXS)]);
  check("tx delete keeps a photo a note still uses", await exists(shared));
  await push([del("notes", NS)]);
  check("…deleted once the note goes too", !(await exists(shared)));

  // ---------- Web actions (auth + next/cache stubbed) ----------
  console.log("notes/content: web actions");
  const stubDir = await mkdtemp(join(tmpdir(), "ghina-stubs-"));
  await writeFile(join(stubDir, "auth.mjs"), "export async function requireUser() { return globalThis.__ghinaTestUser; }\n");
  await writeFile(join(stubDir, "cache.mjs"), "export function revalidatePath() {}\n");
  globalThis.__ghinaTestUser = await prisma.user.findUnique({ where: { id: user.id } });
  const jitiW = createJiti(import.meta.url, {
    alias: { "@/lib/auth-helpers": join(stubDir, "auth.mjs"), "next/cache": join(stubDir, "cache.mjs"), "@": join(root, "src") },
    moduleCache: false,
  });
  const na = await jitiW.import(join(root, "src/app/(dashboard)/notes/actions.ts"));
  const ca = await jitiW.import(join(root, "src/app/(dashboard)/content/actions.ts"));
  const onDisk = (u) => existsSync(join(root, "public", u));
  const wallet = await prisma.wallet.create({ data: { userId: user.id, name: "Notes wallet", balance: 1000 } });
  const incomeCat = await prisma.category.findFirst({ where: { userId: user.id, type: "income" } });

  let a = await na.createNote({ title: "Belanja", body: "Beli beras Rp 125.000 di https://contoh.invalid/toko", labels: [IDEA, "nope"] });
  check("createNote", a.ok && typeof a.id === "string", a);
  const WN = a.id;
  let wn = await prisma.note.findUnique({ where: { id: WN } });
  check("createNote: labels filtered, links from body", wn.labels === JSON.stringify([IDEA]) && JSON.parse(wn.links).length === 1, wn);
  a = await na.updateNote(WN, { pinned: true, color: "green" });
  wn = await prisma.note.findUnique({ where: { id: WN } });
  check("updateNote patch keeps other fields", a.ok && wn.pinned && wn.color === "green" && wn.title === "Belanja", wn);
  check("updateNote invalid color → Indonesian error", !(await na.setNoteColor(WN, "#123456")).ok && (await na.setNoteColor(WN, "#123456")).error === "Warna catatan tidak valid");
  check("string-id guard: object id → not found", (await na.updateNote({ not: "" }, { pinned: false })).error === "Catatan tidak ditemukan" && (await na.deleteNote({ id: { not: "" } })).ok === false);
  a = await na.addChecklistItem(WN, "Beras");
  const it1 = a.itemId;
  await na.addChecklistItem(WN, "Telur");
  const it0 = (await na.addChecklistItem(WN, "Minyak", { index: 0 })).itemId;
  await na.toggleChecklistItem(WN, it1);
  let cl = JSON.parse((await prisma.note.findUnique({ where: { id: WN } })).checklist);
  check("checklist add/insert/toggle", eq(cl.map((c) => [c.text, c.done]), [["Minyak", false], ["Beras", true], ["Telur", false]]), cl);
  await na.updateChecklistItem(WN, it0, { text: "Minyak goreng" });
  a = await na.reorderChecklist(WN, [cl[2].id, cl[0].id, cl[1].id]);
  await na.clearCheckedItems(WN);
  cl = JSON.parse((await prisma.note.findUnique({ where: { id: WN } })).checklist);
  check("checklist update/reorder/clear checked", a.ok && eq(cl.map((c) => c.text), ["Telur", "Minyak goreng"]), cl);
  check("reorderChecklist with a wrong id set → error", !(await na.reorderChecklist(WN, [cl[0].id])).ok);
  await na.removeChecklistItem(WN, cl[0].id);
  check("removeChecklistItem", JSON.parse((await prisma.note.findUnique({ where: { id: WN } })).checklist).length === 1);

  a = await na.createNoteLabel({ name: "Belanja", color: "#FF9600" });
  const LB = a.id;
  check("createNoteLabel (sortOrder after last)", a.ok && (await prisma.noteLabel.findUnique({ where: { id: LB } })).sortOrder === 1, a);
  check("createNoteLabel duplicate (case-insensitive) → error", (await na.createNoteLabel({ name: "belanja" })).error === "Nama label sudah dipakai");
  a = await na.updateNoteLabel(LB, { name: "Belanjaan", pinnedTab: true });
  check("updateNoteLabel rename + pin", a.ok && (await prisma.noteLabel.findUnique({ where: { id: LB } })).name === "Belanjaan");
  await na.setNoteLabels(WN, [IDEA, LB]);
  a = await na.reorderNoteLabels([LB, IDEA]);
  check("reorderNoteLabels", a.ok && (await prisma.noteLabel.findUnique({ where: { id: LB } })).sortOrder === 0);
  a = await na.deleteNoteLabel(LB);
  check("deleteNoteLabel strips it from notes", a.ok && (await prisma.note.findUnique({ where: { id: WN } })).labels === JSON.stringify([IDEA]));

  const fd = (o) => {
    const f = new FormData();
    for (const [k, v] of Object.entries(o)) for (const x of [v].flat()) f.append(k, x);
    return f;
  };
  const pngFile = (nm) => new File([png], `${nm}.png`, { type: "image/png" });
  const m4aFile = (nm) => new File([m4a], `${nm}.m4a`, { type: "audio/mp4" });
  a = await na.uploadNoteMedia(fd({ noteId: WN, photos: [pngFile("a"), pngFile("b")], audio: [m4aFile("v")], audioDuration: ["42.5"], audioTranscript: ["beli beras"] }));
  check("uploadNoteMedia: photos + audio", a.ok && a.photos.length === 2 && a.audio.length === 1 && a.audio[0].durationSec === 42.5 && a.audio[0].transcript === "beli beras" && onDisk(a.photos[0]) && onDisk(a.audio[0].url), a);
  const [wp1, wp2] = a.photos;
  const wa1 = a.audio[0].url;
  const filesBefore = (await readdir(join(root, "public", "uploads"))).length;
  a = await na.uploadNoteMedia(fd({ noteId: WN, audio: [pngFile("x")], audioDuration: ["1"] }));
  check("uploadNoteMedia: image as audio → error, no file left", !a.ok && (await readdir(join(root, "public", "uploads"))).length === filesBefore, a);
  a = await na.uploadNoteMedia(fd({ noteId: WN, audio: [m4aFile("y")] }));
  check("uploadNoteMedia: audio without duration → error", !a.ok && /Durasi/.test(a.error), a);
  a = await na.setAudioTranscript(WN, wa1, "beli beras 5 kg");
  check("setAudioTranscript", a.ok && JSON.parse((await prisma.note.findUnique({ where: { id: WN } })).audio)[0].transcript === "beli beras 5 kg");
  a = await na.updateNote(WN, { photos: [wp2, wp1] });
  check("updateNote reorders photos", a.ok && (await prisma.note.findUnique({ where: { id: WN } })).photos === JSON.stringify([wp2, wp1]));
  check("updateNote can't adopt a foreign photo", !(await na.updateNote(WN, { photos: [wp1, "/uploads/other.png"] })).ok);
  a = await na.removeNoteMedia(WN, wp2);
  check("removeNoteMedia deletes the file", a.ok && !onDisk(wp2) && onDisk(wp1));

  a = await na.getNoteConversion(WN);
  check("getNoteConversion prefill (amount parsed, photos, title)", a.ok && a.transaction.amount === 125000 && eq(a.transaction.photos, [wp1]) && a.task.title === "Belanja" && a.content.idea.startsWith("Beli beras"), a);
  a = await na.convertNoteToTask(WN, { areaId: KERJA, bucket: "fire" });
  const wt = await prisma.task.findUnique({ where: { id: a.taskId } });
  check("convertNoteToTask: task created + linkedTaskId", a.ok && wt?.title === "Belanja" && wt.bucket === "fire" && (await prisma.note.findUnique({ where: { id: WN } })).linkedTaskId === a.taskId, a);
  a = await na.convertNoteToContent(WN, { format: "reel" });
  const wc = await prisma.contentItem.findUnique({ where: { id: a.contentId } });
  check("convertNoteToContent: item at ide with noteId + photos, note.linkedContentId", a.ok && wc.stage === "ide" && wc.noteId === WN && wc.format === "reel" && wc.photos === JSON.stringify([wp1]) && (await prisma.note.findUnique({ where: { id: WN } })).linkedContentId === wc.id, wc);
  const WC = wc.id;
  a = await na.createTransactionFromNote(WN, { type: "expense", amount: 125000, walletId: wallet.id });
  const wtx = await prisma.transaction.findUnique({ where: { id: a.transactionId } });
  check("createTransactionFromNote: ledger tx with note photos, balance moved, link set",
    a.ok && wtx.amount === 125000 && wtx.note === "Belanja" && wtx.photos === JSON.stringify([wp1]) && (await prisma.wallet.findUnique({ where: { id: wallet.id } })).balance === -124000 &&
    (await prisma.note.findUnique({ where: { id: WN } })).linkedTransactionId === wtx.id, a);
  check("createTransactionFromNote: income category on expense → error", !(await na.createTransactionFromNote(WN, { type: "expense", amount: 1, walletId: wallet.id, categoryId: incomeCat.id })).ok);
  check("createTransactionFromNote: foreign photo → error", !(await na.createTransactionFromNote(WN, { type: "expense", amount: 1, walletId: wallet.id, photos: ["/uploads/x.png"] })).ok);

  console.log("notes/content: content web actions");
  a = await ca.createSocialAccount({ platform: "instagram", handle: "@ghina", targetPerWeek: 2 });
  const WA = a.id;
  check("createSocialAccount (platform color)", a.ok && (await prisma.socialAccount.findUnique({ where: { id: WA } })).color === "#E1306C", a);
  check("createSocialAccount other w/o name → Indonesian error", /nama platform/.test((await ca.createSocialAccount({ platform: "other", handle: "x" })).error ?? ""));
  a = await ca.updateSocialAccount(WA, { platform: "youtube" });
  check("updateSocialAccount platform switch resets default color", a.ok && (await prisma.socialAccount.findUnique({ where: { id: WA } })).color === "#FF0000");
  const WA2 = (await ca.createSocialAccount({ platform: "tiktok", handle: "g" })).id;
  check("reorderSocialAccounts", (await ca.reorderSocialAccounts([WA2, WA])).ok && (await prisma.socialAccount.findUnique({ where: { id: WA2 } })).sortOrder === 0);
  a = await ca.createContentPillar({ name: "Review" });
  check("createContentPillar + duplicate", a.ok && (await ca.createContentPillar({ name: "review" })).error === "Nama pilar sudah dipakai");
  const WPIL = a.id;
  a = await ca.createContentItem({ title: "Review HP", pillar: "Review", sponsor: { brand: "HPku", amount: 2000000, due: "2026-10-10" } });
  const WI = a.id;
  check("createContentItem with sponsor", a.ok && JSON.parse((await prisma.contentItem.findUnique({ where: { id: WI } })).sponsor).paid === false, a);
  a = await ca.updateContentPillar(WPIL, { name: "Ulasan" });
  check("updateContentPillar rename cascades to items", a.ok && (await prisma.contentItem.findUnique({ where: { id: WI } })).pillar === "Ulasan");
  a = await ca.moveContentStage(WI, "siap");
  check("moveContentStage", a.ok && (await prisma.contentItem.findUnique({ where: { id: WI } })).stage === "siap");
  check("moveContentStage bad stage → error", !(await ca.moveContentStage(WI, "done")).ok);
  const when = new Date(Date.now() + 2 * 86_400_000).toISOString();
  a = await ca.createContentPost({ contentId: WI, accountId: WA, caption: "Cek!", scheduledAt: when });
  const WP1 = a.id;
  check("createContentPost scheduled → item auto-advances to terjadwal", a.ok && a.stage === "terjadwal" && (await prisma.contentItem.findUnique({ where: { id: WI } })).stage === "terjadwal", a);
  check("createContentPost same account twice → error", (await ca.createContentPost({ contentId: WI, accountId: WA })).error === "Akun ini sudah ada di konten ini");
  a = await ca.createContentPost({ contentId: WI, accountId: WA2 });
  const WP2 = a.id;
  check("second variant (draft)", a.ok && (await prisma.contentPost.findUnique({ where: { id: WP2 } })).status === "draft");
  a = await ca.markPostPosted(WP1, { url: "https://youtube.com/watch?v=1" });
  check("markPostPosted: stays terjadwal while another variant is unposted", a.ok && a.stage === null && (await prisma.contentPost.findUnique({ where: { id: WP1 } })).status === "posted");
  a = await ca.setPostSkipped(WP2, true);
  check("skipping the last unposted variant → tayang", a.ok && a.stage === "tayang" && (await prisma.contentItem.findUnique({ where: { id: WI } })).stage === "tayang", a);
  a = await ca.setPostMetrics(WP1, { views: 1234, likes: 56, bogus: 1 });
  const mrow = await prisma.contentPost.findUnique({ where: { id: WP1 } });
  check("setPostMetrics", a.ok && mrow.metrics === JSON.stringify({ views: 1234, likes: 56 }) && mrow.metricsAt, mrow);
  check("setPostMetrics negative → error", !(await ca.setPostMetrics(WP1, { views: -5 })).ok);
  a = await ca.scheduleContentPost(WP2, when);
  check("scheduleContentPost keeps a skipped status", a.ok && (await prisma.contentPost.findUnique({ where: { id: WP2 } })).status === "skipped");

  a = await ca.markSponsorPaid(WI, { walletId: wallet.id, categoryId: incomeCat.id });
  const sp = JSON.parse((await prisma.contentItem.findUnique({ where: { id: WI } })).sponsor);
  const stx = await prisma.transaction.findUnique({ where: { id: a.transactionId } });
  check("markSponsorPaid records income via ledger + links it",
    a.ok && sp.paid && sp.transactionId === stx.id && stx.type === "income" && stx.amount === 2000000 && stx.note === "Endorse HPku" && (await prisma.wallet.findUnique({ where: { id: wallet.id } })).balance === 1876000, { a, sp });
  a = await ca.markSponsorPaid(WI, { walletId: wallet.id });
  check("markSponsorPaid twice never records a second income", a.ok && a.transactionId === stx.id && (await prisma.transaction.count({ where: { walletId: wallet.id, type: "income" } })) === 1);
  check("markSponsorPaid with an expense category → error", !(await ca.markSponsorPaid(WC, { walletId: wallet.id })).ok);
  a = await ca.markSponsorUnpaid(WI, { deleteTransaction: true });
  check("markSponsorUnpaid + deleteTransaction reverses the income", a.ok && (await prisma.transaction.count({ where: { id: stx.id } })) === 0 && (await prisma.wallet.findUnique({ where: { id: wallet.id } })).balance === -124000 && JSON.parse((await prisma.contentItem.findUnique({ where: { id: WI } })).sponsor).paid === false);
  const spAt = async () => JSON.parse((await prisma.contentItem.findUnique({ where: { id: WI } })).sponsor);
  check("… and the deleted income is unlinked", (await spAt()).transactionId === null);
  a = await ca.markSponsorPaid(WI, { walletId: wallet.id });
  const stx2 = a.ok ? a.transactionId : null;
  check("paid again after the income was deleted → a new income", a.ok && stx2 && stx2 !== stx.id && (await prisma.transaction.count({ where: { walletId: wallet.id, type: "income" } })) === 1, a);
  a = await ca.markSponsorUnpaid(WI);
  check("markSponsorUnpaid without deleting keeps the income linked", a.ok && (await spAt()).paid === false && (await spAt()).transactionId === stx2 && (await prisma.transaction.count({ where: { id: stx2 } })) === 1, await spAt());
  a = await ca.markSponsorPaid(WI, { walletId: wallet.id });
  check("paid again reuses the linked income (never a second one)", a.ok && a.transactionId === stx2 && (await prisma.transaction.count({ where: { walletId: wallet.id, type: "income" } })) === 1 && (await prisma.wallet.findUnique({ where: { id: wallet.id } })).balance === 1876000, a);
  a = await ca.updateContentItem(WI, { sponsor: null });
  check("removing a sponsor whose income is linked → error, sponsor kept", !a.ok && (await spAt())?.transactionId === stx2, a);
  a = await ca.markSponsorUnpaid(WI, { deleteTransaction: true });
  a = await ca.updateContentItem(WI, { sponsor: null });
  check("… after deleting the income the sponsor can be removed", a.ok && (await prisma.contentItem.findUnique({ where: { id: WI } })).sponsor === null, a);
  a = await ca.updateContentItem(WI, { sponsor: { brand: "HPku", amount: 2000000, due: "2026-10-10" } });

  const today = new Date().toISOString().slice(0, 10);
  const in10 = new Date(Date.now() + 10 * 86_400_000).toISOString().slice(0, 10);
  a = await ca.fetchContentCalendar({ from: today, to: in10 });
  const calDay = a.ok && a.calendar.days.find((d) => d.posts.some((p) => p.id === WP1));
  check("fetchContentCalendar places the posted post on its day, with title + week slots", a.ok && calDay && calDay.posts.find((p) => p.id === WP1).title === "Review HP" && a.calendar.weeks.length >= 2 && a.calendar.weeks[0].slots.some((s) => s.accountId === WA && s.target === 2), a.ok ? a.calendar.weeks[0] : a);
  check("fetchContentCalendar rejects a bad range", !(await ca.fetchContentCalendar({ from: in10, to: today })).ok && !(await ca.fetchContentCalendar({ from: "2026-01-01", to: "2026-12-31" })).ok);
  a = await ca.fetchContentReport({ from: today, to: today });
  check("fetchContentReport: posted count + best post + sponsor unpaid list", a.ok && a.report.totals.posted === 1 && a.report.bestByViews[0]?.postId === WP1 && a.sponsors.unpaid.some((u) => u.contentId === WI), a.ok ? a.report.totals : a);
  const inbox = await cs.getIdeaInbox(user.id);
  check("idea inbox: labelled notes not yet turned into content", !inbox.some((x) => x.id === WN), inbox.map((x) => x.id));
  const NI = (await na.createNote({ title: "Ide: vlog", labels: [IDEA] })).id;
  check("idea inbox includes a fresh idea note", (await cs.getIdeaInbox(user.id)).some((x) => x.id === NI));

  a = await ca.deleteContentPost(WP2);
  check("deleteContentPost (tombstone)", a.ok && (await prisma.syncTombstone.count({ where: { entity: "contentPosts", entityId: WP2 } })) === 1);
  a = await ca.deleteSocialAccount(WA);
  check("deleteSocialAccount cascades posts", a.ok && (await prisma.contentPost.count({ where: { id: WP1 } })) === 0 && (await prisma.syncTombstone.count({ where: { entity: "contentPosts", entityId: WP1 } })) === 1);
  a = await ca.deleteContentPillar(WPIL);
  check("deleteContentPillar clears items' pillar", a.ok && (await prisma.contentItem.findUnique({ where: { id: WI } })).pillar === null);
  a = await ca.deleteContentItem(WC);
  check("deleteContentItem: note.linkedContentId null, shared photo kept (note/tx use it)", a.ok && (await prisma.note.findUnique({ where: { id: WN } })).linkedContentId === null && onDisk(wp1));
  a = await na.deleteNote(WN);
  check("deleteNote: tombstone, audio removed, photo kept (transaction uses it)", a.ok && (await prisma.syncTombstone.count({ where: { entity: "notes", entityId: WN } })) === 1 && !onDisk(wa1) && onDisk(wp1));
  await rm(stubDir, { recursive: true, force: true });
}

try {
  await main();
} catch (err) {
  failed++;
  console.error("Test run crashed:", err);
} finally {
  // Files still referenced by the throwaway users' rows would be orphaned by the DB cascade.
  const users = await prisma.user.findMany({ where: { email: { in: createdEmails } }, select: { id: true } });
  const where = { userId: { in: users.map((u) => u.id) } };
  const refs = [
    ...(await prisma.transaction.findMany({ where, select: { photos: true } })).map((x) => x.photos),
    ...(await prisma.note.findMany({ where, select: { photos: true, audio: true } })).flatMap((x) => [x.photos, x.audio]),
    ...(await prisma.contentItem.findMany({ where, select: { photos: true } })).map((x) => x.photos),
    ...(await prisma.foodLog.findMany({ where, select: { photoUrl: true } })).map((x) => JSON.stringify(x.photoUrl)),
  ].join(" ");
  for (const u of new Set(refs.match(/\/uploads\/[A-Za-z0-9-]+\.[a-z0-9]+/g) ?? [])) await rm(join(root, "public", u), { force: true });
  // Clean up the throwaway users (DB cascades remove their data and tombstones).
  await prisma.user.deleteMany({ where: { email: { in: createdEmails } } });
  await prisma.$disconnect();
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}
