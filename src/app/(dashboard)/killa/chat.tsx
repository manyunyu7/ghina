"use client";

import * as React from "react";
import { AlertTriangle, Bot, RotateCcw, Send } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Select, Textarea } from "@/components/ui/input";
import { EmptyState } from "@/components/ui/misc";
import { SavingHint } from "@/components/ui/saving-hint";
import type { KillaMessageDTO } from "@/lib/killa";
import { KILLA_MODELS, KILLA_TEXT_MAX, type KillaModel } from "@/lib/schemas";
import { cn } from "@/lib/utils";
import { Markdown } from "../notes/markdown";
import { loadOlderKillaMessages, newKillaSession, sendKillaChat } from "./actions";

const MODEL_LABELS: Record<KillaModel, string> = {
  default: "Default",
  fable: "Fable",
  opus: "Opus",
  sonnet: "Sonnet",
  haiku: "Haiku",
};

const timeFmt = new Intl.DateTimeFormat("id-ID", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

/**
 * The Killa chat: recorded history (newest page from the server, older pages loaded on
 * demand), a composer and the "sesi baru" button. A reply can take minutes, so the sent
 * message shows optimistically with a "Killa sedang mengerjakan…" bubble until it lands.
 */
export function KillaChat({ messages, nextBefore }: { messages: KillaMessageDTO[]; nextBefore: string | null }) {
  // Every message seen so far (server pages merged by id), so a revalidated newest page
  // never drops messages that were shown before or loaded via "Muat pesan lama".
  const [known, setKnown] = React.useState(messages);
  const [prevMessages, setPrevMessages] = React.useState(messages);
  if (messages !== prevMessages) {
    setPrevMessages(messages);
    setKnown((k) => mergeMessages(k, messages));
  }
  const [cursor, setCursor] = React.useState(nextBefore);
  const [loadingOlder, setLoadingOlder] = React.useState(false);
  const [all, addOptimistic] = React.useOptimistic(known, (s: KillaMessageDTO[], m: KillaMessageDTO) => [...s, m]);
  const [sending, startSend] = React.useTransition();
  const [resetting, startReset] = React.useTransition();
  const [text, setText] = React.useState("");
  const [model, setModel] = React.useState<KillaModel>("default");
  const [error, setError] = React.useState<string | null>(null);
  const bottomRef = React.useRef<HTMLDivElement>(null);
  const listRef = React.useRef<HTMLDivElement>(null);

  const lastId = all.at(-1)?.id;

  React.useEffect(() => {
    bottomRef.current?.scrollIntoView({ block: "end" });
  }, [lastId, sending]);

  function send() {
    const body = text.trim();
    if (!body || sending) return;
    setError(null);
    setText("");
    startSend(async () => {
      addOptimistic({
        id: `pending-${Date.now()}`,
        role: "user",
        body,
        model: model === "default" ? null : model,
        createdAt: new Date().toISOString(),
      });
      try {
        const res = await sendKillaChat({ text: body, model });
        if (res.ok) setKnown((k) => mergeMessages(k, [res.userMessage, res.reply]));
        else setError(res.error);
      } catch {
        setError("Koneksi terputus. Balasan mungkin tetap tersimpan — muat ulang halaman nanti.");
      }
    });
  }

  function reset() {
    setError(null);
    startReset(async () => {
      const res = await newKillaSession().catch(() => ({ ok: false as const, error: "Terjadi kesalahan, coba lagi" }));
      if (!res.ok) setError(res.error);
    });
  }

  async function loadOlder() {
    if (!cursor) return;
    setLoadingOlder(true);
    const list = listRef.current;
    const prevHeight = list?.scrollHeight ?? 0;
    const res = await loadOlderKillaMessages(cursor).catch(() => null);
    setLoadingOlder(false);
    if (!res?.ok) {
      setError(res?.error ?? "Gagal memuat pesan lama");
      return;
    }
    setKnown((k) => mergeMessages(k, res.messages));
    setCursor(res.nextBefore);
    // Keep the view anchored on the message that was at the top.
    requestAnimationFrame(() => {
      if (list) list.scrollTop += list.scrollHeight - prevHeight;
    });
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <label htmlFor="killa-model" className="text-sm font-medium text-muted">
            Model
          </label>
          <Select
            id="killa-model"
            value={model}
            onChange={(e) => setModel(e.target.value as KillaModel)}
            className="h-9 w-32"
            disabled={sending}
          >
            {KILLA_MODELS.map((m) => (
              <option key={m} value={m}>
                {MODEL_LABELS[m]}
              </option>
            ))}
          </Select>
        </div>
        <div className="flex items-center gap-2">
          <SavingHint pending={resetting} label="Memulai sesi…" />
          <Button variant="outline" size="sm" onClick={reset} loading={resetting} disabled={sending}>
            {!resetting && <RotateCcw className="h-4 w-4" />} Sesi baru
          </Button>
        </div>
      </div>

      <Card className="overflow-hidden">
        <div ref={listRef} className="max-h-[60vh] min-h-64 space-y-3 overflow-y-auto p-4">
          {cursor && (
            <div className="flex justify-center">
              <Button variant="ghost" size="sm" onClick={loadOlder} loading={loadingOlder}>
                Muat pesan lama
              </Button>
            </div>
          )}
          {all.length === 0 && !sending ? (
            <EmptyState icon={Bot} title="Belum ada percakapan" description="Tulis pesan untuk mulai ngobrol dengan Killa." />
          ) : (
            all.map((m) => <MessageRow key={m.id} m={m} />)
          )}
          {sending && <ThinkingBubble />}
          <div ref={bottomRef} />
        </div>
      </Card>

      {error && (
        <div role="alert" className="flex items-start gap-2 rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      <form
        onSubmit={(e) => {
          e.preventDefault();
          send();
        }}
        className="flex items-end gap-2"
      >
        <Textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
              e.preventDefault();
              send();
            }
          }}
          placeholder="Tulis pesan untuk Killa… (Enter kirim, Shift+Enter baris baru)"
          maxLength={KILLA_TEXT_MAX}
          rows={2}
          className="max-h-60 min-h-11 flex-1 resize-y"
          aria-label="Pesan"
        />
        <Button type="submit" size="icon" className="h-11 w-11" loading={sending} disabled={!text.trim()} aria-label="Kirim">
          <Send className="h-4 w-4" />
        </Button>
      </form>
    </div>
  );
}

function mergeMessages(a: KillaMessageDTO[], b: KillaMessageDTO[]): KillaMessageDTO[] {
  const byId = new Map(a.map((m) => [m.id, m]));
  for (const m of b) byId.set(m.id, m);
  return [...byId.values()].sort((x, y) => x.createdAt.localeCompare(y.createdAt) || x.id.localeCompare(y.id));
}

function MessageRow({ m }: { m: KillaMessageDTO }) {
  const time = timeFmt.format(new Date(m.createdAt));
  if (m.role === "system") {
    return (
      <div className="flex items-center gap-3 py-1 text-xs font-medium text-muted">
        <div className="h-px flex-1 bg-border" />
        <span>
          {m.body} · {time}
        </span>
        <div className="h-px flex-1 bg-border" />
      </div>
    );
  }
  const me = m.role === "user";
  return (
    <div className={cn("flex", me ? "justify-end" : "justify-start")}>
      <div
        className={cn(
          "max-w-[85%] rounded-2xl px-3.5 py-2.5",
          me ? "rounded-br-md bg-primary text-white" : "rounded-bl-md bg-accent text-foreground",
          m.id.startsWith("pending-") && "opacity-70",
        )}
      >
        {me ? (
          <p className="whitespace-pre-wrap break-words text-sm leading-relaxed">{m.body}</p>
        ) : (
          <Markdown text={m.body} />
        )}
        <p className={cn("mt-1 text-[11px]", me ? "text-white/70" : "text-muted")}>
          {time}
          {m.model ? ` · ${m.model}` : ""}
        </p>
      </div>
    </div>
  );
}

/** Shown while a reply is on its way, with elapsed time (replies can take minutes). */
function ThinkingBubble() {
  const [secs, setSecs] = React.useState(0);
  React.useEffect(() => {
    const t = setInterval(() => setSecs((s) => s + 1), 1000);
    return () => clearInterval(t);
  }, []);
  const elapsed = secs >= 60 ? `${Math.floor(secs / 60)}m ${secs % 60}d` : `${secs}d`;
  return (
    <div className="flex justify-start">
      <div className="rounded-2xl rounded-bl-md bg-accent px-3.5 py-2.5">
        <SavingHint pending label={`Killa sedang mengerjakan… ${elapsed}`} className="text-sm" />
      </div>
    </div>
  );
}
