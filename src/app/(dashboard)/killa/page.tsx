import type { Metadata } from "next";
import { PageHeader } from "@/components/ui/misc";
import { killaChatKey, killaEngine, listKillaMessages, requireKillaUser, type KillaModelState } from "@/lib/killa";
import { KillaNav } from "./killa-nav";
import { KillaChat } from "./chat";

export const metadata: Metadata = { title: "Killa — Ghina" };

export default async function KillaPage() {
  const user = await requireKillaUser();
  // The persisted model is best-effort: an unreachable engine must not break the log.
  const [{ messages, nextBefore }, modelState] = await Promise.all([
    listKillaMessages(user.id),
    killaEngine.getModel(killaChatKey(user.id)).catch((): KillaModelState | null => null),
  ]);
  return (
    <div>
      <PageHeader title="Killa" description="Agen Claude pribadi. Semua percakapan tersimpan di Ghina." />
      <KillaNav />
      <KillaChat messages={messages} nextBefore={nextBefore} modelState={modelState} />
    </div>
  );
}
