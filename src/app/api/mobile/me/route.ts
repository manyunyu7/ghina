import { prisma } from "@/lib/prisma";
import { profileSchema } from "@/lib/schemas";
import { handle, readJson, requireMobileUser } from "@/lib/mobile/http";
import { serializeUser } from "@/lib/mobile/serialize";

export const GET = handle(async (req: Request) => {
  const user = await requireMobileUser(req);
  return Response.json({ user: serializeUser(user) });
});

export const PATCH = handle(async (req: Request) => {
  const user = await requireMobileUser(req);
  const data = await readJson(req, profileSchema.partial());
  const updated = await prisma.user.update({ where: { id: user.id }, data });
  return Response.json({ user: serializeUser(updated) });
});
