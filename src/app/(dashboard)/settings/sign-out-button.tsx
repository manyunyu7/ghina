"use client";

import { LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";

export function SignOutButton({ action }: { action: () => Promise<void> }) {
  return (
    <form action={action}>
      <Button type="submit" variant="outline">
        <LogOut className="h-4 w-4" />
        Sign out
      </Button>
    </form>
  );
}
