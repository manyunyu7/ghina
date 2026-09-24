import type { Metadata } from "next";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { getTaskAreas } from "../data";
import { AreaManager } from "./area-manager";

export const metadata: Metadata = { title: "Area tugas — Ghina" };

export default async function TaskAreasPage() {
  const user = await requireUser();
  const [areas, counts] = await Promise.all([
    getTaskAreas(user.id),
    prisma.task.groupBy({ by: ["areaId"], where: { userId: user.id }, _count: { _all: true } }),
  ]);
  const taskCounts = Object.fromEntries(counts.map((c) => [c.areaId, c._count._all]));
  return <AreaManager areas={areas} taskCounts={taskCounts} />;
}
