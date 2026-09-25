# Investments (portfolio) — spec (web + mobile)

Track stock holdings (IDX first) and other assets, with values that follow market prices,
so net worth reflects real portfolio value. Holdings are **derived from trades** (source
of truth), never edited directly.

Pure rules: `src/lib/investments.ts` (unit-tested by `scripts/test-investments.mjs`;
mobile mirrors it). Prices: `src/lib/prices.ts`. DB helpers: `src/lib/investments-server.ts`.
Web actions: `src/app/(dashboard)/investments/actions.ts`.

## Model

```prisma
model Asset {                // an instrument the user holds or watches
  id        String  @id @default(cuid())
  userId    String
  kind      String           // stock | fund | gold | crypto | bond | other
  symbol    String           // stock: IDX ticker "BBCA"; crypto: "BTC"; others: free code ≤ 20
  name      String?          // display name (auto-filled for stocks/crypto when known)
  currency  String  @default("IDR")
  priceMode String  @default("auto")   // auto (stock/crypto only) | manual
  manualPrice Float?          // per unit, used when priceMode = manual (fund NAV, gold/gram…)
  manualPriceAt DateTime?
  unit      String  @default("lembar") // lembar | unit | gram | koin | …
  walletId  String?          // investment wallet / RDN this asset lives in (SetNull)
  archived  Boolean @default(false)
  sortOrder Int     @default(0)
  createdAt, updatedAt
  @@unique([userId, kind, symbol])
}

model AssetTrade {
  id        String   @id @default(cuid())
  userId    String
  assetId   String            // → Asset, cascade (tombstoned)
  type      String            // buy | sell | dividend | split | fee
  date      DateTime
  quantity  Float?            // buy/sell: units — SHARES (UI may input lots: 1 lot = 100 lembar)
  price     Float?            // buy/sell: per unit
  fee       Float    @default(0)   // buy/sell: broker fee + tax, in currency
  amount    Float?            // dividend: cash received; fee: the fee
  ratio     Float?            // split: new units per old unit (e.g. 2 for 1:2)
  note      String?
  cashTransactionId String? @unique // the linked wallet transaction (see Cash effect), SetNull
  createdAt, updatedAt
}
```

Fields per trade type (others are stored as null, `fee` as 0): buy/sell: quantity > 0,
price > 0, fee ≥ 0 · dividend: amount > 0 · split: ratio > 0, ≠ 1 · fee: amount > 0.

## Derived holding (average-cost method)

Process trades by date (then createdAt, then id):
- buy: `cost += q*p + fee; shares += q`
- sell: `avg = cost/shares; realized += q*p − fee − q*avg; cost −= q*avg; shares −= q`
  (selling more than held is rejected)
- split: `shares *= ratio` (cost unchanged)
- dividend: `dividends += amount` (no share change)
- fee: `realized −= amount`
Outputs: shares, avgPrice (= cost/shares), costBasis, realized P/L, dividends total.
Market value = shares × current price; unrealized P/L = market value − costBasis (and %).
Total return = unrealized + realized + dividends.

## Cash effect (optional, default ON when the asset has a wallet)

Each trade can move cash in the asset's wallet (the RDN), through the normal ledger
(`tradeCashEffect`, amounts rounded to 2 decimals):
- buy → a transaction of new type **`investment`** with signed amount −(q·p + fee)
- sell → `investment` +(q·p − fee)
- dividend → a regular **income** transaction (category "Dividen", seeded if missing) —
  dividends ARE income in reports
- fee → `investment` −amount
- split → no cash
`investment` transactions behave like `adjustment` in reports (excluded from income/
expense/budgets/forecast/XP; included in balances and net worth). Deleting/editing a
trade updates or deletes its linked transaction atomically.

## Prices

- Server-side price service (never from the client directly): `SecurityPrice {kind,
  symbol, name, price, prevClose, change, changePct, currency, asOf, source, fetchedAt,
  checkedAt, error}` shared across users (not user data).
- Stocks (IDX): Yahoo Finance chart endpoint for `<SYMBOL>.JK`
  (`https://query1.finance.yahoo.com/v8/finance/chart/BBCA.JK?range=1d&interval=1d`),
  crypto: `<SYMBOL>-IDR`. Cache: stocks 15 min during IDX hours (Mon–Fri 09:00–16:15
  WIB), otherwise until the next session; crypto 15 min. Per-request timeout 5 s; batched
  (one request per symbol, ≤ 4 in flight, duplicates shared); failures keep the last price
  and mark it stale. Validate the symbol exists on first add (name auto-filled).
- Manual assets use `manualPrice` (+ date), shown as "harga manual per <date>".
- Endpoints: `GET /api/mobile/prices?symbols=stock:BBCA,crypto:BTC` → latest prices
  (mobile caches them locally for offline display, shows "terakhir diperbarui …");
  web reads through the same service.
- `PortfolioSnapshot {userId, date, value, cost}` for the value history chart (server
  cron-free: taken lazily by portfolio requests, one row per local day).

## Net worth & wallets

Net worth = Σ wallet balances + Σ asset market values. The investment wallet card shows
cash (RDN) + portfolio value separately. Reports' net worth includes investments.

## UI

- **Portofolio** page (web `/investments`, mobile "Investasi" from home/profile + a home
  card with total value and today's change): summary (market value, cost, unrealized P/L
  Rp and %, today's change, realized, dividends), allocation donut (by asset and by
  kind), value history line, holdings list (symbol, name, lots/lembar, avg, last price,
  day change, value, P/L colored), asset detail (trades history, P/L breakdown, price
  info), add trade form (buy/sell with lot↔lembar toggle, price, fee presets e.g. buy
  0.15% / sell 0.25% configurable, date, cash effect toggle and wallet), dividends, split,
  manual price update for manual assets, add asset (search/validate ticker).
- Mobile works offline with cached prices and pending trades.

## Sync

Entities `assets`, `assetTrades` (+ transaction type `investment` on `transactions`,
signed amount, no category, no toWalletId — same rules as `adjustment`). Server validates
trade sanity (no negative holdings after the trade in date order; quantity/price > 0 for
buy/sell). Prices are not synced as entities — fetched via the prices endpoint. Details:
docs/mobile-sync.md "Investments".

## Clarifications

Decisions taken while implementing the backend (2026-09-25):

1. **Symbols**: stock/crypto are uppercased (`.JK` / `-IDR` suffixes stripped); stock
   `^[A-Z0-9][A-Z0-9-]{0,11}$`, crypto `^[A-Z0-9]{1,15}$`; other kinds keep the typed code
   (trimmed, ≤ 20). (kind, symbol) is unique per user **case-insensitively** → `duplicate`.
2. **priceMode**: only stock/crypto may be `auto`; every other kind is stored as `manual`.
   `unit` defaults per kind (stock lembar, crypto koin, gold gram, else unit).
3. **Cash link is created by the client**: offline-first, the device pushes the linked
   wallet transaction as a normal `transactions` upsert (type `investment`, or `income`
   for dividends) **before** the trade, then the trade with `cashTransactionId`. The
   server validates the link: a missing/foreign transaction id → stored as null (it may
   have been deleted offline); wrong type or sign, or a transaction already linked to
   another trade → `rejected`. Amounts are not compared (client rounding). The web
   actions create/update the linked transaction server-side in the same DB transaction.
4. **Deletes**: deleting a trade deletes its linked transaction through the ledger
   (balance reversed; tombstoned) — for dividends too. Deleting an asset deletes all its
   trades (and their linked transactions). **Archive** is the non-destructive option; the
   UI should say so when deleting. Deleting a linked transaction directly (transactions
   page, sync) keeps the trade and nulls `cashTransactionId` (the holding is unchanged).
   Deleting a wallet nulls `Asset.walletId` (and, through its deleted transactions,
   trades' `cashTransactionId`).
5. **Sanity check**: a trade upsert (sync or web) is rejected when, with the change applied,
   holdings go negative in date order where they didn't before ("Jumlah jual (X)
   melebihi kepemilikan (Y) per YYYY-MM-DD"). Deletes are never rejected (a client can't
   undo a local delete); holdings are then derived leniently (an oversell is clamped and
   reported in `Holding.issues`).
6. **Ordering ties**: same `date` → `createdAt` → id. Send real times in `date`.
7. **Dividen category**: `category-dividen-<userId>` (income, `#10b981`,
   `circle-dollar-sign`). An existing income category named "Dividen" (case-insensitive)
   is used instead. The pull seeds it once for users with ≥ 1 asset (not re-seeded after
   the user deletes it); the web dividend action re-creates it when needed. Mobile may
   create the same id locally.
8. **Currency**: amounts are in the asset's currency and moved into the wallet as-is (no
   FX); UIs should pick a wallet with the same currency.
9. **Fees**: `FEE_PRESETS` (buy 0.15 %, sell 0.25 %) + `estimateFee`; per-user overrides
   are a client preference (not stored server-side).
10. **Prices**: a 200 without a usable price counts as not found. Failures: per-symbol
    retry after 10 min; HTTP 429 pauses every Yahoo call for 15 min (process-wide);
    unknown symbols are remembered for 6 h. Adding a stock/crypto while Yahoo is
    unavailable is allowed (name stays empty). Holidays are not modelled (a refetch just
    returns the same close).
11. **Valuation**: auto assets use the cached quote (stale is still used, flagged);
    manual assets `manualPrice`; no price → market value null, and totals/net worth count
    the cost basis instead (`unpricedCount`). Net worth excludes archived assets (like
    archived wallets).
12. **Snapshots**: every portfolio summary request upserts today's (Asia/Jakarta) row, so
    the day's row holds its last value. Snapshots are server-only (not synced) and survive
    a reset.
13. **Reset all data** keeps assets, trades and snapshots: assets lose `walletId`, trades
    `cashTransactionId` (their transactions are wiped with the wallets).
14. Dashboard "Total Balance" and the reports' net worth now include the portfolio value
    (`getNetWorth`).
