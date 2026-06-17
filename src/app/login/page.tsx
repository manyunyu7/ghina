import { redirect } from "next/navigation";
import { auth, signIn, googleEnabled } from "@/auth";
import { AuthShell, GoogleIcon } from "@/components/auth-shell";
import { AuthForm } from "./auth-form";

export default async function LoginPage() {
  const session = await auth();
  if (session?.user) redirect("/dashboard");

  async function signInWithGoogle() {
    "use server";
    await signIn("google", { redirectTo: "/dashboard" });
  }

  return (
    <AuthShell>
      <h2 className="text-2xl font-bold text-foreground">Welcome back</h2>
      <p className="mt-2 text-sm text-muted">Sign in to continue to your dashboard.</p>

      <div className="mt-8">
        <AuthForm mode="login" />
      </div>

      {googleEnabled && (
        <>
          <div className="my-6 flex items-center gap-3 text-xs text-muted-soft">
            <div className="h-px flex-1 bg-border" />
            OR
            <div className="h-px flex-1 bg-border" />
          </div>
          <form action={signInWithGoogle}>
            <button
              type="submit"
              className="flex w-full items-center justify-center gap-3 rounded-lg border border-border bg-surface px-4 py-3 text-sm font-semibold text-foreground shadow-sm transition hover:bg-accent"
            >
              <GoogleIcon />
              Continue with Google
            </button>
          </form>
        </>
      )}
    </AuthShell>
  );
}
