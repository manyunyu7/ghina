"use client";

import Link from "next/link";
import { useActionState, type ReactNode } from "react";
import { useFormStatus } from "react-dom";
import { AlertCircle, Loader2 } from "lucide-react";
import { Input, Field } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { authenticate, registerUser, type AuthState } from "./actions";

export function AuthForm({ mode }: { mode: "login" | "register" }) {
  const action = mode === "login" ? authenticate : registerUser;
  const [state, formAction, pending] = useActionState<AuthState, FormData>(action, undefined);

  return (
    <form action={formAction} className="space-y-4">
      {state?.error && (
        <div className="flex items-start gap-2 rounded-lg bg-expense-soft px-3 py-2.5 text-sm text-expense">
          <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>{state.error}</span>
        </div>
      )}

      {mode === "register" && (
        <Field label="Name">
          <Input name="name" type="text" placeholder="Your name" required autoComplete="name" />
        </Field>
      )}

      <Field label="Email">
        <Input
          name="email"
          type="email"
          placeholder="you@example.com"
          required
          autoComplete="email"
        />
      </Field>

      <Field label="Password">
        <Input
          name="password"
          type="password"
          placeholder={mode === "register" ? "At least 6 characters" : "Your password"}
          required
          minLength={mode === "register" ? 6 : undefined}
          autoComplete={mode === "register" ? "new-password" : "current-password"}
        />
      </Field>

      <Button type="submit" size="lg" className="w-full" loading={pending}>
        {pending
          ? mode === "login" ? "Masuk…" : "Membuat akun…"
          : mode === "login" ? "Sign in" : "Create account"}
      </Button>

      <p className="text-center text-sm text-muted">
        {mode === "login" ? (
          <>
            Don&apos;t have an account?{" "}
            <Link href="/register" className="font-semibold text-primary hover:underline">
              Sign up
            </Link>
          </>
        ) : (
          <>
            Already have an account?{" "}
            <Link href="/login" className="font-semibold text-primary hover:underline">
              Sign in
            </Link>
          </>
        )}
      </p>
    </form>
  );
}

/** "Continue with Google" submit: spinner + disabled while the redirect to Google is pending. */
export function GoogleSubmitButton({ children }: { children: ReactNode }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      aria-busy={pending || undefined}
      className="flex w-full items-center justify-center gap-3 rounded-lg border border-border bg-surface px-4 py-3 text-sm font-semibold text-foreground shadow-sm transition hover:bg-accent disabled:pointer-events-none disabled:opacity-60"
    >
      {pending ? <Loader2 aria-hidden className="h-5 w-5 animate-spin" /> : children}
      {pending ? "Menghubungkan ke Google…" : "Continue with Google"}
    </button>
  );
}
