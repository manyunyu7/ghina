import type * as React from "react";
import { cn } from "@/lib/utils";

/** Building blocks for route `loading.tsx` skeletons (server components, no JS). */
export function SkeletonPage({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="animate-pulse" aria-busy="true" aria-label={label}>
      <span className="nav-progress" aria-hidden />
      {children}
    </div>
  );
}

export function SkeletonHeader({ action = "w-32" }: { action?: string | null }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <div className="h-7 w-40 rounded-lg bg-accent" />
        <div className="mt-2 h-4 w-64 max-w-full rounded bg-accent" />
      </div>
      {action && <div className={cn("h-10 rounded-lg bg-accent", action)} />}
    </div>
  );
}

export function SkeletonBox({ className, children }: { className?: string; children?: React.ReactNode }) {
  return <div className={cn("rounded-card border border-border bg-card", className)}>{children}</div>;
}

export function SkeletonPills({ widths, className }: { widths: number[]; className?: string }) {
  return (
    <div className={cn("flex flex-wrap gap-2", className)}>
      {widths.map((w, i) => (
        <div key={i} className="h-9 rounded-lg bg-accent" style={{ width: w }} />
      ))}
    </div>
  );
}
