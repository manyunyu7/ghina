import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

const currencyConfig: Record<string, { locale: string; maximumFractionDigits: number }> = {
  IDR: { locale: "id-ID", maximumFractionDigits: 0 },
  USD: { locale: "en-US", maximumFractionDigits: 2 },
  EUR: { locale: "de-DE", maximumFractionDigits: 2 },
  GBP: { locale: "en-GB", maximumFractionDigits: 2 },
  JPY: { locale: "ja-JP", maximumFractionDigits: 0 },
  SGD: { locale: "en-SG", maximumFractionDigits: 2 },
  MYR: { locale: "ms-MY", maximumFractionDigits: 2 },
};

export function formatCurrency(amount: number, currency = "IDR"): string {
  const cfg = currencyConfig[currency] ?? currencyConfig.IDR;
  return new Intl.NumberFormat(cfg.locale, {
    style: "currency",
    currency,
    maximumFractionDigits: cfg.maximumFractionDigits,
  }).format(amount);
}

export function formatCompactCurrency(amount: number, currency = "IDR"): string {
  const cfg = currencyConfig[currency] ?? currencyConfig.IDR;
  return new Intl.NumberFormat(cfg.locale, {
    style: "currency",
    currency,
    notation: "compact",
    maximumFractionDigits: 1,
  }).format(amount);
}

export function formatDate(date: Date | string, opts?: Intl.DateTimeFormatOptions): string {
  const d = typeof date === "string" ? new Date(date) : date;
  return new Intl.DateTimeFormat("en-US", opts ?? { day: "numeric", month: "short", year: "numeric" }).format(d);
}

export const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

export const CURRENCIES = ["IDR", "USD", "EUR", "GBP", "JPY", "SGD", "MYR"];
