// Musync Worker: lee playlists del catálogo de Apple Music (storefront origen),
// comprueba qué canciones existen en el storefront destino y publica un JSON.
// Sin dependencias ni build. Secrets: APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY, API_TOKEN.

const APPLE_API = "https://api.music.apple.com";
const MAX_PAGES = 30;
const DEFAULT_TARGET = "us";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const enc = new TextEncoder();

export const chunk = (arr, n) => {
  const out = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
};

const norm = (s) =>
  String(s ?? "")
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();

// ---------- Playlist refs ----------

/** Extrae {id, storefront} de una URL de playlist de Apple Music. */
export function parsePlaylistRef(input) {
  let url;
  try {
    url = new URL(String(input).trim());
  } catch {
    return null;
  }
  if (!url.hostname.endsWith("music.apple.com")) return null;
  const parts = url.pathname.split("/").filter(Boolean);
  const i = parts.indexOf("playlist");
  if (i < 0) return null;
  const id = parts.slice(i + 1).find((p) => p.startsWith("pl."));
  if (!id) return null;
  const storefront = /^[a-z]{2}$/.test(parts[0]) ? parts[0] : "es";
  return { id, storefront };
}

/** Normaliza una entrada de config (URL o {url, source?, target?}). */
export function normalizeEntry(entry) {
  const raw = typeof entry === "string" ? { url: entry } : entry;
  const ref = raw && parsePlaylistRef(raw.url);
  if (!ref) return null;
  return {
    id: ref.id,
    url: raw.url,
    source: (raw.source || ref.storefront).toLowerCase(),
    target: (raw.target || DEFAULT_TARGET).toLowerCase(),
  };
}

// ---------- Developer token (JWT ES256) ----------

const b64url = (data) => {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

export async function makeDeveloperToken({ teamId, keyId, privateKey }, nowMs = Date.now(), ttlSeconds = 3600) {
  const pem = String(privateKey).replace(/\\n/g, "\n");
  const der = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const raw = Uint8Array.from(atob(der), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", raw, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const iat = Math.floor(nowMs / 1000);
  const head = b64url(enc.encode(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" })));
  const body = b64url(enc.encode(JSON.stringify({ iss: teamId, iat, exp: iat + ttlSeconds })));
  // WebCrypto devuelve la firma r||s (P1363), que es lo que exige JWT.
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(head + "." + body));
  return head + "." + body + "." + b64url(sig);
}

// ---------- Apple Music API ----------

export class AppleError extends Error {
  constructor(status, detail) {
    super("Apple Music API " + status + ": " + detail);
    this.status = status;
  }
}

export class AppleMusic {
  constructor(token, { fetchImpl = fetch, limit = 45 } = {}) {
    this.token = token;
    this.fetchImpl = fetchImpl;
    this.limit = limit; // el plan gratis permite 50 subrequests externas por ejecución
    this.requests = 0;
  }

  async get(path, params = {}) {
    // La query se construye a mano para no codificar comas ni corchetes (filter[isrc]).
    const query = Object.entries(params).map(([k, v]) => k + "=" + v).join("&");
    const base = path.startsWith("http") ? path : APPLE_API + path;
    const url = query ? base + (base.includes("?") ? "&" : "?") + query : base;
    for (let attempt = 0; attempt < 3; attempt++) {
      if (this.requests >= this.limit) throw new Error("Presupuesto de subrequests agotado (" + this.limit + ")");
      this.requests++;
      // Sin `this`: llamar a fetch como método de otro objeto lanza "Illegal invocation" en Workers.
      const doFetch = this.fetchImpl;
      const res = await doFetch(url, { headers: { Authorization: "Bearer " + this.token } });
      if (res.status === 429 || res.status >= 500) {
        const ra = Number(res.headers.get("retry-after"));
        await sleep(Number.isFinite(ra) && ra > 0 ? Math.min(ra, 10) * 1000 : 1000 * (attempt + 1));
        continue;
      }
      if (res.status === 404) return null;
      if (!res.ok) throw new AppleError(res.status, (await res.text()).slice(0, 200));
      return res.json();
    }
    throw new AppleError(503, "no disponible tras reintentos");
  }
}

export async function fetchSourcePlaylist(am, id, storefront) {
  const first = await am.get("/v1/catalog/" + storefront + "/playlists/" + id, { include: "tracks" });
  const pl = first?.data?.[0];
  if (!pl) throw new Error("Playlist " + id + " no encontrada en el storefront " + storefront);
  const rel = pl.relationships?.tracks;
  const data = [...(rel?.data ?? [])];
  let next = rel?.next;
  for (let page = 1; next && page < MAX_PAGES; page++) {
    const r = await am.get(next);
    if (!r) break;
    data.push(...(r.data ?? []));
    next = r.next;
  }
  const tracks = data
    .filter((t) => t.type === "songs")
    .map((t) => ({
      id: t.id,
      title: t.attributes?.name,
      artist: t.attributes?.artistName,
      album: t.attributes?.albumName,
      isrc: t.attributes?.isrc,
    }));
  return {
    id,
    name: pl.attributes?.name,
    curator: pl.attributes?.curatorName,
    url: pl.attributes?.url,
    lastModified: pl.attributes?.lastModifiedDate,
    tracks,
  };
}

/**
 * Para cada pista: su equivalente oficial en el storefront destino (filter[equivalents]),
 * o, si Apple no lo da, la coincidencia por ISRC; o null. La correspondencia origen→destino
 * sale de meta.filters.equivalents, nunca del orden de la respuesta.
 */
export async function matchToTarget(am, tracks, target) {
  const byId = new Map(); // id origen -> canción destino
  for (const ids of chunk([...new Set(tracks.map((t) => t.id))], 100)) {
    let r = await am.get("/v1/catalog/" + target + "/songs", { "filter[equivalents]": ids.join(",") });
    const resources = new Map();
    const mappings = {};
    for (let page = 0; r && page < 5; page++) {
      for (const s of r.data ?? []) resources.set(s.id, s);
      Object.assign(mappings, r.meta?.filters?.equivalents ?? {});
      if (!r.next) break;
      r = await am.get(r.next);
    }
    for (const id of ids) {
      const ref = mappings[id]?.[0];
      if (ref && resources.has(ref.id)) byId.set(id, resources.get(ref.id));
    }
  }
  const isrcs = [...new Set(tracks.filter((t) => !byId.has(t.id) && t.isrc).map((t) => t.isrc))];
  const byIsrc = new Map();
  for (const group of chunk(isrcs, 25)) {
    const r = await am.get("/v1/catalog/" + target + "/songs", { "filter[isrc]": group.join(",") });
    for (const s of r?.data ?? []) {
      const k = s.attributes?.isrc;
      if (!byIsrc.has(k)) byIsrc.set(k, []);
      byIsrc.get(k).push(s);
    }
  }
  return tracks.map((track) => {
    if (byId.has(track.id)) return { track, song: byId.get(track.id), how: "equivalent" };
    const candidates = byIsrc.get(track.isrc) ?? [];
    const best = candidates.find((s) => norm(s.attributes?.name) === norm(track.title)) ?? candidates[0];
    return best ? { track, song: best, how: "isrc" } : { track, song: null, how: null };
  });
}

// ---------- Término de búsqueda ----------

const cleanText = (str) =>
  String(str ?? "")
    .replace(/[\u2018\u2019'`]/g, "") // apóstrofos: Auli'i -> Aulii
    .replace(/[^\p{L}\p{N}\s]/gu, " ") // comillas, paréntesis, barras, & ...: fuera
    .replace(/\s+/g, " ")
    .trim();

/**
 * Término para "Buscar en iTunes Store": título sin paréntesis/corchetes (remasterizado, "De ...",
 * feat. ...) ni signos raros, más el primer artista. Las comillas dobles y similares hacían
 * fallar la acción de Atajos ("los datos no tienen el formato correcto").
 */
export function searchTerm(title, artist) {
  const rawTitle = String(title ?? "");
  const noGroups = rawTitle.replace(/\([^)]*\)|\[[^\]]*\]/g, " ");
  const t = cleanText(noGroups) || cleanText(rawTitle);
  const first = String(artist ?? "").split(/,| & | y | feat\.| ft\.| con /i)[0];
  return [t, cleanText(first)].filter(Boolean).join(" ");
}

// ---------- Documento JSON ----------

export function buildDocument({ entry, source, matches, previous, now }) {
  const seen = new Set();
  const songs = [];
  const notFound = [];
  for (const m of matches) {
    if (!m.song) {
      notFound.push({ sourceId: m.track.id, title: m.track.title, artist: m.track.artist, isrc: m.track.isrc });
      continue;
    }
    if (seen.has(m.song.id)) continue;
    seen.add(m.song.id);
    const a = m.song.attributes ?? {};
    songs.push({
      id: m.song.id,
      title: a.name,
      artist: a.artistName,
      album: a.albumName,
      isrc: a.isrc,
      match: m.how,
      sourceId: m.track.id,
      url: a.url,
      term: searchTerm(a.name, a.artistName), // para "Buscar en iTunes Store" en Atajos
      lookup: "https://itunes.apple.com/lookup?id=" + m.song.id + "&country=" + entry.target,
    });
  }
  const prevSongs = previous?.songs ?? [];
  const same = previous && prevSongs.length === songs.length && prevSongs.every((s, i) => s.id === songs[i].id);
  const prevIds = new Set(prevSongs.map((s) => s.id));
  const curIds = new Set(songs.map((s) => s.id));
  const revision = same ? previous.revision : (previous?.revision ?? 0) + 1;
  const updated = same ? previous.updated : now;
  return {
    version: 1,
    id: entry.id,
    name: source.name,
    suggestedName: source.name + " (" + updated.slice(0, 10) + ")",
    revision,
    updated, // solo cambia cuando cambia la lista de canciones
    checked: now,
    source: { storefront: entry.source, url: source.url, curator: source.curator, lastModified: source.lastModified },
    target: entry.target,
    counts: { source: source.tracks.length, matched: songs.length, notFound: notFound.length },
    songs,
    // Diferencias respecto a la revisión anterior (se conservan si no hay cambios nuevos).
    added: same ? previous.added : songs.filter((s) => !prevIds.has(s.id)).map((s) => s.id),
    removed: same ? previous.removed : [...prevIds].filter((id) => !curIds.has(id)),
    notFound,
  };
}

// ---------- Ejecución ----------

async function loadConfig(env) {
  const cfg = (await env.MUSYNC.get("config", "json")) ?? { playlists: [] };
  return (cfg.playlists ?? []).map(normalizeEntry).filter(Boolean);
}

export async function runAll(env, { only, trigger = "manual", fetchImpl = fetch, now = new Date() } = {}) {
  const startedAt = now.toISOString();
  let entries = await loadConfig(env);
  if (only) entries = entries.filter((e) => e.id === only);

  const previous = new Map();
  for (const e of entries) previous.set(e.id, await env.MUSYNC.get("playlist:" + e.id, "json"));
  // Primero las que hace más tiempo que no se revisan (por si se agota el presupuesto).
  entries.sort((a, b) => (previous.get(a.id)?.checked ?? "").localeCompare(previous.get(b.id)?.checked ?? ""));

  const results = [];
  let am = null;
  try {
    const token = await makeDeveloperToken({
      teamId: env.APPLE_TEAM_ID,
      keyId: env.APPLE_KEY_ID,
      privateKey: env.APPLE_PRIVATE_KEY,
    });
    am = new AppleMusic(token, { fetchImpl, limit: Number(env.MAX_SUBREQUESTS) || 45 });
  } catch (err) {
    for (const e of entries) results.push({ id: e.id, ok: false, error: "Developer token: " + err.message });
  }
  if (am) {
    for (const entry of entries) {
      try {
        const source = await fetchSourcePlaylist(am, entry.id, entry.source);
        const matches = await matchToTarget(am, source.tracks, entry.target);
        const doc = buildDocument({ entry, source, matches, previous: previous.get(entry.id), now: now.toISOString() });
        await env.MUSYNC.put("playlist:" + entry.id, JSON.stringify(doc));
        results.push({ id: entry.id, ok: true, name: doc.name, revision: doc.revision, ...doc.counts });
      } catch (err) {
        results.push({ id: entry.id, ok: false, error: err.message });
      }
    }
  }
  const status = {
    trigger,
    startedAt,
    finishedAt: new Date().toISOString(),
    requests: am?.requests ?? 0,
    results,
  };
  await env.MUSYNC.put("status", JSON.stringify(status));
  return status;
}

// ---------- HTTP ----------

const json = (body, status = 200) =>
  new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });

async function authorized(request, env) {
  const given = request.headers.get("authorization") ?? "";
  const expected = "Bearer " + (env.API_TOKEN ?? "");
  if (!env.API_TOKEN) return false;
  const [a, b] = await Promise.all(
    [given, expected].map(async (s) => new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(s)))),
  );
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export async function handleRequest(request, env, { fetchImpl = fetch } = {}) {
  if (!(await authorized(request, env))) return json({ error: "unauthorized" }, 401);
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "");
  const method = request.method;

  if (path === "/v1/config") {
    if (method === "GET") return json((await env.MUSYNC.get("config", "json")) ?? { playlists: [] });
    if (method === "PUT") {
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: "JSON inválido" }, 400);
      }
      const list = body?.playlists;
      if (!Array.isArray(list)) return json({ error: "Falta 'playlists' (array)" }, 400);
      const invalid = list.filter((e) => !normalizeEntry(e));
      if (invalid.length) return json({ error: "Entradas no válidas", invalid }, 400);
      await env.MUSYNC.put("config", JSON.stringify({ playlists: list }));
      return json({ ok: true, count: list.length });
    }
  }

  if (path === "/v1/run" && method === "POST") {
    return json(await runAll(env, { only: url.searchParams.get("id") || undefined, trigger: "manual", fetchImpl }));
  }

  if (path === "/v1/status" && method === "GET") {
    return json((await env.MUSYNC.get("status", "json")) ?? { results: [] });
  }

  if (path === "/v1/playlists" && method === "GET") {
    const entries = await loadConfig(env);
    const out = [];
    for (const e of entries) {
      const d = await env.MUSYNC.get("playlist:" + e.id, "json");
      out.push({
        id: e.id,
        name: d?.name ?? null,
        revision: d?.revision ?? null,
        updated: d?.updated ?? null,
        checked: d?.checked ?? null,
        counts: d?.counts ?? null,
      });
    }
    return json({ playlists: out });
  }

  const m = path.match(/^\/v1\/playlists\/(pl\.[^/]+)$/);
  if (m && method === "GET") {
    const d = await env.MUSYNC.get("playlist:" + m[1], "json");
    return d ? json(d) : json({ error: "not found" }, 404);
  }

  return json({ error: "not found" }, 404);
}

export default {
  fetch: (request, env) => handleRequest(request, env),
  scheduled: (event, env, ctx) => {
    ctx.waitUntil(runAll(env, { trigger: "cron" }));
  },
};
