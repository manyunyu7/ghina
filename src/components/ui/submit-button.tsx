"use client";

import type { ReactNode } from "react";
import { useFormStatus } from "react-dom";
import { Button, type ButtonProps } from "@/components/ui/button";

/**
 * Submit button for `<form action={...}>`: reads the parent form's pending state, so it
 * disables itself (no double submits) and shows the shared spinner while the action runs.
 * Must be rendered inside the <form>.
 */
export function SubmitButton({
  pendingText,
  children,
  loading,
  ...props
}: ButtonProps & { /** Label while pending, e.g. "Menyimpan…". Defaults to the normal label. */ pendingText?: ReactNode }) {
  const { pending } = useFormStatus();
  const busy = pending || !!loading;
  return (
    <Button type="submit" loading={busy} {...props}>
      {busy && pendingText ? pendingText : children}
    </Button>
  );
}

/** Secondary button of a `<form action>` (e.g. Cancel): disabled while the form submits. */
export function FormCancelButton({ disabled, type = "button", ...props }: ButtonProps) {
  const { pending } = useFormStatus();
  return <Button type={type} disabled={pending || disabled} {...props} />;
}
