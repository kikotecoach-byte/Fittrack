-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — SEGURIDAD · PASO 3 (refuerzos tras la prueba de seguridad)
-- Ejecuta en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
-- Requiere seguridad-1.sql y seguridad-2.sql ya ejecutados.
--
--   1. Fotos: cada atleta solo puede subir o cambiar SUS fotos (antes un atleta
--      con cuenta podía sobrescribir la foto de perfil o de progreso de otro).
--   2. Reservas: aunque alguien se salte la app, su reserva queda pendiente de
--      tu aprobación (si la tienes activada), no puede ser en el pasado ni pasar
--      del aforo de la hora.
--   3. Vuelve a cerrar las tablas que algún SQL antiguo podría haber reabierto
--      (políticas «abiertas a todos»).
-- ─────────────────────────────────────────────────────────────────────────

-- 1) Fotos: subir/cambiar solo en tu carpeta (el coach, todo).
--    avatars: «fotos/<tu id>/…» (progreso) · forum: «<tu id>_…»
drop policy if exists kikote_subir  on storage.objects;
drop policy if exists kikote_editar on storage.objects;
create policy kikote_subir on storage.objects for insert to authenticated with check (
  bucket_id in ('avatars','forum') and (
    public.is_admin()
    or (bucket_id = 'avatars' and name like 'fotos/' || public.my_client_id()::text || '/%')
    or (bucket_id = 'forum'   and name like public.my_client_id()::text || '\_%')));
create policy kikote_editar on storage.objects for update to authenticated using (
  bucket_id in ('avatars','forum') and (
    public.is_admin()
    or (bucket_id = 'avatars' and name like 'fotos/' || public.my_client_id()::text || '/%')
    or (bucket_id = 'forum'   and name like public.my_client_id()::text || '\_%')));

-- 2) Reservas hechas por un atleta: aprobación, pasado y aforo los decide el servidor.
create or replace function public.guard_athlete_booking() returns trigger
language plpgsql security definer set search_path = public as $$
declare cfg jsonb; cap int; n int; hoy date := (now() at time zone 'Europe/Madrid')::date;
begin
  if coalesce(public.is_admin(), false) then return new; end if;     -- el coach, sin límites
  select config into cfg from public.app_settings where id = 1;
  cfg := coalesce(cfg, '{}'::jsonb);
  -- Aprobación del coach (por defecto activada, como en la app)
  if coalesce((cfg ->> 'approveBookings')::boolean, true) then
    new.requested := true; new.status := 'pending';
  else
    new.requested := false; if coalesce(new.status,'') not in ('confirmed','pending') then new.status := 'confirmed'; end if;
  end if;
  -- Nada en el pasado
  if new.date::date < hoy then raise exception 'No se puede reservar un día pasado'; end if;
  -- Aforo de esa hora
  cap := coalesce((cfg -> 'capacity' ->> left(new.time::text, 5))::int, (cfg ->> 'defaultCapacity')::int, 3);
  select count(*) into n from public.sessions where date = new.date and left(time::text, 5) = left(new.time::text, 5);
  if n >= cap then raise exception 'La clase de las % está completa', left(new.time::text, 5); end if;
  return new;
end $$;
drop trigger if exists guard_athlete_booking on public.sessions;
create trigger guard_athlete_booking before insert on public.sessions
  for each row execute function public.guard_athlete_booking();

-- 3) Quita políticas «abiertas a todos» que pudieran haber quedado de SQL antiguos.
do $$ declare r record; begin
  for r in select tablename, policyname from pg_policies
            where schemaname = 'public'
              and policyname in ('app_settings_all','waitlist_all','exercise_notes_all','rm_tests_all','leads_all','client_photos_all','abierto_temporal') loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;
-- y se asegura de que esas tablas tienen sus políticas cerradas
do $$
declare t text;
  own    text[] := array['waitlist','client_photos','rm_tests'];
  coach  text[] := array['leads','exercise_notes'];
begin
  foreach t in array own || coach || array['app_settings'] loop
    if to_regclass('public.' || t) is null then continue; end if;
    execute format('alter table public.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t and policyname='coach_todo') then
      execute format('create policy coach_todo on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
    end if;
  end loop;
  foreach t in array own loop
    if to_regclass('public.' || t) is null then continue; end if;
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t and policyname='atleta_lee') then
      execute format('create policy atleta_lee on public.%I for select to authenticated using (client_id = public.my_client_id())', t);
    end if;
  end loop;
  if to_regclass('public.app_settings') is not null and not exists (select 1 from pg_policies where schemaname='public' and tablename='app_settings' and policyname='miembro_lee') then
    create policy miembro_lee on public.app_settings for select to authenticated using (public.is_member());
  end if;
end $$;

-- Comprobación: no debe salir ninguna política abierta (using true) en public.
select tablename, policyname, roles, qual from pg_policies
 where schemaname = 'public' and (qual = 'true' or with_check = 'true');
