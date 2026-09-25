import { z } from "zod";
import { CATEGORY_ICONS, WALLET_TYPES } from "@/lib/constants";
import { CURRENCIES } from "@/lib/utils";

/**
 * Validation rules shared by the web server actions (FormData) and the mobile
 * sync endpoint (JSON). Keep them in one place so both clients get the same rules.
 */

const hexColor = z.string().regex(/^#[0-9a-fA-F]{6}$/, "Invalid color");
const currency = z.enum(CURRENCIES as [string, ...string[]]);

/** Optional id: "", null and undefined all mean "none". */
const optionalId = z
  .string()
  .nullish()
  .transform((v) => (v && v.length > 0 ? v : null));

export const walletSchema = z.object({
  name: z.string().trim().min(1, "Name is required").max(60),
  type: z.enum(WALLET_TYPES.map((t) => t.value) as [string, ...string[]]),
  balance: z.coerce.number().finite(),
  currency,
  color: hexColor,
  icon: z.string().trim().min(1).max(40),
});

export const categorySchema = z.object({
  name: z.string().trim().min(1, "Name is required").max(60),
  type: z.enum(["expense", "income"]),
  color: hexColor,
  icon: z.enum(CATEGORY_ICONS as [string, ...string[]]),
});

export const TRANSACTION_TYPES = ["expense", "income", "transfer", "adjustment", "investment"] as const;
/**
 * Types that are real money in/out — the only ones summed in income/expense totals.
 * Transfers, balance adjustments and `investment` (trade cash, docs/investments.md) never are.
 */
export const CASHFLOW_TYPES = ["income", "expense"] as const;
/**
 * Types with a signed amount, no category and no destination wallet: a balance
 * `adjustment` (docs/balance-adjustment.md) and an `investment` trade's cash
 * (docs/investments.md). Both move only their wallet's balance by `+amount`.
 */
export const SIGNED_TRANSACTION_TYPES = ["adjustment", "investment"] as const;
export const isSignedType = (type: string) => (SIGNED_TRANSACTION_TYPES as readonly string[]).includes(type);

/**
 * amount > 0 for expense/income/transfer. A balance `adjustment` (docs/balance-adjustment.md)
 * has a signed, non-zero amount (new balance − old balance); so does `investment`
 * (buy/fee negative, sell positive).
 */
export const transactionSchema = z
  .object({
    type: z.enum(TRANSACTION_TYPES),
    amount: z.coerce.number().finite("Amount must be a number"),
    walletId: z.string().min(1, "Wallet is required"),
    toWalletId: optionalId,
    categoryId: optionalId,
    note: z
      .string()
      .nullish()
      .transform((v) => (v && v.trim().length > 0 ? v.trim() : null)),
    date: z.coerce.date(),
  })
  .superRefine((t, ctx) => {
    if (isSignedType(t.type)) {
      if (t.amount === 0)
        ctx.addIssue({
          code: "custom",
          path: ["amount"],
          message: t.type === "adjustment" ? "Adjustment amount must not be 0" : "Investment amount must not be 0",
        });
    } else if (!(t.amount > 0)) {
      ctx.addIssue({ code: "custom", path: ["amount"], message: "Amount must be greater than 0" });
    }
  });

export const budgetSchema = z.object({
  categoryId: z.string().trim().min(1, "Category is required"),
  amount: z.number().positive("Amount must be greater than 0"),
  month: z.number().int().min(1, "Invalid month").max(12, "Invalid month"),
  year: z.number().int().min(1970, "Invalid year").max(9999, "Invalid year"),
});

export const subscriptionSchema = z.object({
  name: z.string().trim().min(1, "Name is required").max(80),
  amount: z.coerce.number().positive("Amount must be greater than 0"),
  currency: z.string().min(1).max(8),
  cycle: z.enum(["weekly", "monthly", "yearly"]),
  nextBilling: z.coerce.date(),
  categoryId: z.string().optional().nullable(),
  walletId: z.string().optional().nullable(),
  color: hexColor.default("#6366f1"),
  icon: z.string().min(1).default("credit-card"),
  note: z.string().max(200).optional().nullable(),
  active: z.coerce.boolean().optional(),
});

export const plannedSchema = z.object({
  type: z.enum(["expense", "income"]),
  amount: z.coerce.number().positive("Amount must be greater than 0"),
  note: z.string().trim().max(200).optional().nullable(),
  date: z.coerce.date(),
  categoryId: z.string().optional().nullable(),
  walletId: z.string().optional().nullable(),
});

export const profileSchema = z.object({
  currency,
  name: z.string().trim().min(1, "Name is required").max(60),
});

// Health and food: the web parses these by hand from FormData; these zod
// versions encode the same rules for JSON input.

const optionalRange = (min: number, max: number, message: string, int = false) =>
  (int ? z.number().int() : z.number()).min(min, message).max(max, message).nullish().transform((v) => v ?? null);

const trimmedNote = z
  .string()
  .nullish()
  .transform((v) => (v && v.trim().length > 0 ? v.trim() : null));

export const healthSchema = z
  .object({
    date: z.coerce.date(),
    weight: optionalRange(1, 500, "Weight looks off (1–500 kg)"),
    systolic: optionalRange(50, 300, "Systolic looks off (50–300)", true),
    diastolic: optionalRange(30, 200, "Diastolic looks off (30–200)", true),
    pulse: optionalRange(20, 250, "Pulse looks off (20–250)", true),
    note: trimmedNote,
  })
  .refine((d) => (d.systolic != null) === (d.diastolic != null), {
    message: "Enter both systolic and diastolic for blood pressure",
  })
  .refine((d) => d.weight != null || d.systolic != null || d.pulse != null, {
    message: "Enter at least one measurement",
  });

/** Public path of a file saved by src/lib/uploads.ts, e.g. /uploads/<uuid>.jpg */
export const UPLOAD_PATH_RE = /^\/uploads\/[A-Za-z0-9-]+\.[a-z]+$/;

export const MEALS = ["breakfast", "lunch", "dinner", "snack"];

export const foodSchema = z.object({
  date: z.coerce.date(),
  name: z.string().trim().min(1, "Name is required").max(120, "Name is too long"),
  // Unknown meal values become null, like the web form.
  meal: z
    .string()
    .nullish()
    .transform((v) => (v && MEALS.includes(v) ? v : null)),
  calories: z
    .number()
    .min(0, "Calories looks off (0–20000)")
    .max(20000, "Calories looks off (0–20000)")
    .nullish()
    .transform((v) => (v == null ? null : Math.round(v))),
  // Only paths returned by our own upload endpoint (also guards file deletion against traversal).
  photoUrl: z
    .string()
    .regex(UPLOAD_PATH_RE, "Invalid photo URL")
    .or(z.literal(""))
    .nullish()
    .transform((v) => (v && v.length > 0 ? v : null)),
  note: trimmedNote,
});
