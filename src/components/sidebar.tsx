"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import {
  LayoutDashboard, ArrowLeftRight, Wallet, Target, Tags, PieChart,
  Settings, Repeat, Moon, HeartPulse, Menu, X, Wallet as Logo,
} from "lucide-react";
import { NAV_ITEMS } from "@/lib/nav";
import { cn } from "@/lib/utils";

const ICONS = { LayoutDashboard, ArrowLeftRight, Wallet, Target, Tags, PieChart, Settings, Repeat, Moon, HeartPulse };

export function Sidebar({ user }: { user: { name?: string | null; email?: string | null; image?: string | null } }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  const nav = (
    <nav className="flex flex-1 flex-col gap-1">
      {NAV_ITEMS.map((item) => {
        const Icon = ICONS[item.icon as keyof typeof ICONS];
        const active = pathname === item.href || pathname.startsWith(item.href + "/");
        return (
          <Link
            key={item.href}
            href={item.href}
            onClick={() => setOpen(false)}
            className={cn(
              "flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors",
              active
                ? "bg-primary-soft text-primary"
                : "text-muted hover:bg-accent hover:text-foreground",
            )}
          >
            <Icon className="h-[18px] w-[18px]" />
            {item.label}
          </Link>
        );
      })}
    </nav>
  );

  return (
    <>
      {/* Mobile top bar */}
      <div className="flex items-center justify-between border-b border-border bg-surface px-4 py-3 lg:hidden">
        <div className="flex items-center gap-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-white">
            <Logo className="h-5 w-5" />
          </div>
          <span className="text-lg font-bold">Ghina</span>
        </div>
        <button onClick={() => setOpen(true)} className="rounded-lg p-2 hover:bg-accent" aria-label="Open menu">
          <Menu className="h-5 w-5" />
        </button>
      </div>

      {/* Mobile drawer */}
      {open && (
        <div className="fixed inset-0 z-40 lg:hidden">
          <div className="absolute inset-0 bg-slate-900/40 backdrop-blur-sm" onClick={() => setOpen(false)} />
          <aside className="absolute left-0 top-0 flex h-full w-72 flex-col bg-surface p-4 shadow-xl">
            <div className="mb-6 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-white">
                  <Logo className="h-5 w-5" />
                </div>
                <span className="text-lg font-bold">Ghina</span>
              </div>
              <button onClick={() => setOpen(false)} className="rounded-lg p-2 hover:bg-accent" aria-label="Close menu">
                <X className="h-5 w-5" />
              </button>
            </div>
            {nav}
            <UserCard user={user} />
          </aside>
        </div>
      )}

      {/* Desktop sidebar */}
      <aside className="hidden w-64 shrink-0 flex-col border-r border-border bg-surface p-4 lg:flex">
        <div className="mb-8 flex items-center gap-2 px-2">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary text-white">
            <Logo className="h-5 w-5" />
          </div>
          <span className="text-xl font-bold tracking-tight">Ghina</span>
        </div>
        {nav}
        <UserCard user={user} />
      </aside>
    </>
  );
}

function UserCard({ user }: { user: { name?: string | null; email?: string | null; image?: string | null } }) {
  return (
    <div className="mt-4 border-t border-border pt-4">
      <Link href="/settings" className="flex items-center gap-3 rounded-lg p-2 transition hover:bg-accent">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={user.image || `https://api.dicebear.com/9.x/initials/svg?seed=${encodeURIComponent(user.name || "U")}`}
          alt={user.name || "User"}
          className="h-9 w-9 rounded-full bg-accent object-cover"
        />
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium text-foreground">{user.name || "User"}</p>
          <p className="truncate text-xs text-muted">{user.email}</p>
        </div>
      </Link>
    </div>
  );
}
