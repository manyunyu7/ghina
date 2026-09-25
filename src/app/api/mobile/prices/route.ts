import type { NextRequest } from "next/server";
import { handle, HttpError, requireMobileUser } from "@/lib/mobile/http";
import { parsePriceSymbols, priceService } from "@/lib/prices";

/**
 * Latest market prices (docs/investments.md "Prices"):
 * `GET /api/mobile/prices?symbols=stock:BBCA,crypto:BTC` (≤ 50 symbols) →
 * `{ serverTime, prices: Quote[] }` in request order (duplicates dropped). Served from the
 * shared cache; stale symbols are refreshed from Yahoo first (5-s timeout each).
 */
export const GET = handle(async (req: NextRequest) => {
  await requireMobileUser(req);
  const parsed = parsePriceSymbols(req.nextUrl.searchParams.get("symbols"));
  if (!parsed.ok) throw new HttpError(400, parsed.error);
  const prices = await priceService().getQuotes(parsed.items);
  return Response.json({ serverTime: Date.now(), prices });
});
