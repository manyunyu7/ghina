# Balance adjustment — spec (web + mobile)

Editing a wallet's balance no longer overwrites `Wallet.balance`. It records a
**balance adjustment transaction** holding the difference, so every change has history
and it is safe with offline sync (a relative delta never conflicts; an absolute value does).

## Model

`Transaction.type` gains `"adjustment"`:
- `amount` is **signed** and non-zero: new balance − current balance. (All other types
  keep `amount > 0`.)
- `walletId` = the wallet; `toWalletId = null`, `categoryId = null`.
- `note` defaults to `"Penyesuaian saldo: Rp X → Rp Y"` (formatted in the **wallet's**
  currency — the balance is in that currency; for the usual single-currency user this is
  the same as the user currency); the user may add their own note, which is appended:
  `"Penyesuaian saldo: Rp X → Rp Y — <user note>"`.
- `date` = now (user may pick another date).
- Ledger effect (`src/lib/ledger.ts`, mobile ledger use case): `+amount` to `walletId`.
  Edit = reverse old + apply new; delete = reverse (restores the previous balance).

## Behaviour

- Web wallet edit form: the balance field in edit mode becomes "Saldo sekarang". If it
  changed, the action creates the adjustment transaction (in the same DB transaction as
  the other wallet field updates) instead of writing `balance`. Unchanged = no row
  (difference rounded to 2 decimals, so float noise never creates a row).
  Web implementation: `adjustWalletBalance()` in `src/lib/ledger.ts`.
  Creating a wallet keeps using the initial balance as today (no adjustment row).
- Mobile: wallet detail/edit gets "Sesuaikan saldo" (enter the real current balance →
  preview the difference → save). Works offline: delta = entered − displayed balance.
- Transaction lists show adjustments with a neutral style (scale/tune icon, gray/blue,
  sign shown), label "Penyesuaian saldo". Filterable by type. Tapping opens edit
  (amount can be changed/deleted like any transaction).
- **Excluded** from: income/expense totals, dashboard month income/expense, budgets
  spent, reports (income vs expense, by category, savings rate, cashflow), forecast
  history averages, gamification XP/streak (it is not "logging a transaction").
  Included in: wallet balances, net worth, the wallet's history.
- Web wallets page: each wallet gets a "Riwayat" link → transactions filtered by that
  wallet (existing filter), which now includes adjustments and also transfers **into** the
  wallet (`walletId = X or toWalletId = X`) so the list explains the balance.

## Sync

`transactions` wire format unchanged; `type` may be `adjustment` with a signed `amount`.
Server validation: adjustment requires non-zero finite amount, no category, no
toWalletId (a non-null `categoryId`/`toWalletId` is rejected, not silently dropped). Update `docs/mobile-sync.md` accordingly. The mobile app must tolerate
unknown transaction types from the server without crashing (skip or show generically) —
future-proofing.
