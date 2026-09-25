"use client";

import * as React from "react";
import { Modal } from "@/components/ui/modal";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { SavingHint } from "@/components/ui/saving-hint";
import { ENCOURAGEMENTS, URGE_BREATHING_SECONDS, URGE_QUICK_ACTIONS } from "@/lib/habits";
import type { ActionResult } from "@/lib/action-utils";
import { urgeToRelapse } from "./actions";
import { ErrorLine } from "./parts";
import { RelapseDone, RelapseForm, relapseInput, type RelapseFields } from "./relapse-dialog";

export type UrgeLogState = { pending: boolean; error: string | null; urgesToday: number | null };

const PHASES = ["Tarik napas…", "Tahan…", "Hembuskan pelan…", "Tahan…"];
const PHASE_SECONDS = 4;

/**
 * Tombol darurat: the urge is logged by the caller as the dialog opens; here the user
 * breathes for 60 s (box breathing, 4-4-4-4), reads their "why", then either keeps the
 * urge as resisted or converts it to a relapse (`urgeToRelapse`).
 */
export function UrgeDialog({
  open,
  onClose,
  habitId,
  habitName,
  why,
  color,
  today,
  current,
  log,
  onRetry,
}: {
  open: boolean;
  onClose: () => void;
  habitId: string;
  habitName: string;
  why: string | null;
  color: string;
  today: string;
  current: number;
  log: UrgeLogState;
  onRetry: () => void;
}) {
  return (
    <Modal open={open} onClose={onClose} className="sm:max-w-lg">
      {open && (
        <UrgeFlow
          habitId={habitId}
          habitName={habitName}
          why={why}
          color={color}
          today={today}
          current={current}
          log={log}
          onRetry={onRetry}
          onClose={onClose}
        />
      )}
    </Modal>
  );
}

type Step = "breathe" | "choose" | "relapse" | "relapsed" | "resisted";

function UrgeFlow({
  habitId,
  habitName,
  why,
  color,
  today,
  current,
  log,
  onRetry,
  onClose,
}: {
  habitId: string;
  habitName: string;
  why: string | null;
  color: string;
  today: string;
  current: number;
  log: UrgeLogState;
  onRetry: () => void;
  onClose: () => void;
}) {
  const [line] = React.useState(() => ENCOURAGEMENTS[Math.floor(Math.random() * ENCOURAGEMENTS.length)]);
  const [elapsed, setElapsed] = React.useState(0);
  const [step, setStep] = React.useState<Step>("breathe");
  const [pending, startTransition] = React.useTransition();
  const [error, setError] = React.useState<string | null>(null);
  const [previous, setPrevious] = React.useState(0);

  const breathing = step === "breathe" && elapsed < URGE_BREATHING_SECONDS;
  React.useEffect(() => {
    if (!breathing) return;
    const t = setInterval(() => setElapsed((e) => Math.min(e + 1, URGE_BREATHING_SECONDS)), 1000);
    return () => clearInterval(t);
  }, [breathing]);

  const left = URGE_BREATHING_SECONDS - elapsed;
  const phase = PHASES[Math.floor((elapsed % (PHASE_SECONDS * 4)) / PHASE_SECONDS)];

  function relapse(f: RelapseFields) {
    setError(null);
    startTransition(async () => {
      let res: ActionResult<{ previousStreak: number }>;
      try {
        res = await urgeToRelapse(habitId, relapseInput({ ...f, date: today }));
      } catch {
        res = { ok: false, error: "Gagal menyimpan, periksa koneksi" };
      }
      if (res.ok) {
        setPrevious(res.previousStreak);
        setStep("relapsed");
      } else setError(res.error);
    });
  }

  if (step === "relapsed") return <RelapseDone previousStreak={previous} onClose={onClose} />;

  if (step === "relapse")
    return (
      <div>
        <h2 className="text-lg font-semibold text-foreground">Aku kalah kali ini</h2>
        <p className="mb-4 mt-1 text-sm text-muted">{habitName}</p>
        <RelapseForm
          today={today}
          color={color}
          previous={current}
          pending={pending}
          error={error}
          showDate={false}
          submitLabel="Catat"
          onSubmit={relapse}
          onCancel={() => setStep("choose")}
        />
      </div>
    );

  if (step === "resisted")
    return (
      <div className="space-y-4 text-center">
        <div className="text-5xl" aria-hidden>
          💪
        </div>
        <p className="text-base font-semibold text-foreground">Kamu berhasil melewatinya!</p>
        <p className="text-sm text-muted">
          {log.urgesToday != null && log.urgesToday > 1
            ? `${log.urgesToday}× kamu tahan hari ini. Otakmu lagi belajar jalan baru.`
            : "Setiap kali kamu tahan, otakmu belajar jalan baru."}
        </p>
        <Button className="w-full" onClick={onClose}>
          Selesai
        </Button>
      </div>
    );

  return (
    <div className="space-y-5 text-center">
      <style>{`
        @keyframes habit-box-breath {
          0% { transform: scale(0.55); }
          25% { transform: scale(1); }
          50% { transform: scale(1); }
          75% { transform: scale(0.55); }
          100% { transform: scale(0.55); }
        }
      `}</style>
      <div>
        <p className="text-xs font-semibold uppercase tracking-wide text-muted">Tombol darurat · {habitName}</p>
        <p className="mt-1 text-lg font-semibold text-foreground">Tarik napas bareng, ya.</p>
        <div className="mt-1 flex h-5 items-center justify-center">
          {log.error ? (
            <span className="text-xs text-expense">
              {log.error}{" "}
              <button type="button" className="font-semibold underline" onClick={onRetry}>
                Coba lagi
              </button>
            </span>
          ) : (
            <SavingHint pending={log.pending} label="Mencatat…" />
          )}
        </div>
      </div>

      {/* Box breathing: 4 s in, 4 s hold, 4 s out, 4 s hold. */}
      <div className="relative mx-auto flex h-52 w-52 items-center justify-center" aria-live="polite">
        <div
          className={cn("absolute inset-0 rounded-3xl", breathing && "motion-safe:animate-[habit-box-breath_16s_linear_infinite]")}
          style={{ background: `${color}33`, border: `3px solid ${color}`, transform: "scale(0.8)" }}
        />
        <div className="relative">
          <p className="text-base font-semibold text-foreground">{breathing ? phase : "Selesai 🌿"}</p>
          <p className="mt-1 text-3xl font-bold tabular-nums text-foreground">{breathing ? `${left}s` : ""}</p>
        </div>
      </div>

      <p className="text-sm italic text-foreground">“{line}”</p>

      {why && (
        <div className="rounded-xl border border-border bg-accent/60 p-3 text-left">
          <p className="text-xs font-semibold text-muted">Alasanku berhenti</p>
          <p className="mt-1 whitespace-pre-line text-sm text-foreground">{why}</p>
        </div>
      )}

      <p className="text-sm text-muted">
        {current > 0 ? (
          <>
            Kamu sudah bersih <b className="text-foreground">{current} hari</b>. Jaga sebentar lagi, ya.
          </>
        ) : (
          "Hari ini awal yang baru. Kamu bisa."
        )}
      </p>

      <div className="flex flex-wrap justify-center gap-2">
        {URGE_QUICK_ACTIONS.map((a) => (
          <span key={a} className="rounded-full bg-accent px-3 py-1 text-xs font-medium text-muted">
            {a}
          </span>
        ))}
      </div>

      {!breathing ? (
        <div className="grid gap-2 sm:grid-cols-2">
          <Button size="lg" onClick={() => setStep("resisted")} disabled={log.pending} style={{ background: color }}>
            Berhasil tahan 💪
          </Button>
          <Button size="lg" variant="outline" onClick={() => setStep("relapse")} disabled={log.pending || !!log.error}>
            Aku kalah kali ini
          </Button>
        </div>
      ) : (
        <button type="button" className="text-xs font-medium text-muted underline-offset-2 hover:underline" onClick={() => setStep("choose")}>
          Sudah tenang? Lewati hitungan
        </button>
      )}
      <ErrorLine error={error} />
    </div>
  );
}
