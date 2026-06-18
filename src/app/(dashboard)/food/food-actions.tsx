"use client";

import * as React from "react";
import { Pencil, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { FoodForm, type FoodFormData } from "./food-form";
import { deleteFood } from "./actions";

export function FoodActions({ entry }: { entry: FoodFormData }) {
  const [editing, setEditing] = React.useState(false);
  const [confirming, setConfirming] = React.useState(false);
  const [pending, startTransition] = React.useTransition();

  function runDelete() {
    const fd = new FormData();
    fd.set("id", entry.id);
    startTransition(async () => {
      await deleteFood(fd);
      setConfirming(false);
    });
  }

  return (
    <div className="flex items-center gap-0.5">
      <Button variant="ghost" size="icon" onClick={() => setEditing(true)} aria-label="Edit">
        <Pencil className="h-4 w-4" />
      </Button>
      <Button variant="ghost" size="icon" onClick={() => setConfirming(true)} aria-label="Delete">
        <Trash2 className="h-4 w-4 text-expense" />
      </Button>

      <FoodForm open={editing} onClose={() => setEditing(false)} entry={entry} />

      <Modal open={confirming} onClose={() => setConfirming(false)} title="Delete meal?" description="This meal and its photo will be permanently removed.">
        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={() => setConfirming(false)} disabled={pending}>
            Cancel
          </Button>
          <Button variant="danger" onClick={runDelete} disabled={pending}>
            {pending ? "Deleting…" : "Delete"}
          </Button>
        </div>
      </Modal>
    </div>
  );
}
