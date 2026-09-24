"use client";

import * as React from "react";
import Link from "next/link";
import { BarChart3, Check, ChevronDown, Copy, ExternalLink, Plus, Send, SkipForward, Trash2, Undo2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Field, Input, Select, Textarea } from "@/components/ui/input";
import {
  CAPTION_MAX,
  captionWithHashtags,
  engagement,
  engagementRate,
  HASHTAGS_MAX,
  hasMetrics,
  METRIC_KEYS,
  METRIC_LABELS,
  needsMetricsPrompt,
  platformInfo,
  platformLabel,
  platformUrl,
  POST_STATUSES,
  type Metrics,
  type PostStatus,
} from "@/lib/content";
import { isHttpUrl } from "@/lib/notes";
import { cn } from "@/lib/utils";
import {
  createContentPost,
  deleteContentPost,
  markPostPosted,
  setPostMetrics,
  setPostSkipped,
  updateContentPost,
} from "./actions";
import { usePlanner } from "./planner";
import {
  AccountAvatar,
  formatDateTime,
  formatNumber,
  formatPercent,
  fromLocalInput,
  handleText,
  PostStatusChip,
  REMIND_OPTIONS,
  stageMovedText,
  toLocalInput,
  useToast,
} from "./ui";
import type { ContentItemDTO, ContentPostDTO, SocialAccountDTO } from "./types";
import { LinkPending } from "@/components/link-pending";

/** "Posting per akun": one variant per target account. */
export function PostsSection({ item }: { item: ContentItemDTO }) {
  const { data, state, accountById, mutate } = usePlanner();
  const toast = useToast();
  const order = new Map(data.accounts.map((a, i) => [a.id, i]));
  const posts = state.posts
    .filter((p) => p.contentId === item.id)
    .sort((a, b) => (order.get(a.accountId) ?? 99) - (order.get(b.accountId) ?? 99));
  const used = new Set(posts.map((p) => p.accountId));
  const addable = data.accounts.filter((a) => !a.archived && !used.has(a.id));
  // Open/closed per post survives the editor remounting after a save.
  const [openIds, setOpenIds] = React.useState<Set<string>>(
    () => new Set(posts.filter((p) => posts.length <= 2 || needsMetricsPrompt(p)).map((p) => p.id)),
  );
  const toggle = (id: string) =>
    setOpenIds((s) => {
      const n = new Set(s);
      if (n.has(id)) n.delete(id);
      else n.add(id);
      return n;
    });

  function add(a: SocialAccountDTO) {
    const now = new Date().toISOString();
    const temp: ContentPostDTO = {
      id: `tmp-${a.id}`,
      createdAt: now,
      updatedAt: now,
      contentId: item.id,
      accountId: a.id,
      caption: "",
      hashtags: "",
      scheduledAt: null,
      remindBefore: null,
      status: "draft",
      postedAt: null,
      url: null,
      metrics: {},
      metricsAt: null,
    };
    mutate(
      (s) => ({ ...s, posts: [...s.posts, temp] }),
      () => createContentPost({ contentId: item.id, accountId: a.id }),
      (r) => {
        setOpenIds((s) => new Set(s).add(r.id));
        toast({ text: `${platformLabel(a)} ditambahkan`, tone: "info" });
      },
    );
  }

  return (
    <section aria-labelledby="content-posts">
      <h3 id="content-posts" className="mb-2 text-sm font-semibold text-foreground">
        Posting per akun
      </h3>
      {data.accounts.filter((a) => !a.archived).length === 0 ? (
        <div className="rounded-lg border border-dashed border-border p-4 text-sm text-muted">
          Tambah akun dulu di{" "}
          <Link href="/content/accounts" className="font-medium text-primary hover:underline">
            Pengaturan
            <LinkPending spinner={false} />
          </Link>{" "}
          supaya konten ini bisa dijadwalkan per akun.
        </div>
      ) : (
        <>
          {posts.length === 0 && <p className="mb-2 text-sm text-muted">Pilih akun tujuan untuk menulis caption dan menjadwalkan tayang.</p>}
          <div className="space-y-3">
            {posts.map((p) => {
              const a = accountById.get(p.accountId);
              return a ? <PostEditor key={`${p.id}:${p.updatedAt}`} post={p} account={a} open={openIds.has(p.id)} onToggle={() => toggle(p.id)} /> : null;
            })}
          </div>
          {addable.length > 0 && (
            <div className="mt-3 flex flex-wrap gap-2">
              {addable.map((a) => (
                <Button key={a.id} type="button" variant="outline" size="sm" onClick={() => add(a)}>
                  <Plus className="h-3.5 w-3.5" />
                  <AccountAvatar account={a} size="sm" className="ring-0" />
                  {platformLabel(a)} {handleText(a.handle)}
                </Button>
              ))}
            </div>
          )}
        </>
      )}
    </section>
  );
}

function PostEditor({ post, account, open, onToggle }: { post: ContentPostDTO; account: SocialAccountDTO; open: boolean; onToggle: () => void }) {
  const { mutate, tz } = usePlanner();
  const toast = useToast();
  const temp = post.id.startsWith("tmp-");
  const promptMetrics = needsMetricsPrompt(post);
  const [caption, setCaption] = React.useState(post.caption);
  const [hashtags, setHashtags] = React.useState(post.hashtags);
  const [when, setWhen] = React.useState(toLocalInput(post.scheduledAt));
  const [remind, setRemind] = React.useState(post.remindBefore == null ? "" : String(post.remindBefore));
  const [status, setStatus] = React.useState<PostStatus>(post.status as PostStatus);
  const [url, setUrl] = React.useState(post.url ?? "");
  const [posting, setPosting] = React.useState(false);
  const [postUrl, setPostUrl] = React.useState("");
  const [showMetrics, setShowMetrics] = React.useState(promptMetrics);
  // Which request is in flight (drives the spinner on the button that started it).
  const [busyOp, setBusyOp] = React.useState<null | "save" | "skip" | "posted" | "metrics">(null);
  const busy = busyOp !== null;

  const dirty =
    caption !== post.caption ||
    hashtags !== post.hashtags ||
    // Compare at input (minute) precision: a time with seconds (e.g. from mobile) isn't a change.
    when !== toLocalInput(post.scheduledAt) ||
    remind !== (post.remindBefore == null ? "" : String(post.remindBefore)) ||
    status !== post.status ||
    url !== (post.url ?? "");

  const info = platformInfo(account.platform);
  const openUrl = platformUrl(info.createUrl, account.handle) ?? platformUrl(info.profileUrl, account.handle);
  const time = post.status === "posted" ? post.postedAt : post.scheduledAt;

  function run<T extends { ok: boolean; error?: string; stage?: string | null }>(
    op: NonNullable<typeof busyOp>,
    action: () => Promise<T>,
    okText: string | null,
    after?: () => void,
  ) {
    if (busy) return;
    setBusyOp(op);
    mutate(
      null,
      async () => {
        try {
          return await action();
        } finally {
          setBusyOp(null);
        }
      },
      (r) => {
        after?.();
        const moved = stageMovedText((r as { stage?: string | null }).stage);
        const text = [okText, moved].filter(Boolean).join(" · ");
        if (text) toast({ text, tone: "success" });
      },
    );
  }

  function save(e: React.FormEvent) {
    e.preventDefault();
    const scheduledAt = when === toLocalInput(post.scheduledAt) ? post.scheduledAt : fromLocalInput(when);
    if (status === "scheduled" && !scheduledAt) return toast({ text: "Isi waktu tayang untuk status Terjadwal", tone: "error" });
    if (url.trim() && !isHttpUrl(url.trim())) return toast({ text: "Link posting harus diawali http:// atau https://", tone: "error" });
    // Picking a time on a draft schedules it.
    const nextStatus: PostStatus = status === "draft" && scheduledAt && post.status === "draft" && !post.scheduledAt ? "scheduled" : status;
    run(
      "save",
      () =>
        updateContentPost(post.id, {
          caption,
          hashtags,
          scheduledAt,
          remindBefore: scheduledAt && remind !== "" ? Number(remind) : null,
          status: nextStatus,
          url: url.trim() || null,
        }),
      "Posting disimpan ✓",
    );
  }

  async function copy() {
    const text = captionWithHashtags({ caption, hashtags });
    if (!text) return toast({ text: "Caption masih kosong", tone: "error" });
    try {
      await navigator.clipboard.writeText(text);
      toast({ text: "Caption + hashtag disalin ✓", tone: "success" });
    } catch {
      toast({ text: "Gagal menyalin — izinkan akses clipboard", tone: "error" });
    }
  }

  function markPosted() {
    const u = postUrl.trim();
    if (u && !isHttpUrl(u)) return toast({ text: "Link posting harus diawali http:// atau https://", tone: "error" });
    run("posted", () => markPostPosted(post.id, u ? { url: u } : {}), "Ditandai sudah tayang 🎉", () => setPosting(false));
  }

  function remove() {
    if (!window.confirm(`Hapus posting ${platformLabel(account)} ${handleText(account.handle)} dari konten ini?`)) return;
    mutate(
      (s) => ({ ...s, posts: s.posts.filter((p) => p.id !== post.id) }),
      () => deleteContentPost(post.id),
    );
  }

  return (
    <div className={cn("rounded-xl border bg-card", promptMetrics ? "border-primary/50" : "border-border", temp && "opacity-60")}>
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={open}
        className="flex w-full items-center gap-2 p-3 text-left"
      >
        <AccountAvatar account={account} status={post.status} />
        <span className="min-w-0 flex-1">
          <span className="block truncate text-sm font-semibold text-foreground">
            {platformLabel(account)} <span className="font-normal text-muted">{handleText(account.handle)}</span>
          </span>
          <span className="flex flex-wrap items-center gap-1.5 text-xs text-muted">
            <PostStatusChip status={post.status} />
            {time && <span>{formatDateTime(time, tz)}</span>}
            {promptMetrics && <span className="rounded-full bg-primary-soft px-1.5 py-0.5 font-semibold text-primary">Isi performa?</span>}
            {hasMetrics(post.metrics) && post.metrics.views != null && <span>{formatNumber(post.metrics.views)} tayangan</span>}
          </span>
        </span>
        <ChevronDown className={cn("h-4 w-4 shrink-0 text-muted transition", open && "rotate-180")} />
      </button>

      {open && !temp && (
        <div className="space-y-3 border-t border-border p-3">
          <form onSubmit={save} className="space-y-3">
            <Field label={`Caption (${caption.length}/${CAPTION_MAX})`}>
              <Textarea value={caption} onChange={(e) => setCaption(e.target.value)} maxLength={CAPTION_MAX} rows={4} placeholder="Tulis caption…" />
            </Field>
            <Field label="Hashtag">
              <Input value={hashtags} onChange={(e) => setHashtags(e.target.value)} maxLength={HASHTAGS_MAX} placeholder="#konten #tips" />
            </Field>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <Field label="Jadwal tayang">
                <Input type="datetime-local" value={when} onChange={(e) => setWhen(e.target.value)} />
              </Field>
              <Field label="Pengingat (aplikasi)">
                <Select value={remind} onChange={(e) => setRemind(e.target.value)} disabled={!when}>
                  {REMIND_OPTIONS.map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="Status">
                <Select value={status} onChange={(e) => setStatus(e.target.value as PostStatus)}>
                  {POST_STATUSES.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.label}
                    </option>
                  ))}
                </Select>
              </Field>
            </div>
            {post.status === "posted" && (
              <Field label="Link posting">
                <Input value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://…" inputMode="url" />
              </Field>
            )}
            <div className="flex flex-wrap items-center gap-2">
              <Button type="submit" size="sm" loading={busyOp === "save"} disabled={!dirty || busy}>
                {busyOp === "save" ? "Menyimpan…" : "Simpan"}
              </Button>
              <Button type="button" variant="outline" size="sm" onClick={copy}>
                <Copy className="h-3.5 w-3.5" /> Salin caption
              </Button>
              {openUrl && (
                <a
                  href={openUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-border bg-surface px-3 text-sm font-medium text-foreground transition hover:bg-accent"
                >
                  <ExternalLink className="h-3.5 w-3.5" /> Buka {platformLabel(account)}
                </a>
              )}
              {post.status !== "posted" && post.status !== "skipped" && (
                <Button type="button" size="sm" variant="secondary" onClick={() => setPosting((v) => !v)} disabled={dirty} title={dirty ? "Simpan dulu" : undefined}>
                  <Send className="h-3.5 w-3.5" /> Sudah tayang
                </Button>
              )}
              {post.status === "posted" && (
                <Button type="button" size="sm" variant={promptMetrics ? "primary" : "secondary"} onClick={() => setShowMetrics((v) => !v)}>
                  <BarChart3 className="h-3.5 w-3.5" /> {hasMetrics(post.metrics) ? "Perbarui performa" : "Isi performa"}
                </Button>
              )}
              <span className="ml-auto flex gap-1">
                {post.status !== "posted" && (
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    loading={busyOp === "skip"}
                    disabled={busy || dirty}
                    onClick={() => run("skip", () => setPostSkipped(post.id, post.status !== "skipped"), post.status === "skipped" ? "Posting diaktifkan lagi" : "Posting dilewati")}
                  >
                    {busyOp === "skip" ? null : post.status === "skipped" ? <Undo2 className="h-3.5 w-3.5" /> : <SkipForward className="h-3.5 w-3.5" />}
                    {post.status === "skipped" ? "Batal lewati" : "Lewati"}
                  </Button>
                )}
                <Button type="button" variant="ghost" size="sm" onClick={remove} aria-label="Hapus posting" className="text-muted hover:text-expense">
                  <Trash2 className="h-3.5 w-3.5" />
                </Button>
              </span>
            </div>
          </form>

          {posting && (
            <div className="flex flex-wrap items-end gap-2 rounded-lg bg-income-soft/60 p-3">
              <Field label="Link posting (opsional)" className="min-w-0 flex-1">
                <Input
                  value={postUrl}
                  onChange={(e) => setPostUrl(e.target.value)}
                  placeholder="Tempel link postingan…"
                  inputMode="url"
                  autoFocus
                  onKeyDown={(e) => e.key === "Enter" && (e.preventDefault(), markPosted())}
                />
              </Field>
              <Button type="button" size="sm" className="h-10" onClick={markPosted} loading={busyOp === "posted"} disabled={busy}>
                {busyOp !== "posted" && <Check className="h-4 w-4" />} {busyOp === "posted" ? "Menyimpan…" : "Tandai tayang"}
              </Button>
            </div>
          )}

          {post.status === "posted" && (
            <div className="text-xs text-muted">
              Tayang {post.postedAt ? formatDateTime(post.postedAt, tz, { year: true }) : "—"}
              {post.url && (
                <>
                  {" · "}
                  <a href={post.url} target="_blank" rel="noopener noreferrer" className="font-medium text-primary hover:underline">
                    Lihat postingan
                  </a>
                </>
              )}
              {hasMetrics(post.metrics) && <MetricsSummary m={post.metrics} />}
            </div>
          )}

          {showMetrics && post.status === "posted" && (
            <MetricsForm post={post} busy={busyOp === "metrics"} onSave={(m) => run("metrics", () => setPostMetrics(post.id, m), "Performa disimpan ✓", () => setShowMetrics(false))} />
          )}
        </div>
      )}
    </div>
  );
}

function MetricsSummary({ m }: { m: Metrics }) {
  const rate = engagementRate(m);
  return (
    <p className="mt-1 flex flex-wrap gap-x-3 gap-y-0.5">
      {METRIC_KEYS.filter((k) => m[k] != null).map((k) => (
        <span key={k}>
          {METRIC_LABELS[k]}: <b className="font-semibold text-foreground">{formatNumber(m[k]!)}</b>
        </span>
      ))}
      <span>
        Engagement: <b className="font-semibold text-foreground">{formatNumber(engagement(m))}</b>
        {rate != null && ` (${formatPercent(rate)})`}
      </span>
    </p>
  );
}

function MetricsForm({ post, busy, onSave }: { post: ContentPostDTO; busy: boolean; onSave: (m: Metrics) => void }) {
  const [vals, setVals] = React.useState<Record<string, string>>(() =>
    Object.fromEntries(METRIC_KEYS.map((k) => [k, post.metrics[k] != null ? String(post.metrics[k]) : ""])),
  );
  const [err, setErr] = React.useState<string | null>(null);

  function submit(e: React.FormEvent) {
    e.preventDefault();
    const m: Metrics = {};
    for (const k of METRIC_KEYS) {
      const v = vals[k].trim();
      if (!v) continue;
      const n = Number(v);
      if (!Number.isInteger(n) || n < 0) return setErr(`${METRIC_LABELS[k]} harus bilangan bulat ≥ 0`);
      m[k] = n;
    }
    setErr(null);
    onSave(m);
  }

  return (
    <form onSubmit={submit} className="rounded-lg bg-accent/60 p-3">
      <p className="mb-2 text-sm font-medium text-foreground">Performa posting</p>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
        {METRIC_KEYS.map((k) => (
          <Field key={k} label={METRIC_LABELS[k]}>
            <Input type="number" min={0} step={1} inputMode="numeric" value={vals[k]} onChange={(e) => setVals((v) => ({ ...v, [k]: e.target.value }))} className="h-9" />
          </Field>
        ))}
      </div>
      {err && (
        <p role="alert" className="mt-2 text-xs text-expense">
          {err}
        </p>
      )}
      <div className="mt-3 flex justify-end">
        <Button type="submit" size="sm" loading={busy}>
          {busy ? "Menyimpan…" : "Simpan performa"}
        </Button>
      </div>
    </form>
  );
}
