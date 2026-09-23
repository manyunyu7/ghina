import { hkdfSync } from "node:crypto";
import { SignJWT, jwtVerify } from "jose";

/** Mobile API bearer tokens: HS256 JWTs, `sub` = user id, valid 90 days. */

const ISSUER = "ghina-mobile";
const TTL = "90d";

let cachedKey: Uint8Array | null = null;

/** Signing key derived from AUTH_SECRET, so it differs from the key Auth.js uses. */
function key(): Uint8Array {
  if (cachedKey) return cachedKey;
  const secret = process.env.AUTH_SECRET;
  if (!secret) throw new Error("AUTH_SECRET is not set");
  cachedKey = new Uint8Array(hkdfSync("sha256", secret, "", "ghina-mobile-jwt", 32));
  return cachedKey;
}

export function signMobileToken(userId: string): Promise<string> {
  return new SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userId)
    .setIssuer(ISSUER)
    .setIssuedAt()
    .setExpirationTime(TTL)
    .sign(key());
}

/** Returns the user id, or null for a missing/invalid/expired token. */
export async function verifyMobileToken(token: string): Promise<string | null> {
  try {
    const { payload } = await jwtVerify(token, key(), { algorithms: ["HS256"], issuer: ISSUER });
    return typeof payload.sub === "string" && payload.sub.length > 0 ? payload.sub : null;
  } catch {
    return null;
  }
}
