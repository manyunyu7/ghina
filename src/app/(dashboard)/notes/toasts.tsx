"use client";

import * as React from "react";
import Link from "next/link";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";
import type { ToastInput } from "./shared";

type Toast = ToastInput & { id: number };

export function useToasts() {
  const [toasts, setToasts] = React.useState<Toast[]>([]);
  const seq = React.useRef(0);
  const dismiss = React.useCallback((id: number) => setToasts((t) => t.filter((x) => x.id !== id)), []);
  const push = React.useCallback(
    (t: ToastInput) => {
      const id = ++seq.current;
      setToasts((prev) => [...prev.slice(-2), { ...t, id }]);
      setTimeout(() => dismiss(id), t.action || t.href ? 7000 : 4500);
    },
    [dismiss],
  );
  return { toasts, push, dismiss };
}

export function Toasts({ toasts, dismiss }: { toasts: Toast[]; dismiss: (id: number) => void }) {
  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-4 z-[80] flex flex-col items-center gap-2 px-4" aria-live="polite">
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
          {t.href && (
            <Link
              href={t.href.url}
              onClick={() => dismiss(t.id)}
              className="shrink-0 font-semibold text-primary-soft underline-offset-2 hover:underline"
            >
              {t.href.label}
            </Link>
          )}
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
  );
}
