"use client";

import * as React from "react";
import { Check } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Input, Field, Label } from "@/components/ui/input";
import { CategoryIcon } from "@/components/icon";
import { cn } from "@/lib/utils";
import { COLOR_PALETTE, CATEGORY_ICONS } from "@/lib/constants";
import { createCategory, updateCategory, type CategoryActionResult } from "./actions";

export type CategoryFormData = {
  id: string;
  name: string;
  type: string;
  color: string;
  icon: string;
};

export function CategoryForm({
  open,
  onClose,
  category,
  defaultType = "expense",
}: {
  open: boolean;
  onClose: () => void;
  /** When provided, the form edits this category; otherwise it creates a new one. */
  category?: CategoryFormData;
  defaultType?: "expense" | "income";
}) {
  const isEdit = Boolean(category);

  const [type, setType] = React.useState(category?.type ?? defaultType);
  const [color, setColor] = React.useState(category?.color ?? COLOR_PALETTE[0]);
  const [icon, setIcon] = React.useState(category?.icon ?? CATEGORY_ICONS[0]);
  const [error, setError] = React.useState<string | null>(null);
  const [pending, setPending] = React.useState(false);

  // Reset local state during render whenever the modal is (re)opened or the target
  // category changes — the React-recommended alternative to syncing via an effect.
  const instanceKey = `${open ? "open" : "closed"}:${category?.id ?? "new"}:${defaultType}`;
  const [prevKey, setPrevKey] = React.useState(instanceKey);
  if (prevKey !== instanceKey) {
    setPrevKey(instanceKey);
    setType(category?.type ?? defaultType);
    setColor(category?.color ?? COLOR_PALETTE[0]);
    setIcon(category?.icon ?? CATEGORY_ICONS[0]);
    setError(null);
    setPending(false);
  }

  async function handleAction(formData: FormData) {
    setPending(true);
    setError(null);
    const action = isEdit ? updateCategory : createCategory;
    let result: CategoryActionResult;
    try {
      result = await action(formData);
    } catch {
      result = { ok: false, error: "Something went wrong" };
    }
    setPending(false);
    if (result.ok) {
      onClose();
    } else {
      setError(result.error ?? "Something went wrong");
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? "Edit category" : "Add category"}
      description={
        isEdit ? "Update your category details." : "Create a category to organize your transactions."
      }
    >
      <form action={handleAction} className="space-y-4">
        {isEdit && <input type="hidden" name="id" value={category!.id} />}
        <input type="hidden" name="type" value={type} />
        <input type="hidden" name="color" value={color} />
        <input type="hidden" name="icon" value={icon} />

        {/* Live preview */}
        <div className="flex items-center gap-3 rounded-lg border border-border bg-surface p-3">
          <div
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full"
            style={{ background: `${color}1a`, color }}
          >
            <CategoryIcon name={icon} className="h-5 w-5" />
          </div>
          <span className="font-medium text-foreground">Preview</span>
        </div>

        <Field label="Name">
          <Input
            name="name"
            placeholder="e.g. Groceries"
            defaultValue={category?.name ?? ""}
            autoFocus
            required
            maxLength={60}
          />
        </Field>

        <div>
          <Label>Type</Label>
          <div className="grid grid-cols-2 gap-2">
            {(["expense", "income"] as const).map((t) => {
              const active = type === t;
              return (
                <button
                  type="button"
                  key={t}
                  onClick={() => setType(t)}
                  aria-pressed={active}
                  className={cn(
                    "rounded-lg border px-3 py-2.5 text-sm font-medium capitalize transition",
                    active && t === "expense" && "border-expense bg-expense-soft text-expense",
                    active && t === "income" && "border-income bg-income-soft text-income",
                    !active && "border-border bg-surface text-muted hover:bg-accent hover:text-foreground",
                  )}
                >
                  {t}
                </button>
              );
            })}
          </div>
        </div>

        <div>
          <Label>Color</Label>
          <div className="flex flex-wrap gap-2">
            {COLOR_PALETTE.map((c) => {
              const active = color === c;
              return (
                <button
                  type="button"
                  key={c}
                  onClick={() => setColor(c)}
                  aria-label={`Select color ${c}`}
                  aria-pressed={active}
                  style={{ background: c }}
                  className={cn(
                    "flex h-8 w-8 items-center justify-center rounded-full transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40",
                    active ? "ring-2 ring-offset-2 ring-offset-card ring-foreground/60" : "hover:scale-110",
                  )}
                >
                  {active && <Check className="h-4 w-4 text-white" />}
                </button>
              );
            })}
          </div>
        </div>

        <div>
          <Label>Icon</Label>
          <div className="grid max-h-44 grid-cols-7 gap-2 overflow-y-auto rounded-lg border border-border bg-surface p-2">
            {CATEGORY_ICONS.map((name) => {
              const active = icon === name;
              return (
                <button
                  type="button"
                  key={name}
                  onClick={() => setIcon(name)}
                  aria-label={`Select icon ${name}`}
                  aria-pressed={active}
                  className={cn(
                    "flex aspect-square items-center justify-center rounded-lg border transition",
                    active
                      ? "border-primary bg-primary-soft text-primary"
                      : "border-transparent text-muted hover:bg-accent hover:text-foreground",
                  )}
                >
                  <CategoryIcon name={name} className="h-5 w-5" />
                </button>
              );
            })}
          </div>
        </div>

        {error && <p className="text-sm text-expense">{error}</p>}

        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="ghost" onClick={onClose} disabled={pending}>
            Cancel
          </Button>
          <Button type="submit" disabled={pending}>
            {pending ? "Saving…" : isEdit ? "Save changes" : "Create category"}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
