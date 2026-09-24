"use client";

import * as React from "react";
import Link from "next/link";
import { Plus, UserPlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/ui/misc";
import type { StageId } from "@/lib/content";
import { ContentNav } from "./content-nav";
import { Board } from "./board";
import { IdeaInbox } from "./idea-inbox";
import { ContentCalendar } from "./calendar";
import { ContentReportView } from "./report";
import { ItemDialog } from "./item-dialog";
import { runSafe, ToastProvider, useHydrated, useTimeZone, useToast } from "./ui";
import type { ContentItemDTO, ContentPostDTO, ContentTab, PlannerData, SocialAccountDTO } from "./types";
import { LinkPendingIcon } from "@/components/link-pending";
import { SavingHint } from "@/components/ui/saving-hint";

type State = { items: ContentItemDTO[]; posts: ContentPostDTO[] };
type Mutator = <T extends { ok: boolean; error?: string }>(
  optimistic: ((s: State) => State) | null,
  action: () => Promise<T>,
  onOk?: (r: Extract<T, { ok: true }>) => void,
) => void;

export type DialogTarget = { mode: "edit"; id: string } | { mode: "create"; stage: StageId };

type Ctx = {
  data: PlannerData;
  state: State;
  accountById: Map<string, SocialAccountDTO>;
  tz: string;
  mutate: Mutator;
  openItem: (t: DialogTarget) => void;
  /** Bumped after each successful mutation — the calendar/report refetch on it. */
  version: number;
};

const PlannerContext = React.createContext<Ctx | null>(null);
export function usePlanner(): Ctx {
  const c = React.useContext(PlannerContext);
  if (!c) throw new Error("usePlanner outside ContentPlanner");
  return c;
}

export function ContentPlanner(props: { data: PlannerData; initialTab: ContentTab; initialItemId: string | null }) {
  return (
    <ToastProvider>
      <Planner {...props} />
    </ToastProvider>
  );
}

function Planner({ data, initialTab, initialItemId }: { data: PlannerData; initialTab: ContentTab; initialItemId: string | null }) {
  const tz = useTimeZone();
  // Dialog forms use the browser zone (datetime-local): never server-render them.
  const hydrated = useHydrated();
  const toast = useToast();
  const [tab, setTab] = React.useState<ContentTab>(initialTab);
  const [dialog, setDialog] = React.useState<DialogTarget | null>(
    initialItemId && data.items.some((i) => i.id === initialItemId) ? { mode: "edit", id: initialItemId } : null,
  );
  const [version, setVersion] = React.useState(0);

  const base = React.useMemo<State>(() => ({ items: data.items, posts: data.posts }), [data.items, data.posts]);
  const [state, addOptimistic] = React.useOptimistic(base, (s: State, fn: (s: State) => State) => fn(s));
  const [saving, startTransition] = React.useTransition();

  const accountById = React.useMemo(() => new Map(data.accounts.map((a) => [a.id, a])), [data.accounts]);

  const mutate = React.useCallback<Mutator>(
    (optimistic, action, onOk) => {
      startTransition(async () => {
        if (optimistic) addOptimistic(optimistic);
        const res = await runSafe(action);
        if (res.ok) {
          setVersion((v) => v + 1);
          onOk?.(res as never);
        } else toast({ text: res.error ?? "Terjadi kesalahan", tone: "error" });
      });
    },
    [addOptimistic, toast],
  );

  function selectTab(t: ContentTab) {
    setTab(t);
    const url = t === "papan" ? "/content" : `/content?tab=${t}`;
    window.history.replaceState(null, "", url);
  }

  function closeDialog() {
    setDialog(null);
    // A deep link (?item=…) must not reopen the dialog on reload / back.
    const url = new URL(window.location.href);
    if (url.searchParams.has("item")) {
      url.searchParams.delete("item");
      window.history.replaceState(null, "", url.pathname + url.search);
    }
  }

  const ctx: Ctx = { data, state, accountById, tz, mutate, openItem: setDialog, version };
  const hasAccounts = data.accounts.some((a) => !a.archived);

  return (
    <PlannerContext.Provider value={ctx}>
      <PageHeader
        title="Konten"
        description="Rencanakan, jadwalkan, dan pantau postingan akun sosial mediamu."
        action={
          <div className="flex items-center gap-2">
            <SavingHint pending={saving} />
            <Button onClick={() => setDialog({ mode: "create", stage: "ide" })}>
              <Plus className="h-4 w-4" /> Konten baru
            </Button>
          </div>
        }
      />
      <ContentNav active={tab} onSelect={selectTab} inboxCount={data.inbox.length} />

      {!hasAccounts && (
        <div className="mb-5 flex flex-wrap items-center gap-3 rounded-card border border-dashed border-primary/40 bg-primary-soft/50 p-4 text-sm">
          <UserPlus className="h-5 w-5 shrink-0 text-primary" />
          <p className="min-w-0 flex-1 text-foreground">
            <span className="font-semibold">Tambah akun dulu.</span> Daftarkan akun Instagram, TikTok, YouTube, dll. supaya konten bisa
            dijadwalkan per akun dan punya target mingguan.
          </p>
          <Link href="/content/accounts">
            <Button size="sm">
              <LinkPendingIcon /> Tambah akun
            </Button>
          </Link>
        </div>
      )}

      {tab === "papan" && <Board />}
      {tab === "ide" && <IdeaInbox />}
      {tab === "kalender" && <ContentCalendar />}
      {tab === "laporan" && <ContentReportView />}

      {dialog && hydrated && <ItemDialog key={dialog.mode === "edit" ? dialog.id : "new"} target={dialog} onClose={closeDialog} onCreated={(id) => setDialog({ mode: "edit", id })} />}
    </PlannerContext.Provider>
  );
}
