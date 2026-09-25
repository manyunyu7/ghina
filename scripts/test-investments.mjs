#!/usr/bin/env node
// Unit tests for the pure investments module and the price service with a mocked fetch
// and an in-memory store (docs/investments.md). No server/DB/network needed:
//
//   node scripts/test-investments.mjs
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createJiti } from "jiti";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const jiti = createJiti(import.meta.url, { alias: { "@": join(root, "src") } });
const inv = await jiti.import(join(root, "src/lib/investments.ts"));
const pr = await jiti.import(join(root, "src/lib/prices.ts"));
const ledger = await jiti.import(join(root, "src/lib/ledger.ts"));
const schemas = await jiti.import(join(root, "src/lib/schemas.ts"));

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
const near = (a, b, e = 1e-6) => Math.abs(a - b) < e;
const err = (schema, v) => {
  const r = schema.safeParse(v);
  return r.success ? null : r.error.issues[0].message;
};
const T = (type, date, f = {}) => ({ id: `${type}-${date}-${f.quantity ?? f.amount ?? f.ratio ?? ""}`, type, date: `${date}T03:00:00.000Z`, quantity: null, price: null, fee: 0, amount: null, ratio: null, ...f });

console.log("constants / lots / fees");
check("kinds", eq(inv.ASSET_KIND_IDS, ["stock", "fund", "gold", "crypto", "bond", "other"]) && inv.assetKindInfo("gold").unit === "gram");
check("lot ↔ shares", inv.lotsToShares(10) === 1000 && inv.sharesToLots(250) === 2.5 && inv.isWholeLots(1000) && !inv.isWholeLots(150));
check("fee presets 0.15% / 0.25%", inv.FEE_PRESETS.buy === 0.0015 && inv.FEE_PRESETS.sell === 0.0025);
check("estimateFee", inv.estimateFee("buy", 9_500_000) === 14250 && inv.estimateFee("sell", 10_000_000) === 25000 &&
  inv.estimateFee("buy", 1000, { buy: 0.01, sell: 0 }) === 10 && inv.estimateFee("sell", 0) === 0);

console.log("symbols");
check("stock uppercased, .JK stripped", eq(inv.normalizeSymbol("stock", " bbca.jk "), { ok: true, symbol: "BBCA" }));
check("stock invalid", !inv.normalizeSymbol("stock", "BB CA").ok && !inv.normalizeSymbol("stock", "").ok);
check("crypto -IDR stripped", eq(inv.normalizeSymbol("crypto", "btc-idr"), { ok: true, symbol: "BTC" }));
check("other kinds free code ≤ 20 (case kept)", eq(inv.normalizeSymbol("fund", " Sucor MM "), { ok: true, symbol: "Sucor MM" }) && !inv.normalizeSymbol("gold", "x".repeat(21)).ok);
check("assetKey case-insensitive", inv.assetKey("fund", "abc") === inv.assetKey("fund", "ABC"));

console.log("asset schema");
{
  const a = inv.assetSchema.parse({ kind: "stock", symbol: "bbca" });
  check("stock defaults: auto, lembar, IDR", a.symbol === "BBCA" && a.priceMode === "auto" && a.unit === "lembar" && a.currency === "IDR" && a.walletId === null && a.archived === false, a);
  const g = inv.assetSchema.parse({ kind: "gold", symbol: "Antam", priceMode: "auto", manualPrice: 1_300_000, manualPriceAt: "2026-09-25T00:00:00Z", walletId: "" });
  check("gold forced manual, gram, manual price", g.priceMode === "manual" && g.unit === "gram" && g.manualPrice === 1_300_000 && g.manualPriceAt instanceof Date && g.walletId === null, g);
  check("crypto manual allowed", inv.assetSchema.parse({ kind: "crypto", symbol: "btc", priceMode: "manual" }).priceMode === "manual");
  check("bad kind / symbol / currency / negative price rejected",
    err(inv.assetSchema, { kind: "house", symbol: "x" }) !== null && /Kode saham/.test(err(inv.assetSchema, { kind: "stock", symbol: "!!" }) ?? "") &&
    err(inv.assetSchema, { kind: "stock", symbol: "BBCA", currency: "rupiah" }) !== null && err(inv.assetSchema, { kind: "fund", symbol: "x", manualPrice: -1 }) !== null);
}

console.log("trade schema");
{
  const b = inv.tradeSchema.parse({ assetId: "a", type: "buy", date: "2026-09-25T03:00:00Z", quantity: 1000, price: 9500, fee: 14250, amount: 5, ratio: 2, note: " beli " });
  check("buy keeps q/p/fee, drops amount/ratio", b.quantity === 1000 && b.price === 9500 && b.fee === 14250 && b.amount === null && b.ratio === null && b.note === "beli" && b.cashTransactionId === null, b);
  check("buy needs quantity/price > 0", /Jumlah/.test(err(inv.tradeSchema, { assetId: "a", type: "buy", date: "2026-09-25T03:00:00Z", quantity: 0, price: 1 }) ?? "") &&
    /Harga/.test(err(inv.tradeSchema, { assetId: "a", type: "sell", date: "2026-09-25T03:00:00Z", quantity: 1 }) ?? ""));
  const d = inv.tradeSchema.parse({ assetId: "a", type: "dividend", date: "2026-09-25T03:00:00Z", amount: 250000, quantity: 5, fee: 3 });
  check("dividend: amount only, fee 0", d.amount === 250000 && d.quantity === null && d.fee === 0, d);
  check("split ratio > 0 and ≠ 1", err(inv.tradeSchema, { assetId: "a", type: "split", date: "2026-09-25T03:00:00Z", ratio: 1 }) !== null &&
    inv.tradeSchema.parse({ assetId: "a", type: "split", date: "2026-09-25T03:00:00Z", ratio: 5 }).ratio === 5);
  check("fee needs amount > 0", err(inv.tradeSchema, { assetId: "a", type: "fee", date: "2026-09-25T03:00:00Z" }) !== null);
  check("date needs offset; negative fee rejected", err(inv.tradeSchema, { assetId: "a", type: "fee", date: "2026-09-25", amount: 1 }) !== null &&
    err(inv.tradeSchema, { assetId: "a", type: "buy", date: "2026-09-25T03:00:00Z", quantity: 1, price: 1, fee: -1 }) !== null);
}

console.log("holding derivation (average cost)");
{
  const trades = [
    T("buy", "2026-01-10", { quantity: 1000, price: 9000, fee: 13500 }),
    T("buy", "2026-02-10", { quantity: 1000, price: 10000, fee: 15000 }),
    T("sell", "2026-03-10", { quantity: 500, price: 11000, fee: 13750 }),
    T("dividend", "2026-04-10", { amount: 200000 }),
    T("fee", "2026-05-10", { amount: 5000 }),
  ];
  const hld = inv.deriveHolding([...trades].reverse()); // order by date regardless of input order
  // cost after buys = 9,013,500 + 10,015,000 = 19,028,500 for 2000 → avg 9514.25
  // sell 500: realized = 5,500,000 − 13,750 − 500·9514.25 = 729,125; cost −= 4,757,125 → 14,271,375
  check("shares 1500", hld.shares === 1500, hld);
  check("cost basis 14,271,375 / avg 9514.25", near(hld.cost, 14_271_375) && near(hld.avgPrice, 9514.25), hld);
  check("realized 729,125 − fee row 5,000 = 724,125", near(hld.realized, 724_125), hld.realized);
  check("dividends 200,000; fees total", near(hld.dividends, 200_000) && near(hld.fees, 13500 + 15000 + 13750 + 5000));
  check("no issues", hld.issues.length === 0 && inv.tradeSequenceError(trades) === null);

  const split = inv.deriveHolding([T("buy", "2026-01-01", { quantity: 100, price: 5000 }), T("split", "2026-02-01", { ratio: 5 })]);
  check("split: shares ×5, cost unchanged, avg ÷5", split.shares === 500 && split.cost === 500_000 && split.avgPrice === 1000, split);

  const full = inv.deriveHolding([T("buy", "2026-01-01", { quantity: 300, price: 1000 }), T("sell", "2026-02-01", { quantity: 300, price: 1200, fee: 900 })]);
  check("full exit: 0 shares, 0 cost, avg null, realized 59,100", full.shares === 0 && full.cost === 0 && full.avgPrice === null && near(full.realized, 59_100), full);

  const over = [T("buy", "2026-01-01", { quantity: 100, price: 1000 }), T("sell", "2026-02-01", { quantity: 150, price: 1000 })];
  check("sell more than held → issue (Indonesian) + clamped", inv.deriveHolding(over).issues.length === 1 && inv.deriveHolding(over).shares === 0 &&
    /melebihi kepemilikan/.test(inv.tradeSequenceError(over) ?? ""), inv.tradeSequenceError(over));
  const outOfOrder = [T("sell", "2026-01-01", { quantity: 100, price: 1000 }), T("buy", "2026-02-01", { quantity: 100, price: 1000 })];
  check("date order matters: sell before buy is rejected", inv.tradeSequenceError(outOfOrder) !== null);
  const sameDay = [
    { ...T("buy", "2026-01-01", { quantity: 100, price: 1000 }), createdAt: "2026-01-01T05:00:00Z" },
    { ...T("sell", "2026-01-01", { quantity: 100, price: 1100 }), createdAt: "2026-01-01T06:00:00Z" },
  ];
  check("same date: createdAt breaks the tie", inv.tradeSequenceError(sameDay) === null && inv.tradeSequenceError([sameDay[1], { ...sameDay[0], createdAt: "2026-01-01T07:00:00Z" }]) !== null);
  check("float tolerance (0.1 + 0.2 crypto)", inv.tradeSequenceError([T("buy", "2026-01-01", { quantity: 0.1, price: 1 }), T("buy", "2026-01-02", { quantity: 0.2, price: 1 }), T("sell", "2026-01-03", { quantity: 0.3, price: 1 })]) === null);
}

console.log("valuation / allocation");
{
  const hld = inv.deriveHolding([T("buy", "2026-01-01", { quantity: 1000, price: 9000, fee: 13500 })]);
  const v = inv.valueHolding(hld, 9500, 9400);
  check("market value / unrealized / %", v.marketValue === 9_500_000 && v.unrealized === 486_500 && near(v.unrealizedPct, (486_500 / 9_013_500) * 100), v);
  check("day change", v.dayChange === 100_000 && near(v.dayChangePct, (100 / 9400) * 100));
  check("total return = unrealized + realized + dividends", v.totalReturn === 486_500);
  const nv = inv.valueHolding(hld, null);
  check("no price → nulls, totalReturn without unrealized", nv.marketValue === null && nv.unrealized === null && nv.dayChange === null && nv.totalReturn === 0);
  const al = inv.allocation([{ key: "a", label: "BBCA", value: 300 }, { key: "b", label: "BTC", value: 100 }, { key: "a", label: "BBCA", value: 100 }, { key: "c", label: "X", value: 0 }, { key: "d", label: "Y", value: null }]);
  check("allocation merged, sorted, pct, empties dropped", eq(al.map((x) => [x.key, x.value, x.pct]), [["a", 400, 80], ["b", 100, 20]]), al);
}

console.log("cash effect");
{
  check("buy → investment −(q·p + fee)", eq(inv.tradeCashEffect({ type: "buy", quantity: 1000, price: 9500, fee: 14250, amount: null }), { type: "investment", amount: -9_514_250 }));
  check("sell → investment +(q·p − fee)", eq(inv.tradeCashEffect({ type: "sell", quantity: 500, price: 10000, fee: 12500, amount: null }), { type: "investment", amount: 4_987_500 }));
  check("fee → investment −amount", eq(inv.tradeCashEffect({ type: "fee", quantity: null, price: null, fee: 0, amount: 5000 }), { type: "investment", amount: -5000 }));
  check("dividend → income +amount", eq(inv.tradeCashEffect({ type: "dividend", quantity: null, price: null, fee: 0, amount: 200000 }), { type: "income", amount: 200000 }));
  check("split → none; zero → none", inv.tradeCashEffect({ type: "split", quantity: null, price: null, fee: 0, amount: null, ratio: 2 }) === null &&
    inv.tradeCashEffect({ type: "sell", quantity: 1, price: 10, fee: 10, amount: null }) === null);
  check("rounded to 2 decimals", inv.tradeCashEffect({ type: "buy", quantity: 0.5, price: 1000.555, fee: 0, amount: null }).amount === -500.28);
  check("note: lots for stocks", inv.tradeTransactionNote({ type: "buy", quantity: 1000, price: 9500 }, { kind: "stock", symbol: "BBCA" }) === "Beli BBCA 10 lot @ 9.500");
  check("note: units otherwise", inv.tradeTransactionNote({ type: "sell", quantity: 0.5, price: 1e9 }, { kind: "crypto", symbol: "BTC", unit: "koin" }) === "Jual BTC 0,5 koin @ 1.000.000.000");
  check("note: dividend", inv.tradeTransactionNote({ type: "dividend" }, { kind: "stock", symbol: "BBRI" }) === "Dividen BBRI");
  check("linked tx checks", inv.linkedTransactionError("buy", { type: "investment", amount: -5 }) === null &&
    inv.linkedTransactionError("buy", { type: "investment", amount: 5 }) !== null && inv.linkedTransactionError("sell", { type: "expense", amount: 5 }) !== null &&
    inv.linkedTransactionError("dividend", { type: "income", amount: 5 }) === null && inv.linkedTransactionError("split", { type: "investment", amount: 1 }) !== null);
  check("dividend category id deterministic", inv.dividendCategoryId("u1") === "category-dividen-u1" && inv.DIVIDEND_CATEGORY.name === "Dividen");
}

console.log("investment transaction type (ledger + validation)");
{
  check("investment is a transaction type, not cashflow", schemas.TRANSACTION_TYPES.includes("investment") && !schemas.CASHFLOW_TYPES.includes("investment"));
  const ok = schemas.transactionSchema.safeParse({ type: "investment", amount: -9_514_250, walletId: "w", date: "2026-09-25T03:00:00Z" });
  check("signed amount accepted", ok.success && ok.data.amount === -9_514_250);
  check("zero rejected", !schemas.transactionSchema.safeParse({ type: "investment", amount: 0, walletId: "w", date: "2026-09-25T03:00:00Z" }).success);
  check("effect: +amount (signed) to wallet", eq(ledger.effects({ type: "investment", amount: -500, walletId: "w", toWalletId: null }), { w: -500 }));
  check("edit reverses + applies", eq(ledger.ledgerDeltas({ type: "investment", amount: -500, walletId: "w", toWalletId: null }, { type: "investment", amount: 300, walletId: "w", toWalletId: null }), { w: 800 }));
}

console.log("prices: parsing / symbols / session");
{
  const chart = { chart: { result: [{ meta: { currency: "IDR", symbol: "BBCA.JK", regularMarketPrice: 9575, chartPreviousClose: 9500, regularMarketTime: 1790406000, longName: "PT Bank Central Asia Tbk", shortName: "Bank Central Asia Tbk." }, indicators: { quote: [{ close: [9575] }] } }], error: null } };
  const p = pr.parseYahooChart(chart);
  check("parseYahooChart meta", p.price === 9575 && p.prevClose === 9500 && p.currency === "IDR" && p.name === "PT Bank Central Asia Tbk" && p.asOf.getTime() === 1790406000000, p);
  check("fallback to last close", pr.parseYahooChart({ chart: { result: [{ meta: { currency: "IDR" }, indicators: { quote: [{ close: [100, 101, null] }] } }] } }).price === 101);
  check("not-found shape → null", pr.parseYahooChart({ chart: { result: null, error: { code: "Not Found", description: "No data found, symbol may be delisted" } } }) === null);
  const ps = pr.parsePriceSymbols("stock:bbca, crypto:BTC-IDR,STOCK:BBCA.JK,stock:TLKM");
  check("parsePriceSymbols normalizes + dedupes", ps.ok && eq(ps.items, [{ kind: "stock", symbol: "BBCA" }, { kind: "crypto", symbol: "BTC" }, { kind: "stock", symbol: "TLKM" }]), ps);
  check("parsePriceSymbols errors", !pr.parsePriceSymbols("").ok && !pr.parsePriceSymbols("fund:ABC").ok && !pr.parsePriceSymbols("stock:!!").ok &&
    !pr.parsePriceSymbols(Array.from({ length: 51 }, (_, i) => `stock:A${i}`).join(",")).ok && pr.parsePriceSymbols(Array.from({ length: 50 }, (_, i) => `stock:A${i}`).join(",")).ok);
  check("yahoo symbols", pr.yahooSymbol({ kind: "stock", symbol: "BBCA" }) === "BBCA.JK" && pr.yahooSymbol({ kind: "crypto", symbol: "BTC" }) === "BTC-IDR");
  const wib = (s) => new Date(`${s}+07:00`);
  check("IDX open Fri 10:00 WIB, closed 16:15, 08:59, Saturday", pr.idxMarketOpen(wib("2026-09-25T10:00:00")) && !pr.idxMarketOpen(wib("2026-09-25T16:15:00")) &&
    pr.idxMarketOpen(wib("2026-09-25T16:14:59")) && !pr.idxMarketOpen(wib("2026-09-25T08:59:00")) && !pr.idxMarketOpen(wib("2026-09-26T10:00:00")));
  check("last close: Sat → Fri 16:15; Mon 08:00 → Fri; Mon 17:00 → Mon", pr.lastIdxClose(wib("2026-09-26T12:00:00")).getTime() === wib("2026-09-25T16:15:00").getTime() &&
    pr.lastIdxClose(wib("2026-09-28T08:00:00")).getTime() === wib("2026-09-25T16:15:00").getTime() && pr.lastIdxClose(wib("2026-09-28T17:00:00")).getTime() === wib("2026-09-28T16:15:00").getTime());
  check("fresh: open → 15 min", pr.isPriceFresh("stock", wib("2026-09-25T10:00:00"), wib("2026-09-25T10:14:00")) && !pr.isPriceFresh("stock", wib("2026-09-25T10:00:00"), wib("2026-09-25T10:16:00")));
  check("fresh: closed → until next session if fetched after the close", pr.isPriceFresh("stock", wib("2026-09-25T16:20:00"), wib("2026-09-28T08:59:00")) &&
    !pr.isPriceFresh("stock", wib("2026-09-25T16:20:00"), wib("2026-09-28T09:00:00")) && !pr.isPriceFresh("stock", wib("2026-09-25T16:00:00"), wib("2026-09-25T20:00:00")));
  check("crypto: always 15 min", !pr.isPriceFresh("crypto", wib("2026-09-26T10:00:00"), wib("2026-09-26T10:20:00")));
}

console.log("price service (mocked fetch, in-memory store)");
{
  const memStore = () => {
    const rows = new Map();
    return {
      rows,
      async get(reqs) {
        return reqs.map((r) => rows.get(`${r.kind}:${r.symbol}`)).filter(Boolean).map((r) => ({ ...r }));
      },
      async saveSuccess(row) {
        rows.set(`${row.kind}:${row.symbol}`, { ...row, checkedAt: row.fetchedAt, error: null });
      },
      async saveFailure(r, error, at) {
        const row = rows.get(`${r.kind}:${r.symbol}`);
        if (row) Object.assign(row, { checkedAt: at, error });
      },
    };
  };
  const quoteBody = (price, prev, name) => ({ chart: { result: [{ meta: { currency: "IDR", regularMarketPrice: price, chartPreviousClose: prev, regularMarketTime: 1790406000, longName: name } }], error: null } });
  let clock = new Date("2026-09-25T03:00:00Z"); // Fri 10:00 WIB (open)
  const calls = [];
  let responder = () => ({ status: 200, body: quoteBody(9575, 9500, "BCA") });
  const fetchImpl = async (url, init) => {
    calls.push(url);
    const r = await responder(url, init);
    return { status: r.status, ok: r.status >= 200 && r.status < 300, json: async () => r.body };
  };
  const store = memStore();
  const svc = pr.createPriceService({ store, fetchImpl, now: () => clock, timeoutMs: 50 });

  let [q] = await svc.getQuotes([{ kind: "stock", symbol: "BBCA" }]);
  check("first request fetches Yahoo chart for BBCA.JK", calls.length === 1 && calls[0].includes("/v8/finance/chart/BBCA.JK?range=1d&interval=1d"), calls);
  check("quote fields (change, pct, name, fresh)", q.price === 9575 && q.prevClose === 9500 && q.change === 75 && near(q.changePct, (75 / 9500) * 100) && q.name === "BCA" && q.stale === false && q.error === null, q);
  await svc.getQuotes([{ kind: "stock", symbol: "BBCA" }]);
  check("cached within 15 min (no new call)", calls.length === 1);
  clock = new Date(clock.getTime() + 16 * 60_000);
  responder = () => ({ status: 200, body: quoteBody(9600, 9500, "BCA") });
  [q] = await svc.getQuotes([{ kind: "stock", symbol: "BBCA" }]);
  check("refetched after 15 min during session", calls.length === 2 && q.price === 9600);

  // batch: concurrency + dedupe
  let inflight = 0;
  let maxInflight = 0;
  responder = async (url) => {
    inflight++;
    maxInflight = Math.max(maxInflight, inflight);
    await new Promise((r) => setTimeout(r, 5));
    inflight--;
    return { status: 200, body: quoteBody(100 + calls.length, 100, url) };
  };
  const svc2 = pr.createPriceService({ store: memStore(), fetchImpl, now: () => clock, concurrency: 3 });
  const before = calls.length;
  const reqs = Array.from({ length: 8 }, (_, i) => ({ kind: "stock", symbol: `S${i}` }));
  const [r1, r2] = await Promise.all([svc2.getQuotes(reqs), svc2.getQuotes(reqs.slice(0, 2))]);
  check("batched: one call per symbol, concurrent duplicates share a fetch", calls.length - before === 8 && r1.every((x) => x.price != null) && r2.every((x) => x.price != null), calls.length - before);
  check("batched: ≤ concurrency in flight", maxInflight <= 3 + 2, maxInflight);

  // failures keep the last price, marked stale; retried only after 10 min
  clock = new Date(clock.getTime() + 20 * 60_000);
  responder = () => ({ status: 503, body: null });
  [q] = await svc.getQuotes([{ kind: "stock", symbol: "BBCA" }]);
  check("failure → last price kept, stale, error unavailable", q.price === 9600 && q.stale === true && q.error === "unavailable", q);
  const n = calls.length;
  clock = new Date(clock.getTime() + 5 * 60_000);
  [q] = await svc.getQuotes([{ kind: "stock", symbol: "BBCA" }]);
  check("no retry within 10 min of a failure", calls.length === n && q.stale, q);
  clock = new Date(clock.getTime() + 6 * 60_000);
  responder = () => ({ status: 200, body: quoteBody(9700, 9600, "BCA") });
  [q] = await svc.getQuotes([{ kind: "stock", symbol: "BBCA" }]);
  check("retried after 10 min → fresh again", calls.length === n + 1 && q.price === 9700 && !q.stale && q.error === null, q);

  // timeout
  clock = new Date(clock.getTime() + 16 * 60_000);
  responder = (_url, init) => new Promise((_res, rej) => init.signal.addEventListener("abort", () => rej(new Error("aborted"))));
  const t0 = Date.now();
  const keepAlive = setInterval(() => {}, 1000); // AbortSignal.timeout's timer is unref'd
  [q] = await svc.getQuotes([{ kind: "stock", symbol: "BBCA" }]);
  clearInterval(keepAlive);
  check("per-request timeout → unavailable, last price kept", Date.now() - t0 < 2000 && q.price === 9700 && q.stale && q.error === "unavailable", q);

  // not found
  responder = () => ({ status: 404, body: { chart: { result: null, error: { code: "Not Found", description: "No data found, symbol may be delisted" } } } });
  let lk = await svc.lookup({ kind: "stock", symbol: "ZZZZ" });
  check("lookup unknown symbol → not_found", lk.status === "not_found");
  const n2 = calls.length;
  [q] = await svc.getQuotes([{ kind: "stock", symbol: "ZZZZ" }]);
  check("unknown symbol remembered (no refetch), price null", calls.length === n2 && q.price === null && q.error === "not_found", q);
  responder = () => ({ status: 200, body: quoteBody(1_650_000_000, 1_640_000_000, "Bitcoin IDR") });
  lk = await svc.lookup({ kind: "crypto", symbol: "BTC" });
  check("lookup ok → name + price (crypto BTC-IDR)", lk.status === "ok" && lk.quote.name === "Bitcoin IDR" && calls.at(-1).includes("BTC-IDR"), lk);

  // 429 → global pause
  clock = new Date(clock.getTime() + 16 * 60_000);
  responder = () => ({ status: 429, body: null });
  [q] = await svc.getQuotes([{ kind: "crypto", symbol: "BTC" }]);
  const n3 = calls.length;
  const qs = await svc.getQuotes([{ kind: "crypto", symbol: "ETH" }, { kind: "stock", symbol: "TLKM" }]);
  check("429 → rate_limited, every symbol paused (no further calls)", q.error === "rate_limited" && q.stale && calls.length === n3 && qs.every((x) => x.error === "rate_limited"), { q, qs });
  lk = await svc.lookup({ kind: "stock", symbol: "TLKM" });
  check("lookup while rate limited → unavailable (asset can still be added)", lk.status === "unavailable");
  clock = new Date(clock.getTime() + 16 * 60_000);
  responder = () => ({ status: 200, body: quoteBody(3000, 2950, "Telkom") });
  [q] = await svc.getQuotes([{ kind: "stock", symbol: "TLKM" }]);
  check("resumes after the pause", q.price === 3000 && !q.stale);

  const cached = await svc.getQuotes([{ kind: "stock", symbol: "BBCA" }], { refresh: false });
  check("refresh:false answers from cache only", cached[0].price === 9700 && cached[0].stale === true);
  check("empty request → []", (await svc.getQuotes([])).length === 0);
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
