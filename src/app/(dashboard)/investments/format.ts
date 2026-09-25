import { LOT_SIZE, isWholeLots, sharesToLots } from "@/lib/investments";

/** Display helpers for the portfolio UI (client-safe, Indonesian formatting). */

const WIB = "Asia/Jakarta";

/** YYYY-MM-DD of `d` in Asia/Jakarta. */
export function dateKeyWIB(d: Date | string = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: WIB, year: "numeric", month: "2-digit", day: "2-digit" }).format(
    typeof d === "string" ? new Date(d) : d,
  );
}

/** YYYY-MM-DD `days` before today (WIB). */
export function daysAgoKey(days: number): string {
  return dateKeyWIB(new Date(Date.now() - days * 86_400_000));
}

export function fmtDate(d: Date | string, opts: Intl.DateTimeFormatOptions = { day: "numeric", month: "short", year: "numeric" }) {
  return new Intl.DateTimeFormat("id-ID", { timeZone: WIB, ...opts }).format(typeof d === "string" ? new Date(d) : d);
}

/** "25 Sep 2026" for a YYYY-MM-DD key. */
export const fmtDateKey = (key: string, opts?: Intl.DateTimeFormatOptions) => fmtDate(`${key}T12:00:00+07:00`, opts);

export function fmtDateTime(d: Date | string) {
  return fmtDate(d, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
}

export function fmtNum(n: number, maxFrac = 4) {
  return new Intl.NumberFormat("id-ID", { maximumFractionDigits: maxFrac }).format(n);
}

/** Market price (public data, not masked): up to 2 decimals below 1000, whole otherwise. */
export function fmtPrice(n: number, currency = "IDR") {
  const frac = Math.abs(n) < 1000 ? 2 : 0;
  return new Intl.NumberFormat("id-ID", { style: "currency", currency, maximumFractionDigits: frac, minimumFractionDigits: 0 }).format(n);
}

export function fmtPct(n: number | null | undefined, sign = true) {
  if (n == null || !Number.isFinite(n)) return "–";
  const s = new Intl.NumberFormat("id-ID", { maximumFractionDigits: 2, minimumFractionDigits: 2 }).format(Math.abs(n));
  return `${sign ? (n > 0 ? "+" : n < 0 ? "−" : "") : n < 0 ? "−" : ""}${s}%`;
}

/** Green / red / muted text for a P/L number. */
export function plTone(n: number | null | undefined) {
  if (n == null || Math.abs(n) < 0.005) return "text-muted";
  return n > 0 ? "text-income" : "text-expense";
}

/** "12 lot · 1.200 lembar" for stocks, "3,5 gram" otherwise. */
export function qtyLabel(asset: { kind: string; unit: string }, shares: number): { main: string; sub: string | null } {
  if (asset.kind === "stock") {
    const lots = sharesToLots(shares);
    const lembar = `${fmtNum(shares)} lembar`;
    return isWholeLots(shares) ? { main: `${fmtNum(lots)} lot`, sub: lembar } : { main: lembar, sub: `${fmtNum(lots, 2)} lot` };
  }
  return { main: `${fmtNum(shares, 8)} ${asset.unit}`, sub: null };
}

export { LOT_SIZE };

/** Chart colors for kinds (stable across views). */
export const KIND_COLORS: Record<string, string> = {
  stock: "#6366f1",
  fund: "#10b981",
  gold: "#eab308",
  crypto: "#f97316",
  bond: "#0ea5e9",
  other: "#64748b",
};
