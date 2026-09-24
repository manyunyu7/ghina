import { lookup as dnsLookup, type LookupAddress } from "node:dns";
import http from "node:http";
import https from "node:https";
import { BlockList, isIP } from "node:net";
import { LINK_TITLE_MAX } from "@/lib/notes";

/**
 * Page titles for note links (docs/notes.md): `og:title`, else `<title>`. Best effort,
 * server side, no third-party service. SSRF-safe:
 * - http/https only, no credentials in the URL;
 * - every address a host resolves to must be public — private, loopback, link-local
 *   (incl. cloud metadata 169.254.169.254 / fd00:ec2::254), CGNAT, multicast, reserved,
 *   documentation and IPv4-mapped/NAT64/6to4 forms of those are refused. The check runs
 *   inside the socket's DNS lookup, so the address connected to is the one checked (no
 *   DNS-rebinding gap); IP-literal hosts are checked before connecting;
 * - redirects are followed manually (max 3), each hop re-validated;
 * - 3 s overall timeout, at most 256 KB read, only `text/html` responses.
 */

export const TITLE_FETCH_TIMEOUT_MS = 3000;
export const TITLE_FETCH_MAX_BYTES = 256 * 1024;
export const TITLE_FETCH_MAX_REDIRECTS = 3;

// ---------- Address policy ----------

const blocked = new BlockList();
for (const [net, prefix] of [
  ["0.0.0.0", 8], // "this" network
  ["10.0.0.0", 8],
  ["100.64.0.0", 10], // CGNAT
  ["127.0.0.0", 8],
  ["169.254.0.0", 16], // link-local, cloud metadata
  ["172.16.0.0", 12],
  ["192.0.0.0", 24],
  ["192.0.2.0", 24], // TEST-NET-1
  ["192.88.99.0", 24], // 6to4 relay
  ["192.168.0.0", 16],
  ["198.18.0.0", 15], // benchmarking
  ["198.51.100.0", 24], // TEST-NET-2
  ["203.0.113.0", 24], // TEST-NET-3
  ["224.0.0.0", 4], // multicast
  ["240.0.0.0", 4], // reserved + broadcast
] as const) {
  blocked.addSubnet(net, prefix, "ipv4");
}
for (const [net, prefix] of [
  ["::", 128], // unspecified
  ["::1", 128], // loopback
  ["100::", 64], // discard
  ["64:ff9b:1::", 48], // NAT64 local-use (RFC 8215) — translates to private IPv4
  ["2001::", 23], // IETF protocol assignments (Teredo, ORCHID, …)
  ["2001:db8::", 32], // documentation
  ["fc00::", 7], // unique local (incl. fd00:ec2::254 metadata)
  ["fe80::", 10], // link-local
  ["fec0::", 10], // site-local (deprecated)
  ["ff00::", 8], // multicast
] as const) {
  blocked.addSubnet(net, prefix, "ipv6");
}

/** Expand an IPv6 address to 8 hextets (numbers), or null. Handles an embedded IPv4 tail. */
function ipv6Hextets(addr: string): number[] | null {
  let a = addr.toLowerCase().split("%")[0];
  const v4 = /(\d+\.\d+\.\d+\.\d+)$/.exec(a);
  if (v4) {
    const o = v4[1].split(".").map(Number);
    if (o.some((x) => x > 255)) return null;
    a = a.slice(0, -v4[1].length) + `${((o[0] << 8) | o[1]).toString(16)}:${((o[2] << 8) | o[3]).toString(16)}`;
  }
  const [head, tail] = a.split("::");
  const h = head ? head.split(":") : [];
  const t = tail !== undefined && tail ? tail.split(":") : [];
  const fill = a.includes("::") ? 8 - h.length - t.length : 0;
  const parts = [...h, ...Array(Math.max(fill, 0)).fill("0"), ...t];
  if (parts.length !== 8) return null;
  const nums = parts.map((p) => parseInt(p, 16));
  return nums.some((n) => !Number.isFinite(n) || n < 0 || n > 0xffff) ? null : nums;
}

const v4FromHextets = (hi: number, lo: number) => `${hi >> 8}.${hi & 255}.${lo >> 8}.${lo & 255}`;

/**
 * Whether an IP address is a public unicast address a server may fetch from.
 * IPv6 forms that embed an IPv4 address (mapped ::ffff:a.b.c.d, compatible ::a.b.c.d,
 * NAT64 64:ff9b::/96, 6to4 2002::/16) are judged by that IPv4 address.
 */
export function isPublicAddress(ip: string): boolean {
  const fam = isIP(ip);
  if (fam === 4) return !blocked.check(ip, "ipv4");
  if (fam !== 6) return false;
  const h = ipv6Hextets(ip);
  if (!h) return false;
  const zeros = (n: number) => h.slice(0, n).every((x) => x === 0);
  if (zeros(5) && h[5] === 0xffff) return isPublicAddress(v4FromHextets(h[6], h[7])); // ::ffff:a.b.c.d
  if (zeros(6) && (h[6] !== 0 || h[7] > 1)) return isPublicAddress(v4FromHextets(h[6], h[7])); // ::a.b.c.d
  if (h[0] === 0x64 && h[1] === 0xff9b && h[2] === 0 && h[3] === 0 && h[4] === 0 && h[5] === 0)
    return isPublicAddress(v4FromHextets(h[6], h[7])); // NAT64
  if (h[0] === 0x2002) return isPublicAddress(v4FromHextets(h[1], h[2])); // 6to4
  return !blocked.check(ip, "ipv6");
}

// ---------- Fetch ----------

export class TitleFetchError extends Error {}

export type TitleFetchOptions = {
  timeoutMs?: number;
  maxBytes?: number;
  maxRedirects?: number;
  /**
   * Address policy (default `isPublicAddress`). Only tests pass something else (to reach
   * a local test server); user input never reaches this.
   */
  isAllowedAddress?: (ip: string) => boolean;
};

type LookupCb = (err: NodeJS.ErrnoException | null, address: string | LookupAddress[], family?: number) => void;

/** A socket `lookup` that refuses hosts resolving to any disallowed address. */
function guardedLookup(allowed: (ip: string) => boolean) {
  return (hostname: string, options: { all?: boolean; family?: number | string } | number, cb: LookupCb) => {
    const opts = typeof options === "number" ? { family: options } : (options ?? {});
    dnsLookup(hostname, { all: true, family: (opts.family as number | undefined) ?? 0 }, (err, addrs) => {
      if (err) return cb(err, "");
      const list = addrs as unknown as LookupAddress[];
      if (!list.length) return cb(Object.assign(new Error("No address"), { code: "ENOTFOUND" }), "");
      if (list.some((a) => !allowed(a.address))) {
        return cb(Object.assign(new TitleFetchError(`Blocked address for ${hostname}`), { code: "EBLOCKED" }), "");
      }
      if (opts.all) cb(null, list);
      else cb(null, list[0].address, list[0].family);
    });
  };
}

type Hop = { status: number; location: string | null; contentType: string; body: Buffer | null };

function requestOnce(url: URL, allowed: (ip: string) => boolean, deadline: number, maxBytes: number): Promise<Hop> {
  return new Promise((resolve, reject) => {
    const remaining = deadline - Date.now();
    if (remaining <= 0) return reject(new TitleFetchError("Timeout"));
    const mod = url.protocol === "https:" ? https : http;
    const req = mod.request(
      url,
      {
        method: "GET",
        lookup: guardedLookup(allowed) as never,
        agent: false,
        headers: {
          "user-agent": "Mozilla/5.0 (compatible; GhinaLinkPreview/1.0)",
          accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1",
          "accept-language": "id,en;q=0.8",
          // Identity only: never decompress unbounded data.
          "accept-encoding": "identity",
        },
      },
      (res) => {
        const status = res.statusCode ?? 0;
        const location = typeof res.headers.location === "string" ? res.headers.location : null;
        const contentType = String(res.headers["content-type"] ?? "").toLowerCase();
        if ((status >= 300 && status < 400) || status >= 400 || !contentType.startsWith("text/html")) {
          res.destroy();
          return resolve({ status, location, contentType, body: null });
        }
        const chunks: Buffer[] = [];
        let size = 0;
        const finish = () => {
          res.destroy();
          resolve({ status, location, contentType, body: Buffer.concat(chunks).subarray(0, maxBytes) });
        };
        res.on("data", (c: Buffer) => {
          chunks.push(c);
          size += c.length;
          // Stop once the <head> is in hand (title + og:title live there) or at the cap.
          if (size >= maxBytes || /<\/head>|<body[\s>]/i.test(c.toString("latin1"))) finish();
        });
        res.on("end", finish);
        res.on("error", reject);
      },
    );
    const timer = setTimeout(() => req.destroy(new TitleFetchError("Timeout")), remaining);
    req.on("close", () => clearTimeout(timer));
    req.on("error", reject);
    req.end();
  });
}

function checkUrl(raw: string | URL, allowed: (ip: string) => boolean): URL {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    throw new TitleFetchError("Invalid URL");
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") throw new TitleFetchError("Only http/https");
  if (u.username || u.password) throw new TitleFetchError("Credentials in URL");
  const host = u.hostname.replace(/^\[|\]$/g, "");
  if (!host) throw new TitleFetchError("Invalid URL");
  // IP literals never go through the (guarded) DNS lookup, so check them here.
  if (isIP(host) && !allowed(host)) throw new TitleFetchError(`Blocked address ${host}`);
  return u;
}

/**
 * Fetch `url` (following ≤ 3 validated redirects) and return its page title, or null when
 * the page has none. Throws `TitleFetchError`/network errors on blocked hosts, timeouts,
 * non-HTML responses, HTTP errors.
 */
export async function fetchPageTitle(url: string, opts: TitleFetchOptions = {}): Promise<string | null> {
  const allowed = opts.isAllowedAddress ?? isPublicAddress;
  const deadline = Date.now() + (opts.timeoutMs ?? TITLE_FETCH_TIMEOUT_MS);
  const maxBytes = opts.maxBytes ?? TITLE_FETCH_MAX_BYTES;
  const maxRedirects = opts.maxRedirects ?? TITLE_FETCH_MAX_REDIRECTS;
  let current = checkUrl(url, allowed);
  for (let hop = 0; ; hop++) {
    const res = await requestOnce(current, allowed, deadline, maxBytes);
    if (res.status >= 300 && res.status < 400) {
      if (!res.location) throw new TitleFetchError("Redirect without location");
      if (hop >= maxRedirects) throw new TitleFetchError("Too many redirects");
      current = checkUrl(new URL(res.location, current), allowed);
      continue;
    }
    if (res.status < 200 || res.status >= 300) throw new TitleFetchError(`HTTP ${res.status}`);
    if (!res.body) throw new TitleFetchError("Not HTML");
    return extractTitle(decodeHtml(res.body, res.contentType));
  }
}

// ---------- HTML → title ----------

function decodeHtml(body: Buffer, contentType: string): string {
  let charset = /charset=["']?([\w-]+)/i.exec(contentType)?.[1];
  if (!charset) {
    const head = body.subarray(0, 4096).toString("latin1");
    charset = /<meta[^>]+charset=["']?([\w-]+)/i.exec(head)?.[1];
  }
  try {
    return new TextDecoder(charset?.toLowerCase() || "utf-8").decode(body);
  } catch {
    return new TextDecoder("utf-8").decode(body);
  }
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", "#39": "'" };

export function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+\d*);/gi, (m, e: string) => {
    const k = e.toLowerCase();
    if (k.startsWith("#x")) return safeChar(parseInt(k.slice(2), 16)) ?? m;
    if (k.startsWith("#")) return safeChar(parseInt(k.slice(1), 10)) ?? m;
    return ENTITIES[k] ?? m;
  });
}

function safeChar(cp: number): string | null {
  if (!Number.isFinite(cp) || cp <= 0 || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) return null;
  return String.fromCodePoint(cp);
}

function attr(tag: string, name: string): string | null {
  const m = new RegExp(`\\s${name}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s>]+))`, "i").exec(tag);
  return m ? (m[2] ?? m[3] ?? m[4] ?? "") : null;
}

const clean = (s: string) => {
  const t = decodeEntities(s).replace(/[\u0000-\u001F\u007F]/g, " ").replace(/\s+/g, " ").trim();
  return t.length > LINK_TITLE_MAX ? `${t.slice(0, LINK_TITLE_MAX - 1).trimEnd()}…` : t;
};

/** `og:title` (or `twitter:title`) meta, else `<title>`; null when neither has text. */
export function extractTitle(html: string): string | null {
  const metas = html.match(/<meta\b[^>]*>/gi) ?? [];
  for (const key of ["og:title", "twitter:title"]) {
    for (const tag of metas) {
      const p = (attr(tag, "property") ?? attr(tag, "name"))?.toLowerCase();
      if (p === key) {
        const c = attr(tag, "content");
        if (c && clean(c)) return clean(c);
      }
    }
  }
  const t = /<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(html);
  return t && clean(t[1]) ? clean(t[1]) : null;
}

// ---------- Cache ----------

type CacheEntry = { title: string | null; at: number };
const cache = new Map<string, CacheEntry>();
const inflight = new Map<string, Promise<string | null>>();
const CACHE_MAX = 1000;
const TTL_OK = 24 * 3600_000;
const TTL_FAIL = 3600_000;

/**
 * Cached `fetchPageTitle` (per URL: 24 h for a title, 1 h for "no title"/failure —
 * failures are cached too so a dead link isn't refetched on every save). Never throws.
 */
export async function getLinkTitle(url: string, opts?: TitleFetchOptions): Promise<string | null> {
  const hit = cache.get(url);
  if (hit && Date.now() - hit.at < (hit.title ? TTL_OK : TTL_FAIL)) return hit.title;
  const running = inflight.get(url);
  if (running) return running;
  const p = fetchPageTitle(url, opts)
    .catch(() => null)
    .then((title) => {
      if (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value!);
      cache.set(url, { title, at: Date.now() });
      inflight.delete(url);
      return title;
    });
  inflight.set(url, p);
  return p;
}

/** Test helper: forget cached titles. */
export function clearLinkTitleCache() {
  cache.clear();
}
