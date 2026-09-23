import { Smartphone } from "lucide-react";
import { cn } from "@/lib/utils";

// Served by the reverse proxy from outside the deploy dir, so redeploys never delete it.
export const ANDROID_APK_URL = "/download/ghina.apk";

/** Link to the Android app (offline-first mobile companion, see mobile/). */
export function AppDownload({ compact = false, className }: { compact?: boolean; className?: string }) {
  return (
    <a
      href={ANDROID_APK_URL}
      download
      className={cn(
        "flex items-center gap-3 rounded-xl border border-border bg-surface transition hover:bg-accent",
        compact ? "p-2 text-sm" : "p-3",
        className,
      )}
    >
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary-soft text-primary">
        <Smartphone className="h-5 w-5" />
      </div>
      <div className="min-w-0">
        <p className="font-medium text-foreground">Download app Android</p>
        {!compact && <p className="text-xs text-muted">Bisa dipakai offline, sync otomatis</p>}
      </div>
    </a>
  );
}
