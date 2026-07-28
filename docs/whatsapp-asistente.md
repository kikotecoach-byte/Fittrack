# Asistente de WhatsApp de Kikote Gym

Un número de WhatsApp que habla en nombre de Kikote con inteligencia artificial:
responde a los clientes, les recuerda sesiones y les avisa de renovaciones y de la
caducidad de sus bonos.

## Cómo funciona

```
Cliente escribe por WhatsApp
        ↓
WhatsApp Business Cloud API (Meta)  ── oficial y gratis en su nivel básico
        ↓  (webhook)
Supabase Edge Function  ──►  lee los datos del cliente (sesiones, bonos, pagos)
        ↓
Claude (el "cerebro", con la personalidad de Kikote)
        ↓
Responde por WhatsApp en nombre de Kikote

+ Un cron diario que envía recordatorios proactivos (renovación / caducidad)
```

- **`whatsapp-webhook`** — recibe cada mensaje del cliente y responde con IA.
- **`send-reminders`** — corre cada mañana y manda avisos proactivos por plantilla.
- **`wa_conversations`** — tabla donde se guarda el hilo de cada conversación.

---

## Lo que necesitas conseguir tú (una sola vez)

### 1. Clave de la API de Claude
1. Entra en <https://console.anthropic.com> → **API Keys** → crea una clave.
2. Guárdala; la usarás como `ANTHROPIC_API_KEY`.

### 2. WhatsApp Business Cloud API (Meta)
1. Crea una cuenta en <https://developers.facebook.com>.
2. Crea una app de tipo **Business** y añade el producto **WhatsApp**.
3. En *WhatsApp → API Setup* obtienes:
   - **Phone number ID** → `WHATSAPP_PHONE_NUMBER_ID`
   - Un **token temporal** para pruebas → `WHATSAPP_TOKEN`
     (para producción, genera un *System User* con token permanente).
4. Inventa una contraseña cualquiera para verificar el webhook → `WHATSAPP_VERIFY_TOKEN`
   (por ejemplo `kikote-verify-2026`).

---

## Instalar (con la CLI de Supabase)

Necesitas la [CLI de Supabase](https://supabase.com/docs/guides/cli) instalada y el
proyecto vinculado (`supabase link --project-ref <PROJECT_REF>`).

### 1. Guardar los secretos

```bash
supabase secrets set \
  ANTHROPIC_API_KEY="sk-ant-..." \
  ANTHROPIC_MODEL="claude-opus-5" \
  WHATSAPP_TOKEN="EAAG..." \
  WHATSAPP_PHONE_NUMBER_ID="123456789012345" \
  WHATSAPP_VERIFY_TOKEN="kikote-verify-2026" \
  CRON_SECRET="$(openssl rand -hex 16)" \
  REMINDER_TEMPLATE="recordatorio_kikote" \
  REMINDER_TEMPLATE_LANG="es"
```

> `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` ya están disponibles automáticamente
> dentro de las Edge Functions; no hace falta configurarlos.

Apunta el valor de `CRON_SECRET`: lo necesitarás en el paso del cron.

### 2. Crear la tabla de conversaciones

```bash
supabase db push
```

(o pega el contenido de `supabase/migrations/20260728120000_whatsapp_assistant.sql`
en el editor SQL del panel de Supabase).

### 3. Desplegar las funciones

```bash
# El webhook debe ser público (Meta lo llama sin token de Supabase):
supabase functions deploy whatsapp-webhook --no-verify-jwt

# Los recordatorios se protegen con CRON_SECRET:
supabase functions deploy send-reminders
```

La URL del webhook será:
`https://<PROJECT_REF>.supabase.co/functions/v1/whatsapp-webhook`

### 4. Conectar el webhook en Meta
1. En *WhatsApp → Configuration → Webhook* pega la URL anterior.
2. En **Verify token** pon el mismo valor de `WHATSAPP_VERIFY_TOKEN`.
3. Pulsa **Verify and save** (Meta hará un GET y la función responderá el challenge).
4. Suscríbete al campo **messages**.

¡Listo! Escribe al número desde tu móvil y Kikote debería contestarte. 🎉

---

## Recordatorios proactivos (cron diario)

### 1. Plantilla de mensaje aprobada
WhatsApp **no deja** escribir el primero a alguien que no te ha hablado en 24h salvo
con una plantilla aprobada. Créala en *WhatsApp Manager → Message Templates*:

- **Nombre:** `recordatorio_kikote` (debe coincidir con `REMINDER_TEMPLATE`).
- **Idioma:** Español (`es`).
- **Categoría:** Utility.
- **Cuerpo:** `Hola {{1}} 👋, {{2}}`
  - `{{1}}` = nombre del cliente
  - `{{2}}` = el detalle (renovación o sesiones)

Ejemplo de cómo se verá: *"Hola María 👋, te quedan 2 sesiones. Avísame y te preparo
la renovación."*

Espera a que Meta la apruebe (suele tardar minutos).

### 2. Programar el cron
En el panel de Supabase → **Database → Extensions**, activa `pg_cron` y `pg_net`.
Luego, en el editor SQL, ejecuta (descomentado y con tus valores) el bloque final del
archivo de migración:

```sql
select cron.schedule(
  'recordatorios-kikote-diario',
  '0 9 * * *',                              -- 09:00 UTC cada día
  $$
  select net.http_post(
    url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/send-reminders',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer <CRON_SECRET>'
    )
  );
  $$
);
```

> **Zona horaria:** el cron usa UTC. España va +1h en invierno y +2h en verano, así que
> `0 9 * * *` equivale a las 10:00 (invierno) u 11:00 (verano). Ajusta la hora a tu gusto.

Para probarlo al momento sin esperar al cron:

```bash
curl -X POST "https://<PROJECT_REF>.supabase.co/functions/v1/send-reminders" \
  -H "Authorization: Bearer <CRON_SECRET>"
```

Devuelve cuántos avisos se han enviado.

---

## Coste y modelo de IA

- El modelo por defecto es `claude-opus-5` (el más capaz). Para **abaratar** en volumen
  alto, cambia el secreto a un modelo más económico sin tocar el código:
  ```bash
  supabase secrets set ANTHROPIC_MODEL="claude-haiku-4-5"
  ```
- La personalidad de Kikote se cachea (prompt caching), así que las llamadas repetidas
  son más baratas automáticamente.
- WhatsApp Cloud API tiene un nivel gratuito de conversaciones al mes; a partir de ahí
  cobra por conversación (céntimos). Revisa los precios actuales de Meta.

## Personalizar el tono de Kikote

Edita el texto `KIKOTE_SYSTEM` en `supabase/functions/_shared/kikote.ts` y vuelve a
desplegar el webhook. Ahí defines cómo habla, qué puede y qué no puede hacer.

## Seguridad

- Ninguna clave está en el código: todo vive en los *Secrets* de Supabase.
- La tabla de conversaciones tiene RLS activado y sin políticas públicas: el frontend
  anónimo no puede leerla.
- `send-reminders` solo responde si recibe el `CRON_SECRET` correcto.
