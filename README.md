# 💰 Buddget

A complete personal **budget & expense tracker**, built from scratch with the latest stack. Track transactions, manage multiple wallets, set monthly budgets per category, and visualize your money with rich reports — all behind **Sign in with Google**.

![stack](https://img.shields.io/badge/Next.js-16-black) ![react](https://img.shields.io/badge/React-19-blue) ![prisma](https://img.shields.io/badge/Prisma-6-2D3748) ![auth](https://img.shields.io/badge/Auth.js-v5-green)

## ✨ Features

- 🔐 **Authentication** — email/password (works out of the box) **and** optional Google sign-in (Auth.js v5, JWT sessions)
- 📊 **Dashboard** — balance, monthly income/expense/net, spending donut, 6-month trend, recent activity, budget snapshot
- 💳 **Wallets** — multiple accounts (cash, bank, e-wallet, credit, savings, investment) with live balances, colors & icons
- 🔁 **Transactions** — income / expense, filter by type/wallet/category/month, search, grouped by date; wallet balances update automatically
- 🏷️ **Categories** — custom income & expense categories with icon + color pickers, one-click default set
- 🎯 **Budgets** — monthly budget per category with progress bars and over-budget warnings
- 📈 **Reports** — income vs expense over time, spending by category, top categories, cashflow, savings rate
- ⚙️ **Settings** — profile, default currency (IDR, USD, EUR, GBP, JPY, SGD, MYR), reset data, sign out
- 🎨 Polished, responsive fintech UI (Tailwind v4) with a shared component library

## 🧱 Tech stack

| Layer | Choice |
|-------|--------|
| Framework | Next.js 16 (App Router, Server Actions, RSC) |
| UI | React 19, Tailwind CSS v4, lucide-react |
| Charts | Recharts |
| Auth | Auth.js (NextAuth v5) — Google OAuth |
| ORM / DB | Prisma 6 + SQLite (swap to Postgres easily) |
| Validation | Zod |

## 🚀 Getting started

### 1. Install

```bash
npm install
```

### 2. Configure environment

The repo ships with a `.env`. Generate a fresh auth secret:

```bash
npx auth secret          # writes AUTH_SECRET into .env
```

That's all you need for **email/password** login. Google sign-in is optional (step 3).

### 3. (Optional) Set up Google OAuth

Skip this to use email/password only — the Google button appears automatically once these vars are set.

1. Go to the [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials).
2. **Create Credentials → OAuth client ID → Web application**.
3. Under **Authorized redirect URIs** add:
   ```
   http://localhost:3000/api/auth/callback/google
   ```
4. Copy the **Client ID** and **Client secret** into `.env`:
   ```
   AUTH_GOOGLE_ID="...apps.googleusercontent.com"
   AUTH_GOOGLE_SECRET="..."
   ```
   (On the OAuth consent screen, add yourself as a Test user if the app is in "Testing".)

### 4. Create the database

```bash
npm run db:push     # creates dev.db (SQLite) from prisma/schema.prisma
```

### 5. Run

```bash
npm run dev
```

Open <http://localhost:3000>, click **Sign up**, and create an account with your email + password (a starter "Cash" wallet and default categories are created for you). Or use Google if you configured it.

### 6. (Optional) Seed demo data

After signing up **once** (this creates your user record), populate your account with sample wallets, categories, transactions and budgets:

```bash
npm run seed
```

## 📜 Scripts

| Script | Description |
|--------|-------------|
| `npm run dev` | Start the dev server |
| `npm run build` / `npm start` | Production build & serve |
| `npm run lint` | ESLint |
| `npm run db:push` | Sync Prisma schema → SQLite |
| `npm run db:studio` | Open Prisma Studio (DB GUI) |
| `npm run seed` | Seed demo data for the signed-in user |

## 🗂️ Project structure

```
src/
├── auth.ts                     # Auth.js config (Google + Prisma adapter)
├── app/
│   ├── layout.tsx              # Root layout + theme
│   ├── page.tsx                # Redirects to /dashboard or /login
│   ├── login/                  # Google sign-in screen
│   ├── api/auth/[...nextauth]/ # Auth.js route handlers
│   └── (dashboard)/            # Authenticated app (sidebar shell)
│       ├── layout.tsx          # requireUser() guard + sidebar
│       ├── dashboard/          # Overview
│       ├── transactions/       # CRUD + filters
│       ├── wallets/            # CRUD
│       ├── budgets/            # Monthly budgets
│       ├── categories/         # CRUD + icon/color pickers
│       ├── reports/            # Analytics & charts
│       └── settings/           # Profile, currency, reset, sign out
├── components/                 # Sidebar, icon resolver, ui/ primitives
└── lib/                        # prisma, auth-helpers, queries, utils, constants
```

## 🔄 Switching to PostgreSQL

1. In `prisma/schema.prisma` set `datasource db { provider = "postgresql" }`.
2. Point `DATABASE_URL` at your Postgres instance.
3. `npm run db:push`.

## 🔒 Security notes

- Every page and every Server Action calls `requireUser()` and scopes all queries by the authenticated user id — Server Actions are treated as untrusted endpoints.
- Ownership is verified before any update/delete.

---

Built with Next.js 16 + Auth.js + Prisma.
