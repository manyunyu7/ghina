"use client";

import * as React from "react";
import { Archive, ArchiveRestore, Pencil, Plus, Trash2, UserPlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Field, Input } from "@/components/ui/input";
import { Modal } from "@/components/ui/modal";
import { EmptyState, PageHeader } from "@/components/ui/misc";
import { SavingHint } from "@/components/ui/saving-hint";
import {
  HANDLE_MAX,
  PILLAR_NAME_MAX,
  PLATFORM_NAME_MAX,
  PLATFORMS,
  platformInfo,
  platformLabel,
  TARGET_PER_WEEK_MAX,
  type PlatformId,
} from "@/lib/content";
import { cn } from "@/lib/utils";
import {
  createContentPillar,
  createSocialAccount,
  deleteContentPillar,
  deleteSocialAccount,
  reorderContentPillars,
  reorderSocialAccounts,
  updateContentPillar,
  updateSocialAccount,
} from "../actions";
import { ContentNav } from "../content-nav";
import { AccountAvatar, handleText, MoveButtons, PlatformIcon, runSafe, ToastProvider, useToast } from "../ui";
import type { ContentPillarDTO, SocialAccountDTO } from "../types";

const SWATCHES = ["#58CC02", "#1CB0F6", "#FF9600", "#FF4B4B", "#CE82FF", "#FFC800", "#2B70C9", "#FF86D0", "#00C2A8", "#8E8E93"];

type Props = {
  accounts: SocialAccountDTO[];
  pillars: ContentPillarDTO[];
  postCounts: Record<string, number>;
  pillarUse: Record<string, number>;
};

export function ContentSettings(props: Props) {
  return (
    <ToastProvider>
      <PageHeader title="Konten" description="Akun sosial media dan pilar konten." />
      <ContentNav active="pengaturan" />
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Accounts {...props} />
        <Pillars {...props} />
      </div>
    </ToastProvider>
  );
}

/** Run an action; toast the error; returns ok. */
function useRunner() {
  const toast = useToast();
  const [pending, start] = React.useTransition();
  const run = React.useCallback(
    (action: () => Promise<{ ok: boolean; error?: string }>, okText?: string, after?: () => void) =>
      start(async () => {
        const r = await runSafe(action);
        if (r.ok) {
          after?.();
          if (okText) toast({ text: okText, tone: "success" });
        } else toast({ text: r.error ?? "Terjadi kesalahan", tone: "error" });
      }),
    [toast],
  );
  return { run, pending };
}

// ---------- Accounts ----------

function Accounts({ accounts, postCounts }: Props) {
  const { run, pending } = useRunner();
  const [editing, setEditing] = React.useState<SocialAccountDTO | "new" | null>(null);
  const live = accounts.filter((a) => !a.archived);
  const archived = accounts.filter((a) => a.archived);

  function reorder(id: string, dir: -1 | 1) {
    const ids = live.map((a) => a.id);
    const i = ids.indexOf(id);
    const j = i + dir;
    if (j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j], ids[i]];
    run(() => reorderSocialAccounts([...ids, ...archived.map((a) => a.id)]));
  }

  function remove(a: SocialAccountDTO) {
    const n = postCounts[a.id] ?? 0;
    const msg = `Hapus akun ${platformLabel(a)} ${handleText(a.handle)}?${n ? ` ${n} posting untuk akun ini ikut terhapus (kontennya tetap ada).` : ""}\n\nTips: arsipkan saja jika hanya ingin menyembunyikannya.`;
    if (!window.confirm(msg)) return;
    run(() => deleteSocialAccount(a.id), "Akun dihapus");
  }

  const row = (a: SocialAccountDTO, i: number, list: SocialAccountDTO[]) => (
    <li key={a.id} className={cn("flex items-center gap-3 py-3 first:pt-0 last:pb-0", a.archived && "opacity-60")}>
      <AccountAvatar account={a} size="lg" />
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-semibold text-foreground">
          {platformLabel(a)} <span className="font-normal text-muted">{handleText(a.handle)}</span>
        </p>
        <p className="text-xs text-muted">
          {a.targetPerWeek ? `Target ${a.targetPerWeek}× / minggu` : "Tanpa target"} · {postCounts[a.id] ?? 0} posting
        </p>
      </div>
      {!a.archived && (
        <MoveButtons label={a.handle} onUp={() => reorder(a.id, -1)} onDown={() => reorder(a.id, 1)} upDisabled={pending || i === 0} downDisabled={pending || i === list.length - 1} />
      )}
      <Button variant="ghost" size="icon" aria-label={`Ubah ${a.handle}`} onClick={() => setEditing(a)}>
        <Pencil className="h-4 w-4" />
      </Button>
      <Button
        variant="ghost"
        size="icon"
        aria-label={a.archived ? `Aktifkan lagi ${a.handle}` : `Arsipkan ${a.handle}`}
        title={a.archived ? "Aktifkan lagi" : "Arsipkan (sembunyikan dari papan & kalender)"}
        onClick={() => run(() => updateSocialAccount(a.id, { archived: !a.archived }), a.archived ? "Akun aktif lagi" : "Akun diarsipkan")}
        disabled={pending}
      >
        {a.archived ? <ArchiveRestore className="h-4 w-4" /> : <Archive className="h-4 w-4" />}
      </Button>
      <Button variant="ghost" size="icon" aria-label={`Hapus ${a.handle}`} className="hover:text-expense" onClick={() => remove(a)} disabled={pending}>
        <Trash2 className="h-4 w-4" />
      </Button>
    </li>
  );

  return (
    <Card className="min-w-0">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          Akun <SavingHint pending={pending} />
        </CardTitle>
        <Button size="sm" onClick={() => setEditing("new")}>
          <Plus className="h-4 w-4" /> Tambah akun
        </Button>
      </CardHeader>
      <CardContent>
        {accounts.length === 0 ? (
          <EmptyState
            icon={UserPlus}
            title="Tambah akun dulu"
            description="Daftarkan akun yang kamu kelola (Instagram, TikTok, YouTube, …) beserta target posting per minggu."
            action={
              <Button onClick={() => setEditing("new")}>
                <Plus className="h-4 w-4" /> Tambah akun
              </Button>
            }
          />
        ) : (
          <>
            <ul className="divide-y divide-border">{live.map(row)}</ul>
            {archived.length > 0 && (
              <>
                <p className="mb-2 mt-5 text-xs font-medium uppercase tracking-wide text-muted-soft">Diarsipkan</p>
                <ul className="divide-y divide-border">{archived.map(row)}</ul>
              </>
            )}
          </>
        )}
      </CardContent>
      {editing && <AccountDialog account={editing === "new" ? null : editing} onClose={() => setEditing(null)} />}
    </Card>
  );
}

function AccountDialog({ account, onClose }: { account: SocialAccountDTO | null; onClose: () => void }) {
  const { run, pending } = useRunner();
  const [platform, setPlatform] = React.useState<PlatformId>((account?.platform as PlatformId) ?? "instagram");
  const [platformName, setPlatformName] = React.useState(account?.platformName ?? "");
  const [handle, setHandle] = React.useState(account?.handle ?? "");
  const [color, setColor] = React.useState<string | null>(account?.color ?? null);
  const [target, setTarget] = React.useState(account?.targetPerWeek ? String(account.targetPerWeek) : "");
  const [error, setError] = React.useState<string | null>(null);
  const effColor = color ?? platformInfo(platform).color;

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!handle.trim()) return setError("Username wajib diisi");
    if (platform === "other" && !platformName.trim()) return setError("Isi nama platform");
    const t = target.trim() ? Number(target) : 0;
    if (!Number.isInteger(t) || t < 0 || t > TARGET_PER_WEEK_MAX) return setError(`Target per minggu 0–${TARGET_PER_WEEK_MAX}`);
    setError(null);
    const input = {
      platform,
      platformName: platform === "other" ? platformName.trim() : null,
      handle: handle.trim(),
      color: effColor,
      targetPerWeek: t || null,
    };
    run(() => (account ? updateSocialAccount(account.id, input) : createSocialAccount(input)), account ? "Akun disimpan ✓" : "Akun ditambahkan ✓", onClose);
  }

  return (
    <Modal open onClose={onClose} title={account ? "Ubah akun" : "Tambah akun"} className="sm:max-w-lg">
      <form onSubmit={submit} className="space-y-4">
        <fieldset>
          <legend className="mb-1.5 text-sm font-medium text-foreground">Platform</legend>
          <div className="grid grid-cols-4 gap-2" role="radiogroup">
            {PLATFORMS.map((p) => (
              <button
                key={p.id}
                type="button"
                role="radio"
                aria-checked={platform === p.id}
                onClick={() => {
                  setPlatform(p.id);
                  if (!account || color === platformInfo(platform).color) setColor(null);
                }}
                className={cn(
                  "flex flex-col items-center gap-1 rounded-lg border p-2 text-[11px] font-medium transition",
                  platform === p.id ? "border-primary bg-primary-soft text-foreground" : "border-border text-muted hover:bg-accent",
                )}
              >
                <span className="flex h-8 w-8 items-center justify-center rounded-full text-white" style={{ background: p.color }}>
                  <PlatformIcon platform={p.id} className="h-4 w-4" />
                </span>
                <span className="w-full truncate text-center">{p.label}</span>
              </button>
            ))}
          </div>
        </fieldset>
        {platform === "other" && (
          <Field label="Nama platform">
            <Input value={platformName} onChange={(e) => setPlatformName(e.target.value)} maxLength={PLATFORM_NAME_MAX} placeholder="mis. Pinterest" />
          </Field>
        )}
        <Field label="Username / nama channel">
          <Input value={handle} onChange={(e) => setHandle(e.target.value)} maxLength={HANDLE_MAX} placeholder="@namakamu" autoFocus={!account} />
        </Field>
        <Field label="Target posting per minggu">
          <Input type="number" min={0} max={TARGET_PER_WEEK_MAX} step={1} value={target} onChange={(e) => setTarget(e.target.value)} placeholder="mis. 3 (kosong = tanpa target)" />
        </Field>
        <fieldset>
          <legend className="mb-1.5 text-sm font-medium text-foreground">Warna</legend>
          <div className="flex flex-wrap items-center gap-2">
            {[platformInfo(platform).color, ...SWATCHES.filter((s) => s !== platformInfo(platform).color)].map((c, i) => (
              <button
                key={c}
                type="button"
                onClick={() => setColor(i === 0 ? null : c)}
                aria-label={i === 0 ? `Warna bawaan ${platformInfo(platform).label}` : `Warna ${c}`}
                aria-pressed={effColor.toLowerCase() === c.toLowerCase()}
                className={cn("h-7 w-7 rounded-full ring-offset-2 ring-offset-card transition", effColor.toLowerCase() === c.toLowerCase() && "ring-2 ring-foreground")}
                style={{ background: c }}
              />
            ))}
            <label className="ml-1 inline-flex items-center gap-1 text-xs text-muted">
              <input type="color" value={effColor} onChange={(e) => setColor(e.target.value)} className="h-7 w-9 cursor-pointer rounded border border-border bg-transparent" aria-label="Warna kustom" />
              Kustom
            </label>
          </div>
        </fieldset>
        <div className="flex items-center gap-3 rounded-lg bg-accent/60 p-3">
          <AccountAvatar account={{ platform, platformName, color: effColor, handle: handle || "akun" }} size="lg" />
          <p className="text-sm text-foreground">
            {platform === "other" ? platformName || "Lainnya" : platformInfo(platform).label}{" "}
            <span className="text-muted">{handleText(handle || "akun")}</span>
          </p>
        </div>
        {error && (
          <p role="alert" className="text-sm text-expense">
            {error}
          </p>
        )}
        <div className="flex justify-end gap-2">
          <Button type="button" variant="ghost" onClick={onClose}>
            Batal
          </Button>
          <Button type="submit" loading={pending}>
            {pending ? "Menyimpan…" : "Simpan"}
          </Button>
        </div>
      </form>
    </Modal>
  );
}

// ---------- Pillars ----------

function Pillars({ pillars, pillarUse }: Props) {
  const { run, pending } = useRunner();
  const [name, setName] = React.useState("");
  const [color, setColor] = React.useState(SWATCHES[1]);
  const uses = (n: string) => pillarUse[n.toLocaleLowerCase("id-ID")] ?? 0;

  function reorder(id: string, dir: -1 | 1) {
    const ids = pillars.map((p) => p.id);
    const i = ids.indexOf(id);
    const j = i + dir;
    if (j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j], ids[i]];
    run(() => reorderContentPillars(ids));
  }

  function remove(p: ContentPillarDTO) {
    const n = uses(p.name);
    if (!window.confirm(`Hapus pilar “${p.name}”?${n ? ` ${n} konten memakai pilar ini — pilarnya akan dikosongkan.` : ""}`)) return;
    run(() => deleteContentPillar(p.id), "Pilar dihapus");
  }

  return (
    <Card className="min-w-0">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          Pilar konten <SavingHint pending={pending} />
        </CardTitle>
      </CardHeader>
      <CardContent>
        <p className="-mt-2 mb-3 text-xs text-muted">Tema besar kontenmu (mis. Edukasi, Hiburan, Promo). Dipakai untuk filter dan laporan keseimbangan.</p>
        {pillars.length === 0 && <p className="mb-3 text-sm text-muted">Belum ada pilar.</p>}
        <ul className="space-y-2">
          {pillars.map((p, i) => (
            <PillarRow
              key={`${p.id}:${p.updatedAt}`}
              pillar={p}
              uses={uses(p.name)}
              pending={pending}
              onRename={(newName) => {
                const n = uses(p.name);
                if (n && !window.confirm(`Ganti nama “${p.name}” menjadi “${newName}”? ${n} konten ikut diperbarui.`)) return false;
                run(() => updateContentPillar(p.id, { name: newName }), "Pilar diganti nama");
                return true;
              }}
              onColor={(c) => run(() => updateContentPillar(p.id, { color: c }))}
              onDelete={() => remove(p)}
              move={
                <MoveButtons label={p.name} onUp={() => reorder(p.id, -1)} onDown={() => reorder(p.id, 1)} upDisabled={pending || i === 0} downDisabled={pending || i === pillars.length - 1} />
              }
            />
          ))}
        </ul>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (!name.trim()) return;
            run(() => createContentPillar({ name: name.trim(), color }), "Pilar ditambahkan ✓", () => setName(""));
          }}
          className="mt-4 flex items-center gap-2"
        >
          <input type="color" value={color} onChange={(e) => setColor(e.target.value)} aria-label="Warna pilar baru" className="h-10 w-10 shrink-0 cursor-pointer rounded-lg border border-border bg-transparent p-1" />
          <Input value={name} onChange={(e) => setName(e.target.value)} maxLength={PILLAR_NAME_MAX} placeholder="Pilar baru…" aria-label="Nama pilar baru" />
          <Button type="submit" disabled={pending || !name.trim()}>
            <Plus className="h-4 w-4" /> Tambah
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}

function PillarRow({
  pillar,
  uses,
  pending,
  onRename,
  onColor,
  onDelete,
  move,
}: {
  pillar: ContentPillarDTO;
  uses: number;
  pending: boolean;
  onRename: (name: string) => boolean;
  onColor: (c: string) => void;
  onDelete: () => void;
  move: React.ReactNode;
}) {
  const [name, setName] = React.useState(pillar.name);
  const commit = () => {
    const n = name.trim();
    if (!n || n === pillar.name) return setName(pillar.name);
    if (!onRename(n)) setName(pillar.name);
  };
  return (
    <li className="flex items-center gap-2">
      <ColorInput value={pillar.color} onCommit={onColor} label={`Warna ${pillar.name}`} />
      <input
        value={name}
        onChange={(e) => setName(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === "Enter") (e.target as HTMLInputElement).blur();
          if (e.key === "Escape") setName(pillar.name);
        }}
        maxLength={PILLAR_NAME_MAX}
        aria-label={`Nama pilar ${pillar.name}`}
        className="h-9 min-w-0 flex-1 rounded-md border border-transparent bg-transparent px-2 text-sm font-medium outline-none hover:border-border focus:border-primary"
      />
      <span className="shrink-0 text-xs text-muted">{uses} konten</span>
      {move}
      <Button variant="ghost" size="icon" aria-label={`Hapus pilar ${pillar.name}`} onClick={onDelete} disabled={pending} className="hover:text-expense">
        <Trash2 className="h-4 w-4" />
      </Button>
    </li>
  );
}

/** Color picker that commits on the native `change` event (not on every drag step). */
function ColorInput({ value, onCommit, label }: { value: string; onCommit: (c: string) => void; label: string }) {
  const ref = React.useRef<HTMLInputElement>(null);
  const commit = React.useRef(onCommit);
  React.useEffect(() => {
    commit.current = onCommit;
  }, [onCommit]);
  React.useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const on = () => el.value.toLowerCase() !== value.toLowerCase() && commit.current(el.value);
    el.addEventListener("change", on);
    return () => el.removeEventListener("change", on);
  }, [value]);
  return (
    <input
      ref={ref}
      type="color"
      defaultValue={value}
      aria-label={label}
      className="h-8 w-8 shrink-0 cursor-pointer rounded-md border border-border bg-transparent p-0.5"
    />
  );
}
