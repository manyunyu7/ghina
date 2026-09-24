"use client";

import * as React from "react";
import { useRouter } from "next/navigation";

/**
 * `router.push` / `router.replace` wrapped in a transition, so callers get a `pending`
 * flag for the whole navigation (until the new RSC payload has rendered). Pair it with
 * <PendingBar pending={pending} /> and/or `aria-busy` on the control that triggered it.
 */
export function useNavTransition() {
  const router = useRouter();
  const [pending, startTransition] = React.useTransition();
  const push = React.useCallback(
    (href: string, opts?: { scroll?: boolean }) => startTransition(() => router.push(href, opts)),
    [router],
  );
  const replace = React.useCallback(
    (href: string, opts?: { scroll?: boolean }) => startTransition(() => router.replace(href, opts)),
    [router],
  );
  return { pending, push, replace };
}
