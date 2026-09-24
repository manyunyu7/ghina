"use client";

import * as React from "react";
import { Check } from "lucide-react";
import { CURRENCIES } from "@/lib/utils";
import { SubmitButton } from "@/components/ui/submit-button";
import { Input, Select, Field } from "@/components/ui/input";
import { updateProfile, type SettingsActionResult } from "./actions";

export function PreferencesForm({
  defaultName,
  defaultCurrency,
}: {
  defaultName: string;
  defaultCurrency: string;
}) {
  const [result, setResult] = React.useState<SettingsActionResult | null>(null);

  async function onSubmit(formData: FormData) {
    setResult(null);
    try {
      setResult(await updateProfile(formData));
    } catch {
      setResult({ ok: false, error: "Something went wrong" });
    }
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
        <SubmitButton pendingText="Menyimpan…">
          {"Save changes"}
        </SubmitButton>
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
