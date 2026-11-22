// ─────────────────────────────────────────────────────────────────────────
// Kikote Gym — avisar-coach (Supabase Edge Function)
// Envía notificaciones push al móvil del coach cuando un cliente reserva una
// clase (y, si se activa, cuando termina su entreno), aunque la app esté cerrada.
//
// Despliegue (una vez): Supabase → Edge Functions → Deploy a new function →
// Via Editor → nombre «avisar-coach» → pega este archivo → Deploy.
// No necesita secretos: las claves VAPID se crean solas la primera vez y se
// guardan en la tabla privada push_config (docs/avisos-push.sql).
//
// Acciones (POST JSON):
//   {action:"key"}                         → {publicKey}
//   {action:"subscribe", sub, ua}          → guarda este móvil (solo coach)
//   {action:"unsubscribe", endpoint}       → lo quita (solo coach)
//   {action:"status", endpoint}            → {on, devices} (solo coach)
//   {action:"test"}                        → aviso de prueba (solo coach)
//   {action:"booking", ids}                → lo llama la base de datos cuando un
//                                            cliente reserva clase(s); manda el aviso
//   {action:"event", table, id}            → lo llama la base de datos al
//                                            terminar un entreno; manda el aviso
// Sin dependencias: Web Push (RFC 8291 + VAPID) hecho con Web Crypto.
// ─────────────────────────────────────────────────────────────────────────

const enc = new TextEncoder();
const b64u = (buf: ArrayBuffer | Uint8Array) => {
  const b = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let s = ""; for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};
const ub64 = (s: string) => {
  s = s.replace(/-/g, "+").replace(/_/g, "/"); while (s.length % 4) s += "=";
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
};
const concat = (...arr: Uint8Array[]) => {
  const out = new Uint8Array(arr.reduce((n, a) => n + a.length, 0)); let o = 0;
  for (const a of arr) { out.set(a, o); o += a.length; } return out;
};
async function hkdf(salt: Uint8Array, ikm: Uint8Array, info: Uint8Array, len: number) {
  const key = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info }, key, len * 8));
}

export type Vapid = { publicKey: string; privateJwk: JsonWebKey };
export type Sub = { endpoint: string; keys: { p256dh: string; auth: string } };

export async function genVapid(): Promise<Vapid> {
  const kp = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  return { publicKey: b64u(await crypto.subtle.exportKey("raw", kp.publicKey)), privateJwk: await crypto.subtle.exportKey("jwk", kp.privateKey) };
}

// Cabecera Authorization de VAPID (JWT ES256 firmado con la clave privada).
export async function vapidHeader(endpoint: string, v: Vapid, subject: string) {
  const h = b64u(enc.encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const p = b64u(enc.encode(JSON.stringify({ aud: new URL(endpoint).origin, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: subject })));
  const key = await crypto.subtle.importKey("jwk", v.privateJwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(h + "." + p));
  return `vapid t=${h}.${p}.${b64u(sig)}, k=${v.publicKey}`;
}

// Cifrado del mensaje para ese navegador (aes128gcm, RFC 8291).
export async function encryptPayload(sub: Sub, payload: Uint8Array) {
  const uaPub = ub64(sub.keys.p256dh), authSecret = ub64(sub.keys.auth);
  const as = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]) as CryptoKeyPair;
  const asPub = new Uint8Array(await crypto.subtle.exportKey("raw", as.publicKey));
  const uaKey = await crypto.subtle.importKey("raw", uaPub, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const ecdh = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: uaKey } as EcdhKeyDeriveParams, as.privateKey, 256));
  const ikm = await hkdf(authSecret, ecdh, concat(enc.encode("WebPush: info\0"), uaPub, asPub), 32);
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(salt, ikm, enc.encode("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(salt, ikm, enc.encode("Content-Encoding: nonce\0"), 12);
  const key = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, key, concat(payload, new Uint8Array([2]))));
  const rs = new Uint8Array(4); new DataView(rs.buffer).setUint32(0, 4096);
  return concat(salt, rs, new Uint8Array([asPub.length]), asPub, ct);
}

export async function sendPush(sub: Sub, data: unknown, v: Vapid, subject: string, f: typeof fetch = fetch) {
  const body = await encryptPayload(sub, enc.encode(JSON.stringify(data)));
  return f(sub.endpoint, {
    method: "POST",
    headers: { TTL: "86400", Urgency: "high", "Content-Encoding": "aes128gcm", "Content-Type": "application/octet-stream", Authorization: await vapidHeader(sub.endpoint, v, subject) },
    body,
  });
}

// ── Base de datos (PostgREST con la clave de servicio) ──────────────────────
const env = (k: string) => (globalThis as any).Deno?.env.get(k) ?? (globalThis as any).process?.env?.[k];
const SB = () => env("SUPABASE_URL") as string, SRK = () => env("SUPABASE_SERVICE_ROLE_KEY") as string;
async function rest(path: string, init: RequestInit = {}) {
  const r = await fetch(`${SB()}/rest/v1/${path}`, { ...init, headers: { apikey: SRK(), Authorization: `Bearer ${SRK()}`, "Content-Type": "application/json", Prefer: "return=representation", ...(init.headers || {}) } });
  let data: any = null; try { data = await r.json(); } catch (_) { /* vacío */ }
  return { ok: r.ok, status: r.status, data };
}
const SUBJECT = "https://fittrack-seven-pi.vercel.app";

async function getVapid(): Promise<Vapid> {
  let r = await rest("push_config?id=eq.1&select=public_key,private_jwk");
  if (r.ok && r.data && r.data[0]) return { publicKey: r.data[0].public_key, privateJwk: r.data[0].private_jwk };
  const v = await genVapid();
  await rest("push_config?on_conflict=id", { method: "POST", headers: { Prefer: "resolution=ignore-duplicates,return=representation" }, body: JSON.stringify({ id: 1, public_key: v.publicKey, private_jwk: v.privateJwk }) });
  r = await rest("push_config?id=eq.1&select=public_key,private_jwk"); // por si otro lo creó a la vez
  return { publicKey: r.data[0].public_key, privateJwk: r.data[0].private_jwk };
}

// ¿Quien llama es el coach? (comprueba su sesión y la tabla admins)
async function coachId(req: Request): Promise<string | null> {
  const auth = req.headers.get("Authorization") || ""; if (!auth) return null;
  const u = await fetch(`${SB()}/auth/v1/user`, { headers: { apikey: SRK(), Authorization: auth } });
  if (!u.ok) return null; const user = await u.json().catch(() => null); if (!user || !user.id) return null;
  const a = await rest(`admins?user_id=eq.${user.id}&select=user_id`);
  return a.ok && a.data && a.data.length ? user.id : null;
}

async function sendAll(data: Record<string, unknown>, onlyUser?: string) {
  const v = await getVapid();
  const r = await rest(`push_subs?select=id,endpoint,p256dh,auth${onlyUser ? `&user_id=eq.${onlyUser}` : ""}`);
  let sent = 0;
  for (const s of (r.data || [])) {
    try {
      const res = await sendPush({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, data, v, SUBJECT);
      if (res.status === 404 || res.status === 410) await rest(`push_subs?id=eq.${s.id}`, { method: "DELETE" }); // ese móvil ya no existe
      else if (res.ok) sent++;
    } catch (_) { /* sigue con los demás */ }
  }
  return sent;
}

// ── Texto del aviso ─────────────────────────────────────────────────────────
const TZ = "Europe/Madrid";
const todayMadrid = () => new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date());
const fmtDay = (d: string) => d === todayMadrid() ? "hoy" : new Date(d + "T12:00:00Z").toLocaleDateString("es-ES", { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" });
const repsLow = (t: unknown) => { const m = String(t ?? "").match(/\d+/); return m ? parseInt(m[0]) : 0; };

async function sessionSummary(sessionId: string) {
  const r = await rest(`assigned_exercises?session_id=eq.${sessionId}&select=*`);
  const exs = (r.data || []).filter((e: any) => !/^(WOD |Hyrox|Bloque metab|Benchmark|Finisher|Circuito)/i.test(String(e.exercise_name || ""))); // sin cabeceras de WOD
  const done = exs.filter((e: any) => e.done || e.completed);
  let vol = 0; const rpes: number[] = [];
  for (const e of done) {
    const kg = Number(e.actual_weight ?? e.prescribed_weight); if (!e.load_band && kg > 0) vol += kg * (parseInt(e.sets) || 1) * repsLow(e.actual_reps ?? e.reps);
    if (e.rpe_felt != null && !isNaN(Number(e.rpe_felt))) rpes.push(Number(e.rpe_felt));
  }
  const rpe = rpes.length ? Math.round(rpes.reduce((a, b) => a + b, 0) / rpes.length * 10) / 10 : null;
  return { done: done.length, total: exs.length, vol: Math.round(vol), rpe };
}

export async function buildMessage(table: string, id: string) {
  const isOpen = table === "open_sessions";
  const r = await rest(`${table}?id=eq.${id}&select=*`); const row = r.data && r.data[0];
  if (!row || !["done", "completed"].includes(row.status)) return null;
  const c = await rest(`clients?id=eq.${row.client_id}&select=name`); const name = (c.data && c.data[0] && c.data[0].name) || "Un cliente";
  const first = String(name).split(" ")[0], date = String(row.date || "").slice(0, 10);
  let sum = null;
  if (isOpen) { const a = await rest(`assigned_sessions?client_id=eq.${row.client_id}&date=eq.${date}&select=id`); if (a.data && a.data[0]) sum = await sessionSummary(a.data[0].id); }
  else sum = await sessionSummary(id);
  let open = isOpen;
  if (!isOpen) { const o = await rest(`open_sessions?client_id=eq.${row.client_id}&date=eq.${date}&select=id`); open = !!(o.data && o.data.length); }
  const parts = [fmtDay(date) + (isOpen && row.time ? ` · ${String(row.time).slice(0, 5)}` : "")];
  if (sum && sum.total) parts.push(`${sum.done}/${sum.total} ejercicios`);
  if (sum && sum.vol) parts.push(`${String(sum.vol).replace(/\B(?=(\d{3})+(?!\d))/g, ".")} kg movidos`);
  if (sum && sum.rpe != null) parts.push(`RPE medio ${String(sum.rpe).replace(".", ",")}`);
  return {
    title: open ? `🔓 ${first} ha hecho su open ✅` : `✅ ${first} ha terminado su entreno`,
    body: parts.join(" · "), tag: `kk-done-${table}-${id}`, url: "/?aviso=entreno",
    client_id: row.client_id, date,
  };
}

// Aviso de reserva: un aviso por cliente con todas las clases que acaba de reservar.
export async function bookingMessages(ids: string[]) {
  const r = await rest(`sessions?id=in.(${ids.join(",")})&select=*`);
  const byClient = new Map<string, any[]>();
  for (const s of (r.data || [])) { if (!byClient.has(s.client_id)) byClient.set(s.client_id, []); byClient.get(s.client_id)!.push(s); }
  const out = [];
  for (const [cid, list] of byClient) {
    list.sort((a, b) => (String(a.date) + String(a.time)).localeCompare(String(b.date) + String(b.time)));
    const c = await rest(`clients?id=eq.${cid}&select=name`); const name = (c.data && c.data[0] && c.data[0].name) || "Un cliente";
    const first = String(name).split(" ")[0];
    const when = list.map((s) => `${fmtDay(String(s.date || "").slice(0, 10))}${s.time ? " · " + String(s.time).slice(0, 5) : ""}`);
    const pend = list.some((s) => s.status === "pending" || s.requested);
    out.push({
      title: list.length > 1 ? `📅 ${first} ha reservado ${list.length} clases` : `📅 ${first} ha reservado clase`,
      body: when.join(", ") + (pend ? " · pendiente de confirmar" : ""),
      tag: `kk-book-${list[0].id}`, url: "/?aviso=reserva",
    });
  }
  return out;
}

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });

export async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  let b: any = {}; try { b = await req.json(); } catch (_) { /* sin cuerpo */ }
  try {
    switch (b.action) {
      case "key": return json({ publicKey: (await getVapid()).publicKey });
      case "booking": {
        const ids = (Array.isArray(b.ids) ? b.ids : []).map(String).filter((x: string) => /^[0-9a-f-]+$/i.test(x)).slice(0, 50);
        if (!ids.length) return json({ error: "bad" }, 400);
        // Solo las reservas que aún no se han avisado (por si la llamada llega dos veces).
        const d = await rest("push_sent?on_conflict=key", { method: "POST", headers: { Prefer: "resolution=ignore-duplicates,return=representation" }, body: JSON.stringify(ids.map((id: string) => ({ key: `book:${id}` }))) });
        const fresh = (d.data || []).map((x: any) => String(x.key).slice(5));
        if (!fresh.length) return json({ skipped: "ya avisado" });
        let sent = 0; for (const msg of await bookingMessages(fresh)) sent += await sendAll(msg);
        return json({ sent });
      }
      case "event": {
        if (!["assigned_sessions", "open_sessions"].includes(b.table) || !/^[0-9a-f-]{8,}$/i.test(String(b.id || ""))) return json({ error: "bad" }, 400);
        const msg = await buildMessage(b.table, b.id); if (!msg) return json({ skipped: "no hecho" });
        // Un solo aviso por persona y día (aunque desmarque y vuelva a marcar, o
        // marque a la vez el open y su entreno).
        const d = await rest("push_sent?on_conflict=key", { method: "POST", headers: { Prefer: "resolution=ignore-duplicates,return=representation" }, body: JSON.stringify({ key: `${msg.client_id}:${msg.date}` }) });
        if (!d.ok || !d.data || !d.data.length) return json({ skipped: "ya avisado" });
        return json({ sent: await sendAll(msg) });
      }
      default: {
        const uid = await coachId(req); if (!uid) return json({ error: "solo el coach" }, 401);
        if (b.action === "subscribe") {
          const s = b.sub || {}; if (!s.endpoint || !s.keys || !s.keys.p256dh || !s.keys.auth) return json({ error: "bad" }, 400);
          const r = await rest("push_subs?on_conflict=endpoint", { method: "POST", headers: { Prefer: "resolution=merge-duplicates,return=representation" },
            body: JSON.stringify({ user_id: uid, endpoint: s.endpoint, p256dh: s.keys.p256dh, auth: s.keys.auth, ua: String(b.ua || "").slice(0, 200) }) });
          return json({ ok: r.ok });
        }
        if (b.action === "unsubscribe") { await rest(`push_subs?endpoint=eq.${encodeURIComponent(b.endpoint || "")}`, { method: "DELETE" }); return json({ ok: true }); }
        if (b.action === "status") {
          const all = await rest(`push_subs?user_id=eq.${uid}&select=endpoint`);
          return json({ on: !!(all.data || []).some((x: any) => x.endpoint === b.endpoint), devices: (all.data || []).length });
        }
        if (b.action === "test") return json({ sent: await sendAll({ title: "🔔 Avisos activados", body: "Así te llegará cuando un cliente reserve una clase 📅", tag: "kk-test", url: "/" }, uid) });
        return json({ error: "acción desconocida" }, 400);
      }
    }
  } catch (e) { return json({ error: String((e as Error)?.message || e) }, 500); }
}

if ((globalThis as any).Deno?.serve) (globalThis as any).Deno.serve(handle);
