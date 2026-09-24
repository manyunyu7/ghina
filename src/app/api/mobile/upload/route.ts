import { saveMediaUpload } from "@/lib/uploads";
import { handle, HttpError, requireMobileUser } from "@/lib/mobile/http";

/**
 * Store an image (≤ 5 MB) or an audio clip (≤ 20 MB) — e.g. a food photo or a voice note
 * recorded offline; the client then syncs the returned url. The kind is detected from
 * the bytes. Response: `{url, kind: "image" | "audio"}`.
 */
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
    return Response.json(await saveMediaUpload(file, ["image", "audio"]));
  } catch (e) {
    throw new HttpError(400, e instanceof Error ? e.message : "Upload failed");
  }
});
