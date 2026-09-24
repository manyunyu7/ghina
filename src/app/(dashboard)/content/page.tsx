import type { Metadata } from "next";
import { requireUser } from "@/lib/auth-helpers";
import { getPlannerData } from "./data";
import { ContentPlanner } from "./planner";
import { CONTENT_TABS, type ContentTab } from "./types";

export const metadata: Metadata = { title: "Konten — Ghina" };

export default async function ContentPage({ searchParams }: { searchParams: Promise<{ tab?: string; item?: string }> }) {
  const user = await requireUser();
  const sp = await searchParams;
  const tab = (CONTENT_TABS.some((t) => t.id === sp.tab) ? sp.tab : "papan") as ContentTab;
  const data = await getPlannerData(user.id, user.currency);
  return <ContentPlanner data={data} initialTab={tab} initialItemId={typeof sp.item === "string" ? sp.item : null} />;
}
