#!/usr/bin/env node
// End-to-end test of the mobile API (docs/mobile-sync.md) against a running server.
//
//   npm run dev -- -p 3100          # in another terminal (or any running instance)
//   node scripts/test-mobile-sync.mjs [baseUrl]   # default http://localhost:3100
//
// Creates throwaway users (mobile-test-*@example.test) and deletes them at the end.
// Also exercises the web delete / reset helpers directly (via jiti) to confirm they
// write tombstones and rotate the sync epoch.
import { randomUUID } from "node:crypto";
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
const statuses = (r) => r.json?.results?.map((x) => x.status);
const byId = (rows, id) => rows.find((r) => r.id === id);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const createdEmails = [];

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
  check("all 9 entity keys present", Object.keys(full.changes).length === 9, Object.keys(full.changes));
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
  r = await api("POST", "/api/mobile/sync", { token, body: { epoch: user.syncEpoch, mutations: [mut("wallets", randomUUID(), wallet("zombie", 0))] } });
  check("push with old epoch → 409 + new epoch, nothing applied", r.status === 409 && r.json.epoch === after.syncEpoch, r.json);
  check("zombie wallet not created", (await prisma.wallet.count({ where: { userId: user.id } })) === 0);
  r = await api("GET", `/api/mobile/sync?since=${cursor3}`, { token });
  check("pull reports new epoch", r.json.epoch === after.syncEpoch);
}

try {
  await main();
} catch (err) {
  failed++;
  console.error("Test run crashed:", err);
} finally {
  // Clean up the throwaway users (DB cascades remove their data and tombstones).
  await prisma.user.deleteMany({ where: { email: { in: createdEmails } } });
  await prisma.$disconnect();
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}
