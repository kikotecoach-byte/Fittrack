# Avisos en el móvil del coach

Cuando un cliente **termina su entreno** te llega un aviso al móvil **aunque tengas la app cerrada**. Termina su entreno cuando marca todos los ejercicios de su sesión de clase, o cuando marca su open como hecho.

> ✅ **Luis ha terminado su entreno**
> hoy · 6/6 ejercicios · 4.320 kg movidos · RPE medio 8

> 🔓 **Ana ha hecho su open ✅**
> hoy · 18:30 · 5/5 ejercicios

- Si lo marcas tú (coach) desde la ejecución, no te avisa.
- Llega un solo aviso por persona y día, aunque desmarque y vuelva a marcar.
- Si tienes la app abierta, el aviso sale también en pantalla y los datos se actualizan solos.

## Pasos (una vez)

### 1. Despliega la función `avisar-coach`
1. Abre Supabase → **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. En el nombre de la función escribe `avisar-coach`.
3. Borra el código de ejemplo y pega el contenido de
   [`supabase/functions/avisar-coach/index.ts`](../supabase/functions/avisar-coach/index.ts).
4. Pulsa **Deploy function**. Deja «Verify JWT» activado, que es lo que viene por defecto.

No hace falta configurar claves ni secretos. La función crea sola sus claves la primera vez y las guarda en una tabla privada.

### 2. Ejecuta el SQL
Supabase → **SQL Editor** → pega [`docs/avisos-push.sql`](avisos-push.sql) → **Run**. Se puede volver a ejecutar sin problema.

### 3. Actívalo en tu móvil
- **Android (Chrome):** abre la app → **Inicio** → «📲 Recibir en el móvil cuando un cliente termine su entreno» → **Permitir**. Te llega un aviso de prueba.
- **iPhone/iPad (iOS 16.4 o posterior):** en Safari pulsa **Compartir → «Añadir a pantalla de inicio»**. Abre la app **desde ese icono** y actívalo desde ahí.
- También puedes activarlo en el ordenador. En **Alertas → «Avisos en tu móvil»** verás el estado y podrás **Enviar prueba** o **Desactivar**.

## Si no llega
- **La tarjeta pone «Falta un paso en Supabase»:** te falta el paso 1 o el 2.
- **La tarjeta pone «Bloqueados en el navegador»:** activa las notificaciones de la app en los ajustes del navegador o del móvil.
- **iPhone:** solo funciona con la app añadida a la pantalla de inicio y abierta desde ese icono.
- Para ver los envíos, mira Supabase → Edge Functions → `avisar-coach` → **Logs**.
