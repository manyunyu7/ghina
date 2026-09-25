import { z } from "zod";
import { cleanLine, cleanText } from "@/lib/notes";

/**
 * Investments (portfolio) — pure, shared rules (docs/investments.md). No DB access:
 * used by the web server actions, the mobile sync endpoint and the web UI. The mobile
 * app mirrors these constants and algorithms exactly.
 *
 * Holdings are derived from trades (average-cost method), never stored.
 */

// ---------- Constants ----------

export const ASSET_KINDS = [
  { id: "stock", label: "Saham", unit: "lembar", auto: true },
  { id: "fund", label: "Reksa dana", unit: "unit", auto: false },
  { id: "gold", label: "Emas", unit: "gram", auto: false },
  { id: "crypto", label: "Kripto", unit: "koin", auto: true },
  { id: "bond", label: "Obligasi", unit: "unit", auto: false },
  { id: "other", label: "Lainnya", unit: "unit", auto: false },
] as const;
export type AssetKind = (typeof ASSET_KINDS)[number]["id"];
export const ASSET_KIND_IDS = ASSET_KINDS.map((k) => k.id) as [AssetKind, ...AssetKind[]];
/** Kinds whose price comes from the price service (src/lib/prices.ts). */
export const AUTO_PRICE_KINDS = ["stock", "crypto"] as const;
export type AutoPriceKind = (typeof AUTO_PRICE_KINDS)[number];
export const isAutoKind = (kind: string): kind is AutoPriceKind => (AUTO_PRICE_KINDS as readonly string[]).includes(kind);
export const assetKindInfo = (kind: string) => ASSET_KINDS.find((k) => k.id === kind) ?? ASSET_KINDS[5];

export const PRICE_MODES = ["auto", "manual"] as const;
export const TRADE_TYPES = ["buy", "sell", "dividend", "split", "fee"] as const;
export type TradeType = (typeof TRADE_TYPES)[number];
export const TRADE_TYPE_LABELS: Record<TradeType, string> = {
  buy: "Beli",
  sell: "Jual",
  dividend: "Dividen",
  split: "Stock split",
  fee: "Biaya",
};

/** IDX: 1 lot = 100 lembar. Quantities are always stored in shares/units. */
export const LOT_SIZE = 100;
/** Default broker fee presets (fraction of gross value, incl. levies/tax). Users may override per trade. */
export const FEE_PRESETS = { buy: 0.0015, sell: 0.0025 } as const;

export const STOCK_SYMBOL_RE = /^[A-Z0-9][A-Z0-9-]{0,11}$/;
export const CRYPTO_SYMBOL_RE = /^[A-Z0-9]{1,15}$/;
export const SYMBOL_MAX = 20;
export const ASSET_NAME_MAX = 100;
export const ASSET_UNIT_MAX = 20;
export const TRADE_NOTE_MAX = 500;
export const CURRENCY_RE = /^[A-Z]{3}$/;

/** Income category used for dividend cash (deterministic id per user). */
export const DIVIDEND_CATEGORY = { name: "Dividen", color: "#10b981", icon: "circle-dollar-sign" } as const;
export const dividendCategoryId = (userId: string) => `category-dividen-${userId}`;

/** Floating-point tolerance for share counts. */
const EPS = 1e-9;

export const roundMoney = (n: number) => Math.round(n * 100) / 100;

// ---------- Lots ----------

export const lotsToShares = (lots: number) => lots * LOT_SIZE;
export const sharesToLots = (shares: number) => shares / LOT_SIZE;
/** Whether a share count is a whole number of lots. */
export const isWholeLots = (shares: number) => Math.abs(shares / LOT_SIZE - Math.round(shares / LOT_SIZE)) < EPS;

/** Estimated fee for a buy/sell of `gross` (= quantity × price) at the preset (or given) rate. */
export function estimateFee(side: "buy" | "sell", gross: number, rates: { buy: number; sell: number } = FEE_PRESETS): number {
  if (!(gross > 0)) return 0;
  return roundMoney(gross * rates[side]);
}

// ---------- Symbols ----------

/** Normalized symbol for a kind: stock/crypto uppercased (and validated), others trimmed. */
export function normalizeSymbol(kind: string, raw: string): { ok: true; symbol: string } | { ok: false; error: string } {
  const v = cleanLine(raw);
  if (!v) return { ok: false, error: "Kode wajib diisi" };
  if (kind === "stock") {
    const s = v.toUpperCase().replace(/\.JK$/, "");
    return STOCK_SYMBOL_RE.test(s) ? { ok: true, symbol: s } : { ok: false, error: "Kode saham tidak valid (contoh: BBCA)" };
  }
  if (kind === "crypto") {
    const s = v.toUpperCase().replace(/-IDR$/, "");
    return CRYPTO_SYMBOL_RE.test(s) ? { ok: true, symbol: s } : { ok: false, error: "Kode kripto tidak valid (contoh: BTC)" };
  }
  if (v.length > SYMBOL_MAX) return { ok: false, error: `Kode maksimal ${SYMBOL_MAX} karakter` };
  return { ok: true, symbol: v };
}

/** Case-insensitive key for (kind, symbol) uniqueness. */
export const assetKey = (kind: string, symbol: string) => `${kind}:${symbol.toLocaleUpperCase("en-US")}`;

// ---------- Payload schemas (sync wire format; the web actions build the same shape) ----------

const optionalId = z
  .string()
  .nullish()
  .transform((v) => (v && v.length > 0 ? v : null));

const isoDate = (label: string) =>
  z.iso.datetime({ offset: true, message: `${label} harus ISO-8601 dengan Z/offset` }).transform((v) => new Date(v));

/**
 * An asset row (full row: missing optional fields get defaults). Normalization: the
 * symbol per kind (`normalizeSymbol`); kinds without a price feed are always `manual`;
 * `unit` defaults per kind.
 */
export const assetSchema = z
  .object({
    kind: z.enum(ASSET_KIND_IDS, { error: "Jenis aset tidak valid" }),
    symbol: z.string({ error: "Kode wajib diisi" }),
    name: z
      .string()
      .nullish()
      .transform((v) => (v == null ? null : cleanLine(v) || null))
      .refine((v) => v == null || v.length <= ASSET_NAME_MAX, `Nama maksimal ${ASSET_NAME_MAX} karakter`),
    currency: z
      .string()
      .nullish()
      .transform((v) => (v ? v.trim().toUpperCase() : "IDR"))
      .refine((v) => CURRENCY_RE.test(v), "Mata uang harus 3 huruf (IDR)"),
    priceMode: z.enum(PRICE_MODES, { error: "Mode harga tidak valid" }).nullish(),
    manualPrice: z.number().finite().min(0, "Harga tidak boleh negatif").nullish().transform((v) => v ?? null),
    manualPriceAt: isoDate("Tanggal harga").nullish().transform((v) => v ?? null),
    unit: z
      .string()
      .nullish()
      .transform((v) => (v == null ? null : cleanLine(v) || null))
      .refine((v) => v == null || v.length <= ASSET_UNIT_MAX, `Satuan maksimal ${ASSET_UNIT_MAX} karakter`),
    walletId: optionalId,
    archived: z.boolean().nullish().transform((v) => v ?? false),
    sortOrder: z.number().int().min(-1_000_000).max(1_000_000).nullish().transform((v) => v ?? 0),
  })
  .transform((a, ctx) => {
    const sym = normalizeSymbol(a.kind, a.symbol);
    if (!sym.ok) {
      ctx.addIssue({ code: "custom", path: ["symbol"], message: sym.error });
      return z.NEVER;
    }
    const auto = isAutoKind(a.kind);
    return {
      ...a,
      symbol: sym.symbol,
      priceMode: auto ? (a.priceMode ?? "auto") : "manual",
      unit: a.unit ?? assetKindInfo(a.kind).unit,
    };
  });
export type AssetData = z.output<typeof assetSchema>;

const positive = (msg: string) => z.number().finite(msg).positive(msg);

/**
 * A trade row. Per type (irrelevant fields are stored as null, `fee` as 0):
 * - buy/sell: quantity > 0, price > 0, fee ≥ 0
 * - dividend: amount > 0 (cash received, net)
 * - split: ratio > 0 and ≠ 1 (new units per old unit, 2 = 1:2)
 * - fee: amount > 0
 */
export const tradeSchema = z
  .object({
    assetId: z.string({ error: "Aset wajib diisi" }).min(1, "Aset wajib diisi").max(128),
    type: z.enum(TRADE_TYPES, { error: "Jenis transaksi aset tidak valid" }),
    date: isoDate("Tanggal"),
    quantity: z.number().finite("Jumlah tidak valid").nullish().transform((v) => v ?? null),
    price: z.number().finite("Harga tidak valid").nullish().transform((v) => v ?? null),
    fee: z.number().finite("Biaya tidak valid").min(0, "Biaya tidak boleh negatif").nullish().transform((v) => v ?? 0),
    amount: z.number().finite("Nominal tidak valid").nullish().transform((v) => v ?? null),
    ratio: z.number().finite("Rasio tidak valid").nullish().transform((v) => v ?? null),
    note: z
      .string()
      .nullish()
      .transform((v) => (v == null ? null : cleanText(v).trim() || null))
      .refine((v) => v == null || v.length <= TRADE_NOTE_MAX, `Catatan maksimal ${TRADE_NOTE_MAX} karakter`),
    cashTransactionId: optionalId,
  })
  .transform((t, ctx) => {
    const fail = (path: string, message: string) => {
      ctx.addIssue({ code: "custom", path: [path], message });
      return z.NEVER;
    };
    const base = { ...t, quantity: null, price: null, fee: 0, amount: null, ratio: null } as TradeFields;
    if (t.type === "buy" || t.type === "sell") {
      if (!positive("x").safeParse(t.quantity).success) return fail("quantity", "Jumlah harus lebih dari 0");
      if (!positive("x").safeParse(t.price).success) return fail("price", "Harga harus lebih dari 0");
      return { ...base, quantity: t.quantity, price: t.price, fee: t.fee };
    }
    if (t.type === "split") {
      if (!positive("x").safeParse(t.ratio).success || t.ratio === 1) return fail("ratio", "Rasio split harus lebih dari 0 dan bukan 1");
      return { ...base, ratio: t.ratio };
    }
    if (!positive("x").safeParse(t.amount).success) return fail("amount", "Nominal harus lebih dari 0");
    return { ...base, amount: t.amount };
  });

export type TradeFields = {
  assetId: string;
  type: TradeType;
  date: Date;
  quantity: number | null;
  price: number | null;
  fee: number;
  amount: number | null;
  ratio: number | null;
  note: string | null;
  cashTransactionId: string | null;
};
export type TradeData = z.output<typeof tradeSchema>;

// ---------- Holding derivation (average cost) ----------

export type TradeLike = {
  id?: string;
  type: string;
  date: Date | string;
  quantity: number | null;
  price: number | null;
  fee: number;
  amount: number | null;
  ratio: number | null;
  createdAt?: Date | string | null;
};

const ms = (d: Date | string | null | undefined) => (d == null ? Number.POSITIVE_INFINITY : new Date(d).getTime());

/** Processing order: date, then createdAt (unsaved last), then id. */
export function compareTrades(a: TradeLike, b: TradeLike): number {
  return ms(a.date) - ms(b.date) || ms(a.createdAt) - ms(b.createdAt) || (a.id ?? "").localeCompare(b.id ?? "");
}

export type HoldingIssue = { tradeId: string | null; date: string; message: string };

export type Holding = {
  shares: number;
  /** Remaining cost basis (incl. buy fees). */
  cost: number;
  /** cost / shares, null when nothing is held. */
  avgPrice: number | null;
  realized: number;
  dividends: number;
  /** Total fees paid (buy/sell fees + fee rows). */
  fees: number;
  /** Total bought / sold value (q × p, without fees). */
  invested: number;
  proceeds: number;
  tradeCount: number;
  /** Sells beyond the held quantity (clamped in the lenient derivation). */
  issues: HoldingIssue[];
};

const fmtQty = (n: number) => String(Math.round(n * 1e6) / 1e6);

/**
 * Average-cost derivation (docs/investments.md), trades processed by `compareTrades`:
 * buy: cost += q·p + fee; shares += q · sell: realized += q·p − fee − q·avg; cost −= q·avg;
 * shares −= q · split: shares *= ratio · dividend: dividends += amount · fee: realized −= amount.
 * A sell of more than held is reported in `issues` and clamped to the held quantity.
 */
export function deriveHolding(trades: readonly TradeLike[]): Holding {
  const h: Holding = {
    shares: 0,
    cost: 0,
    avgPrice: null,
    realized: 0,
    dividends: 0,
    fees: 0,
    invested: 0,
    proceeds: 0,
    tradeCount: trades.length,
    issues: [],
  };
  for (const t of [...trades].sort(compareTrades)) {
    const q = t.quantity ?? 0;
    const p = t.price ?? 0;
    if (t.type === "buy") {
      h.cost += q * p + t.fee;
      h.shares += q;
      h.fees += t.fee;
      h.invested += q * p;
    } else if (t.type === "sell") {
      let qty = q;
      if (qty > h.shares + EPS * Math.max(1, h.shares)) {
        h.issues.push({
          tradeId: t.id ?? null,
          date: new Date(t.date).toISOString(),
          message: `Jumlah jual (${fmtQty(q)}) melebihi kepemilikan (${fmtQty(h.shares)})`,
        });
        qty = h.shares;
      }
      const avg = h.shares > 0 ? h.cost / h.shares : 0;
      h.realized += qty * p - t.fee - qty * avg;
      h.cost -= qty * avg;
      h.shares -= qty;
      h.fees += t.fee;
      h.proceeds += qty * p;
      if (h.shares <= EPS) {
        h.shares = 0;
        h.cost = 0;
      }
    } else if (t.type === "split") {
      if (t.ratio && t.ratio > 0) h.shares *= t.ratio;
    } else if (t.type === "dividend") {
      h.dividends += t.amount ?? 0;
    } else if (t.type === "fee") {
      h.realized -= t.amount ?? 0;
      h.fees += t.amount ?? 0;
    }
  }
  h.avgPrice = h.shares > 0 ? h.cost / h.shares : null;
  return h;
}

/**
 * Sanity check for a trade list (sync + web): holdings must never go negative in date
 * order. Returns the first problem as an Indonesian message, or null.
 */
export function tradeSequenceError(trades: readonly TradeLike[]): string | null {
  const issue = deriveHolding(trades).issues[0];
  if (!issue) return null;
  return `${issue.message} per ${issue.date.slice(0, 10)}`;
}

// ---------- Valuation ----------

export type Valuation = {
  price: number | null;
  marketValue: number | null;
  unrealized: number | null;
  unrealizedPct: number | null;
  /** shares × (price − prevClose), auto-priced assets only. */
  dayChange: number | null;
  dayChangePct: number | null;
  /** unrealized + realized + dividends (unrealized counts as 0 without a price). */
  totalReturn: number;
};

/** Market value and P/L of a holding at `price` (null = unknown). */
export function valueHolding(h: Holding, price: number | null, prevClose: number | null = null): Valuation {
  const marketValue = price == null ? null : h.shares * price;
  const unrealized = marketValue == null ? null : marketValue - h.cost;
  const unrealizedPct = unrealized == null || h.cost <= 0 ? null : (unrealized / h.cost) * 100;
  const dayChange = price == null || prevClose == null || h.shares === 0 ? null : h.shares * (price - prevClose);
  const dayChangePct = price == null || prevClose == null || prevClose === 0 ? null : ((price - prevClose) / prevClose) * 100;
  return {
    price,
    marketValue,
    unrealized,
    unrealizedPct,
    dayChange,
    dayChangePct,
    totalReturn: (unrealized ?? 0) + h.realized + h.dividends,
  };
}

export type AllocationSlice = { key: string; label: string; value: number; pct: number };

/** Allocation by any key, largest first (non-positive values left out). */
export function allocation(items: readonly { key: string; label: string; value: number | null }[]): AllocationSlice[] {
  const sums = new Map<string, { label: string; value: number }>();
  for (const it of items) {
    if (!(it.value != null && it.value > 0)) continue;
    const e = sums.get(it.key) ?? { label: it.label, value: 0 };
    e.value += it.value;
    sums.set(it.key, e);
  }
  const total = [...sums.values()].reduce((s, e) => s + e.value, 0);
  return [...sums.entries()]
    .map(([key, e]) => ({ key, label: e.label, value: e.value, pct: total > 0 ? (e.value / total) * 100 : 0 }))
    .sort((a, b) => b.value - a.value);
}

// ---------- Cash effect ----------

export type CashEffect = { type: "investment" | "income"; amount: number };

/**
 * The wallet transaction a trade creates (docs/investments.md "Cash effect"):
 * buy → investment −(q·p + fee) · sell → investment +(q·p − fee) · fee → investment −amount ·
 * dividend → income +amount · split → none. Rounded to 2 decimals; a zero amount → none.
 */
export function tradeCashEffect(t: Pick<TradeLike, "type" | "quantity" | "price" | "fee" | "amount">): CashEffect | null {
  const q = t.quantity ?? 0;
  const p = t.price ?? 0;
  let e: CashEffect | null = null;
  if (t.type === "buy") e = { type: "investment", amount: -roundMoney(q * p + t.fee) };
  else if (t.type === "sell") e = { type: "investment", amount: roundMoney(q * p - t.fee) };
  else if (t.type === "fee") e = { type: "investment", amount: -roundMoney(t.amount ?? 0) };
  else if (t.type === "dividend") e = { type: "income", amount: roundMoney(t.amount ?? 0) };
  if (!e || e.amount === 0 || (e.type === "income" && e.amount < 0)) return null;
  return e;
}

const fmtNum = (n: number) => new Intl.NumberFormat("id-ID", { maximumFractionDigits: 8 }).format(n);

/** Note of a trade's wallet transaction: "Beli BBCA 10 lot @ 9.500", "Dividen BBCA", … */
export function tradeTransactionNote(
  t: Pick<TradeLike, "type" | "quantity" | "price">,
  asset: { kind: string; symbol: string; unit?: string },
): string {
  const label = TRADE_TYPE_LABELS[t.type as TradeType] ?? "Investasi";
  if (t.type === "buy" || t.type === "sell") {
    const q = t.quantity ?? 0;
    const qty = asset.kind === "stock" && isWholeLots(q) ? `${fmtNum(sharesToLots(q))} lot` : `${fmtNum(q)} ${asset.unit ?? ""}`.trim();
    return `${label} ${asset.symbol} ${qty} @ ${fmtNum(t.price ?? 0)}`;
  }
  return `${label} ${asset.symbol}`;
}

/** Expected transaction type for a trade's linked transaction (null for split: no cash). */
export function linkedTransactionType(tradeType: string): "investment" | "income" | null {
  if (tradeType === "dividend") return "income";
  if (tradeType === "buy" || tradeType === "sell" || tradeType === "fee") return "investment";
  return null;
}

/**
 * Whether a linked transaction fits a trade: right type and sign (buy/fee negative,
 * sell positive, dividend income). Amounts are not compared (client rounding).
 */
export function linkedTransactionError(
  tradeType: string,
  tx: { type: string; amount: number },
): string | null {
  const want = linkedTransactionType(tradeType);
  if (!want) return "Stock split tidak punya transaksi kas";
  if (tx.type !== want)
    return want === "income" ? "Transaksi dividen harus berupa pemasukan" : "Transaksi kas harus bertipe investasi";
  if (tradeType === "sell" && !(tx.amount > 0)) return "Transaksi kas penjualan harus bernilai positif";
  if ((tradeType === "buy" || tradeType === "fee") && !(tx.amount < 0)) return "Transaksi kas pembelian/biaya harus bernilai negatif";
  return null;
}
