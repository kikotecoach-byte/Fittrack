-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — SEGURIDAD · PASO 2 de 2 (cierra la base de datos)
-- Ejecútalo SOLO cuando ya entres a la app con tu usuario de coach
-- (email + contraseña) y tu cuenta esté en la tabla admins.
--
-- A partir de aquí:
--   · Nadie sin iniciar sesión puede leer ni cambiar nada.
--   · El coach (admins) puede todo.
--   · Cada atleta solo ve y cambia lo suyo; el aforo y la comunidad
--     llegan por funciones seguras (sin datos privados de los demás).
-- Si algo falla, la vuelta atrás está al final del archivo.
-- ─────────────────────────────────────────────────────────────────────────

do $$
declare t text; r record;
  own    text[] := array['sessions','history','payments','client_plans','progress','personal_records','achievements',
                         'client_weights','assigned_sessions','weight_history','waitlist','client_photos','rm_tests'];
  shared text[] := array['blocked_slots','forum_posts','exercises','training_plans','plan_days','plan_exercises',
                         'annual_blocks','session_templates','template_exercises','app_settings'];
  coach  text[] := array['leads','exercise_notes','claim_attempts'];
  allt   text[];
begin
  allt := own || shared || coach || array['clients','assigned_exercises'];
  -- 1) Quita las políticas abiertas y deja solo «el coach puede todo».
  foreach t in array allt loop
    if to_regclass('public.' || t) is null then continue; end if;
    for r in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy if exists %I on public.%I', r.policyname, t);
    end loop;
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy coach_todo on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
  -- 2) Cada atleta lee lo suyo.
  foreach t in array own loop
    if to_regclass('public.' || t) is null then continue; end if;
    execute format('create policy atleta_lee on public.%I for select to authenticated using (client_id = public.my_client_id())', t);
  end loop;
  -- 3) Lo compartido (ejercicios, programación, horario, comunidad) lo leen los miembros.
  foreach t in array shared loop
    if to_regclass('public.' || t) is null then continue; end if;
    execute format('create policy miembro_lee on public.%I for select to authenticated using (public.is_member())', t);
  end loop;
end $$;

-- 4) Casos concretos
create policy atleta_lee on public.clients for select to authenticated using (id = public.my_client_id());

create policy atleta_lee on public.assigned_exercises for select to authenticated
  using (session_id in (select id from public.assigned_sessions where client_id = public.my_client_id()));
create policy atleta_marca on public.assigned_exercises for update to authenticated
  using (session_id in (select id from public.assigned_sessions where client_id = public.my_client_id()))
  with check (session_id in (select id from public.assigned_sessions where client_id = public.my_client_id()));
create policy atleta_marca on public.assigned_sessions for update to authenticated
  using (client_id = public.my_client_id()) with check (client_id = public.my_client_id());

create policy atleta_reserva on public.sessions for insert to authenticated with check (client_id = public.my_client_id());

do $$
declare x text[];
  acts text[][] := array[
    array['waitlist','insert'], array['waitlist','delete'],
    array['progress','insert'], array['progress','delete'],
    array['personal_records','insert'], array['achievements','insert'],
    array['client_photos','insert'], array['client_photos','update'], array['client_photos','delete'],
    array['forum_posts','insert'], array['forum_posts','delete']];
begin
  foreach x slice 1 in array acts loop
    if to_regclass('public.' || x[1]) is null then continue; end if;
    if x[2] = 'insert' then
      execute format('create policy %I on public.%I for insert to authenticated with check (client_id = public.my_client_id())', 'atleta_' || x[2], x[1]);
    elsif x[2] = 'update' then
      execute format('create policy %I on public.%I for update to authenticated using (client_id = public.my_client_id()) with check (client_id = public.my_client_id())', 'atleta_' || x[2], x[1]);
    else
      execute format('create policy %I on public.%I for delete to authenticated using (client_id = public.my_client_id())', 'atleta_' || x[2], x[1]);
    end if;
  end loop;
end $$;

-- 5) Fotos (buckets avatars y forum): subir/ver solo con sesión iniciada.
--    (Las fotos ya subidas siguen abriéndose con su enlace, que es imposible de adivinar.)
do $$ declare r record; begin
  for r in select policyname from pg_policies
            where schemaname = 'storage' and tablename = 'objects'
              and (roles @> array['anon']::name[] or roles @> array['public']::name[]) loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
  end loop;
end $$;
drop policy if exists kikote_ver on storage.objects;
drop policy if exists kikote_subir on storage.objects;
drop policy if exists kikote_editar on storage.objects;
drop policy if exists kikote_borrar on storage.objects;
create policy kikote_ver    on storage.objects for select to authenticated using (bucket_id in ('avatars','forum') and public.is_member());
create policy kikote_subir  on storage.objects for insert to authenticated with check (bucket_id in ('avatars','forum') and public.is_member());
create policy kikote_editar on storage.objects for update to authenticated using (bucket_id in ('avatars','forum') and public.is_member());
create policy kikote_borrar on storage.objects for delete to authenticated using (bucket_id in ('avatars','forum') and public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────
-- VUELTA ATRÁS (solo si algo va mal y necesitas abrirlo de nuevo un momento):
--
-- do $$ declare t text; begin
--   foreach t in array array['clients','sessions','history','payments','blocked_slots','forum_posts','exercises',
--     'training_plans','plan_days','plan_exercises','client_plans','progress','personal_records','achievements',
--     'annual_blocks','session_templates','template_exercises','client_weights','assigned_sessions','assigned_exercises',
--     'weight_history','waitlist','leads','app_settings','client_photos','exercise_notes','rm_tests'] loop
--     if to_regclass('public.'||t) is not null then
--       execute format('drop policy if exists abierto_temporal on public.%I', t);
--       execute format('create policy abierto_temporal on public.%I for all using (true) with check (true)', t);
--     end if; end loop; end $$;
-- ─────────────────────────────────────────────────────────────────────────
