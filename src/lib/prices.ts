import { prisma } from "@/lib/prisma";
import { CRYPTO_SYMBOL_RE, STOCK_SYMBOL_RE, type AutoPriceKind } from "@/lib/investments";

/**
 * Market price service (docs/investments.md "Prices"). Server-side only: clients never
 * call Yahoo directly — mobile uses `GET /api/mobile/prices`, the web reads through here.
 *
 * - Source: Yahoo Finance chart endpoint, `<SYM>.JK` (IDX stocks) / `<SYM>-IDR` (crypto).
 *   One request per symbol (the chart endpoint is single-symbol), at most
 *   `CONCURRENCY` in flight, 5-s timeout each, concurrent requests for the same symbol
 *   share one fetch.
 * - Cache (`SecurityPrice`, shared across users): stocks 15 min during IDX hours
 *   (Mon–Fri 09:00–16:15 WIB), otherwise until the next session (a price fetched after
 *   the last session close stays fresh); crypto 15 min around the clock.
 * - Failures keep the last price and mark it `stale`. A failed symbol is retried after
 *   10 min; an HTTP 429 pauses every Yahoo call for 15 min; an unknown symbol is
 *   remembered (in memory) for 6 h.
 */

export type PriceKind = AutoPriceKind;
export type PriceRequest = { kind: PriceKind; symbol: string };
export type PriceError = "not_found" | "unavailable" | "rate_limited";

/** What clients receive per requested symbol. */
export type Quote = {
  kind: PriceKind;
  symbol: string;
  name: string | null;
  /** null when no price is known (never fetched successfully). */
  price: number | null;
  prevClose: number | null;
  change: number | null;
  changePct: number | null;
  currency: string;
  /** Market time of the price (ISO). */
  asOf: string | null;
  /** Last successful fetch (ISO). */
  fetchedAt: string | null;
  source: string;
  /** The price is older than the cache rules allow (the last refresh failed or was skipped). */
  stale: boolean;
  /** Why no fresh price: not_found (unknown symbol) | unavailable (timeout/5xx/network) | rate_limited. */
  error: PriceError | null;
};

export type StoredPrice = {
  kind: string;
  symbol: string;
  name: string | null;
  price: number;
  prevClose: number | null;
  change: number | null;
  changePct: number | null;
  currency: string;
  asOf: Date;
  source: string;
  fetchedAt: Date;
  checkedAt: Date | null;
  error: string | null;
};

export interface PriceStore {
  get(reqs: readonly PriceRequest[]): Promise<StoredPrice[]>;
  saveSuccess(row: Omit<StoredPrice, "checkedAt" | "error">): Promise<void>;
  saveFailure(req: PriceRequest, error: PriceError, at: Date): Promise<void>;
}

export type FetchLike = (url: string, init?: { signal?: AbortSignal; headers?: Record<string, string> }) => Promise<{
  status: number;
  ok: boolean;
  json(): Promise<unknown>;
}>;

export const MAX_PRICE_SYMBOLS = 50;
export const PRICE_TTL_MS = 15 * 60_000;
export const PRICE_TIMEOUT_MS = 5000;
export const FAILURE_RETRY_MS = 10 * 60_000;
export const RATE_LIMIT_BACKOFF_MS = 15 * 60_000;
export const NOT_FOUND_TTL_MS = 6 * 60 * 60_000;
export const CONCURRENCY = 4;
const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart/";
const USER_AGENT = "Mozilla/5.0 (compatible; Ghina/1.0; +https://ghina.tentrem.space)";

// ---------- Symbols ----------

export const yahooSymbol = (r: PriceRequest) => (r.kind === "stock" ? `${r.symbol}.JK` : `${r.symbol}-IDR`);
export const priceKey = (r: PriceRequest) => `${r.kind}:${r.symbol}`;

/**
 * Parse `stock:BBCA,crypto:BTC` (case-insensitive, `.JK`/`-IDR` suffixes tolerated,
 * duplicates dropped, order kept). Error message for the 400 response otherwise.
 */
export function parsePriceSymbols(raw: string | null, max = MAX_PRICE_SYMBOLS): { ok: true; items: PriceRequest[] } | { ok: false; error: string } {
  if (!raw || !raw.trim()) return { ok: false, error: "symbols is required (e.g. stock:BBCA,crypto:BTC)" };
  const parts = raw.split(",").map((s) => s.trim()).filter(Boolean);
  const seen = new Set<string>();
  const items: PriceRequest[] = [];
  for (const p of parts) {
    const m = /^(stock|crypto):(.+)$/i.exec(p);
    if (!m) return { ok: false, error: `Invalid symbol "${p.slice(0, 40)}" (use stock:BBCA or crypto:BTC)` };
    const kind = m[1].toLowerCase() as PriceKind;
    let symbol = m[2].trim().toUpperCase();
    symbol = kind === "stock" ? symbol.replace(/\.JK$/, "") : symbol.replace(/-IDR$/, "");
    if (!(kind === "stock" ? STOCK_SYMBOL_RE : CRYPTO_SYMBOL_RE).test(symbol))
      return { ok: false, error: `Invalid symbol "${p.slice(0, 40)}"` };
    const k = `${kind}:${symbol}`;
    if (seen.has(k)) continue;
    seen.add(k);
    items.push({ kind, symbol });
  }
  if (items.length > max) return { ok: false, error: `Too many symbols (max ${max})` };
  return { ok: true, items };
}

// ---------- Yahoo response ----------

export type ParsedChart = { price: number; prevClose: number | null; currency: string; asOf: Date; name: string | null };

const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

/**
 * Read `chart.result[0].meta` of the chart endpoint: regularMarketPrice (fallback: the
 * last non-null close), chartPreviousClose (fallback previousClose), currency,
 * regularMarketTime (s), longName/shortName. null when there is no usable price.
 */
export function parseYahooChart(json: unknown): ParsedChart | null {
  const result = (json as { chart?: { result?: unknown[] | null } } | null)?.chart?.result?.[0] as
    | { meta?: Record<string, unknown>; indicators?: { quote?: { close?: unknown[] }[] } }
    | undefined;
  const meta = result?.meta;
  if (!meta) return null;
  let price = num(meta.regularMarketPrice);
  if (price == null) {
    const closes = result?.indicators?.quote?.[0]?.close ?? [];
    for (let i = closes.length - 1; i >= 0 && price == null; i--) price = num(closes[i]);
  }
  if (price == null || price < 0) return null;
  const t = num(meta.regularMarketTime);
  const name = typeof meta.longName === "string" ? meta.longName : typeof meta.shortName === "string" ? meta.shortName : null;
  return {
    price,
    prevClose: num(meta.chartPreviousClose) ?? num(meta.previousClose),
    currency: typeof meta.currency === "string" && /^[A-Za-z]{3}$/.test(meta.currency) ? meta.currency.toUpperCase() : "IDR",
    asOf: t != null ? new Date(t * 1000) : new Date(),
    name: name ? name.trim().slice(0, 100) || null : null,
  };
}

// ---------- IDX session / cache rules ----------

const WIB_OFFSET_MS = 7 * 3600_000;
const OPEN_MIN = 9 * 60;
const CLOSE_MIN = 16 * 60 + 15;

/** Whether IDX is in session at `now` (Mon–Fri 09:00–16:15 WIB; holidays not modelled). */
export function idxMarketOpen(now: Date): boolean {
  const w = new Date(now.getTime() + WIB_OFFSET_MS);
  const day = w.getUTCDay();
  if (day === 0 || day === 6) return false;
  const min = w.getUTCHours() * 60 + w.getUTCMinutes();
  return min >= OPEN_MIN && min < CLOSE_MIN;
}

/** The most recent session close (Mon–Fri 16:15 WIB) at or before `now`. */
export function lastIdxClose(now: Date): Date {
  const w = new Date(now.getTime() + WIB_OFFSET_MS);
  for (let k = 0; k < 8; k++) {
    const d = new Date(Date.UTC(w.getUTCFullYear(), w.getUTCMonth(), w.getUTCDate() - k));
    const day = d.getUTCDay();
    if (day === 0 || day === 6) continue;
    const close = new Date(d.getTime() + CLOSE_MIN * 60_000 - WIB_OFFSET_MS);
    if (close <= now) return close;
  }
  return new Date(now.getTime() - 7 * 86_400_000);
}

/** Cache rule: is a price fetched at `fetchedAt` still fresh at `now`? */
export function isPriceFresh(kind: string, fetchedAt: Date, now: Date): boolean {
  const age = now.getTime() - fetchedAt.getTime();
  if (age < 0) return true;
  if (kind === "crypto" || idxMarketOpen(now)) return age < PRICE_TTL_MS;
  return fetchedAt >= lastIdxClose(now);
}

// ---------- Service ----------

type FetchOutcome = { ok: true; data: ParsedChart } | { ok: false; error: PriceError };

export type PriceServiceOptions = {
  store: PriceStore;
  fetchImpl?: FetchLike;
  now?: () => Date;
  timeoutMs?: number;
  concurrency?: number;
};

export function createPriceService(opts: PriceServiceOptions) {
  const store = opts.store;
  const fetchImpl: FetchLike = opts.fetchImpl ?? ((url, init) => fetch(url, init));
  const now = opts.now ?? (() => new Date());
  const timeoutMs = opts.timeoutMs ?? PRICE_TIMEOUT_MS;
  const concurrency = Math.max(1, opts.concurrency ?? CONCURRENCY);
  const inflight = new Map<string, Promise<FetchOutcome>>();
  const notFoundUntil = new Map<string, number>();
  /** Failures of symbols without a stored row (no checkedAt to look at). */
  const failedUntil = new Map<string, number>();
  let rateLimitedUntil = 0;
  let calls = 0;

  async function fetchOne(r: PriceRequest): Promise<FetchOutcome> {
    if (now().getTime() < rateLimitedUntil) return { ok: false, error: "rate_limited" };
    calls++;
    try {
      const res = await fetchImpl(`${YAHOO_CHART}${encodeURIComponent(yahooSymbol(r))}?range=1d&interval=1d`, {
        signal: AbortSignal.timeout(timeoutMs),
        headers: { "user-agent": USER_AGENT, accept: "application/json" },
      });
      if (res.status === 429) {
        rateLimitedUntil = now().getTime() + RATE_LIMIT_BACKOFF_MS;
        return { ok: false, error: "rate_limited" };
      }
      let body: unknown = null;
      try {
        body = await res.json();
      } catch {
        body = null;
      }
      const notFound =
        res.status === 404 ||
        (body as { chart?: { error?: { code?: string } | null } } | null)?.chart?.error?.code === "Not Found";
      if (notFound) return { ok: false, error: "not_found" };
      if (!res.ok) return { ok: false, error: "unavailable" };
      const data = parseYahooChart(body);
      // A 200 without a usable price: Yahoo knows no such instrument (or it has no data).
      return data ? { ok: true, data } : { ok: false, error: "not_found" };
    } catch {
      return { ok: false, error: "unavailable" };
    }
  }

  /** Fetch (deduplicated) and persist one symbol. */
  function refresh(r: PriceRequest): Promise<FetchOutcome> {
    const key = priceKey(r);
    let p = inflight.get(key);
    if (!p) {
      p = (async () => {
        const out = await fetchOne(r);
        const at = now();
        if (out.ok) {
          const d = out.data;
          const change = d.prevClose != null ? d.price - d.prevClose : null;
          await store.saveSuccess({
            kind: r.kind,
            symbol: r.symbol,
            name: d.name,
            price: d.price,
            prevClose: d.prevClose,
            change,
            changePct: change != null && d.prevClose ? (change / d.prevClose) * 100 : null,
            currency: d.currency,
            asOf: d.asOf,
            source: "yahoo",
            fetchedAt: at,
          });
          notFoundUntil.delete(key);
          failedUntil.delete(key);
        } else {
          if (out.error === "not_found") notFoundUntil.set(key, at.getTime() + NOT_FOUND_TTL_MS);
          else if (out.error === "unavailable") failedUntil.set(key, at.getTime() + FAILURE_RETRY_MS);
          if (out.error !== "rate_limited") await store.saveFailure(r, out.error, at);
        }
        return out;
      })().finally(() => inflight.delete(key));
      inflight.set(key, p);
    }
    return p;
  }

  function toQuote(r: PriceRequest, row: StoredPrice | undefined, error: PriceError | null, t: Date): Quote {
    if (!row)
      return {
        kind: r.kind,
        symbol: r.symbol,
        name: null,
        price: null,
        prevClose: null,
        change: null,
        changePct: null,
        currency: "IDR",
        asOf: null,
        fetchedAt: null,
        source: "yahoo",
        stale: true,
        error: error ?? "unavailable",
      };
    const fresh = isPriceFresh(r.kind, row.fetchedAt, t);
    return {
      kind: r.kind,
      symbol: r.symbol,
      name: row.name,
      price: row.price,
      prevClose: row.prevClose,
      change: row.change,
      changePct: row.changePct,
      currency: row.currency,
      asOf: row.asOf.toISOString(),
      fetchedAt: row.fetchedAt.toISOString(),
      source: row.source,
      stale: !fresh,
      error: fresh ? null : (error ?? (row.error as PriceError | null) ?? null),
    };
  }

  /** Whether `r` needs a network refresh now (not fresh, not in a backoff window). */
  function wantsRefresh(r: PriceRequest, row: StoredPrice | undefined, t: Date): boolean {
    const key = priceKey(r);
    const ms = t.getTime();
    if ((notFoundUntil.get(key) ?? 0) > ms) return false;
    if ((failedUntil.get(key) ?? 0) > ms) return false;
    if (!row) return true;
    if (isPriceFresh(r.kind, row.fetchedAt, t)) return false;
    if (row.error && row.checkedAt && ms - row.checkedAt.getTime() < FAILURE_RETRY_MS) return false;
    return true;
  }

  /**
   * Quotes for `reqs` (same order). With `refresh` (default) stale symbols are fetched
   * first (≤ `concurrency` at a time); `refresh: false` answers from the cache only.
   */
  async function getQuotes(reqs: readonly PriceRequest[], o: { refresh?: boolean } = {}): Promise<Quote[]> {
    if (reqs.length === 0) return [];
    const t = now();
    const rows = new Map((await store.get(reqs)).map((r) => [`${r.kind}:${r.symbol}`, r]));
    const errors = new Map<string, PriceError>();
    for (const r of reqs) if ((notFoundUntil.get(priceKey(r)) ?? 0) > t.getTime()) errors.set(priceKey(r), "not_found");
    if (o.refresh !== false) {
      const todo = reqs.filter((r) => wantsRefresh(r, rows.get(priceKey(r)), t));
      let i = 0;
      const worker = async () => {
        while (i < todo.length) {
          const r = todo[i++];
          const out = await refresh(r);
          if (!out.ok) errors.set(priceKey(r), out.error);
        }
      };
      await Promise.all(Array.from({ length: Math.min(concurrency, todo.length) }, worker));
      if (todo.length) for (const r of await store.get(todo)) rows.set(`${r.kind}:${r.symbol}`, r);
    }
    const t2 = now();
    return reqs.map((r) => toQuote(r, rows.get(priceKey(r)), errors.get(priceKey(r)) ?? null, t2));
  }

  /**
   * Validate a symbol when an asset is added: `ok` with the quote (name auto-fill),
   * `not_found`, or `unavailable` (Yahoo down / rate limited — let the user continue).
   */
  async function lookup(r: PriceRequest): Promise<{ status: "ok"; quote: Quote } | { status: "not_found" } | { status: "unavailable" }> {
    const [q] = await getQuotes([r]);
    if (q.price != null && q.error !== "not_found") return { status: "ok", quote: q };
    if (q.error === "not_found") return { status: "not_found" };
    return { status: "unavailable" };
  }

  return { getQuotes, lookup, stats: () => ({ calls, rateLimitedUntil }) };
}

export type PriceService = ReturnType<typeof createPriceService>;

// ---------- Prisma store + default service ----------

export const prismaPriceStore: PriceStore = {
  async get(reqs) {
    if (reqs.length === 0) return [];
    return prisma.securityPrice.findMany({ where: { OR: reqs.map((r) => ({ kind: r.kind, symbol: r.symbol })) } });
  },
  async saveSuccess(row) {
    const data = { ...row, checkedAt: row.fetchedAt, error: null };
    await prisma.securityPrice.upsert({
      where: { kind_symbol: { kind: row.kind, symbol: row.symbol } },
      create: data,
      update: data,
    });
  },
  async saveFailure(r, error, at) {
    await prisma.securityPrice.updateMany({ where: { kind: r.kind, symbol: r.symbol }, data: { checkedAt: at, error } });
  },
};

const globalForPrices = globalThis as unknown as { ghinaPriceService?: PriceService };

/** The process-wide price service (backoff state shared by every request). */
export function priceService(): PriceService {
  return (globalForPrices.ghinaPriceService ??= createPriceService({ store: prismaPriceStore }));
}
