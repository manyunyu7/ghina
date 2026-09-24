#!/usr/bin/env node
// Rough performance check of the mobile sync endpoint at a realistic volume
// (~1500 transactions, 300 tasks, 500 notes with checklists, 200 content items with
// 400 posts): full pull and a 200-mutation push.
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
  const labels = ["pl1", "pl2", "pl3"];
  await push(labels.map((id, i) => mut("noteLabels", id, { name: `Label ${i}`, color: "#58CC02", pinnedTab: i === 0, sortOrder: i })));
  const notes = Array.from({ length: 500 }, (_, i) =>
    mut("notes", `pn${i}`, {
      title: i % 4 ? `Catatan ${i}` : null,
      body: `Isi catatan ${i}\n- satu\n- dua **tebal** https://contoh.example.test/${i}`,
      checklist: Array.from({ length: 1 + (i % 8) }, (_, k) => ({ id: `c${i}-${k}`, text: `Item ${k}`, done: k % 2 === 0 })),
      labels: [labels[i % 3], ...(i % 5 ? [] : [labels[(i + 1) % 3]])],
      color: i % 6 ? null : "blue",
      pinned: i % 50 === 0,
      archived: i % 40 === 0,
    }),
  );
  report("seed push 500 notes (with checklists)", await push(notes));
  const accounts = ["pa-ig", "pa-tt"];
  await push([
    mut("socialAccounts", "pa-ig", { platform: "instagram", platformName: null, handle: "perf", color: "#E1306C", targetPerWeek: 3, archived: false, sortOrder: 0 }),
    mut("socialAccounts", "pa-tt", { platform: "tiktok", platformName: null, handle: "perf", color: "#000000", targetPerWeek: 2, archived: false, sortOrder: 1 }),
  ]);
  const stages = ["ide", "naskah", "produksi", "siap", "terjadwal", "tayang"];
  const items = Array.from({ length: 200 }, (_, i) =>
    mut("contentItems", `pci${i}`, {
      title: `Konten ${i}`,
      stage: stages[i % 6],
      format: "reel",
      pillar: ["Edukasi", "Hiburan", "Promo"][i % 3],
      idea: `Naskah ${i}`.repeat(20),
      checklist: [{ id: `k${i}`, text: "Edit", done: false }],
      sponsor: i % 10 === 0 ? { brand: `Brand ${i}`, amount: 100000, paid: false } : null,
    }),
  );
  const posts = items.flatMap((it, i) =>
    accounts.map((acc, k) =>
      mut("contentPosts", `pcp${i}-${k}`, {
        contentId: it.entityId,
        accountId: acc,
        caption: `Caption ${i} #ghina`,
        hashtags: "#a #b",
        scheduledAt: new Date(Date.now() + (i - 100) * 86400e3).toISOString(),
        remindBefore: 60,
        status: i < 100 ? "posted" : "scheduled",
        postedAt: i < 100 ? new Date(Date.now() + (i - 100) * 86400e3).toISOString() : null,
        metrics: i < 100 ? { views: 1000 + i, likes: i } : {},
      }),
    ),
  );
  report("seed push 200 content items + 400 posts", await push([...items, ...posts]));

  for (let i = 0; i < 3; i++) {
    r = await api("GET", "/api/mobile/sync?since=0", token);
    const c = r.json.changes;
    report(`full pull #${i + 1}`, r.ms, `(${c.transactions.length} tx, ${c.tasks.length} tasks, ${c.notes.length} notes, ${c.contentItems.length} items, ${c.contentPosts.length} posts, ${(r.bytes / 1024).toFixed(0)} KiB)`);
  }
  r = await api("GET", `/api/mobile/sync?since=${Date.now() - 1000}`, token);
  report("incremental pull (nothing changed)", r.ms);

  const mixed = [
    ...Array.from({ length: 100 }, (_, i) => mut("transactions", `pt${i}`, { ...txs[i].data, amount: 5000 + i })),
    ...Array.from({ length: 50 }, (_, i) => mut("tasks", `pk${i}`, { ...tasks[i].data, title: `Edited ${i}` })),
    ...Array.from({ length: 50 }, (_, i) => mut("prayers", randomUUID(), { date: `2026-0${1 + Math.floor(i / 10)}-1${i % 10}`, prayer: ["subuh", "dzuhur", "ashar", "maghrib", "isya"][i % 5], status: "jamaah" })),
  ];
  const noteMix = [
    ...Array.from({ length: 80 }, (_, i) => mut("notes", `pn${i}`, { ...notes[i].data, title: `Diubah ${i}` })),
    ...Array.from({ length: 20 }, (_, i) => mut("notes", randomUUID(), { body: `Baru ${i} https://baru.example.test/${i}`, checklist: [{ id: "x", text: "a", done: false }], labels: [labels[0]] })),
    ...Array.from({ length: 50 }, (_, i) => mut("contentItems", `pci${i}`, { ...items[i].data, title: `Edit ${i}` })),
    ...Array.from({ length: 50 }, (_, i) => mut("contentPosts", `pcp${100 + i}-0`, { ...posts[(100 + i) * 2].data, status: "posted", postedAt: new Date().toISOString() })),
  ];
  const t = await api("POST", "/api/mobile/sync", token, { mutations: mixed });
  const bad = t.json.results.filter((x) => x.status !== "applied");
  report("push 200 mixed mutations (100 tx edits, 50 tasks, 50 prayers)", t.ms, bad.length ? `(${bad.length} not applied: ${JSON.stringify(bad[0])})` : "");
  const tn = await api("POST", "/api/mobile/sync", token, { mutations: noteMix });
  const badN = tn.json.results.filter((x) => x.status !== "applied");
  report("push 200 notes/content mutations (80 note edits, 20 new notes, 50 items, 50 posts)", tn.ms, badN.length ? `(${badN.length} not applied: ${JSON.stringify(badN[0])})` : "");
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
