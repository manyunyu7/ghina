import type { NoteDTO } from "@/lib/notes-server";
import type { ContentItemDTO, ContentPillarDTO, ContentPostDTO, SocialAccountDTO } from "@/lib/content-server";

export type { ContentItemDTO, ContentPillarDTO, ContentPostDTO, SocialAccountDTO, NoteDTO };

export type WalletOption = { id: string; name: string; currency: string; balance: number };
export type CategoryOption = { id: string; name: string };

/** Everything the /content page needs on first render (calendar + report load client-side). */
export type PlannerData = {
  accounts: SocialAccountDTO[];
  pillars: ContentPillarDTO[];
  items: ContentItemDTO[];
  posts: ContentPostDTO[];
  inbox: NoteDTO[];
  wallets: WalletOption[];
  incomeCategories: CategoryOption[];
  currency: string;
};

export type ContentTab = "papan" | "ide" | "kalender" | "laporan";
export const CONTENT_TABS: { id: ContentTab; label: string }[] = [
  { id: "papan", label: "Papan" },
  { id: "ide", label: "Ide masuk" },
  { id: "kalender", label: "Kalender" },
  { id: "laporan", label: "Laporan" },
];
