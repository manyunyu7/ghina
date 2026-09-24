import type { Metadata } from "next";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { getNoteLabels, getNotes } from "@/lib/notes-server";
import { getTaskAreas } from "../tasks/data";
import { NotesApp } from "./notes-app";

export const metadata: Metadata = { title: "Catatan — Ghina" };

export default async function NotesPage({ searchParams }: { searchParams: Promise<{ note?: string | string[] }> }) {
  const user = await requireUser();
  const { note } = await searchParams;
  const [labels, notes, areas, wallets, categories] = await Promise.all([
    getNoteLabels(user.id),
    getNotes(user.id, { archived: "all" }),
    getTaskAreas(user.id),
    prisma.wallet.findMany({
      where: { userId: user.id, archived: false },
      select: { id: true, name: true, currency: true },
      orderBy: { createdAt: "asc" },
    }),
    prisma.category.findMany({
      where: { userId: user.id },
      select: { id: true, name: true, type: true },
      orderBy: { name: "asc" },
    }),
  ]);
  return (
    <NotesApp
      notes={notes}
      labels={labels}
      areas={areas.filter((a) => !a.archived).map((a) => ({ id: a.id, name: a.name, code: a.code, color: a.color }))}
      wallets={wallets}
      categories={categories}
      currency={user.currency}
      initialNoteId={typeof note === "string" ? note : null}
    />
  );
}
