import { Prisma } from "@prisma/client";
import {
  createLedgerTransaction,
  deleteLedgerTransaction,
  updateLedgerTransaction,
  type Db,
} from "@/lib/ledger";
import { prisma } from "@/lib/prisma";
import {
  allocation,
  assetKey,
  assetKindInfo,
  assetSchema,
  deriveHolding,
  DIVIDEND_CATEGORY,
  dividendCategoryId,
  isAutoKind,
  linkedTransactionError,
  tradeCashEffect,
  tradeSchema,
  tradeTransactionNote,
  valueHolding,
  type AllocationSlice,
  type Holding,
  type TradeData,
  type Valuation,
} from "@/lib/investments";
import { nameKey } from "@/lib/notes";
import { priceService, type Quote, type PriceService } from "@/lib/prices";
import { localDateKey } from "@/lib/content";

/**
 * DB-side investment helpers shared by the mobile sync endpoint and the web server
 * actions (docs/investments.md). Pure rules live in src/lib/investments.ts, prices in
 * src/lib/prices.ts, deletes in src/lib/sync-deletes.ts.
 */

/** A validation failure whose message (Indonesian) is safe to show the user / return to a client. */
export class InvestmentError extends Error {}

type AssetRow = Prisma.AssetGetPayload<object>;
type TradeRow = Prisma.AssetTradeGetPayload<object>;

// ---------- Rows → wire / DTO shapes ----------

export function assetRowToInput(r: AssetRow) {
  return {
    kind: r.kind,
    symbol: r.symbol,
    name: r.name,
    currency: r.currency,
    priceMode: r.priceMode,
    manualPrice: r.manualPrice,
    manualPriceAt: r.manualPriceAt?.toISOString() ?? null,
    unit: r.unit,
    walletId: r.walletId,
    archived: r.archived,
    sortOrder: r.sortOrder,
  };
}

export function tradeRowToInput(r: TradeRow) {
  return {
    assetId: r.assetId,
    type: r.type,
    date: r.date.toISOString(),
    quantity: r.quantity,
    price: r.price,
    fee: r.fee,
    amount: r.amount,
    ratio: r.ratio,
    note: r.note,
    cashTransactionId: r.cashTransactionId,
  };
}

const stamps = (r: { id: string; createdAt: Date; updatedAt: Date }) => ({
  id: r.id,
  createdAt: r.createdAt.toISOString(),
  updatedAt: r.updatedAt.toISOString(),
});

export type AssetDTO = ReturnType<typeof toAssetDTO>;
export const toAssetDTO = (r: AssetRow) => ({ ...stamps(r), ...assetRowToInput(r) });
export type TradeDTO = ReturnType<typeof toTradeDTO>;
export const toTradeDTO = (r: TradeRow) => ({ ...stamps(r), ...tradeRowToInput(r) });

// ---------- Dividend category ----------

/**
 * The income category used for dividend cash: an existing income category named
 * "Dividen" (case-insensitive), else `category-dividen-<userId>` (created when missing).
 * With `recreate: false` (pull seeding) a default the user deleted (tombstoned) is not
 * re-created. Returns the category id, or null.
 */
export async function ensureDividendCategory(db: Db, userId: string, opts: { recreate: boolean }): Promise<string | null> {
  const income = await db.category.findMany({ where: { userId, type: "income" }, select: { id: true, name: true } });
  const named = income.find((c) => nameKey(c.name) === nameKey(DIVIDEND_CATEGORY.name));
  if (named) return named.id;
  const id = dividendCategoryId(userId);
  const own = await db.category.findUnique({ where: { id }, select: { userId: true, type: true } });
  if (own) return own.userId === userId && own.type === "income" ? id : null;
  const tomb = await db.syncTombstone.findFirst({ where: { userId, entity: "categories", entityId: id }, select: { id: true } });
  if (tomb && !opts.recreate) return null;
  await db.syncTombstone.deleteMany({ where: { userId, entity: "categories", entityId: id } });
  try {
    await db.category.create({ data: { id, userId, type: "income", ...DIVIDEND_CATEGORY } });
  } catch (e) {
    // Concurrent seed — the other request created it.
    if (!(e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002")) throw e;
  }
  return id;
}

/** Pull seeding: users with at least one asset get the "Dividen" category once. */
export async function ensureDividendCategoryForPull(db: Db, userId: string) {
  if ((await db.asset.count({ where: { userId } })) === 0) return;
  await ensureDividendCategory(db, userId, { recreate: false });
}

// ---------- Saves (sync + web) ----------

/**
 * Validate and create or update asset `id`. (kind, symbol) is unique per user
 * (case-insensitive): another asset holding it → "duplicate". `walletId` is a soft link:
 * a wallet that isn't the user's is stored as null.
 */
export async function saveAsset(
  db: Db,
  userId: string,
  id: string,
  input: unknown,
  exists: boolean,
): Promise<{ outcome: "applied"; row: AssetRow } | { outcome: "duplicate" }> {
  const d = assetSchema.parse(input);
  const others = await db.asset.findMany({ where: { userId, kind: d.kind }, select: { id: true, kind: true, symbol: true } });
  const key = assetKey(d.kind, d.symbol);
  if (others.some((o) => o.id !== id && assetKey(o.kind, o.symbol) === key)) return { outcome: "duplicate" };
  if (d.walletId && !(await db.wallet.findFirst({ where: { id: d.walletId, userId }, select: { id: true } }))) d.walletId = null;
  const row = exists ? await db.asset.update({ where: { id }, data: d }) : await db.asset.create({ data: { id, userId, ...d } });
  return { outcome: "applied", row };
}

/**
 * The trade sanity check (sync + web): with trade `id` replaced by `next` (null = removed),
 * holdings of `assetId` must not go negative where they didn't before. Throws InvestmentError.
 */
export async function assertTradeSequence(db: Db, userId: string, assetId: string, id: string, next: TradeData | null) {
  const rows = await db.assetTrade.findMany({ where: { userId, assetId } });
  const before = deriveHolding(rows);
  const others = rows.filter((r) => r.id !== id);
  const existing = rows.find((r) => r.id === id);
  const after = deriveHolding(next ? [...others, { ...next, id, createdAt: existing?.createdAt ?? null }] : others);
  const introduced = after.issues.length > before.issues.length || after.issues.some((i) => i.tradeId === id);
  if (after.issues.length && introduced) {
    const i = after.issues.find((x) => x.tradeId === id) ?? after.issues[0];
    throw new InvestmentError(`${i.message} per ${i.date.slice(0, 10)}`);
  }
}

/**
 * Validate a trade's `cashTransactionId` (a soft link, sync only): a transaction that
 * isn't the user's → null (it may have been deleted while offline); wrong type/sign or
 * already linked to another trade → InvestmentError.
 */
async function resolveCashLink(db: Db, userId: string, id: string, t: TradeData): Promise<string | null> {
  if (!t.cashTransactionId) return null;
  const tx = await db.transaction.findFirst({
    where: { id: t.cashTransactionId, userId },
    select: { type: true, amount: true },
  });
  if (!tx) return null;
  const err = linkedTransactionError(t.type, tx);
  if (err) throw new InvestmentError(err);
  const holder = await db.assetTrade.findUnique({ where: { cashTransactionId: t.cashTransactionId }, select: { id: true } });
  if (holder && holder.id !== id) throw new InvestmentError("Transaksi kas sudah terhubung ke transaksi aset lain");
  return t.cashTransactionId;
}

/**
 * Sync upsert of a trade: the asset must be the user's, the holding sanity check must
 * pass, and a linked cash transaction must fit (the client pushes that transaction as a
 * normal `transactions` upsert **before** the trade). Throws InvestmentError.
 */
export async function saveTrade(db: Db, userId: string, id: string, input: unknown, exists: boolean) {
  const t = tradeSchema.parse(input);
  const asset = await db.asset.findFirst({ where: { id: t.assetId, userId }, select: { id: true } });
  if (!asset) throw new InvestmentError("Aset tidak ditemukan");
  await assertTradeSequence(db, userId, t.assetId, id, t);
  const data = { ...t, cashTransactionId: await resolveCashLink(db, userId, id, t) };
  return exists ? db.assetTrade.update({ where: { id }, data }) : db.assetTrade.create({ data: { id, userId, ...data } });
}

/** How a web trade save handles cash: a wallet (default: the asset's), none, or keep as is (update). */
export type CashOption = { walletId?: string | null } | false | undefined;

/**
 * Web: create or update a trade together with its linked wallet transaction, atomically
 * (docs/investments.md "Cash effect"). `cash`:
 * - `{ walletId? }` → the trade moves cash in that wallet (default: the asset's wallet);
 * - `false` → no cash effect (a linked transaction is deleted, balance reversed);
 * - `undefined` → create: on when the asset has a wallet; update: keep the current link.
 * Split trades never move cash. Run inside `prisma.$transaction`. Returns the trade and
 * upload files to clean up (from a deleted linked transaction).
 */
export async function saveTradeWithCash(
  db: Db,
  userId: string,
  id: string,
  input: unknown,
  existing: TradeRow | null,
  cash: CashOption,
): Promise<{ row: TradeRow; files: string[] }> {
  const t = tradeSchema.parse(input);
  const asset = await db.asset.findFirst({ where: { id: t.assetId, userId } });
  if (!asset) throw new InvestmentError("Aset tidak ditemukan");
  await assertTradeSequence(db, userId, t.assetId, id, t);

  const linked = existing?.cashTransactionId
    ? await db.transaction.findFirst({ where: { id: existing.cashTransactionId, userId } })
    : null;
  let walletId: string | null = null;
  if (cash === undefined) walletId = existing ? (linked?.walletId ?? null) : asset.walletId;
  else if (cash !== false) walletId = cash.walletId ?? linked?.walletId ?? asset.walletId;
  const effect = walletId ? tradeCashEffect(t) : null;
  if (cash && !walletId && t.type !== "split")
    throw new InvestmentError("Pilih dompet untuk efek kas");
  if (walletId) {
    const w = await db.wallet.findFirst({ where: { id: walletId, userId }, select: { id: true } });
    if (!w) throw new InvestmentError("Dompet tidak ditemukan");
  }

  let files: string[] = [];
  let cashTransactionId: string | null = null;
  if (effect && walletId) {
    const categoryId = effect.type === "income" ? await ensureDividendCategory(db, userId, { recreate: true }) : null;
    const txData = {
      type: effect.type,
      amount: effect.amount,
      walletId,
      toWalletId: null,
      categoryId,
      note: tradeTransactionNote(t, asset),
      date: t.date,
    };
    if (linked) {
      // Keep a category the user picked for a dividend income.
      const keepCat = effect.type === "income" && linked.type === "income" && linked.categoryId ? linked.categoryId : categoryId;
      await updateLedgerTransaction(db, linked, { ...txData, categoryId: keepCat });
      cashTransactionId = linked.id;
    } else {
      cashTransactionId = (await createLedgerTransaction(db, userId, txData)).id;
    }
  } else if (linked) {
    files = await deleteLedgerTransaction(db, linked);
  }

  const data = { ...t, cashTransactionId };
  const row = existing
    ? await db.assetTrade.update({ where: { id }, data })
    : await db.assetTrade.create({ data: { id, userId, ...data } });
  return { row, files };
}

// ---------- Portfolio queries ----------

export type HoldingRow = {
  asset: AssetDTO;
  holding: Holding;
  valuation: Valuation;
  /** Price used: auto quote, manual price, or null. */
  priceSource: "auto" | "manual" | null;
  quote: Quote | null;
  /** Value counted in totals: market value, or cost basis when no price is known. */
  value: number;
};

export type PortfolioSummary = {
  marketValue: number;
  cost: number;
  unrealized: number;
  unrealizedPct: number | null;
  dayChange: number;
  realized: number;
  dividends: number;
  totalReturn: number;
  /** Assets valued at cost because no price is known. */
  unpricedCount: number;
  staleCount: number;
  byAsset: AllocationSlice[];
  byKind: AllocationSlice[];
};

export type Portfolio = { summary: PortfolioSummary; holdings: HoldingRow[]; pricesAsOf: string | null };

/**
 * Holdings of the user's assets (archived excluded unless asked) with prices and totals.
 * `refresh` (default true) lets the price service fetch stale quotes (cache rules in
 * src/lib/prices.ts); false = cached prices only. Records today's snapshot (lazy
 * "cron": one row per local day, updated by later requests that day).
 */
export async function getPortfolio(
  userId: string,
  opts: { refresh?: boolean; includeArchived?: boolean; snapshot?: boolean; service?: PriceService } = {},
): Promise<Portfolio> {
  const assets = await prisma.asset.findMany({
    where: { userId, ...(opts.includeArchived ? {} : { archived: false }) },
    orderBy: [{ sortOrder: "asc" }, { createdAt: "asc" }],
  });
  const trades = assets.length
    ? await prisma.assetTrade.findMany({ where: { userId, assetId: { in: assets.map((a) => a.id) } } })
    : [];
  const byAsset = new Map<string, TradeRow[]>();
  for (const t of trades) byAsset.set(t.assetId, [...(byAsset.get(t.assetId) ?? []), t]);

  const autoReqs = assets
    .filter((a) => a.priceMode === "auto" && isAutoKind(a.kind))
    .map((a) => ({ kind: a.kind as "stock" | "crypto", symbol: a.symbol }));
  const quotes = autoReqs.length
    ? await (opts.service ?? priceService()).getQuotes(autoReqs, { refresh: opts.refresh !== false })
    : [];
  const quoteMap = new Map(quotes.map((q) => [`${q.kind}:${q.symbol}`, q]));

  const holdings: HoldingRow[] = assets.map((a) => {
    const holding = deriveHolding(byAsset.get(a.id) ?? []);
    const quote = a.priceMode === "auto" ? (quoteMap.get(`${a.kind}:${a.symbol}`) ?? null) : null;
    let price: number | null = null;
    let prev: number | null = null;
    let priceSource: HoldingRow["priceSource"] = null;
    if (quote?.price != null) {
      price = quote.price;
      prev = quote.prevClose;
      priceSource = "auto";
    } else if (a.priceMode === "manual" && a.manualPrice != null) {
      price = a.manualPrice;
      priceSource = "manual";
    }
    const valuation = valueHolding(holding, price, prev);
    return { asset: toAssetDTO(a), holding, valuation, priceSource, quote, value: valuation.marketValue ?? holding.cost };
  });

  const sum = (f: (h: HoldingRow) => number | null) => holdings.reduce((s, h) => s + (f(h) ?? 0), 0);
  const marketValue = sum((h) => h.value);
  const cost = sum((h) => h.holding.cost);
  const unrealized = sum((h) => h.valuation.unrealized);
  const realized = sum((h) => h.holding.realized);
  const dividends = sum((h) => h.holding.dividends);
  const summary: PortfolioSummary = {
    marketValue,
    cost,
    unrealized,
    unrealizedPct: cost > 0 ? (unrealized / cost) * 100 : null,
    dayChange: sum((h) => h.valuation.dayChange),
    realized,
    dividends,
    totalReturn: unrealized + realized + dividends,
    unpricedCount: holdings.filter((h) => h.holding.shares > 0 && h.valuation.price == null).length,
    staleCount: holdings.filter((h) => h.holding.shares > 0 && h.quote?.stale).length,
    byAsset: allocation(holdings.map((h) => ({ key: h.asset.id, label: h.asset.symbol, value: h.value }))),
    byKind: allocation(holdings.map((h) => ({ key: h.asset.kind, label: assetKindInfo(h.asset.kind).label, value: h.value }))),
  };
  const asOfs = quotes.map((q) => q.fetchedAt).filter((x): x is string => !!x).sort();

  if (opts.snapshot !== false && assets.length > 0) await recordSnapshot(userId, marketValue, cost);
  return { summary, holdings, pricesAsOf: asOfs.length ? asOfs[0] : null };
}

/** Upsert today's (Asia/Jakarta) portfolio snapshot. */
export async function recordSnapshot(userId: string, value: number, cost: number, date = localDateKey(new Date())) {
  await prisma.portfolioSnapshot.upsert({
    where: { userId_date: { userId, date } },
    create: { userId, date, value, cost },
    update: { value, cost },
  });
}

/** Snapshots in [from, to] (YYYY-MM-DD), oldest first. */
export async function getPortfolioHistory(userId: string, range: { from: string; to: string }) {
  const rows = await prisma.portfolioSnapshot.findMany({
    where: { userId, date: { gte: range.from, lte: range.to } },
    orderBy: { date: "asc" },
  });
  return rows.map((r) => ({ date: r.date, value: r.value, cost: r.cost }));
}

export type AssetDetail = {
  asset: AssetDTO;
  holding: Holding;
  valuation: Valuation;
  quote: Quote | null;
  trades: TradeDTO[];
};

/** One asset with its holding, valuation, quote and trades (newest first). */
export async function getAssetDetail(userId: string, assetId: string, opts: { refresh?: boolean; service?: PriceService } = {}): Promise<AssetDetail | null> {
  const a = await prisma.asset.findFirst({ where: { id: assetId, userId } });
  if (!a) return null;
  const trades = await prisma.assetTrade.findMany({ where: { userId, assetId }, orderBy: [{ date: "desc" }, { createdAt: "desc" }] });
  const holding = deriveHolding(trades);
  let quote: Quote | null = null;
  if (a.priceMode === "auto" && isAutoKind(a.kind))
    [quote] = await (opts.service ?? priceService()).getQuotes([{ kind: a.kind, symbol: a.symbol }], { refresh: opts.refresh !== false });
  const price = quote?.price ?? (a.priceMode === "manual" ? a.manualPrice : null);
  return {
    asset: toAssetDTO(a),
    holding,
    valuation: valueHolding(holding, price, quote?.price != null ? quote.prevClose : null),
    quote,
    trades: trades.map(toTradeDTO),
  };
}

export type NetWorth = { cash: number; investments: number; total: number };

/**
 * Net worth = Σ non-archived wallet balances + Σ non-archived asset values (market value,
 * or cost basis when no price is known). Used by the dashboard and reports.
 */
export async function getNetWorth(userId: string, opts: { refresh?: boolean } = {}): Promise<NetWorth> {
  const wallets = await prisma.wallet.findMany({ where: { userId, archived: false }, select: { balance: true } });
  const cash = wallets.reduce((s, w) => s + w.balance, 0);
  const hasAssets = (await prisma.asset.count({ where: { userId, archived: false } })) > 0;
  const investments = hasAssets
    ? (await getPortfolio(userId, { refresh: opts.refresh, snapshot: false })).summary.marketValue
    : 0;
  return { cash, investments, total: cash + investments };
}
