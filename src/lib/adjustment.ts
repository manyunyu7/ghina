import { formatCurrency } from "@/lib/utils";

/** Label of a balance-adjustment transaction (docs/balance-adjustment.md). */
export const ADJUSTMENT_LABEL = "Penyesuaian saldo";

/** Default note: "Penyesuaian saldo: Rp 100.000 → Rp 150.000". */
export function adjustmentNote(from: number, to: number, currency: string): string {
  return `${ADJUSTMENT_LABEL}: ${formatCurrency(from, currency)} → ${formatCurrency(to, currency)}`;
}
