// Webhook de WhatsApp: recibe mensajes de los clientes y responde en nombre de
// Kikote usando Claude. Desplegar con: supabase functions deploy whatsapp-webhook --no-verify-jwt
//
// Meta hace dos cosas contra esta URL:
//   1. GET  → verificación inicial del webhook (una sola vez).
//   2. POST → cada mensaje entrante de un cliente.

import {
  buscarClientePorTelefono,
  contextoCliente,
  db,
  enviarWhatsApp,
  preguntarAKikote,
  Turno,
  WHATSAPP_VERIFY_TOKEN,
} from "../_shared/kikote.ts";

// Cuántos turnos anteriores recordamos por conversación.
const MAX_HISTORIAL = 12;

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // ── 1. Verificación del webhook (Meta manda un GET al configurarlo) ──
  if (req.method === "GET") {
    const mode = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token");
    const challenge = url.searchParams.get("hub.challenge");
    if (mode === "subscribe" && token === WHATSAPP_VERIFY_TOKEN) {
      return new Response(challenge ?? "", { status: 200 });
    }
    return new Response("Forbidden", { status: 403 });
  }

  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  // Respondemos 200 rápido a Meta y procesamos. Si algo falla, lo registramos
  // pero NO devolvemos error: si no, Meta reintenta y el cliente recibe duplicados.
  let payload: unknown;
  try {
    payload = await req.json();
  } catch {
    return new Response("Bad Request", { status: 400 });
  }

  try {
    await procesar(payload);
  } catch (e) {
    console.error("Error procesando webhook:", e);
  }

  return new Response("EVENT_RECEIVED", { status: 200 });
});

// deno-lint-ignore no-explicit-any
async function procesar(payload: any): Promise<void> {
  const value = payload?.entry?.[0]?.changes?.[0]?.value;
  const mensaje = value?.messages?.[0];
  // Los "statuses" (entregado/leído) también llegan aquí; los ignoramos.
  if (!mensaje || mensaje.type !== "text") return;

  const de: string = mensaje.from;
  const texto: string = mensaje.text?.body ?? "";
  if (!texto.trim()) return;

  const sb = db();

  // Contexto del cliente a partir de su número.
  const cliente = await buscarClientePorTelefono(sb, de);
  const contexto = contextoCliente(cliente);

  // Recuperamos el historial reciente de esta conversación.
  const { data: previos } = await sb
    .from("wa_conversations")
    .select("role,content")
    .eq("wa_id", de)
    .order("created_at", { ascending: true })
    .limit(MAX_HISTORIAL);

  const historial: Turno[] = (previos ?? []).map((m) => ({
    role: m.role as "user" | "assistant",
    content: m.content as string,
  }));
  historial.push({ role: "user", content: texto });

  // Le preguntamos a Kikote (Claude).
  const respuesta = await preguntarAKikote(historial, contexto);

  // Enviamos la respuesta por WhatsApp.
  await enviarWhatsApp(de, respuesta);

  // Guardamos ambos turnos para mantener la conversación.
  await sb.from("wa_conversations").insert([
    { wa_id: de, client_id: cliente?.id ?? null, role: "user", content: texto },
    { wa_id: de, client_id: cliente?.id ?? null, role: "assistant", content: respuesta },
  ]);
}
