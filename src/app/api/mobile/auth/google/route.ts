import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { starterUserData } from "@/lib/user-defaults";
import { verifyGoogleIdToken, googleConfigured } from "@/lib/mobile/google";
import { handle, HttpError, readJson } from "@/lib/mobile/http";
import { serializeUser } from "@/lib/mobile/serialize";
import { signMobileToken } from "@/lib/mobile/token";

const schema = z.object({ idToken: z.string().min(1, "idToken is required") });

export const POST = handle(async (req: Request) => {
  if (!googleConfigured()) throw new HttpError(503, "Google sign-in is not configured");
  const { idToken } = await readJson(req, schema);

  const identity = await verifyGoogleIdToken(idToken);
  if (!identity) throw new HttpError(401, "Invalid Google sign-in");

  // Find by email (like the web's dangerous email account linking), create if missing.
  let user = await prisma.user.findUnique({ where: { email: identity.email } });
  if (!user) {
    user = await prisma.user.create({
      data: {
        name: identity.name,
        email: identity.email,
        image: identity.picture,
        emailVerified: new Date(),
        currency: "IDR",
        ...starterUserData(),
      },
    });
  }

  // Link the Google account so web sign-in with Google lands on the same user.
  await prisma.account.upsert({
    where: { provider_providerAccountId: { provider: "google", providerAccountId: identity.sub } },
    create: { userId: user.id, type: "oidc", provider: "google", providerAccountId: identity.sub },
    update: {},
  });

  return Response.json({ token: await signMobileToken(user.id), user: serializeUser(user) });
});
