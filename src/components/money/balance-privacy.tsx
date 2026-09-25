"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { Eye, EyeOff } from "lucide-react";
import { BALANCE_PRIVACY_COOKIE, BALANCE_PRIVACY_STORAGE_KEY, maskedMoney } from "@/lib/balance-privacy";
import { cn, formatCompactCurrency, formatCurrency } from "@/lib/utils";

type Ctx = { hidden: boolean; toggle: () => void; setHidden: (v: boolean) => void };

// No provider (e.g. auth pages) → always visible, toggle is a no-op.
const BalancePrivacyContext = createContext<Ctx>({ hidden: false, toggle: () => {}, setHidden: () => {} });

function persist(hidden: boolean) {
  try {
    localStorage.setItem(BALANCE_PRIVACY_STORAGE_KEY, hidden ? "1" : "0");
  } catch {}
  // Cookie lets the server render masked on the first paint (no flash of real amounts).
  document.cookie = `${BALANCE_PRIVACY_COOKIE}=${hidden ? "1" : "0"}; path=/; max-age=31536000; samesite=lax`;
}

/** Placed in the dashboard layout; [initialHidden] comes from the cookie so SSR matches the client. */
export function BalancePrivacyProvider({ initialHidden, children }: { initialHidden: boolean; children: React.ReactNode }) {
  const [hidden, setHiddenState] = useState(initialHidden);

  // localStorage is the durable copy: if the cookie was cleared, restore from it.
  useEffect(() => {
    let stored: string | null = null;
    try {
      stored = localStorage.getItem(BALANCE_PRIVACY_STORAGE_KEY);
    } catch {}
    if (stored === null) {
      persist(initialHidden);
    } else if ((stored === "1") !== initialHidden) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- one-time sync from browser storage after mount
      setHiddenState(stored === "1");
      persist(stored === "1");
    }
  }, [initialHidden]);

  const setHidden = useCallback((v: boolean) => {
    setHiddenState(v);
    persist(v);
  }, []);
  const toggle = useCallback(() => {
    setHiddenState((h) => {
      persist(!h);
      return !h;
    });
  }, []);

  const value = useMemo(() => ({ hidden, toggle, setHidden }), [hidden, toggle, setHidden]);
  return <BalancePrivacyContext.Provider value={value}>{children}</BalancePrivacyContext.Provider>;
}

export function useBalancePrivacy() {
  return useContext(BalancePrivacyContext);
}

/** Formatter for client code that builds strings (chart axes/tooltips): masked while hidden. */
export function useMoneyFormat() {
  const { hidden } = useBalancePrivacy();
  return useMemo(
    () => ({
      hidden,
      format: (amount: number, currency = "IDR") => (hidden ? maskedMoney(currency) : formatCurrency(amount, currency)),
      compact: (amount: number, currency = "IDR") =>
        hidden ? maskedMoney(currency, true) : formatCompactCurrency(amount, currency),
      /** Chart axis ticks: blank while hidden. */
      axis: (amount: number, currency = "IDR") => (hidden ? "" : formatCompactCurrency(amount, currency)),
    }),
    [hidden],
  );
}

/** Eye button that flips balance privacy (persisted). */
export function BalanceToggle({ className, label = false }: { className?: string; label?: boolean }) {
  const { hidden, toggle } = useBalancePrivacy();
  const Icon = hidden ? EyeOff : Eye;
  const text = hidden ? "Tampilkan saldo" : "Sembunyikan saldo";
  return (
    <button
      type="button"
      onClick={toggle}
      aria-pressed={hidden}
      aria-label={text}
      title={text}
      data-testid="balance-toggle"
      className={cn(
        "inline-flex items-center gap-2 rounded-lg p-2 text-muted transition hover:bg-accent hover:text-foreground active:scale-90",
        className,
      )}
    >
      <Icon key={hidden ? "off" : "on"} className="h-[18px] w-[18px] animate-[pop_0.25s_ease-out]" />
      {label && <span className="text-sm font-medium">{text}</span>}
    </button>
  );
}
