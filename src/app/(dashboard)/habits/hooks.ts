"use client";

import { useCallback, useEffect, useSyncExternalStore } from "react";
import { useRouter } from "next/navigation";
import { browserTimeZone, browserToday } from "./format";

/**
 * The server renders with Asia/Jakarta's today; when the browser's local day (or, with
 * `withTimeZone`, its zone) differs, reload the page with `?today=` / `?tz=` so every
 * check-in lands on the user's own day. Re-checks when the tab becomes visible again
 * (e.g. the page stayed open past midnight).
 */
export function useBrowserToday(today: string, timeZone?: string, withTimeZone = false) {
  const router = useRouter();
  useEffect(() => {
    function sync() {
      const t = browserToday();
      const tz = browserTimeZone();
      const wantTz = withTimeZone && tz !== (timeZone ?? "Asia/Jakarta");
      if (t === today && !wantTz) return;
      const url = new URL(window.location.href);
      // Already asked (the server clamps an implausible day): don't loop.
      if (url.searchParams.get("today") === t && (!wantTz || url.searchParams.get("tz") === tz)) return;
      url.searchParams.set("today", t);
      if (wantTz) url.searchParams.set("tz", tz);
      router.replace(`${url.pathname}?${url.searchParams.toString()}`, { scroll: false });
    }
    sync();
    const onVisible = () => document.visibilityState === "visible" && sync();
    document.addEventListener("visibilitychange", onVisible);
    return () => document.removeEventListener("visibilitychange", onVisible);
  }, [today, timeZone, withTimeZone, router]);
}

// ---------- "Blur names" (shoulder-surfing) toggle, per browser ----------

const BLUR_KEY = "ghina.habits.blurNames";
const blurListeners = new Set<() => void>();

function readBlur(): boolean {
  try {
    return localStorage.getItem(BLUR_KEY) === "1";
  } catch {
    return false;
  }
}

function subscribeBlur(cb: () => void) {
  blurListeners.add(cb);
  const onStorage = (e: StorageEvent) => e.key === BLUR_KEY && cb();
  window.addEventListener("storage", onStorage);
  return () => {
    blurListeners.delete(cb);
    window.removeEventListener("storage", onStorage);
  };
}

/** Whether habit names are blurred on /habits (localStorage; false during SSR). */
export function useBlurNames(): [boolean, (v: boolean) => void] {
  const blur = useSyncExternalStore(subscribeBlur, readBlur, () => false);
  const set = useCallback((v: boolean) => {
    try {
      localStorage.setItem(BLUR_KEY, v ? "1" : "0");
    } catch {}
    blurListeners.forEach((l) => l());
  }, []);
  return [blur, set];
}
