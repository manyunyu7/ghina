import type { Metadata } from "next";
import { PageHeader } from "@/components/ui/misc";
import { listKillaMessages, requireKillaUser } from "@/lib/killa";
import { KillaNav } from "./killa-nav";
import { KillaChat } from "./chat";

export const metadata: Metadata = { title: "Killa — Ghina" };

export default async function KillaPage() {
  const user = await requireKillaUser();
  const { messages, nextBefore } = await listKillaMessages(user.id);
  return (
    <div>
      <PageHeader title="Killa" description="Agen Claude pribadi. Semua percakapan tersimpan di Ghina." />
      <KillaNav />
      <KillaChat messages={messages} nextBefore={nextBefore} />
    </div>
  );
}
