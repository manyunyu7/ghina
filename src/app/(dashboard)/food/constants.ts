export const MEALS: { value: string; label: string; emoji: string }[] = [
  { value: "breakfast", label: "Breakfast", emoji: "🌅" },
  { value: "lunch", label: "Lunch", emoji: "🍱" },
  { value: "dinner", label: "Dinner", emoji: "🌙" },
  { value: "snack", label: "Snack", emoji: "🍪" },
];

export function mealLabel(value?: string | null): string | null {
  return MEALS.find((m) => m.value === value)?.label ?? null;
}
