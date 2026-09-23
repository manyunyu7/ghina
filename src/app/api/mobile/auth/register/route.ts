import bcrypt from "bcryptjs";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { starterUserData } from "@/lib/user-defaults";
import { handle, HttpError, readJson } from "@/lib/mobile/http";
import { serializeUser } from "@/lib/mobile/serialize";
import { signMobileToken } from "@/lib/mobile/token";

const schema = z.object({
  name: z.string().trim().min(1, "Name is required").max(60),
  email: z.string().trim().email("Enter a valid email"),
  password: z.string().min(8, "Password must be at least 8 characters"),
});

export const POST = handle(async (req: Request) => {
  const { name, email, password } = await readJson(req, schema);

  const existing = await prisma.user.findUnique({ where: { email }, select: { id: true } });
  if (existing) throw new HttpError(409, "An account with this email already exists.");

  // Same starter wallet + categories as a web sign-up.
  const user = await prisma.user.create({
    data: { name, email, password: await bcrypt.hash(password, 10), currency: "IDR", ...starterUserData() },
  });

  return Response.json({ token: await signMobileToken(user.id), user: serializeUser(user) });
});
