/** Balance privacy ("sembunyikan saldo"): shared by the server layout and the client toggle. */
export const BALANCE_PRIVACY_COOKIE = "ghina_hide_balance";
export const BALANCE_PRIVACY_STORAGE_KEY = "ghina.hideBalance";

/** `Rp •••••` (compact: `Rp •••`) — roughly the width of a real amount so layouts don't jump. */
export function maskedMoney(currency = "IDR", compact = false): string {
  const dots = compact ? "•••" : "•••••";
  return `${currencySymbol(currency)} ${dots}`;
}

export function currencySymbol(currency = "IDR"): string {
  if (currency === "IDR") return "Rp";
  try {
    const part = new Intl.NumberFormat("en-US", { style: "currency", currency })
      .formatToParts(0)
      .find((p) => p.type === "currency");
    return part?.value ?? currency;
  } catch {
    return currency;
  }
}
