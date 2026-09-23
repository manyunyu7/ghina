import { createRemoteJWKSet, jwtVerify } from "jose";

const GOOGLE_JWKS = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"));

/** Client ids a Google ID token may be issued for: the web client plus the mobile ones. */
function allowedAudiences(): string[] {
  return [process.env.AUTH_GOOGLE_ID, ...(process.env.AUTH_GOOGLE_MOBILE_CLIENT_IDS ?? "").split(",")]
    .map((s) => s?.trim() ?? "")
    .filter(Boolean);
}

export type GoogleIdentity = { sub: string; email: string; name: string | null; picture: string | null };

/** Verify a Google ID token (signature, issuer, audience, expiry). Returns null when invalid. */
export async function verifyGoogleIdToken(idToken: string): Promise<GoogleIdentity | null> {
  const audience = allowedAudiences();
  if (audience.length === 0) return null;
  try {
    const { payload } = await jwtVerify(idToken, GOOGLE_JWKS, {
      issuer: ["https://accounts.google.com", "accounts.google.com"],
      audience,
    });
    const email = typeof payload.email === "string" ? payload.email : null;
    if (!payload.sub || !email || payload.email_verified === false) return null;
    return {
      sub: payload.sub,
      email,
      name: typeof payload.name === "string" ? payload.name : null,
      picture: typeof payload.picture === "string" ? payload.picture : null,
    };
  } catch {
    return null;
  }
}

export const googleConfigured = () => allowedAudiences().length > 0;
