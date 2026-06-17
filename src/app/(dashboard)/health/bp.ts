export type BpCategory = {
  label: string;
  className: string; // pill styling
  color: string; // hex, for charts/accents
};

/** Classify blood pressure using the common AHA categories. */
export function classifyBP(systolic?: number | null, diastolic?: number | null): BpCategory | null {
  if (systolic == null || diastolic == null) return null;

  if (systolic >= 180 || diastolic >= 120)
    return { label: "Hypertensive crisis", className: "bg-expense-soft text-expense", color: "#dc2626" };
  if (systolic >= 140 || diastolic >= 90)
    return { label: "High · Stage 2", className: "bg-expense-soft text-expense", color: "#ef4444" };
  if (systolic >= 130 || diastolic >= 80)
    return { label: "High · Stage 1", className: "bg-amber-100 text-amber-700", color: "#f59e0b" };
  if (systolic >= 120)
    return { label: "Elevated", className: "bg-amber-100 text-amber-700", color: "#f59e0b" };
  return { label: "Normal", className: "bg-income-soft text-income", color: "#16a34a" };
}
