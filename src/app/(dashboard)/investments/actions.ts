"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { deleteSynced } from "@/lib/sync-deletes";
import { deleteUnreferencedUploads } from "@/lib/uploads";
import { assertId, assertIds, assertObject, pick, runAction, UserError, type ActionResult } from "@/lib/action-utils";
import { isValidDateKey } from "@/lib/prayer-quality";
import { isAutoKind, normalizeSymbol, type AssetKind, type TradeType } from "@/lib/investments";
import { priceService, type Quote } from "@/lib/prices";
import {
  assetRowToInput,
  getAssetDetail,
  getPortfolio,
  getPortfolioHistory,
  saveAsset,
  saveTradeWithCash,
  tradeRowToInput,
  type AssetDetail,
  type CashOption,
  type Portfolio,
} from "@/lib/investments-server";

/**
 * Server actions for the web Portfolio page (docs/investments.md). Plain-object
 * arguments, results `{ ok: true, … } | { ok: false, error }` with Indonesian messages.
 * Validation is shared with mobile sync (src/lib/investments.ts,
 * src/lib/investments-server.ts). Trades and their wallet transaction change atomically.
 */

export type AssetInput = {
  kind: AssetKind;
  /** Stock: IDX ticker (BBCA); crypto: BTC; others: free code ≤ 20. */
  symbol: string;
  /** Default for stock/crypto: the name from the price service. */
  name?: string | null;
  currency?: string;
  /** Only stock/crypto can be "auto"; other kinds are always manual. */
  priceMode?: "auto" | "manual";
  manualPrice?: number | null;
  /** YYYY-MM-DD or ISO; default now when manualPrice is given. */
  manualPriceAt?: string | null;
  /** Default per kind: lembar / unit / gram / koin. */
  unit?: string | null;
  /** The investment wallet / RDN (trades move cash here by default). */
  walletId?: string | null;
  archived?: boolean;
  sortOrder?: number;
};

export type TradeInput = {
  assetId: string;
  type: TradeType;
  /** YYYY-MM-DD (stored as 12:00 WIB) or ISO. */
  date: string;
  /** Units (shares). For stocks the UI may convert lots: `lotsToShares(lots)`. */
  quantity?: number | null;
  price?: number | null;
  /** Broker fee + tax (buy/sell). See `estimateFee` / FEE_PRESETS in src/lib/investments.ts. */
  fee?: number;
  /** dividend: cash received; fee: the fee. */
  amount?: number | null;
  /** split: new units per old unit. */
  ratio?: number | null;
  note?: string | null;
};

const ASSET_KEYS = [
  "kind", "symbol", "name", "currency", "priceMode", "manualPrice", "manualPriceAt", "unit", "walletId", "archived", "sortOrder",
] as const;
const TRADE_KEYS = ["assetId", "type", "date", "quantity", "price", "fee", "amount", "ratio", "note"] as const;

function revalidate(money = false) {
  revalidatePath("/investments");
  revalidatePath("/dashboard");
  revalidatePath("/reports");
  if (money) {
    revalidatePath("/wallets");
    revalidatePath("/transactions");
  }
}

/** YYYY-MM-DD → 12:00 WIB; ISO passes through; anything else → UserError. */
function isoFromInput(v: unknown, label = "Tanggal"): string {
  if (typeof v === "string" && isValidDateKey(v)) return new Date(`${v}T12:00:00+07:00`).toISOString();
  if (typeof v === "string" && !Number.isNaN(Date.parse(v)) && /T.*(Z|[+-]\d\d:?\d\d)$/.test(v)) return new Date(v).toISOString();
  throw new UserError(`${label} tidak valid`);
}

function normalizeCash(cash: unknown): CashOption {
  if (cash === undefined) return undefined;
  if (cash === false || cash === null) return false;
  assertObject(cash, "Efek kas");
  const walletId = (cash as { walletId?: unknown }).walletId;
  if (walletId != null) assertId(walletId, "Dompet tidak ditemukan");
  return { walletId: (walletId as string | null | undefined) ?? null };
}

// ---------- Symbols ----------

/**
 * Validate a stock/crypto code against the price service (for "add asset"):
 * `ok` (+ name, price), `not_found`, or `unavailable` (price source down — adding is still allowed).
 */
export async function lookupSymbol(
  kind: "stock" | "crypto",
  symbol: string,
): Promise<ActionResult<{ status: "ok" | "not_found" | "unavailable"; symbol: string; quote: Quote | null }>> {
  return runAction("investments", async () => {
    await requireUser();
    if (kind !== "stock" && kind !== "crypto") throw new UserError("Jenis aset tidak valid");
    if (typeof symbol !== "string") throw new UserError("Kode tidak valid");
    const n = normalizeSymbol(kind, symbol);
    if (!n.ok) throw new UserError(n.error);
    const r = await priceService().lookup({ kind, symbol: n.symbol });
    return { status: r.status, symbol: n.symbol, quote: r.status === "ok" ? r.quote : null };
  });
}

// ---------- Assets ----------

export async function createAsset(input: AssetInput): Promise<ActionResult<{ id: string; name: string | null }>> {
  return runAction("investments", async () => {
    assertObject(input);
    const user = await requireUser();
    const data: Record<string, unknown> = pick(input, ASSET_KEYS);
    if (data.manualPriceAt != null) data.manualPriceAt = isoFromInput(data.manualPriceAt, "Tanggal harga");
    else if (typeof data.manualPrice === "number") data.manualPriceAt = new Date().toISOString();
    // Auto-priced stock/crypto: the code must exist (name auto-filled). If the price source
    // is unavailable the asset is still created (validated on the next price fetch).
    const kind = String(data.kind ?? "");
    if (isAutoKind(kind) && data.priceMode !== "manual" && typeof data.symbol === "string") {
      const n = normalizeSymbol(kind, data.symbol);
      if (n.ok) {
        const r = await priceService().lookup({ kind, symbol: n.symbol });
        if (r.status === "not_found")
          throw new UserError(kind === "stock" ? `Kode saham ${n.symbol} tidak ditemukan di BEI` : `Kode kripto ${n.symbol} tidak ditemukan`);
        if (r.status === "ok" && !data.name) data.name = r.quote.name;
      }
    }
    if (data.sortOrder === undefined) {
      const last = await prisma.asset.findFirst({ where: { userId: user.id }, orderBy: { sortOrder: "desc" }, select: { sortOrder: true } });
      data.sortOrder = (last?.sortOrder ?? -1) + 1;
    }
    const id = randomUUID();
    const res = await saveAsset(prisma, user.id, id, data, false);
    if (res.outcome === "duplicate") throw new UserError("Aset dengan kode ini sudah ada");
    revalidate();
    return { id, name: res.row.name };
  });
}

export async function updateAsset(id: string, patch: Partial<AssetInput>): Promise<ActionResult> {
  return runAction("investments", async () => {
    assertId(id, "Aset tidak ditemukan");
    assertObject(patch);
    const user = await requireUser();
    await prisma.$transaction(async (db) => {
      const a = await db.asset.findFirst({ where: { id, userId: user.id } });
      if (!a) throw new UserError("Aset tidak ditemukan");
      const p: Record<string, unknown> = pick(patch, ASSET_KEYS);
      if (p.manualPriceAt != null) p.manualPriceAt = isoFromInput(p.manualPriceAt, "Tanggal harga");
      const res = await saveAsset(db, user.id, id, { ...assetRowToInput(a), ...p }, true);
      if (res.outcome === "duplicate") throw new UserError("Aset dengan kode ini sudah ada");
    });
    revalidate();
    return {};
  });
}

/**
 * Delete an asset with all its trades; their linked wallet transactions are deleted too
 * (balances reversed). Suggest archiving to keep history.
 */
export async function deleteAsset(id: string): Promise<ActionResult> {
  return runAction("investments", async () => {
    assertId(id, "Aset tidak ditemukan");
    const user = await requireUser();
    const a = await prisma.asset.findFirst({ where: { id, userId: user.id }, select: { id: true } });
    if (!a) throw new UserError("Aset tidak ditemukan");
    await deleteSynced(user.id, "assets", a.id);
    revalidate(true);
    return {};
  });
}

export async function setAssetArchived(id: string, archived: boolean): Promise<ActionResult> {
  return updateAsset(id, { archived: archived === true });
}

export async function reorderAssets(orderedIds: string[]): Promise<ActionResult> {
  return runAction("investments", async () => {
    assertIds(orderedIds, "Aset tidak ditemukan");
    const user = await requireUser();
    await prisma.$transaction(async (db) => {
      for (const [i, id] of orderedIds.entries())
        await db.asset.updateMany({ where: { id, userId: user.id, sortOrder: { not: i } }, data: { sortOrder: i } });
    });
    revalidate();
    return {};
  });
}

/** Manual price (fund NAV, gold per gram, …) "harga manual per <date>". Switches the asset to manual. */
export async function setManualPrice(assetId: string, price: number, date?: string | null): Promise<ActionResult> {
  return runAction("investments", async () => {
    if (!(typeof price === "number" && Number.isFinite(price) && price >= 0)) throw new UserError("Harga tidak valid");
    return unwrap(
      await updateAsset(assetId, {
        priceMode: "manual",
        manualPrice: price,
        manualPriceAt: date ? isoFromInput(date, "Tanggal harga") : new Date().toISOString(),
      }),
    );
  });
}

function unwrap(r: ActionResult): object {
  if (!r.ok) throw new UserError(r.error);
  return {};
}

// ---------- Trades ----------

/**
 * Record a trade. `cash`: `{ walletId? }` moves cash in that wallet (default the asset's
 * wallet) — buy/fee as an `investment` expense-like debit, sell as a credit, dividend as
 * income ("Dividen"); `false` = no cash effect; omitted = on when the asset has a wallet.
 * Rejected when it would sell more than held (in date order).
 */
export async function createTrade(input: TradeInput, cash?: { walletId?: string | null } | false): Promise<ActionResult<{ id: string; cashTransactionId: string | null }>> {
  return runAction("investments", async () => {
    assertObject(input);
    const c = normalizeCash(cash);
    const user = await requireUser();
    const data = { ...pick(input, TRADE_KEYS), date: isoFromInput(input.date) };
    const id = randomUUID();
    const { row, files } = await prisma.$transaction((db) => saveTradeWithCash(db, user.id, id, data, null, c));
    await deleteUnreferencedUploads(files);
    revalidate(true);
    return { id, cashTransactionId: row.cashTransactionId };
  });
}

/** Edit a trade; its linked wallet transaction follows (`cash` as in createTrade; omitted = keep). */
export async function updateTrade(
  id: string,
  patch: Partial<TradeInput>,
  cash?: { walletId?: string | null } | false,
): Promise<ActionResult<{ cashTransactionId: string | null }>> {
  return runAction("investments", async () => {
    assertId(id, "Transaksi aset tidak ditemukan");
    assertObject(patch);
    const c = normalizeCash(cash);
    const user = await requireUser();
    const { row, files } = await prisma.$transaction(async (db) => {
      const existing = await db.assetTrade.findFirst({ where: { id, userId: user.id } });
      if (!existing) throw new UserError("Transaksi aset tidak ditemukan");
      const p: Record<string, unknown> = pick(patch, TRADE_KEYS);
      if (p.date !== undefined) p.date = isoFromInput(p.date);
      return saveTradeWithCash(db, user.id, id, { ...tradeRowToInput(existing), ...p }, existing, c);
    });
    await deleteUnreferencedUploads(files);
    revalidate(true);
    return { cashTransactionId: row.cashTransactionId };
  });
}

/** Delete a trade and its linked wallet transaction (balance reversed). */
export async function deleteTrade(id: string): Promise<ActionResult> {
  return runAction("investments", async () => {
    assertId(id, "Transaksi aset tidak ditemukan");
    const user = await requireUser();
    const t = await prisma.assetTrade.findFirst({ where: { id, userId: user.id }, select: { id: true } });
    if (!t) throw new UserError("Transaksi aset tidak ditemukan");
    await deleteSynced(user.id, "assetTrades", t.id);
    revalidate(true);
    return {};
  });
}

// ---------- Queries ----------

/** Summary + holdings (prices refreshed per the cache rules unless `refresh: false`). */
export async function fetchPortfolio(opts: { refresh?: boolean; includeArchived?: boolean } = {}): Promise<ActionResult<{ portfolio: Portfolio }>> {
  return runAction("investments", async () => {
    assertObject(opts);
    const user = await requireUser();
    return { portfolio: await getPortfolio(user.id, { refresh: opts.refresh !== false, includeArchived: opts.includeArchived === true }) };
  });
}

export async function fetchAssetDetail(assetId: string): Promise<ActionResult<{ detail: AssetDetail }>> {
  return runAction("investments", async () => {
    assertId(assetId, "Aset tidak ditemukan");
    const user = await requireUser();
    const detail = await getAssetDetail(user.id, assetId);
    if (!detail) throw new UserError("Aset tidak ditemukan");
    return { detail };
  });
}

/** Daily value/cost snapshots in [from, to] (YYYY-MM-DD) for the value history chart. */
export async function fetchPortfolioHistory(range: { from: string; to: string }): Promise<ActionResult<{ history: { date: string; value: number; cost: number }[] }>> {
  return runAction("investments", async () => {
    assertObject(range);
    if (typeof range.from !== "string" || !isValidDateKey(range.from) || typeof range.to !== "string" || !isValidDateKey(range.to) || range.from > range.to)
      throw new UserError("Rentang tanggal tidak valid");
    const user = await requireUser();
    return { history: await getPortfolioHistory(user.id, { from: range.from, to: range.to }) };
  });
}
