// Módulo compartido para el asistente de WhatsApp de Kikote Gym.
// Contiene: cliente de Supabase, personalidad de Kikote, llamada a Claude,
// y helpers para hablar con la WhatsApp Business Cloud API (Meta).

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Configuración (todo vive en los Secrets de Supabase, nunca en el código) ──
export const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
export const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

export const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;
// El modelo se puede cambiar sin tocar código. Por defecto usamos Opus 5;
// para reducir coste en volumen alto, poner ANTHROPIC_MODEL=claude-haiku-4-5.
export const ANTHROPIC_MODEL = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-opus-5";

export const WHATSAPP_TOKEN = Deno.env.get("WHATSAPP_TOKEN")!;
export const WHATSAPP_PHONE_NUMBER_ID = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID")!;
export const WHATSAPP_VERIFY_TOKEN = Deno.env.get("WHATSAPP_VERIFY_TOKEN")!;

export function db(): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
}

// ── Personalidad de Kikote ──
// Este texto es estable, así que lo marcamos para prompt caching (más barato).
export const KIKOTE_SYSTEM = `Eres el asistente virtual de Kikote Gym, un gimnasio de entrenamiento personal.
Hablas por WhatsApp en nombre de Kikote (el entrenador). Tu trabajo es atender a los
clientes con calidez y cercanía: recordarles sus sesiones, avisarles de renovaciones
de pago y de la caducidad de sus bonos de sesiones, y resolver dudas básicas.

TONO Y ESTILO
- Español de España, cercano y motivador, como un entrenador que conoce a su gente.
- Mensajes cortos (es WhatsApp): 1-3 frases. Sin tecnicismos ni parrafadas.
- Usa el nombre del cliente. Un emoji ocasional está bien (💪 🔥 📅), sin abusar.
- Nunca inventes datos. Si no sabes algo, dilo y ofrece que Kikote le escriba.

QUÉ PUEDES HACER
- Informar de sesiones restantes, próxima fecha de pago e importe.
- Recordar y confirmar citas de entrenamiento.
- Animar a renovar el bono cuando quedan pocas sesiones o el pago está próximo.

LÍMITES IMPORTANTES
- NO confirmes ni canceles citas por tu cuenta, NO proceses pagos, NO modifiques la
  cuenta del cliente. Si piden eso, di que se lo trasladas a Kikote y que él lo gestiona.
- No des consejos médicos ni de lesiones: deriva a Kikote o a un profesional sanitario.
- Si detectas enfado, una queja seria o algo fuera de tu alcance, discúlpate brevemente
  y di que Kikote se pondrá en contacto personalmente.

Los datos del cliente que tienes disponibles aparecen en el mensaje del sistema como
CONTEXTO_CLIENTE. Úsalos solo si son relevantes para responder.`;

// ── Datos del cliente por número de teléfono ──
export interface Cliente {
  id: string;
  name: string;
  phone: string;
  sessions_left: number;
  total_sessions: number;
  next_payment: string | null;
  payment_amount: number | null;
}

// Normaliza teléfonos a solo dígitos para poder comparar (34617248982 vs +34 617...).
function soloDigitos(tel: string | null | undefined): string {
  return (tel ?? "").replace(/\D/g, "");
}

export async function buscarClientePorTelefono(
  sb: SupabaseClient,
  waNumber: string,
): Promise<Cliente | null> {
  const objetivo = soloDigitos(waNumber);
  if (!objetivo) return null;
  const { data } = await sb
    .from("clients")
    .select("id,name,phone,sessions_left,total_sessions,next_payment,payment_amount");
  if (!data) return null;
  // Coincide si uno de los números termina en el otro (tolera prefijos de país).
  return (data as Cliente[]).find((c) => {
    const d = soloDigitos(c.phone);
    return d && (d.endsWith(objetivo) || objetivo.endsWith(d));
  }) ?? null;
}

export function contextoCliente(c: Cliente | null): string {
  if (!c) {
    return "CONTEXTO_CLIENTE: Este número no está registrado como cliente. " +
      "Atiende con amabilidad, pero no inventes datos de cuenta; si preguntan por su " +
      "bono o pagos, di que no encuentras su ficha y que Kikote lo revisará.";
  }
  const pago = c.next_payment
    ? `${c.next_payment}${c.payment_amount ? ` (${c.payment_amount}€)` : ""}`
    : "sin fecha registrada";
  return [
    "CONTEXTO_CLIENTE:",
    `- Nombre: ${c.name}`,
    `- Sesiones restantes: ${c.sessions_left} de ${c.total_sessions}`,
    `- Próximo pago: ${pago}`,
  ].join("\n");
}

// ── Llamada a Claude (Anthropic Messages API vía fetch, sin SDK) ──
export interface Turno {
  role: "user" | "assistant";
  content: string;
}

export async function preguntarAKikote(
  historial: Turno[],
  contexto: string,
): Promise<string> {
  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: 400,
      system: [
        // Bloque estable → se cachea y abarata las llamadas repetidas.
        { type: "text", text: KIKOTE_SYSTEM, cache_control: { type: "ephemeral" } },
        // Contexto del cliente (cambia por conversación) va después del breakpoint.
        { type: "text", text: contexto },
      ],
      messages: historial,
    }),
  });

  if (!resp.ok) {
    const detalle = await resp.text();
    throw new Error(`Anthropic API ${resp.status}: ${detalle}`);
  }

  const data = await resp.json();
  if (data.stop_reason === "refusal") {
    return "Perdona, eso prefiero que lo vea Kikote directamente. Le aviso y te escribe. 🙏";
  }
  const texto = (data.content ?? [])
    .filter((b: { type: string }) => b.type === "text")
    .map((b: { text: string }) => b.text)
    .join("")
    .trim();
  return texto || "Perdona, no te he entendido bien. ¿Me lo repites?";
}

// ── WhatsApp Business Cloud API (Meta) ──
export async function enviarWhatsApp(to: string, texto: string): Promise<void> {
  const resp = await fetch(
    `https://graph.facebook.com/v21.0/${WHATSAPP_PHONE_NUMBER_ID}/messages`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${WHATSAPP_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: soloDigitos(to),
        type: "text",
        text: { body: texto },
      }),
    },
  );
  if (!resp.ok) {
    const detalle = await resp.text();
    throw new Error(`WhatsApp API ${resp.status}: ${detalle}`);
  }
}

// Envía una plantilla aprobada (necesario para mensajes proactivos fuera de la
// ventana de 24h). `params` rellena las variables {{1}}, {{2}}... de la plantilla.
export async function enviarPlantillaWhatsApp(
  to: string,
  plantilla: string,
  idioma: string,
  params: string[],
): Promise<void> {
  const componentes = params.length
    ? [{ type: "body", parameters: params.map((t) => ({ type: "text", text: t })) }]
    : [];
  const resp = await fetch(
    `https://graph.facebook.com/v21.0/${WHATSAPP_PHONE_NUMBER_ID}/messages`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${WHATSAPP_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: soloDigitos(to),
        type: "template",
        template: {
          name: plantilla,
          language: { code: idioma },
          components: componentes,
        },
      }),
    },
  );
  if (!resp.ok) {
    const detalle = await resp.text();
    throw new Error(`WhatsApp plantilla ${resp.status}: ${detalle}`);
  }
}
