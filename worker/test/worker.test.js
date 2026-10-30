import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import {
  parsePlaylistRef, normalizeEntry, makeDeveloperToken, AppleMusic, runAll, handleRequest,
} from "../src/index.js";

const kv = () => {
  const m = new Map();
  return {
    async get(k, type) { const v = m.get(k); return v === undefined ? null : type === "json" ? JSON.parse(v) : v; },
    async put(k, v) { m.set(k, v); },
    _m: m,
  };
};

const song = (id, name, isrc) => ({ id, type: "songs", attributes: { name, artistName: "A" + id, albumName: "Al", isrc, url: "https://music.apple.com/x/song/" + id } });

async function makeEnv() {
  const { privateKey, publicKey } = crypto.generateKeyPairSync("ec", { namedCurve: "P-256" });
  const pem = privateKey.export({ type: "pkcs8", format: "pem" });
  return {
    env: { MUSYNC: kv(), APPLE_TEAM_ID: "TEAM123456", APPLE_KEY_ID: "KEY1234567", APPLE_PRIVATE_KEY: pem, API_TOKEN: "secret" },
    publicKey,
  };
}

// Apple simulado: ES tiene 5 canciones (en 2 páginas). Equivalentes en US: 1→1, 2→2, 3→33 (otro ID),
// 4 y 5 sin equivalente; 5 existe por ISRC como 55; 4 no existe. La respuesta de equivalentes va desordenada a propósito.
function fakeApple(calls) {
  return async function (url) {
    // Como el fetch real de Workers: falla si se invoca con un `this` ajeno.
    if (this !== undefined && this !== globalThis) throw new TypeError("Illegal invocation");
    const u = String(url);
    calls.push(u);
    const ok = (body) => new Response(JSON.stringify(body), { status: 200 });
    if (u.includes("/catalog/es/playlists/pl.abc/tracks")) return ok({ data: [song("4", "Four", "I4"), song("5", "Five", "I5")] });
    if (u.includes("/catalog/es/playlists/pl.abc")) {
      return ok({ data: [{ id: "pl.abc", attributes: { name: "Novedades", curatorName: "Apple", url: "u" },
        relationships: { tracks: { data: [song("1", "One", "I1"), song("2", "Two", "I2"), song("3", "Three", "I3")], next: "/v1/catalog/es/playlists/pl.abc/tracks?offset=3" } } }] });
    }
    if (u.includes("/catalog/us/songs?filter[equivalents]=")) {
      return ok({
        data: [song("33", "Three", "I3"), song("2", "Two", "I2"), song("1", "One", "I1")],
        meta: { filters: { equivalents: { 1: [{ id: "1" }], 2: [{ id: "2" }], 3: [{ id: "33" }] } } },
      });
    }
    if (u.includes("/catalog/us/songs?filter[isrc]=")) return ok({ data: [song("55", "Five", "I5")] });
    return new Response("{}", { status: 404 });
  };
}

test("parsePlaylistRef", () => {
  assert.deepEqual(parsePlaylistRef("https://music.apple.com/es/playlist/novedades/pl.abc123?l=es"), { id: "pl.abc123", storefront: "es" });
  assert.equal(parsePlaylistRef("https://example.com/es/playlist/x/pl.abc"), null);
  assert.equal(parsePlaylistRef("https://music.apple.com/es/album/x/1"), null);
  assert.equal(normalizeEntry("https://music.apple.com/es/playlist/x/pl.q").target, "us");
});

test("developer token es un JWT ES256 verificable", async () => {
  const { env, publicKey } = await makeEnv();
  const jwt = await makeDeveloperToken({ teamId: "T", keyId: "K", privateKey: env.APPLE_PRIVATE_KEY }, 1_000_000_000_000);
  const [h, b, s] = jwt.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(h, "base64url")), { alg: "ES256", kid: "K", typ: "JWT" });
  const body = JSON.parse(Buffer.from(b, "base64url"));
  assert.equal(body.iss, "T"); assert.equal(body.exp - body.iat, 3600);
  const sig = Buffer.from(s, "base64url");
  assert.equal(sig.length, 64);
  assert.ok(crypto.verify("sha256", Buffer.from(h + "." + b), { key: publicKey, dsaEncoding: "ieee-p1363" }, sig));
});

test("flujo completo: config, run, lectura y diff", async () => {
  const { env } = await makeEnv();
  const calls = [];
  const fetchImpl = fakeApple(calls);
  const call = (method, path, body, token = "secret") =>
    handleRequest(new Request("https://w.test" + path, { method, headers: { authorization: "Bearer " + token }, body: body && JSON.stringify(body) }), env, { fetchImpl });

  assert.equal((await call("GET", "/v1/playlists", null, "mal")).status, 401);
  assert.equal((await call("PUT", "/v1/config", { playlists: ["nope"] })).status, 400);
  assert.equal((await call("PUT", "/v1/config", { playlists: ["https://music.apple.com/es/playlist/novedades/pl.abc"] })).status, 200);

  const run = await (await call("POST", "/v1/run")).json();
  assert.equal(run.results[0].ok, true, JSON.stringify(run));
  assert.deepEqual([run.results[0].matched, run.results[0].notFound], [4, 1]);

  const doc = await (await call("GET", "/v1/playlists/pl.abc")).json();
  assert.deepEqual(doc.songs.map((s) => [s.id, s.match]), [["1", "equivalent"], ["2", "equivalent"], ["33", "equivalent"], ["55", "isrc"]]);
  assert.equal(doc.revision, 1);
  assert.deepEqual(doc.added, ["1", "2", "33", "55"]);
  assert.deepEqual(doc.notFound.map((n) => n.sourceId), ["4"]);
  assert.match(doc.songs[0].lookup, /itunes\.apple\.com\/lookup\?id=1&country=us/);
  assert.ok(calls.some((c) => c.includes("filter[equivalents]=1,2,3,4,5")));
  assert.ok(calls.some((c) => c.includes("filter[isrc]=I4,I5")));

  // Segunda ejecución sin cambios: misma revisión, se conserva added.
  await call("POST", "/v1/run");
  const doc2 = await (await call("GET", "/v1/playlists/pl.abc")).json();
  assert.equal(doc2.revision, 1);
  assert.equal(doc2.updated, doc.updated);
  assert.deepEqual(doc2.added, ["1", "2", "33", "55"]);

  const list = await (await call("GET", "/v1/playlists")).json();
  assert.equal(list.playlists[0].counts.matched, 4);
});

test("presupuesto de subrequests y errores por playlist", async () => {
  const { env } = await makeEnv();
  await env.MUSYNC.put("config", JSON.stringify({ playlists: ["https://music.apple.com/es/playlist/x/pl.abc", "https://music.apple.com/es/playlist/y/pl.zzz"] }));
  const status = await runAll(env, { fetchImpl: fakeApple([]) });
  assert.equal(status.results.find((r) => r.id === "pl.abc").ok, true);
  assert.match(status.results.find((r) => r.id === "pl.zzz").error, /no encontrada/);
  const am = new AppleMusic("t", { fetchImpl: fakeApple([]), limit: 1 });
  await am.get("/v1/catalog/us/songs", { ids: "1" });
  await assert.rejects(() => am.get("/v1/catalog/us/songs", { ids: "1" }), /Presupuesto/);
});

test("token inválido se reporta sin romper", async () => {
  const { env } = await makeEnv();
  env.APPLE_PRIVATE_KEY = "basura";
  await env.MUSYNC.put("config", JSON.stringify({ playlists: ["https://music.apple.com/es/playlist/x/pl.abc"] }));
  const status = await runAll(env, { fetchImpl: fakeApple([]) });
  assert.match(status.results[0].error, /Developer token/);
});
