// Demo data seeder for Buddget.
// Usage: log in once with Google (creates your user), then run `npm run seed`.
// It seeds the FIRST user in the DB, or set SEED_EMAIL=you@example.com to target one.
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

const EXPENSE_CATEGORIES = [
  { name: "Food & Drink", icon: "utensils", color: "#f97316" },
  { name: "Groceries", icon: "shopping-cart", color: "#22c55e" },
  { name: "Transport", icon: "car", color: "#3b82f6" },
  { name: "Shopping", icon: "shopping-bag", color: "#ec4899" },
  { name: "Bills & Utilities", icon: "zap", color: "#eab308" },
  { name: "Housing", icon: "home", color: "#8b5cf6" },
  { name: "Health", icon: "heart-pulse", color: "#ef4444" },
  { name: "Entertainment", icon: "film", color: "#06b6d4" },
];
const INCOME_CATEGORIES = [
  { name: "Salary", icon: "briefcase", color: "#16a34a" },
  { name: "Business", icon: "landmark", color: "#0ea5e9" },
];

const WALLETS = [
  { name: "Cash", type: "cash", balance: 0, color: "#22c55e", icon: "cash" },
  { name: "Bank Account", type: "bank", balance: 0, color: "#6366f1", icon: "bank" },
  { name: "E-Wallet", type: "ewallet", balance: 0, color: "#ec4899", icon: "ewallet" },
];

const rand = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;
const pick = (arr) => arr[rand(0, arr.length - 1)];

async function main() {
  const user = process.env.SEED_EMAIL
    ? await prisma.user.findUnique({ where: { email: process.env.SEED_EMAIL } })
    : await prisma.user.findFirst({ orderBy: { createdAt: "asc" } });

  if (!user) {
    console.error("\n  No user found. Sign in with Google once (npm run dev → /login), then re-run `npm run seed`.\n");
    process.exit(1);
  }
  console.log(`Seeding demo data for: ${user.email ?? user.id}`);

  // Clean previous data for this user (idempotent)
  await prisma.budget.deleteMany({ where: { userId: user.id } });
  await prisma.transaction.deleteMany({ where: { userId: user.id } });
  await prisma.category.deleteMany({ where: { userId: user.id } });
  await prisma.wallet.deleteMany({ where: { userId: user.id } });

  const currency = user.currency || "IDR";

  const wallets = [];
  for (const w of WALLETS) {
    wallets.push(await prisma.wallet.create({ data: { ...w, currency, userId: user.id } }));
  }

  const expenseCats = [];
  for (const c of EXPENSE_CATEGORIES) {
    expenseCats.push(await prisma.category.create({ data: { ...c, type: "expense", userId: user.id } }));
  }
  const incomeCats = [];
  for (const c of INCOME_CATEGORIES) {
    incomeCats.push(await prisma.category.create({ data: { ...c, type: "income", userId: user.id } }));
  }

  // Scale amounts: IDR uses larger numbers
  const big = currency === "IDR" || currency === "JPY";
  const amt = (lo, hi) => (big ? rand(lo, hi) * 1000 : rand(lo, hi));

  const balances = new Map(wallets.map((w) => [w.id, 0]));
  const txData = [];
  const now = new Date();

  // 3 months of data
  for (let monthsAgo = 2; monthsAgo >= 0; monthsAgo--) {
    const base = new Date(now.getFullYear(), now.getMonth() - monthsAgo, 1);

    // Monthly salary (income)
    {
      const wallet = wallets[1];
      const amount = amt(8000, 12000);
      balances.set(wallet.id, balances.get(wallet.id) + amount);
      txData.push({
        userId: user.id, walletId: wallet.id, categoryId: incomeCats[0].id,
        type: "income", amount, note: "Monthly salary",
        date: new Date(base.getFullYear(), base.getMonth(), 25),
      });
    }

    // ~20 expenses spread across the month
    const count = rand(16, 24);
    for (let i = 0; i < count; i++) {
      const cat = pick(expenseCats);
      const wallet = pick(wallets);
      const amount = amt(20, 400);
      balances.set(wallet.id, balances.get(wallet.id) - amount);
      txData.push({
        userId: user.id, walletId: wallet.id, categoryId: cat.id,
        type: "expense", amount,
        note: `${cat.name}`,
        date: new Date(base.getFullYear(), base.getMonth(), rand(1, 28), rand(8, 21), rand(0, 59)),
      });
    }
  }

  await prisma.transaction.createMany({ data: txData });

  // Sync wallet balances to reflect seeded transactions (plus a little starting cash)
  for (const w of wallets) {
    const starting = w.type === "cash" ? amt(500, 1500) : 0;
    await prisma.wallet.update({
      where: { id: w.id },
      data: { balance: starting + balances.get(w.id) },
    });
  }

  // Budgets for the current month (first 6 expense categories)
  const month = now.getMonth() + 1;
  const year = now.getFullYear();
  for (const cat of expenseCats.slice(0, 6)) {
    await prisma.budget.create({
      data: { userId: user.id, categoryId: cat.id, amount: amt(500, 2500), month, year },
    });
  }

  console.log(`✓ Seeded ${wallets.length} wallets, ${expenseCats.length + incomeCats.length} categories, ${txData.length} transactions, 6 budgets.`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
