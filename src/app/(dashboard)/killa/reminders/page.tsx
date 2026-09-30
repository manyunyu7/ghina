import type { Metadata } from "next";
import { AlertTriangle, BellOff } from "lucide-react";
import { EmptyState, PageHeader } from "@/components/ui/misc";
import { KillaError, killaChatKey, killaEngine, killaWaNumber, requireKillaUser, type KillaReminder } from "@/lib/killa";
import { KillaNav } from "../killa-nav";
import { ReminderList } from "./reminder-list";

export const metadata: Metadata = { title: "Pengingat Killa — Ghina" };

/** Killa's scheduled reminders for this chat (GET /v1/reminders), with a cancel button each. */
export default async function KillaRemindersPage() {
  const user = await requireKillaUser();
  let reminders: KillaReminder[] = [];
  let error: string | null = null;
  try {
    reminders = await killaEngine.reminders(killaChatKey(user.id));
  } catch (e) {
    if (!(e instanceof KillaError)) throw e;
    error = e.message;
  }

  return (
    <div>
      <PageHeader
        title="Killa"
        description={
          killaWaNumber()
            ? "Pengingat yang dijadwalkan Killa — dikirim lewat WhatsApp."
            : "Pengingat yang dijadwalkan Killa untuk percakapan ini."
        }
      />
      <KillaNav />
      {error ? (
        <div role="alert" className="flex items-start gap-2 rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>{error}</span>
        </div>
      ) : reminders.length === 0 ? (
        <EmptyState
          icon={BellOff}
          title="Belum ada pengingat"
          description="Minta Killa, mis. “ingetin jam 7 minum obat”."
        />
      ) : (
        <ReminderList reminders={reminders} />
      )}
    </div>
  );
}
