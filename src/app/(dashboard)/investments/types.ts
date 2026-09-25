import type { AssetDTO, HoldingRow, TradeDTO } from "@/lib/investments-server";
import type { Holding } from "@/lib/investments";

export type WalletOption = { id: string; name: string; type: string; currency: string; balance: number };
export type HistoryPoint = { date: string; value: number; cost: number };
export type { AssetDTO, HoldingRow, TradeDTO, Holding };

/** Wallets for pickers: investment wallets first. */
export function sortWallets(wallets: WalletOption[]): WalletOption[] {
  return [...wallets].sort((a, b) => Number(b.type === "investment") - Number(a.type === "investment"));
}
