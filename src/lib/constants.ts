import {
  Wallet,
  Banknote,
  CreditCard,
  PiggyBank,
  TrendingUp,
  Smartphone,
  type LucideIcon,
} from "lucide-react";

export const COLOR_PALETTE = [
  "#6366f1", "#8b5cf6", "#ec4899", "#ef4444", "#f97316",
  "#f59e0b", "#eab308", "#84cc16", "#22c55e", "#10b981",
  "#14b8a6", "#06b6d4", "#0ea5e9", "#3b82f6", "#64748b",
];

export const WALLET_TYPES: { value: string; label: string; icon: LucideIcon }[] = [
  { value: "cash", label: "Cash", icon: Banknote },
  { value: "bank", label: "Bank Account", icon: Wallet },
  { value: "ewallet", label: "E-Wallet", icon: Smartphone },
  { value: "credit", label: "Credit Card", icon: CreditCard },
  { value: "savings", label: "Savings", icon: PiggyBank },
  { value: "investment", label: "Investment", icon: TrendingUp },
];

export const walletIconFor = (type: string): LucideIcon =>
  WALLET_TYPES.find((t) => t.value === type)?.icon ?? Wallet;

// Curated icon names for categories (lucide-react names)
export const CATEGORY_ICONS = [
  "utensils", "shopping-cart", "shopping-bag", "car", "bus", "fuel",
  "home", "zap", "wifi", "phone", "heart-pulse", "pill",
  "graduation-cap", "book-open", "gamepad-2", "film", "music",
  "plane", "gift", "coffee", "dumbbell", "shirt", "baby", "dog",
  "briefcase", "landmark", "piggy-bank", "trending-up", "wallet",
  "banknote", "credit-card", "circle-dollar-sign", "receipt", "circle",
];

export const DEFAULT_EXPENSE_CATEGORIES = [
  { name: "Food & Drink", icon: "utensils", color: "#f97316" },
  { name: "Groceries", icon: "shopping-cart", color: "#22c55e" },
  { name: "Transport", icon: "car", color: "#3b82f6" },
  { name: "Shopping", icon: "shopping-bag", color: "#ec4899" },
  { name: "Bills & Utilities", icon: "zap", color: "#eab308" },
  { name: "Housing", icon: "home", color: "#8b5cf6" },
  { name: "Health", icon: "heart-pulse", color: "#ef4444" },
  { name: "Entertainment", icon: "film", color: "#06b6d4" },
  { name: "Education", icon: "graduation-cap", color: "#14b8a6" },
];

export const DEFAULT_INCOME_CATEGORIES = [
  { name: "Salary", icon: "briefcase", color: "#16a34a" },
  { name: "Business", icon: "landmark", color: "#0ea5e9" },
  { name: "Investment", icon: "trending-up", color: "#8b5cf6" },
  { name: "Gift", icon: "gift", color: "#ec4899" },
];
