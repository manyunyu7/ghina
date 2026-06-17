"use client";

import * as React from "react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Input, Field } from "@/components/ui/input";
import { createHealthEntry, updateHealthEntry } from "./actions";

export type HealthFormData = {
  id: string;
  date: Date | string;
  weight: number | null;
  systolic: number | null;
  diastolic: number | null;
  pulse: number | null;
  note: string | null;
};

function toDateInput(value: Date | string | undefined): string {
  const d = value ? new Date(value) : new Date();
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60_000).toISOString().slice(0, 10);
}

export function HealthForm({
  open,
  onClose,
  entry,
}: {
  open: boolean;
  onClose: () => void;
  entry?: HealthFormData;
}) {
  const isEdit = Boolean(entry);
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? "Edit measurement" : "Add measurement"}
      description="Log your weight, blood pressure, or both."
    >
      {open && <FormBody entry={entry} onClose={onClose} />}
    </Modal>
  );
}

function FormBody({ entry, onClose }: { entry?: HealthFormData; onClose: () => void }) {
  const isEdit = Boolean(entry);
  const [submitting, setSubmitting] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  async function handleAction(formData: FormData) {
    setSubmitting(true);
    setError(null);
    const res = isEdit ? await updateHealthEntry(formData) : await createHealthEntry(formData);
    if (res.ok) onClose();
    else {
      setError(res.error ?? "Something went wrong");
      setSubmitting(false);
    }
  }

  const val = (n: number | null | undefined) => (n == null ? "" : String(n));

  return (
    <form action={handleAction} className="space-y-4">
      {isEdit && entry && <input type="hidden" name="id" value={entry.id} />}

      <Field label="Date">
        <Input name="date" type="date" required defaultValue={toDateInput(entry?.date)} />
      </Field>

      <Field label="Weight (kg)">
        <Input
          name="weight"
          type="number"
          inputMode="decimal"
          step="0.1"
          min="1"
          placeholder="e.g. 68.5"
          defaultValue={val(entry?.weight)}
        />
      </Field>

      <div>
        <p className="mb-1.5 text-sm font-medium text-foreground">Blood pressure (mmHg)</p>
        <div className="grid grid-cols-2 gap-3">
          <Input name="systolic" type="number" inputMode="numeric" min="50" placeholder="Systolic (120)" defaultValue={val(entry?.systolic)} />
          <Input name="diastolic" type="number" inputMode="numeric" min="30" placeholder="Diastolic (80)" defaultValue={val(entry?.diastolic)} />
        </div>
      </div>

      <Field label="Pulse (bpm)">
        <Input name="pulse" type="number" inputMode="numeric" min="20" placeholder="e.g. 72" defaultValue={val(entry?.pulse)} />
      </Field>

      <Field label="Note">
        <Input name="note" placeholder="Optional (e.g. after workout)" defaultValue={entry?.note ?? ""} />
      </Field>

      {error && <p className="text-sm text-expense">{error}</p>}

      <div className="flex justify-end gap-2 pt-1">
        <Button type="button" variant="outline" onClick={onClose} disabled={submitting}>
          Cancel
        </Button>
        <Button type="submit" disabled={submitting}>
          {submitting ? "Saving…" : isEdit ? "Save changes" : "Add measurement"}
        </Button>
      </div>
    </form>
  );
}
