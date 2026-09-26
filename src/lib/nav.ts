export type NavItem = {
  href: string;
  label: string;
  icon: string;
  /** Extra words the sidebar filter ("Cari menu") matches, lowercase. */
  keywords?: readonly string[];
  /** Rendered indented under the previous item (e.g. Laporan Shalat under Sholat). */
  sub?: boolean;
};

export type NavSection = {
  id: string;
  /** Uppercase header; null = ungrouped (always shown, not collapsible). */
  label: string | null;
  items: readonly NavItem[];
};

export const NAV_SECTIONS: readonly NavSection[] = [
  {
    id: "top",
    label: null,
    items: [{ href: "/dashboard", label: "Dashboard", icon: "LayoutDashboard", keywords: ["beranda", "home", "ringkasan"] }],
  },
  {
    id: "uang",
    label: "Uang",
    items: [
      { href: "/transactions", label: "Transaksi", icon: "ArrowLeftRight", keywords: ["transactions", "pengeluaran", "pemasukan", "belanja", "expense", "income", "mutasi"] },
      { href: "/wallets", label: "Dompet", icon: "Wallet", keywords: ["wallets", "uang", "saldo", "rekening", "bank", "akun", "kas", "e-wallet"] },
      { href: "/budgets", label: "Budget", icon: "Target", keywords: ["budgets", "anggaran", "batas"] },
      { href: "/subscriptions", label: "Langganan", icon: "Repeat", keywords: ["subscriptions", "tagihan", "berulang", "netflix", "spotify", "bill"] },
      { href: "/forecast", label: "Proyeksi", icon: "TrendingUp", keywords: ["forecast", "prediksi", "ramalan", "perkiraan"] },
      { href: "/reports", label: "Laporan", icon: "PieChart", keywords: ["reports", "statistik", "grafik", "analisis", "chart"] },
      { href: "/investments", label: "Investasi", icon: "LineChart", keywords: ["investments", "saham", "reksadana", "reksa dana", "emas", "crypto", "kripto", "portofolio", "obligasi", "stock"] },
      { href: "/categories", label: "Kategori", icon: "Tags", keywords: ["categories", "label", "tag"] },
    ],
  },
  {
    id: "hidup",
    label: "Hidup",
    items: [
      { href: "/prayers", label: "Sholat", icon: "Moon", keywords: ["prayers", "salat", "shalat", "solat", "sembahyang", "ibadah", "prayer"] },
      { href: "/prayers/report", label: "Laporan Shalat", icon: "BarChart3", keywords: ["prayer report", "salat", "sholat", "solat", "rekap"], sub: true },
      { href: "/habits", label: "Kebiasaan", icon: "Flame", keywords: ["habits", "habit", "rutinitas", "streak"] },
      { href: "/health", label: "Kesehatan", icon: "HeartPulse", keywords: ["health", "berat", "tidur", "olahraga", "langkah", "sehat"] },
      { href: "/food", label: "Makanan", icon: "Utensils", keywords: ["food log", "food", "makan", "kalori", "minum", "diet"] },
    ],
  },
  {
    id: "produktif",
    label: "Produktif",
    items: [
      { href: "/tasks", label: "Tugas", icon: "ListTodo", keywords: ["tasks", "todo", "to-do", "pekerjaan", "kerjaan"] },
      { href: "/notes", label: "Catatan", icon: "StickyNote", keywords: ["notes", "note", "memo", "jurnal"] },
      { href: "/content", label: "Konten", icon: "Clapperboard", keywords: ["content", "video", "youtube", "tiktok", "ide", "posting"] },
    ],
  },
  {
    id: "lainnya",
    label: "Lainnya",
    items: [{ href: "/settings", label: "Pengaturan", icon: "Settings", keywords: ["settings", "setelan", "profil", "akun", "password", "tema"] }],
  },
];

/** Flat list (all sections, in order). */
export const NAV_ITEMS: readonly NavItem[] = NAV_SECTIONS.flatMap((s) => s.items);

/** Collapsed nav sections: cookie (read by the server layout → no flicker) + localStorage (durable copy). */
export const NAV_COLLAPSED_COOKIE = "ghina_nav_collapsed";
export const NAV_COLLAPSED_STORAGE_KEY = "ghina.navCollapsed";

export function parseCollapsed(value: string | null | undefined): string[] {
  if (!value) return [];
  const ids = new Set(NAV_SECTIONS.filter((s) => s.label).map((s) => s.id));
  return value.split(/[.,]/).filter((id) => ids.has(id));
}

/** The href of the nav item for [pathname]; most specific match wins (/prayers/report beats /prayers). */
export function activeNavHref(pathname: string): string | null {
  let best: string | null = null;
  for (const { href } of NAV_ITEMS) {
    if ((pathname === href || pathname.startsWith(href + "/")) && (!best || href.length > best.length)) best = href;
  }
  return best;
}

const normalize = (s: string) =>
  s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();

/** Filter match on label + keywords (every word of the query must hit one of them). */
export function navItemMatches(item: NavItem, query: string): boolean {
  const q = normalize(query);
  if (!q) return true;
  const hay = [item.label, ...(item.keywords ?? [])].map(normalize);
  return q.split(/\s+/).every((word) => hay.some((h) => h.includes(word)));
}
