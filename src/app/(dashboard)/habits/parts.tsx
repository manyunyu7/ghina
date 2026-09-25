"use client";

import * as React from "react";
import { cn } from "@/lib/utils";

/** Emoji (or first letter) on a soft disc of the habit's color. */
export function HabitAvatar({
  emoji,
  name,
  color,
  size = "md",
  masked = false,
}: {
  emoji: string | null;
  name: string;
  color: string;
  size?: "sm" | "md" | "lg";
  masked?: boolean;
}) {
  const dims = size === "sm" ? "h-8 w-8 text-base" : size === "lg" ? "h-14 w-14 text-3xl" : "h-10 w-10 text-xl";
  return (
    <span
      aria-hidden
      className={cn("flex shrink-0 items-center justify-center rounded-full font-semibold", dims)}
      style={{ background: `${color}22`, color }}
    >
      {masked ? "🔒" : emoji || name.trim().charAt(0).toUpperCase() || "•"}
    </span>
  );
}

/** Circular progress (0–1) with content in the middle. */
export function ProgressRing({
  value,
  color,
  size = 56,
  stroke = 6,
  children,
  className,
  label,
}: {
  value: number;
  color: string;
  size?: number;
  stroke?: number;
  children?: React.ReactNode;
  className?: string;
  label?: string;
}) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const v = Math.max(0, Math.min(1, Number.isFinite(value) ? value : 0));
  return (
    <div
      className={cn("relative shrink-0", className)}
      style={{ width: size, height: size }}
      role="progressbar"
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={Math.round(v * 100)}
      aria-label={label}
    >
      <svg width={size} height={size} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--color-accent)" strokeWidth={stroke} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={color}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={c * (1 - v)}
          style={{ transition: "stroke-dashoffset 0.4s ease" }}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center text-center leading-tight">{children}</div>
    </div>
  );
}

/** Inline error line under a control group. */
export function ErrorLine({ error, className }: { error: string | null; className?: string }) {
  if (!error) return null;
  return (
    <p role="alert" className={cn("text-xs font-medium text-expense", className)}>
      {error}
    </p>
  );
}

/** Tag-like toggle chip. */
export function Chip({
  active,
  onClick,
  children,
  className,
  color,
  disabled,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
  className?: string;
  color?: string;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={active}
      className={cn(
        "inline-flex h-8 items-center gap-1 rounded-full border px-3 text-sm font-medium transition disabled:opacity-50",
        active ? "border-transparent text-white" : "border-border bg-surface text-foreground hover:bg-accent",
        className,
      )}
      style={active ? { background: color ?? "var(--color-primary)" } : undefined}
    >
      {children}
    </button>
  );
}
