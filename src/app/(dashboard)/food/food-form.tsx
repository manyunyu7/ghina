"use client";

import * as React from "react";
import { ImagePlus, X } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Input, Select, Field } from "@/components/ui/input";
import { MEALS } from "./constants";
import { createFood, updateFood } from "./actions";

export type FoodFormData = {
  id: string;
  date: Date | string;
  name: string;
  meal: string | null;
  calories: number | null;
  photoUrl: string | null;
  note: string | null;
};

function toDateInput(value: Date | string | undefined): string {
  const d = value ? new Date(value) : new Date();
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60_000).toISOString().slice(0, 10);
}

export function FoodForm({
  open,
  onClose,
  entry,
}: {
  open: boolean;
  onClose: () => void;
  entry?: FoodFormData;
}) {
  const isEdit = Boolean(entry);
  return (
    <Modal open={open} onClose={onClose} title={isEdit ? "Edit meal" : "Log a meal"} description="Snap a photo, add calories, jot a note.">
      {open && <FormBody entry={entry} onClose={onClose} />}
    </Modal>
  );
}

function FormBody({ entry, onClose }: { entry?: FoodFormData; onClose: () => void }) {
  const isEdit = Boolean(entry);
  const [submitting, setSubmitting] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const [preview, setPreview] = React.useState<string | null>(entry?.photoUrl ?? null);
  const [removed, setRemoved] = React.useState(false);
  const fileRef = React.useRef<HTMLInputElement>(null);

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (f) {
      setPreview(URL.createObjectURL(f));
      setRemoved(false);
    }
  }
  function clearPhoto() {
    setPreview(null);
    setRemoved(true);
    if (fileRef.current) fileRef.current.value = "";
  }

  async function handleAction(formData: FormData) {
    setSubmitting(true);
    setError(null);
    const res = isEdit ? await updateFood(formData) : await createFood(formData);
    if (res.ok) onClose();
    else {
      setError(res.error ?? "Something went wrong");
      setSubmitting(false);
    }
  }

  return (
    <form action={handleAction} className="space-y-4">
      {isEdit && entry && <input type="hidden" name="id" value={entry.id} />}
      <input type="hidden" name="removePhoto" value={removed ? "true" : "false"} />

      {/* Photo */}
      <div>
        {preview ? (
          <div className="relative overflow-hidden rounded-xl border border-border">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={preview} alt="Meal preview" className="h-44 w-full object-cover" />
            <button
              type="button"
              onClick={clearPhoto}
              className="absolute right-2 top-2 rounded-full bg-slate-900/60 p-1.5 text-white transition hover:bg-slate-900/80"
              aria-label="Remove photo"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        ) : (
          <button
            type="button"
            onClick={() => fileRef.current?.click()}
            className="flex h-32 w-full flex-col items-center justify-center gap-2 rounded-xl border border-dashed border-border bg-background text-muted transition hover:bg-accent"
          >
            <ImagePlus className="h-6 w-6" />
            <span className="text-sm font-medium">Add photo</span>
          </button>
        )}
        <input ref={fileRef} type="file" name="photo" accept="image/*" capture="environment" onChange={onFileChange} className="hidden" />
        {preview && !preview.startsWith("/uploads/") && (
          <button type="button" onClick={() => fileRef.current?.click()} className="mt-2 text-xs font-medium text-primary hover:underline">
            Choose a different photo
          </button>
        )}
      </div>

      <Field label="What did you eat?">
        <Input name="name" required autoFocus placeholder="e.g. Nasi goreng + telur" defaultValue={entry?.name ?? ""} />
      </Field>

      <div className="grid grid-cols-2 gap-3">
        <Field label="Meal">
          <Select name="meal" defaultValue={entry?.meal ?? ""}>
            <option value="">—</option>
            {MEALS.map((m) => (
              <option key={m.value} value={m.value}>
                {m.emoji} {m.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Calories (kcal)">
          <Input name="calories" type="number" inputMode="numeric" min="0" placeholder="optional" defaultValue={entry?.calories == null ? "" : String(entry.calories)} />
        </Field>
      </div>

      <Field label="Date">
        <Input name="date" type="date" required defaultValue={toDateInput(entry?.date)} />
      </Field>

      <Field label="Note">
        <Input name="note" placeholder="Optional (e.g. too salty, felt full)" defaultValue={entry?.note ?? ""} />
      </Field>

      {error && <p className="text-sm text-expense">{error}</p>}

      <div className="flex justify-end gap-2 pt-1">
        <Button type="button" variant="outline" onClick={onClose} disabled={submitting}>
          Cancel
        </Button>
        <Button type="submit" disabled={submitting}>
          {submitting ? "Saving…" : isEdit ? "Save changes" : "Log meal"}
        </Button>
      </div>
    </form>
  );
}
