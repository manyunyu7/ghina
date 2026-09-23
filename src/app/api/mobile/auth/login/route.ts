import bcrypt from "bcryptjs";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { handle, HttpError, readJson } from "@/lib/mobile/http";
import { serializeUser } from "@/lib/mobile/serialize";
import { signMobileToken } from "@/lib/mobile/token";

const schema = z.object({
  email: z.string().trim().email("Enter a valid email"),
  password: z.string().min(1, "Password is required"),
});

export const POST = handle(async (req: Request) => {
  const { email, password } = await readJson(req, schema);

  const user = await prisma.user.findUnique({ where: { email } });
  const valid = user?.password ? await bcrypt.compare(password, user.password) : false;
  if (!user || !valid) throw new HttpError(401, "Incorrect email or password.");

  return Response.json({ token: await signMobileToken(user.id), user: serializeUser(user) });
});
