"use client";

import * as React from "react";
import { Check } from "lucide-react";
import { CURRENCIES } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Input, Select, Field } from "@/components/ui/input";
import { updateProfile, type SettingsActionResult } from "./actions";

export function PreferencesForm({
  defaultName,
  defaultCurrency,
}: {
  defaultName: string;
  defaultCurrency: string;
}) {
  const [pending, setPending] = React.useState(false);
  const [result, setResult] = React.useState<SettingsActionResult | null>(null);

  async function onSubmit(formData: FormData) {
    setPending(true);
    setResult(null);
    const res = await updateProfile(formData);
    setResult(res);
    setPending(false);
  }

  return (
    <form action={onSubmit} className="space-y-4">
      <Field label="Display name">
        <Input
          name="name"
          defaultValue={defaultName}
          maxLength={60}
          placeholder="Your name"
        />
      </Field>

      <Field label="Default currency">
        <Select name="currency" defaultValue={defaultCurrency}>
          {CURRENCIES.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </Select>
        <p className="mt-1.5 text-xs text-muted-soft">
          Used as the default for new wallets and totals.
        </p>
      </Field>

      <div className="flex items-center gap-3">
        <Button type="submit" disabled={pending}>
          {pending ? "Saving…" : "Save changes"}
        </Button>
        {result?.ok && (
          <span className="inline-flex items-center gap-1 text-sm text-income">
            <Check className="h-4 w-4" /> Saved
          </span>
        )}
        {result && !result.ok && (
          <span className="text-sm text-expense">{result.error}</span>
        )}
      </div>
    </form>
  );
}
