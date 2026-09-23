import { saveUpload } from "@/lib/uploads";
import { handle, HttpError, requireMobileUser } from "@/lib/mobile/http";

const MAX_BYTES = 5 * 1024 * 1024;

/** Store an image (e.g. a food photo taken offline); the client then syncs the returned url. */
export const POST = handle(async (req: Request) => {
  await requireMobileUser(req);

  let form: FormData;
  try {
    form = await req.formData();
  } catch {
    throw new HttpError(400, "Expected a multipart/form-data body");
  }
  const file = form.get("file");
  if (!(file instanceof File) || file.size === 0) throw new HttpError(400, "Missing file");

  try {
    return Response.json({ url: await saveUpload(file, MAX_BYTES) });
  } catch (e) {
    throw new HttpError(400, e instanceof Error ? e.message : "Upload failed");
  }
});
