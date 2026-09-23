import { DEFAULT_EXPENSE_CATEGORIES, DEFAULT_INCOME_CATEGORIES } from "@/lib/constants";

/** Nested-create data giving a new user a starter Cash wallet and the default category set. */
export function starterUserData() {
  return {
    wallets: {
      create: { name: "Cash", type: "cash", balance: 0, currency: "IDR", color: "#22c55e", icon: "cash" },
    },
    categories: {
      create: [
        ...DEFAULT_EXPENSE_CATEGORIES.map((c) => ({ ...c, type: "expense" })),
        ...DEFAULT_INCOME_CATEGORIES.map((c) => ({ ...c, type: "income" })),
      ],
    },
  };
}
