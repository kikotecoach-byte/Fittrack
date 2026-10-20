# Seguridad de Kikote Gym

## Qué estaba mal (antes de este cambio)

| Problema | Riesgo |
|---|---|
| Al abrir el enlace, la app descargaba **todos los datos** (nombres, teléfonos, códigos, pagos, lesiones, medidas, fotos, notas) **antes de iniciar sesión**. | Cualquiera con el enlace podía verlos desde el navegador. |
| La base de datos permitía leer y modificar todo a cualquiera (políticas `using (true)`). | Se podían borrar o cambiar datos sin entrar en la app. |
| El acceso de coach y de atleta se comprobaba solo en el navegador. | Se podía entrar como coach u otro atleta trucando el navegador. |
| Códigos de 4 dígitos visibles para todos. | Entrar con el nombre + código de otra persona. |

## Cómo queda

- **Coach**: entra con **email + contraseña** (usuario de Supabase). Lo que puede hacer lo decide el servidor (tabla `admins`).
- **Atleta**: la primera vez **activa su cuenta** con su nombre y su código y elige su contraseña (mín. 8). Después entra con **código + contraseña**. El coach no conoce su contraseña.
- **Sin iniciar sesión no se descarga nada.**
- Con el paso 2, la **base de datos solo da a cada uno lo suyo**:
  - Coach: todo.
  - Atleta: sus reservas, historial, pagos, medidas, fotos, entrenos y marcas. Ve los ejercicios, la programación, el horario y la comunidad.
  - El aforo de las clases y la comunidad llegan por funciones seguras: solo nombre de pila, color y foto de perfil de los demás.
  - Notas del gesto, valoraciones (leads) y los datos de otros atletas: **solo el coach**.
- «Me gusta» en la comunidad sin poder editar publicaciones ajenas.
- Activación con **límite de 5 intentos por hora**.
- Al cerrar sesión se borran los datos de la memoria del dispositivo.
- El coach puede **restablecer el acceso** de un atleta (si olvida la contraseña) y **enviarle las instrucciones por WhatsApp**.

## Pasos (en este orden)

### Paso 1 — sin cortar nada
1. Supabase → **Authentication → Sign In / Providers → Email**: activado y **«Confirm email» desactivado** → *Save*.
2. Supabase → **SQL Editor**: ejecuta `docs/seguridad-1.sql`.
3. Supabase → **Authentication → Users → Add user → Create new user**: tu email y una contraseña fuerte, con **Auto Confirm User** marcado.
4. SQL Editor: hazte coach (cambia el email):
   ```sql
   insert into public.admins(user_id) select id from auth.users where email = 'TU_EMAIL' on conflict do nothing;
   ```
5. Fusiona el PR y entra en la app → **Coach** → email + contraseña.
6. Envía a cada atleta su acceso (Clientes → atleta → **📲 Enviar acceso**) para que active su cuenta.

Mientras tanto sigue disponible «Acceso antiguo (temporal)» debajo del formulario.

### Paso 2 — cerrar la base de datos
Cuando entres bien como coach:
1. SQL Editor: ejecuta `docs/seguridad-2.sql`.
2. Se publica la versión sin «Acceso antiguo».

Al final de `seguridad-2.sql` hay una **vuelta atrás** por si algo fallara.

## Lo que queda por mejorar (opcional)
- Las fotos ya subidas se abren con su enlace directo (largo e imposible de adivinar). Para que ni con el enlace se vean, habría que pasar el almacenamiento a privado con enlaces temporales.
- Las reglas de aforo y de bono se comprueban en la app. Un atleta con conocimientos técnicos podría reservarse a sí mismo por encima del aforo, aunque nunca para otra persona.
- Pon el repositorio de GitHub en **privado**.
