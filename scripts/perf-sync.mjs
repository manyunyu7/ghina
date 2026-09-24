#!/usr/bin/env node
// Rough performance check of the mobile sync endpoint at a realistic volume
// (~1500 transactions, 300 tasks): full pull and a 200-mutation push.
//
//   node scripts/perf-sync.mjs [baseUrl]   # default http://localhost:3100
//
// Creates a throwaway user (mobile-test-perf-*@example.test) and deletes it.
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";

const BASE = process.argv[2] ?? "http://localhost:3100";
const prisma = new PrismaClient();
const email = `mobile-test-perf-${Date.now()}@example.test`;

async function api(method, path, token, body) {
  const t0 = performance.now();
  const res = await fetch(BASE + path, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = await res.json();
  return { status: res.status, json, ms: performance.now() - t0, bytes: JSON.stringify(json).length };
}
const mut = (entity, entityId, data) => ({ id: randomUUID(), entity, op: "upsert", entityId, data, clientUpdatedAt: new Date().toISOString() });
const fmt = (ms) => `${(ms / 1000).toFixed(2)} s`;
const results = [];
const report = (name, ms, extra = "") => {
  results.push({ name, ms });
  console.log(`${ms > 2000 ? "SLOW" : "ok  "} ${name}: ${fmt(ms)} ${extra}`);
};

try {
  const reg = await api("POST", "/api/mobile/auth/register", null, { name: "Perf", email, password: "rahasia123" });
  const token = reg.json.token;
  let r = await api("GET", "/api/mobile/sync?since=0", token);
  const cats = r.json.changes.categories;
  const exp = cats.filter((c) => c.type === "expense").map((c) => c.id);
  const area = r.json.changes.taskAreas[0].id;
  const wallets = ["pw1", "pw2", "pw3"];
  const push = async (ms) => {
    let total = 0;
    for (let i = 0; i < ms.length; i += 1000) {
      const res = await api("POST", "/api/mobile/sync", token, { mutations: ms.slice(i, i + 1000) });
      if (res.status !== 200 || res.json.results.some((x) => x.status !== "applied")) throw new Error(JSON.stringify(res.json).slice(0, 500));
      total += res.ms;
    }
    return total;
  };
  await push(wallets.map((id, i) => mut("wallets", id, { name: `W${i}`, type: "cash", balance: 1e7, currency: "IDR", color: "#22c55e", icon: "wallet" })));
  const txs = Array.from({ length: 1500 }, (_, i) =>
    mut("transactions", `pt${i}`, {
      walletId: wallets[i % 3], toWalletId: null, categoryId: exp[i % exp.length], type: "expense",
      amount: 1000 + i, note: i % 2 ? `note ${i}` : null, date: new Date(Date.now() - i * 3600e3 * 5).toISOString(),
    }),
  );
  report("seed push 1500 transactions (2 requests)", await push(txs));
  const tasks = Array.from({ length: 300 }, (_, i) =>
    mut("tasks", `pk${i}`, { areaId: area, title: `Task ${i}`, bucket: ["fire", "want", "should"][i % 3], dueDate: "2026-10-01", recurrence: i % 10 === 0 ? { freq: "weekly" } : null, done: i % 4 === 0, doneAt: i % 4 === 0 ? new Date().toISOString() : null }),
  );
  report("seed push 300 tasks", await push(tasks));

  for (let i = 0; i < 3; i++) {
    r = await api("GET", "/api/mobile/sync?since=0", token);
    report(`full pull #${i + 1}`, r.ms, `(${r.json.changes.transactions.length} tx, ${r.json.changes.tasks.length} tasks, ${(r.bytes / 1024).toFixed(0)} KiB)`);
  }
  r = await api("GET", `/api/mobile/sync?since=${Date.now() - 1000}`, token);
  report("incremental pull (nothing changed)", r.ms);

  const mixed = [
    ...Array.from({ length: 100 }, (_, i) => mut("transactions", `pt${i}`, { ...txs[i].data, amount: 5000 + i })),
    ...Array.from({ length: 50 }, (_, i) => mut("tasks", `pk${i}`, { ...tasks[i].data, title: `Edited ${i}` })),
    ...Array.from({ length: 50 }, (_, i) => mut("prayers", randomUUID(), { date: `2026-0${1 + Math.floor(i / 10)}-1${i % 10}`, prayer: ["subuh", "dzuhur", "ashar", "maghrib", "isya"][i % 5], status: "jamaah" })),
  ];
  const t = await api("POST", "/api/mobile/sync", token, { mutations: mixed });
  const bad = t.json.results.filter((x) => x.status !== "applied");
  report("push 200 mixed mutations (100 tx edits, 50 tasks, 50 prayers)", t.ms, bad.length ? `(${bad.length} not applied: ${JSON.stringify(bad[0])})` : "");
  const fresh = Array.from({ length: 200 }, (_, i) =>
    mut("transactions", randomUUID(), { ...txs[i].data, note: `offline ${i}` }),
  );
  const f = await api("POST", "/api/mobile/sync", token, { mutations: fresh });
  report("push 200 new transactions (offline backlog)", f.ms, `(${f.json.results.filter((x) => x.status === "applied").length} applied)`);
  r = await api("GET", `/api/mobile/sync?since=${Date.now() - 60000}`, token);
  report("incremental pull after that push", r.ms, `(${r.json.changes.transactions.length} tx)`);
} finally {
  await prisma.user.deleteMany({ where: { email } });
  await prisma.$disconnect();
}
