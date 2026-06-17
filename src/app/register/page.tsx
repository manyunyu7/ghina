import { redirect } from "next/navigation";
import { auth } from "@/auth";
import { AuthShell } from "@/components/auth-shell";
import { AuthForm } from "../login/auth-form";

export default async function RegisterPage() {
  const session = await auth();
  if (session?.user) redirect("/dashboard");

  return (
    <AuthShell>
      <h2 className="text-2xl font-bold text-foreground">Create your account</h2>
      <p className="mt-2 text-sm text-muted">Start tracking your money in seconds.</p>

      <div className="mt-8">
        <AuthForm mode="register" />
      </div>
    </AuthShell>
  );
}
