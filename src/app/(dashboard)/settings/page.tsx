import { Wallet, ArrowLeftRight, Tags, Target } from "lucide-react";
import { requireUser } from "@/lib/auth-helpers";
import { signOut } from "@/auth";
import { prisma } from "@/lib/prisma";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { Badge, PageHeader } from "@/components/ui/misc";
import { PreferencesForm } from "./preferences-form";
import { ResetDataButton } from "./reset-data-button";
import { SignOutButton } from "./sign-out-button";

export default async function SettingsPage() {
  const user = await requireUser();

  async function doSignOut() {
    "use server";
    await signOut({ redirectTo: "/login" });
  }

  const [walletCount, transactionCount, categoryCount, budgetCount] = await Promise.all([
    prisma.wallet.count({ where: { userId: user.id } }),
    prisma.transaction.count({ where: { userId: user.id } }),
    prisma.category.count({ where: { userId: user.id } }),
    prisma.budget.count({ where: { userId: user.id } }),
  ]);

  const displayName = user.name ?? "User";
  const avatarUrl =
    user.image ??
    `https://api.dicebear.com/9.x/initials/svg?seed=${encodeURIComponent(displayName)}`;

  const stats = [
    { label: "Wallets", value: walletCount, icon: Wallet },
    { label: "Transactions", value: transactionCount, icon: ArrowLeftRight },
    { label: "Categories", value: categoryCount, icon: Tags },
    { label: "Budgets", value: budgetCount, icon: Target },
  ];

  return (
    <div>
      <PageHeader title="Settings" description="Manage your profile, preferences, and data." />

      <div className="grid gap-6 lg:grid-cols-2">
        {/* Profile */}
        <Card>
          <CardHeader>
            <CardTitle>Profile</CardTitle>
            <Badge variant="primary">Google</Badge>
          </CardHeader>
          <CardContent>
            <div className="flex items-center gap-4">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={avatarUrl}
                alt={displayName}
                className="h-16 w-16 rounded-full border border-border bg-accent object-cover"
              />
              <div className="min-w-0">
                <p className="truncate text-base font-semibold text-foreground">{displayName}</p>
                <p className="truncate text-sm text-muted">{user.email ?? "No email"}</p>
                <p className="mt-1 text-xs text-muted-soft">
                  Name and email come from your Google account.
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Preferences */}
        <Card>
          <CardHeader>
            <CardTitle>Preferences</CardTitle>
          </CardHeader>
          <CardContent>
            <PreferencesForm defaultName={displayName} defaultCurrency={user.currency} />
          </CardContent>
        </Card>

        {/* Account stats */}
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Account stats</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
              {stats.map(({ label, value, icon: Icon }) => (
                <div
                  key={label}
                  className="rounded-card border border-border bg-surface p-4"
                >
                  <div className="flex items-center gap-2 text-muted">
                    <Icon className="h-4 w-4" />
                    <span className="text-xs font-medium">{label}</span>
                  </div>
                  <p className="mt-2 text-2xl font-bold text-foreground">{value}</p>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Danger zone */}
        <Card className="border-expense/40 lg:col-span-2">
          <CardHeader>
            <CardTitle className="text-expense">Danger zone</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Reset all data</p>
                <p className="text-sm text-muted">
                  Permanently delete all wallets, transactions, categories, and budgets.
                </p>
              </div>
              <ResetDataButton />
            </div>

            <div className="mt-6 flex flex-col gap-4 border-t border-border pt-6 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Sign out</p>
                <p className="text-sm text-muted">Sign out of your Buddget account.</p>
              </div>
              <SignOutButton action={doSignOut} />
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
