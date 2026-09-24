import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Deletes of synced models must go through src/lib/sync-deletes.ts (or the ledger)
  // so mobile clients get a SyncTombstone. See docs/mobile-sync.md.
  {
    files: ["src/**/*.{ts,tsx}"],
    ignores: ["src/lib/sync-deletes.ts", "src/lib/ledger.ts"],
    rules: {
      "no-restricted-syntax": [
        "error",
        {
          selector:
            "CallExpression[callee.property.name=/^delete(Many)?$/][callee.object.property.name=/^(wallet|category|transaction|budget|subscription|plannedTransaction|prayerEntry|healthEntry|foodLog|taskArea|task)$/]",
          message: "Delete synced rows via src/lib/sync-deletes.ts so a SyncTombstone is written.",
        },
      ],
    },
  },
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
  ]),
]);

export default eslintConfig;
