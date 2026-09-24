import type { Metadata } from "next";
import { requireUser } from "@/lib/auth-helpers";
import { getBoardData } from "./data";
import { TaskBoard } from "./task-board";

export const metadata: Metadata = { title: "Tugas — Ghina" };

export default async function TasksPage() {
  const user = await requireUser();
  const data = await getBoardData(user.id, user.currency);
  return <TaskBoard data={data} />;
}
