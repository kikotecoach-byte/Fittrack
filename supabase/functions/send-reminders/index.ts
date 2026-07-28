// Recordatorios proactivos: corre cada mañana (vía pg_cron) y avisa por WhatsApp
// de renovaciones de pago próximas y bonos que se están agotando o ya caducados.
//
// IMPORTANTE: para escribir a un cliente que NO ha hablado con nosotros en las
// últimas 24h, WhatsApp obliga a usar PLANTILLAS DE MENSAJE aprobadas por Meta.
// Por eso aquí usamos enviarPlantillaWhatsApp con una plantilla que debes crear
// y aprobar en el WhatsApp Manager (ver docs/whatsapp-asistente.md).
//
// Desplegar con: supabase functions deploy send-reminders
// Esta función se protege con CRON_SECRET para que solo la llame el cron.

import { db, enviarPlantillaWhatsApp } from "../_shared/kikote.ts";

// Nombre e idioma de la plantilla aprobada en el WhatsApp Manager.
// La plantilla debe tener 2 variables en el body: {{1}} = nombre, {{2}} = detalle.
const PLANTILLA = Deno.env.get("REMINDER_TEMPLATE") ?? "recordatorio_kikote";
const PLANTILLA_IDIOMA = Deno.env.get("REMINDER_TEMPLATE_LANG") ?? "es";
const CRON_SECRET = Deno.env.get("CRON_SECRET")!;

// Días de antelación con los que avisamos de un pago próximo.
const DIAS_AVISO_PAGO = 3;

function diasHasta(fecha: string | null): number | null {
  if (!fecha) return null;
  const hoy = new Date();
  hoy.setHours(0, 0, 0, 0);
  const objetivo = new Date(fecha + "T00:00:00");
  return Math.round((objetivo.getTime() - hoy.getTime()) / 86_400_000);
}

Deno.serve(async (req) => {
  // Solo el cron (que conoce el secreto) puede disparar los envíos.
  const auth = req.headers.get("authorization") ?? "";
  if (auth !== `Bearer ${CRON_SECRET}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  const sb = db();
  const { data: clientes, error } = await sb
    .from("clients")
    .select("id,name,phone,sessions_left,total_sessions,next_payment,payment_amount");

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  const enviados: string[] = [];
  const fallidos: { cliente: string; error: string }[] = [];

  for (const c of clientes ?? []) {
    if (!c.phone) continue;

    // Decidimos si hay algo que recordar y con qué texto.
    const dias = diasHasta(c.next_payment);
    let detalle: string | null = null;

    if (c.sessions_left === 0) {
      detalle = "tu bono se ha agotado. ¿Renovamos para seguir entrenando? 💪";
    } else if (c.sessions_left <= 2) {
      detalle = `te quedan ${c.sessions_left} sesión${c.sessions_left === 1 ? "" : "es"}. ` +
        "Avísame y te preparo la renovación.";
    } else if (dias !== null && dias >= 0 && dias <= DIAS_AVISO_PAGO) {
      const importe = c.payment_amount ? ` (${c.payment_amount}€)` : "";
      detalle = dias === 0
        ? `hoy toca renovar tu cuota${importe}.`
        : `en ${dias} día${dias === 1 ? "" : "s"} toca renovar tu cuota${importe}.`;
    }

    if (!detalle) continue;

    try {
      await enviarPlantillaWhatsApp(c.phone, PLANTILLA, PLANTILLA_IDIOMA, [
        c.name,
        detalle,
      ]);
      enviados.push(c.name);
    } catch (e) {
      fallidos.push({ cliente: c.name, error: String(e) });
    }
  }

  return new Response(
    JSON.stringify({ enviados: enviados.length, detalle_enviados: enviados, fallidos }),
    { headers: { "content-type": "application/json" } },
  );
});
