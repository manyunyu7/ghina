"use client";

import * as React from "react";
import { ArrowDown, ArrowUp, AtSign, Briefcase, Camera, Globe, Music2, Play, Users, X, type LucideIcon } from "lucide-react";
import {
  DEFAULT_TIME_ZONE,
  platformInfo,
  platformLabel,
  platformShort,
  POST_STATUSES,
  stageInfo,
} from "@/lib/content";
import { cn } from "@/lib/utils";
import type { ContentPillarDTO, SocialAccountDTO } from "./types";

// ---------- Time zone (browser; server render + hydration use the default zone) ----------

const subscribeNoop = () => () => {};
const browserZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone || DEFAULT_TIME_ZONE;

/**
 * The browser's IANA zone. During SSR and hydration it is the server default
 * (Asia/Jakarta), so formatted times match; afterwards the real zone.
 */
export function useTimeZone(): string {
  return React.useSyncExternalStore(subscribeNoop, browserZone, () => DEFAULT_TIME_ZONE);
}

function subscribeMinute(cb: () => void) {
  const t = setInterval(cb, 60_000);
  return () => clearInterval(t);
}
const minuteNow = () => Math.floor(Date.now() / 60_000) * 60_000;

/** Current time (ms, minute resolution) — 0 during SSR/hydration so markup matches. */
export function useNow(): number {
  return React.useSyncExternalStore(subscribeMinute, minuteNow, () => 0);
}

/** True once hydrated (client-only UI such as "today" markers). */
export function useHydrated(): boolean {
  return React.useSyncExternalStore(subscribeNoop, () => true, () => false);
}

const MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];
export const MONTHS_LONG = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];
export const WEEKDAYS_SHORT = ["Sen", "Sel", "Rab", "Kam", "Jum", "Sab", "Min"];
export const WEEKDAYS_LONG = ["Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu", "Minggu"];

/** "Sen, 24 Sep · 19.00" in `tz`. */
export function formatDateTime(iso: string, tz: string, opts: { weekday?: boolean; year?: boolean } = {}): string {
  return new Intl.DateTimeFormat("id-ID", {
    timeZone: tz,
    weekday: opts.weekday === false ? undefined : "short",
    day: "numeric",
    month: "short",
    year: opts.year ? "numeric" : undefined,
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(iso));
}

export function formatTime(iso: string, tz: string): string {
  return new Intl.DateTimeFormat("id-ID", { timeZone: tz, hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
}

/** "24 Sep 2026" for a YYYY-MM-DD key. */
export function formatDateKey(key: string, withYear = true): string {
  const [y, m, d] = key.split("-").map(Number);
  return `${d} ${MONTHS_SHORT[m - 1]}${withYear ? ` ${y}` : ""}`;
}

export function formatMonthKey(key: string): string {
  const [y, m] = key.split("-").map(Number);
  return `${MONTHS_SHORT[m - 1]} ${y}`;
}

/** ISO → value for <input type="datetime-local"> in the browser zone. */
export function toLocalInput(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

/** <input type="datetime-local"> value (browser zone) → ISO, or null. */
export function fromLocalInput(v: string): string | null {
  if (!v) return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

export const formatNumber = (n: number) => new Intl.NumberFormat("id-ID").format(Math.round(n));
export const formatCompact = (n: number) =>
  new Intl.NumberFormat("id-ID", { notation: "compact", maximumFractionDigits: 1 }).format(n);
export const formatPercent = (r: number) =>
  new Intl.NumberFormat("id-ID", { style: "percent", maximumFractionDigits: 1 }).format(r);

export const REMIND_OPTIONS = [
  { value: "", label: "Tanpa pengingat" },
  { value: "0", label: "Saat jadwal" },
  { value: "10", label: "10 menit sebelumnya" },
  { value: "30", label: "30 menit sebelumnya" },
  { value: "60", label: "1 jam sebelumnya" },
  { value: "120", label: "2 jam sebelumnya" },
  { value: "1440", label: "1 hari sebelumnya" },
];

// ---------- Platforms / accounts ----------

const PLATFORM_ICONS: Record<string, LucideIcon> = {
  camera: Camera,
  "music-2": Music2,
  play: Play,
  "at-sign": AtSign,
  briefcase: Briefcase,
  users: Users,
  globe: Globe,
};

export function PlatformIcon({ platform, className }: { platform: string; className?: string }) {
  const Icon = PLATFORM_ICONS[platformInfo(platform).icon] ?? Globe;
  return <Icon className={className} aria-hidden />;
}

export const accountName = (a: SocialAccountDTO) => `${platformLabel(a)} · ${a.handle.startsWith("@") ? a.handle : `@${a.handle}`}`;
export const handleText = (h: string) => (h.startsWith("@") ? h : `@${h}`);

/** Round account badge (platform icon on the account color) with an optional status dot. */
export function AccountAvatar({
  account,
  status,
  size = "md",
  className,
}: {
  account: Pick<SocialAccountDTO, "platform" | "platformName" | "color" | "handle">;
  status?: string;
  size?: "sm" | "md" | "lg";
  className?: string;
}) {
  const st = status ? POST_STATUSES.find((s) => s.id === status) : null;
  const dims = size === "sm" ? "h-6 w-6" : size === "lg" ? "h-10 w-10" : "h-8 w-8";
  const icon = size === "sm" ? "h-3 w-3" : size === "lg" ? "h-5 w-5" : "h-4 w-4";
  return (
    <span
      className={cn("relative inline-flex shrink-0 items-center justify-center rounded-full text-white ring-2 ring-card", dims, className)}
      style={{ background: account.color }}
      title={`${platformLabel(account)} ${handleText(account.handle)}${st ? ` — ${st.label}` : ""}`}
    >
      <PlatformIcon platform={account.platform} className={icon} />
      {st && (
        <span
          className="absolute -bottom-0.5 -right-0.5 h-2.5 w-2.5 rounded-full ring-2 ring-card"
          style={{ background: st.color }}
          aria-label={st.label}
        />
      )}
    </span>
  );
}

/** "IG" style short code chip on the account color. */
export function AccountCode({ account, className }: { account: Pick<SocialAccountDTO, "platform" | "platformName" | "color">; className?: string }) {
  return (
    <span
      className={cn("inline-flex shrink-0 items-center rounded px-1 text-[10px] font-bold leading-4", className)}
      style={{ background: `${account.color}22`, color: darken(account.color) }}
    >
      {platformShort(account)}
    </span>
  );
}

/** Very dark platform colors (X, Threads) stay readable; light ones are darkened a bit for text. */
function darken(hex: string): string {
  const n = parseInt(hex.slice(1), 16);
  const r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
  const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  if (lum < 0.6) return hex;
  const f = 0.6;
  return `rgb(${Math.round(r * f)},${Math.round(g * f)},${Math.round(b * f)})`;
}

export function StageDot({ stage, className }: { stage: string; className?: string }) {
  return <span className={cn("inline-block h-2 w-2 shrink-0 rounded-full", className)} style={{ background: stageInfo(stage).color }} />;
}

export function PostStatusChip({ status }: { status: string }) {
  const st = POST_STATUSES.find((s) => s.id === status) ?? POST_STATUSES[0];
  return (
    <span className="inline-flex items-center gap-1 rounded-full bg-accent px-2 py-0.5 text-xs font-medium text-foreground">
      <span className="h-2 w-2 rounded-full" style={{ background: st.color }} />
      {st.label}
    </span>
  );
}

export function pillarColor(pillars: ContentPillarDTO[], name: string | null): string {
  if (!name) return "#AFAFAF";
  const k = name.toLocaleLowerCase("id-ID");
  return pillars.find((p) => p.name.toLocaleLowerCase("id-ID") === k)?.color ?? "#AFAFAF";
}

export function PillarChip({ name, color, className }: { name: string; color: string; className?: string }) {
  return (
    <span
      className={cn("inline-flex max-w-full items-center gap-1 truncate rounded-full px-2 py-0.5 text-[11px] font-medium text-foreground", className)}
      style={{ background: `${color}24` }}
    >
      <span className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ background: color }} />
      <span className="truncate">{name}</span>
    </span>
  );
}

// ---------- Segmented tabs ----------

export function Segmented<T extends string>({
  value,
  options,
  onChange,
  label,
  className,
}: {
  value: T;
  options: { id: T; label: React.ReactNode }[];
  onChange: (v: T) => void;
  label: string;
  className?: string;
}) {
  return (
    <div role="tablist" aria-label={label} className={cn("inline-flex rounded-lg bg-accent p-0.5", className)}>
      {options.map((o) => (
        <button
          key={o.id}
          type="button"
          role="tab"
          aria-selected={value === o.id}
          onClick={() => onChange(o.id)}
          className={cn(
            "rounded-md px-3 py-1.5 text-sm font-medium transition",
            value === o.id ? "bg-card text-foreground shadow-sm" : "text-muted hover:text-foreground",
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

// ---------- Toasts ----------

export type Toast = { id: number; text: string; tone: "success" | "error" | "info"; action?: { label: string; run: () => void } };
type PushToast = (t: Omit<Toast, "id">) => void;

const ToastContext = React.createContext<PushToast>(() => {});
export const useToast = () => React.useContext(ToastContext);

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = React.useState<Toast[]>([]);
  const seq = React.useRef(0);
  const dismiss = React.useCallback((id: number) => setToasts((t) => t.filter((x) => x.id !== id)), []);
  const push = React.useCallback<PushToast>(
    (t) => {
      const id = ++seq.current;
      setToasts((prev) => [...prev.slice(-2), { ...t, id }]);
      setTimeout(() => dismiss(id), t.action ? 7000 : 4500);
    },
    [dismiss],
  );
  return (
    <ToastContext.Provider value={push}>
      {children}
      <div className="pointer-events-none fixed inset-x-0 bottom-4 z-[70] flex flex-col items-center gap-2 px-4" aria-live="polite">
        {toasts.map((t) => (
          <div
            key={t.id}
            role={t.tone === "error" ? "alert" : "status"}
            className={cn(
              "pointer-events-auto flex w-full max-w-sm items-center gap-3 rounded-xl px-4 py-3 text-sm font-medium text-white shadow-lg animate-fade-in",
              t.tone === "error" ? "bg-expense" : t.tone === "success" ? "bg-slate-900" : "bg-slate-700",
            )}
          >
            <span className="min-w-0 flex-1">{t.text}</span>
            {t.action && (
              <button
                type="button"
                className="shrink-0 font-semibold text-primary-soft underline-offset-2 hover:underline"
                onClick={() => {
                  t.action!.run();
                  dismiss(t.id);
                }}
              >
                {t.action.label}
              </button>
            )}
            <button type="button" aria-label="Tutup" onClick={() => dismiss(t.id)} className="shrink-0 opacity-70 hover:opacity-100">
              <X className="h-4 w-4" />
            </button>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

/** Run a server action; toast its error. Returns the result (or a failure). */
export async function runSafe<T extends { ok: boolean; error?: string }>(fn: () => Promise<T>): Promise<T | { ok: false; error: string }> {
  try {
    return await fn();
  } catch {
    return { ok: false, error: "Terjadi kesalahan, coba lagi" };
  }
}

export function stageMovedText(stage: string | null | undefined): string | null {
  return stage ? `Tahap konten pindah ke ${stageInfo(stage).label}` : null;
}

export function MoveButtons({ onUp, onDown, upDisabled, downDisabled, label }: { onUp: () => void; onDown: () => void; upDisabled: boolean; downDisabled: boolean; label: string }) {
  return (
    <span className="inline-flex">
      <button type="button" onClick={onUp} disabled={upDisabled} aria-label={`Naikkan ${label}`} className="rounded p-1 text-muted hover:bg-accent disabled:opacity-30">
        <ArrowUp className="h-4 w-4" />
      </button>
      <button type="button" onClick={onDown} disabled={downDisabled} aria-label={`Turunkan ${label}`} className="rounded p-1 text-muted hover:bg-accent disabled:opacity-30">
        <ArrowDown className="h-4 w-4" />
      </button>
    </span>
  );
}
