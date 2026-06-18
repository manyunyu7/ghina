import { redirect } from "next/navigation";
import { auth } from "@/auth";
import { prisma } from "@/lib/prisma";

/**
 * Returns the authenticated user's full DB record (incl. currency).
 * Redirects to /login when there is no session.
 * Use this at the top of every protected page and server action.
 */
export async function requireUser() {
  const session = await auth();
  if (!session?.user?.id) redirect("/login");

  const user = await prisma.user.findUnique({ where: { id: session.user.id } });
  if (!user) redirect("/login");
  return user;
}

/**
 * Returns the authenticated user's DB record, or null.
 * Does NOT redirect — safe for public pages (login/register/home) to decide
 * whether to bounce an already-authenticated user to the dashboard.
 * Returns null for a stale cookie whose user no longer exists in the DB
 * (prevents login<->dashboard redirect loops).
 */
export async function getCurrentUser() {
  const session = await auth();
  if (!session?.user?.id) return null;
  return prisma.user.findUnique({ where: { id: session.user.id } });
}

/** Lightweight: returns just the user id or redirects. */
export async function requireUserId() {
  const session = await auth();
  if (!session?.user?.id) redirect("/login");
  return session.user.id;
}
