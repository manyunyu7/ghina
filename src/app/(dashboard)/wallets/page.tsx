import { Wallet as WalletIcon } from "lucide-react";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { formatCurrency } from "@/lib/utils";
import { walletIconFor, WALLET_TYPES } from "@/lib/constants";
import { Card, CardContent } from "@/components/ui/card";
import { Badge, EmptyState, PageHeader } from "@/components/ui/misc";
import { AddWalletButton } from "./add-wallet-button";
import { WalletCardActions } from "./wallet-card-actions";

export default async function WalletsPage() {
  const user = await requireUser();

  const wallets = await prisma.wallet.findMany({
    where: { userId: user.id, archived: false },
    include: { _count: { select: { transactions: true } } },
    orderBy: { createdAt: "asc" },
  });

  const total = wallets.reduce((sum, w) => sum + w.balance, 0);
  const typeLabel = (value: string) =>
    WALLET_TYPES.find((t) => t.value === value)?.label ?? value;

  return (
    <div>
      <PageHeader
        title="Wallets"
        description="Manage the accounts that hold your money."
        action={<AddWalletButton defaultCurrency={user.currency} />}
      />

      <Card className="mb-6 bg-primary text-white">
        <CardContent className="flex items-center justify-between">
          <div>
            <p className="text-sm font-medium text-white/80">Total balance</p>
            <p className="mt-1 text-3xl font-bold tracking-tight">
              {formatCurrency(total, user.currency)}
            </p>
          </div>
          <div className="flex h-12 w-12 items-center justify-center rounded-full bg-white/15">
            <WalletIcon className="h-6 w-6" />
          </div>
        </CardContent>
      </Card>

      {wallets.length === 0 ? (
        <EmptyState
          icon={WalletIcon}
          title="No wallets yet"
          description="Add your first wallet to start tracking your balances and transactions."
          action={<AddWalletButton defaultCurrency={user.currency} label="Add your first wallet" />}
        />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {wallets.map((w) => {
            const Icon = walletIconFor(w.type);
            const count = w._count.transactions;
            return (
              <Card key={w.id} className="overflow-hidden">
                {/* color accent strip */}
                <div className="h-1.5 w-full" style={{ background: w.color }} />
                <CardContent className="space-y-4">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-center gap-3">
                      <div
                        className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-white"
                        style={{ background: w.color }}
                      >
                        <Icon className="h-5 w-5" />
                      </div>
                      <div className="min-w-0">
                        <p className="truncate font-semibold text-foreground">{w.name}</p>
                        <p className="text-xs text-muted">{typeLabel(w.type)}</p>
                      </div>
                    </div>
                    <WalletCardActions
                      wallet={{
                        id: w.id,
                        name: w.name,
                        type: w.type,
                        balance: w.balance,
                        currency: w.currency,
                        color: w.color,
                      }}
                      transactionCount={count}
                      defaultCurrency={user.currency}
                    />
                  </div>

                  <div>
                    <p className="text-xs text-muted">Balance</p>
                    <p className="mt-0.5 text-2xl font-bold tracking-tight text-foreground">
                      {formatCurrency(w.balance, w.currency)}
                    </p>
                  </div>

                  <div className="flex items-center justify-between">
                    <Badge>
                      {count} transaction{count === 1 ? "" : "s"}
                    </Badge>
                    <Badge variant="default">{w.currency}</Badge>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
