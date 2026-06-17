import { Repeat, CalendarClock, Wallet as WalletIcon, CircleDollarSign } from "lucide-react";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { getWallets, getCategories } from "@/lib/queries";
import { Card } from "@/components/ui/card";
import { EmptyState, PageHeader } from "@/components/ui/misc";
import { formatCurrency, formatDate } from "@/lib/utils";
import { monthlyAmount, yearlyAmount, nextOccurrence } from "./presets";
import { SubscriptionList } from "./subscription-list";
import { AddSubscriptionButton } from "./add-subscription-button";

export default async function SubscriptionsPage() {
  const user = await requireUser();
  const currency = user.currency || "IDR";

  const [subscriptions, wallets, categories] = await Promise.all([
    prisma.subscription.findMany({ where: { userId: user.id }, orderBy: [{ active: "desc" }, { nextBilling: "asc" }] }),
    getWallets(user.id),
    getCategories(user.id),
  ]);

  const active = subscriptions.filter((s) => s.active);
  const perMonth = active.reduce((sum, s) => sum + monthlyAmount(s.amount, s.cycle), 0);
  const perYear = active.reduce((sum, s) => sum + yearlyAmount(s.amount, s.cycle), 0);

  const nextRenewal = active
    .map((s) => ({ name: s.name, date: nextOccurrence(s.nextBilling, s.cycle) }))
    .sort((a, b) => a.date.getTime() - b.date.getTime())[0];

  // Serialize for the client list (Date -> ISO string).
  const items = subscriptions.map((s) => ({
    id: s.id,
    name: s.name,
    amount: s.amount,
    currency: s.currency,
    cycle: s.cycle,
    nextBilling: s.nextBilling.toISOString(),
    categoryId: s.categoryId,
    walletId: s.walletId,
    color: s.color,
    icon: s.icon,
    note: s.note,
    active: s.active,
  }));

  return (
    <div>
      <PageHeader
        title="Subscriptions"
        description="Track your recurring payments and see what they cost you."
        action={
          subscriptions.length > 0 ? (
            <AddSubscriptionButton wallets={wallets} categories={categories} currency={currency} />
          ) : undefined
        }
      />

      {subscriptions.length === 0 ? (
        <EmptyState
          icon={Repeat}
          title="No subscriptions yet"
          description="Add Netflix, Spotify, your gym, or anything you pay for regularly — then see the monthly damage."
          action={
            <AddSubscriptionButton wallets={wallets} categories={categories} currency={currency} />
          }
        />
      ) : (
        <>
          {/* Summary */}
          <div className="mb-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <StatTile
              icon={<CircleDollarSign className="h-5 w-5" />}
              label="Per month"
              value={formatCurrency(perMonth, currency)}
              tint="bg-primary-soft text-primary"
            />
            <StatTile
              icon={<Repeat className="h-5 w-5" />}
              label="Per year"
              value={formatCurrency(perYear, currency)}
              tint="bg-accent text-foreground"
            />
            <StatTile
              icon={<WalletIcon className="h-5 w-5" />}
              label="Active"
              value={`${active.length} of ${subscriptions.length}`}
              tint="bg-income-soft text-income"
            />
            <StatTile
              icon={<CalendarClock className="h-5 w-5" />}
              label="Next renewal"
              value={nextRenewal ? formatDate(nextRenewal.date, { day: "numeric", month: "short" }) : "—"}
              sub={nextRenewal?.name}
              tint="bg-expense-soft text-expense"
            />
          </div>

          <SubscriptionList subscriptions={items} wallets={wallets} categories={categories} currency={currency} />
        </>
      )}
    </div>
  );
}

function StatTile({
  icon,
  label,
  value,
  sub,
  tint,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  sub?: string;
  tint: string;
}) {
  return (
    <Card className="p-4">
      <div className={`mb-3 flex h-9 w-9 items-center justify-center rounded-lg ${tint}`}>{icon}</div>
      <p className="text-sm text-muted">{label}</p>
      <p className="truncate text-xl font-bold text-foreground">{value}</p>
      {sub && <p className="truncate text-xs text-muted-soft">{sub}</p>}
    </Card>
  );
}
