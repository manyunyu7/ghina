"use client";

import { maskedMoney } from "@/lib/balance-privacy";
import { formatCompactCurrency, formatCurrency } from "@/lib/utils";
import { useBalancePrivacy } from "./balance-privacy";

/**
 * A formatted amount that respects balance privacy (`Rp •••••` while hidden).
 * Usable from server components (props are plain values).
 *
 * `sign`: prefix `+`/`-` (e.g. income/expense rows). The sign stays visible when masked.
 * `reveal`: always show (forms where the user types the amount).
 */
export function Money({
  amount,
  currency = "IDR",
  compact = false,
  sign,
  reveal = false,
  className,
}: {
  amount: number;
  currency?: string;
  compact?: boolean;
  sign?: "+" | "-" | "auto";
  reveal?: boolean;
  className?: string;
}) {
  const { hidden } = useBalancePrivacy();
  const prefix = sign === "auto" ? (amount > 0 ? "+" : amount < 0 ? "-" : "") : (sign ?? "");
  const abs = sign ? Math.abs(amount) : amount;
  const text =
    hidden && !reveal
      ? `${prefix}${maskedMoney(currency, compact)}`
      : `${prefix}${compact ? formatCompactCurrency(abs, currency) : formatCurrency(abs, currency)}`;
  return (
    <span className={className} data-money={hidden && !reveal ? "hidden" : undefined}>
      {text}
    </span>
  );
}
