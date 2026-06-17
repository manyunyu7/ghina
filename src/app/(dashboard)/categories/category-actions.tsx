"use client";

import * as React from "react";
import { Pencil, Trash2, AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { CategoryForm, type CategoryFormData } from "./category-form";
import { deleteCategory, type CategoryActionResult } from "./actions";

export function CategoryActions({
  category,
  transactionCount,
}: {
  category: CategoryFormData;
  transactionCount: number;
}) {
  const [editing, setEditing] = React.useState(false);
  const [confirming, setConfirming] = React.useState(false);
  const [pending, setPending] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  async function handleDelete() {
    setPending(true);
    setError(null);
    const formData = new FormData();
    formData.set("id", category.id);
    let result: CategoryActionResult;
    try {
      result = await deleteCategory(formData);
    } catch {
      result = { ok: false, error: "Something went wrong" };
    }
    setPending(false);
    if (result.ok) {
      setConfirming(false);
    } else {
      setError(result.error ?? "Failed to delete category");
    }
  }

  return (
    <>
      <div className="flex items-center gap-1">
        <Button
          variant="ghost"
          size="icon"
          aria-label={`Edit ${category.name}`}
          onClick={() => setEditing(true)}
        >
          <Pencil className="h-4 w-4" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          aria-label={`Delete ${category.name}`}
          onClick={() => setConfirming(true)}
        >
          <Trash2 className="h-4 w-4" />
        </Button>
      </div>

      <CategoryForm open={editing} onClose={() => setEditing(false)} category={category} />

      <Modal open={confirming} onClose={() => setConfirming(false)} title="Delete category">
        <div className="space-y-4">
          <div className="flex gap-3 rounded-lg bg-expense-soft p-3 text-expense">
            <AlertTriangle className="h-5 w-5 shrink-0" />
            <div className="text-sm">
              <p className="font-medium">This cannot be undone.</p>
              <p className="mt-0.5 text-expense/90">
                Deleting <span className="font-semibold">{category.name}</span>
                {transactionCount > 0 ? (
                  <>
                    {" "}
                    will leave its{" "}
                    <span className="font-semibold">
                      {transactionCount} transaction{transactionCount === 1 ? "" : "s"}
                    </span>{" "}
                    uncategorized.
                  </>
                ) : (
                  <>.</>
                )}
              </p>
            </div>
          </div>

          {error && <p className="text-sm text-expense">{error}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={() => setConfirming(false)} disabled={pending}>
              Cancel
            </Button>
            <Button variant="danger" onClick={handleDelete} disabled={pending}>
              {pending ? "Deleting…" : "Delete category"}
            </Button>
          </div>
        </div>
      </Modal>
    </>
  );
}
