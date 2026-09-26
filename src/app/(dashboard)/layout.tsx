import { cookies } from "next/headers";
import { requireUser } from "@/lib/auth-helpers";
import { BALANCE_PRIVACY_COOKIE } from "@/lib/balance-privacy";
import { Sidebar } from "@/components/sidebar";
import { NAV_COLLAPSED_COOKIE, parseCollapsed } from "@/lib/nav";
import { BalancePrivacyProvider } from "@/components/money/balance-privacy";

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();
  // Read on the server so hidden balances are masked in the very first HTML (no flash).
  const jar = await cookies();
  const hideBalance = jar.get(BALANCE_PRIVACY_COOKIE)?.value === "1";
  // Collapsed sidebar sections, also from a cookie so the first HTML matches the client.
  const navCollapsed = parseCollapsed(jar.get(NAV_COLLAPSED_COOKIE)?.value);

  return (
    <BalancePrivacyProvider initialHidden={hideBalance}>
      <div className="flex min-h-screen flex-col lg:flex-row">
        <Sidebar user={{ name: user.name, email: user.email, image: user.image }} initialCollapsed={navCollapsed} />
        <main className="flex-1 overflow-x-hidden">
          <div className="mx-auto w-full max-w-6xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">{children}</div>
        </main>
      </div>
    </BalancePrivacyProvider>
  );
}
