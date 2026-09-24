"use client";

import { useFormStatus } from "react-dom";
import { LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";

function SignOutSubmit() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" variant="outline" loading={pending}>
      {!pending && <LogOut className="h-4 w-4" />}
      {pending ? "Keluar…" : "Sign out"}
    </Button>
  );
}

export function SignOutButton({ action }: { action: () => Promise<void> }) {
  return (
    <form action={action}>
      <SignOutSubmit />
    </form>
  );
}
