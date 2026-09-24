#!/usr/bin/env node
// Server-side helper for the Flutter end-to-end tests (mobile/test/data/e2e_*_test.dart).
// Runs the same code the web uses, directly against the database:
//
//   node scripts/e2e-helper.mjs reset <email>        # web "Reset all data" (new sync epoch)
//   node scripts/e2e-helper.mjs cleanup <emailPrefix> # delete throwaway users + their upload files
//
// Only touches users whose email ends with @example.test.
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { PrismaClient } from "@prisma/client";
import { createJiti } from "jiti";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const jiti = createJiti(import.meta.url, { alias: { "@": join(root, "src") } });
const prisma = new PrismaClient();
const [cmd, arg] = process.argv.slice(2);

const guard = (email) => {
  if (!email || !email.endsWith("@example.test")) throw new Error(`refusing to touch ${email}`);
};

try {
  if (cmd === "reset") {
    guard(arg);
    const user = await prisma.user.findUniqueOrThrow({ where: { email: arg } });
    const { resetFinanceData } = await jiti.import(join(root, "src/lib/sync-deletes.ts"));
    await resetFinanceData(user.id);
    const after = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });
    console.log(JSON.stringify({ epoch: after.syncEpoch }));
  } else if (cmd === "cleanup") {
    if (!arg || arg.length < 8) throw new Error("prefix too short");
    const users = await prisma.user.findMany({
      where: { email: { startsWith: arg, endsWith: "@example.test" } },
      select: { id: true },
    });
    const ids = users.map((u) => u.id);
    const { parsePhotos } = await jiti.import(join(root, "src/lib/photos.ts"));
    const { deleteUpload } = await jiti.import(join(root, "src/lib/uploads.ts"));
    const txs = await prisma.transaction.findMany({ where: { userId: { in: ids } }, select: { photos: true } });
    const food = await prisma.foodLog.findMany({ where: { userId: { in: ids } }, select: { photoUrl: true } });
    const files = [...txs.flatMap((t) => parsePhotos(t.photos)), ...food.map((f) => f.photoUrl).filter(Boolean)];
    for (const f of files) await deleteUpload(f);
    const { count } = await prisma.user.deleteMany({ where: { id: { in: ids } } });
    console.log(JSON.stringify({ users: count, files: files.length }));
  } else {
    throw new Error(`unknown command ${cmd}`);
  }
} finally {
  await prisma.$disconnect();
}
