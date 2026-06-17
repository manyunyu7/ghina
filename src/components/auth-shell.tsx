import { Wallet, TrendingUp, Target, PieChart } from "lucide-react";

export function AuthShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="grid min-h-screen lg:grid-cols-2">
      {/* Left — branding */}
      <div className="relative hidden flex-col justify-between overflow-hidden bg-primary p-12 text-white lg:flex">
        <div className="flex items-center gap-2">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-white/20">
            <Wallet className="h-5 w-5" />
          </div>
          <span className="text-xl font-bold">Ghina</span>
        </div>
        <div className="relative z-10">
          <h1 className="text-4xl font-bold leading-tight">
            Take control of <br /> your money.
          </h1>
          <p className="mt-4 max-w-md text-white/80">
            Track every transaction, manage your wallets, set monthly budgets, and
            visualize where your money goes — all in one place.
          </p>
          <div className="mt-10 grid grid-cols-2 gap-4">
            {[
              { icon: TrendingUp, label: "Income & expense tracking" },
              { icon: Wallet, label: "Multiple wallets" },
              { icon: Target, label: "Monthly budgets" },
              { icon: PieChart, label: "Insightful reports" },
            ].map((f) => (
              <div key={f.label} className="flex items-center gap-3 rounded-xl bg-white/10 p-3">
                <f.icon className="h-5 w-5 shrink-0" />
                <span className="text-sm font-medium">{f.label}</span>
              </div>
            ))}
          </div>
        </div>
        <p className="text-sm text-white/60">Your finances, simplified.</p>
        <div className="absolute -right-20 -top-20 h-72 w-72 rounded-full bg-white/10" />
        <div className="absolute -bottom-24 -left-10 h-72 w-72 rounded-full bg-white/5" />
      </div>

      {/* Right — content */}
      <div className="flex items-center justify-center bg-background p-6">
        <div className="w-full max-w-sm">
          <div className="mb-8 flex items-center gap-2 lg:hidden">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary text-white">
              <Wallet className="h-5 w-5" />
            </div>
            <span className="text-xl font-bold">Ghina</span>
          </div>
          {children}
        </div>
      </div>
    </div>
  );
}

export function GoogleIcon() {
  return (
    <svg className="h-5 w-5" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
      <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
      <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l3.66-2.84z" />
      <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
    </svg>
  );
}
