"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  LayoutDashboard, ArrowLeftRight, Wallet, Target, Tags, PieChart,
  Settings, Repeat, Moon, HeartPulse, Utensils, TrendingUp, BarChart3, ListTodo, Menu, X,
  StickyNote,
  Clapperboard,
  Flame,
  LineChart,
  ChevronDown,
  Search,
} from "lucide-react";
import {
  NAV_COLLAPSED_COOKIE,
  NAV_COLLAPSED_STORAGE_KEY,
  NAV_SECTIONS,
  activeNavHref,
  navItemMatches,
  parseCollapsed,
} from "@/lib/nav";
import { cn } from "@/lib/utils";
import { AppDownload } from "@/components/app-download";
import { NavPending } from "@/components/nav-pending";
import { BalanceToggle } from "@/components/money/balance-privacy";

const ICONS = { LayoutDashboard, ArrowLeftRight, Wallet, Target, Tags, PieChart, Settings, Repeat, Moon, HeartPulse, Utensils, TrendingUp, BarChart3, ListTodo, StickyNote, Clapperboard, Flame, LineChart };

type User = { name?: string | null; email?: string | null; image?: string | null };

/** Ghina's money-tree mascot, the brand mark next to the wordmark. */
function Logo({ className }: { className?: string }) {
  return <Image src="/logo.png" alt="" aria-hidden width={36} height={36} className={cn("shrink-0", className)} loading="eager" />;
}

function persistCollapsed(ids: string[]) {
  const value = ids.join(",");
  try {
    localStorage.setItem(NAV_COLLAPSED_STORAGE_KEY, value);
  } catch {}
  // Cookie lets the server render the same collapsed state on the first paint (no flicker).
  document.cookie = `${NAV_COLLAPSED_COOKIE}=${ids.join(".")}; path=/; max-age=31536000; samesite=lax`;
}

const DESKTOP_QUERY = "(min-width: 1024px)";

/** [initialCollapsed] comes from the cookie (dashboard layout) so SSR matches the client. */
export function Sidebar({ user, initialCollapsed = [] }: { user: User; initialCollapsed?: string[] }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const [collapsed, setCollapsed] = useState<string[]>(initialCollapsed);
  const [query, setQuery] = useState("");
  const desktopFilter = useRef<HTMLInputElement>(null);
  const drawerFilter = useRef<HTMLInputElement>(null);
  const focusDrawerFilter = useRef(false);

  // localStorage is the durable copy: if the cookie was cleared, restore from it.
  useEffect(() => {
    let stored: string | null = null;
    try {
      stored = localStorage.getItem(NAV_COLLAPSED_STORAGE_KEY);
    } catch {}
    if (stored === null) {
      persistCollapsed(initialCollapsed);
    } else {
      const ids = parseCollapsed(stored);
      if (ids.join(",") !== initialCollapsed.join(",")) {
        // eslint-disable-next-line react-hooks/set-state-in-effect -- one-time sync from browser storage after mount
        setCollapsed(ids);
        persistCollapsed(ids);
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- mount only
  }, []);

  const toggleSection = useCallback((id: string) => {
    setCollapsed((prev) => {
      const next = prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id];
      persistCollapsed(next);
      return next;
    });
  }, []);

  // Ctrl/⌘+K focuses "Cari menu" (desktop sidebar, or opens the drawer on small screens).
  // Skips events a field already handled (the notes editor uses ⌘K for links).
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.defaultPrevented || !(e.metaKey || e.ctrlKey) || e.altKey || e.shiftKey) return;
      if (e.key.toLowerCase() !== "k") return;
      if (document.querySelector('[role="dialog"][aria-modal="true"]:not([data-nav-drawer])')) return;
      e.preventDefault();
      if (window.matchMedia(DESKTOP_QUERY).matches) {
        desktopFilter.current?.focus();
        desktopFilter.current?.select();
      } else if (drawerFilter.current) {
        drawerFilter.current.focus();
      } else {
        focusDrawerFilter.current = true;
        setOpen(true);
      }
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => {
    if (open && focusDrawerFilter.current) {
      focusDrawerFilter.current = false;
      drawerFilter.current?.focus();
    }
  }, [open]);

  // Escape closes the drawer.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open]);

  const closeAndReset = useCallback(() => {
    setOpen(false);
    setQuery("");
  }, []);

  const body = (id: string, inputRef: React.RefObject<HTMLInputElement | null>) => (
    <NavBody
      id={id}
      pathname={pathname}
      collapsed={collapsed}
      onToggle={toggleSection}
      query={query}
      onQuery={setQuery}
      inputRef={inputRef}
      onNavigate={closeAndReset}
    />
  );

  return (
    <>
      {/* Mobile top bar */}
      <div className="flex items-center justify-between border-b border-border bg-surface px-4 py-3 lg:hidden">
        <div className="flex items-center gap-2">
          <Logo className="h-8 w-8" />
          <span className="text-lg font-bold">Ghina</span>
        </div>
        <div className="flex items-center gap-1">
          <BalanceToggle />
          <button
            onClick={() => setOpen(true)}
            className="rounded-lg p-2 hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
            aria-label="Buka menu"
            aria-expanded={open}
          >
            <Menu className="h-5 w-5" />
          </button>
        </div>
      </div>

      {/* Mobile drawer */}
      {open && (
        <div className="fixed inset-0 z-40 lg:hidden" role="dialog" aria-modal="true" aria-label="Menu" data-nav-drawer>
          <div className="absolute inset-0 bg-slate-900/40 backdrop-blur-sm" onClick={() => setOpen(false)} />
          <aside className="absolute left-0 top-0 flex h-full w-72 max-w-[85vw] flex-col bg-surface p-4 shadow-xl">
            <div className="mb-3 flex shrink-0 items-center justify-between">
              <div className="flex items-center gap-2">
                <Logo className="h-8 w-8" />
                <span className="text-lg font-bold">Ghina</span>
              </div>
              <button
                onClick={() => setOpen(false)}
                className="rounded-lg p-2 hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
                aria-label="Tutup menu"
              >
                <X className="h-5 w-5" />
              </button>
            </div>
            {body("drawer", drawerFilter)}
            <UserCard user={user} onNavigate={closeAndReset} />
          </aside>
        </div>
      )}

      {/* Desktop sidebar: sticky, full viewport height; the nav list scrolls on its own. */}
      <aside className="hidden w-64 shrink-0 flex-col border-r border-border bg-surface p-4 lg:sticky lg:top-0 lg:flex lg:h-screen">
        <div className="mb-4 flex shrink-0 items-center gap-2 px-2">
          <Logo className="h-9 w-9" />
          <span className="text-xl font-bold tracking-tight">Ghina</span>
          <BalanceToggle className="ml-auto" />
        </div>
        {body("desktop", desktopFilter)}
        <UserCard user={user} />
      </aside>
    </>
  );
}

function NavBody({
  id,
  pathname,
  collapsed,
  onToggle,
  query,
  onQuery,
  inputRef,
  onNavigate,
}: {
  id: string;
  pathname: string;
  collapsed: string[];
  onToggle: (id: string) => void;
  query: string;
  onQuery: (q: string) => void;
  inputRef: React.RefObject<HTMLInputElement | null>;
  onNavigate: () => void;
}) {
  const navRef = useRef<HTMLElement>(null);
  const activeHref = activeNavHref(pathname);
  const filtering = query.trim().length > 0;
  const sections = NAV_SECTIONS.map((s) => ({
    ...s,
    items: filtering ? s.items.filter((it) => navItemMatches(it, query)) : s.items,
  })).filter((s) => s.items.length > 0);
  const matchCount = sections.reduce((n, s) => n + s.items.length, 0);

  function onFilterKey(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Enter") {
      e.preventDefault();
      // Click the real <Link> so NavPending shows its spinner/progress bar.
      navRef.current?.querySelector<HTMLAnchorElement>("a[data-nav-item]")?.click();
    } else if (e.key === "ArrowDown") {
      e.preventDefault();
      navRef.current?.querySelector<HTMLAnchorElement>("a[data-nav-item]")?.focus();
    } else if (e.key === "Escape" && query) {
      e.preventDefault();
      e.stopPropagation();
      e.nativeEvent.stopImmediatePropagation();
      onQuery("");
    }
  }

  return (
    <>
      <div className="relative mb-2 shrink-0" role="search">
        <Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-soft" />
        <input
          ref={inputRef}
          type="search"
          value={query}
          onChange={(e) => onQuery(e.target.value)}
          onKeyDown={onFilterKey}
          placeholder="Cari menu"
          aria-label="Cari menu"
          aria-controls={`${id}-nav`}
          aria-keyshortcuts="Control+K Meta+K"
          autoComplete="off"
          spellCheck={false}
          data-testid="nav-filter"
          className="h-9 w-full rounded-lg border border-border bg-background pl-9 pr-12 text-sm text-foreground placeholder:text-muted-soft focus-visible:border-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 [&::-webkit-search-cancel-button]:hidden"
        />
        <kbd
          aria-hidden
          className="pointer-events-none absolute right-2 top-1/2 hidden -translate-y-1/2 rounded border border-border bg-surface px-1.5 font-sans text-[10px] font-medium text-muted-soft lg:block"
        >
          <ShortcutLabel />
        </kbd>
      </div>
      <nav
        ref={navRef}
        id={`${id}-nav`}
        aria-label="Navigasi utama"
        className="-mx-2 flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto overscroll-contain px-2 pb-2"
      >
        {matchCount === 0 && <p className="px-3 py-2 text-sm text-muted">Tidak ada menu yang cocok.</p>}
        {sections.map((section) => {
          const hasActive = section.items.some((it) => it.href === activeHref);
          // The section with the current page is always open; filtering shows every match.
          const locked = filtering || hasActive;
          const expanded = !section.label || locked || !collapsed.includes(section.id);
          const listId = `${id}-sec-${section.id}`;
          const items = (
            <ul id={listId} hidden={!expanded} className="flex flex-col gap-0.5">
              {section.items.map((item) => {
                const Icon = ICONS[item.icon as keyof typeof ICONS];
                const active = item.href === activeHref;
                return (
                  <li key={item.href}>
                    <Link
                      href={item.href}
                      onClick={onNavigate}
                      data-nav-item
                      aria-current={active ? "page" : undefined}
                      className={cn(
                        "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50",
                        item.sub && !filtering && "ml-5 gap-2.5 py-1.5 text-[13px]",
                        active ? "bg-primary-soft text-primary" : "text-muted hover:bg-accent hover:text-foreground",
                      )}
                    >
                      <Icon aria-hidden className={item.sub && !filtering ? "h-4 w-4" : "h-[18px] w-[18px]"} />
                      {item.label}
                      <NavPending />
                    </Link>
                  </li>
                );
              })}
            </ul>
          );
          if (!section.label) return <div key={section.id}>{items}</div>;
          return (
            <div key={section.id} className="mt-2" data-nav-section={section.id}>
              <button
                type="button"
                onClick={() => !locked && onToggle(section.id)}
                aria-disabled={locked || undefined}
                aria-expanded={expanded}
                aria-controls={listId}
                title={hasActive && !filtering ? "Berisi halaman yang sedang dibuka" : undefined}
                className="group flex w-full items-center gap-2 rounded-md px-3 py-1.5 text-[11px] font-semibold uppercase tracking-wider text-muted-soft transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50 aria-disabled:cursor-default aria-disabled:hover:text-muted-soft"
              >
                {section.label}
                <ChevronDown
                  aria-hidden
                  className={cn(
                    "ml-auto h-3.5 w-3.5 transition-transform group-aria-disabled:opacity-40",
                    !expanded && "-rotate-90",
                  )}
                />
              </button>
              {items}
            </div>
          );
        })}
      </nav>
    </>
  );
}

/** "⌘K" on Apple platforms, "Ctrl K" elsewhere (server renders "Ctrl K"). */
function ShortcutLabel() {
  const [mac, setMac] = useState(false);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- platform is only known in the browser
    setMac(/Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent));
  }, []);
  return <>{mac ? "⌘K" : "Ctrl K"}</>;
}

function UserCard({ user, onNavigate }: { user: User; onNavigate?: () => void }) {
  return (
    <div className="mt-2 shrink-0 border-t border-border pt-3">
      <AppDownload compact className="mb-2" />
      <Link
        href="/settings"
        onClick={onNavigate}
        className="flex items-center gap-3 rounded-lg p-2 transition hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={user.image || `https://api.dicebear.com/9.x/initials/svg?seed=${encodeURIComponent(user.name || "U")}`}
          alt=""
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
