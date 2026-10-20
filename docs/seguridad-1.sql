-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — SEGURIDAD · PASO 1 de 2 (no rompe nada)
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
--
-- Prepara el inicio de sesión seguro:
--   · Coach: email + contraseña (usuario de Supabase Auth).
--   · Atleta: activa su cuenta una vez con nombre + código y elige
--     contraseña; después entra con código + contraseña.
-- Todavía NO cierra la base de datos: eso es el paso 2 (seguridad-2.sql),
-- cuando hayas comprobado que entras bien con tu usuario de coach.
-- ─────────────────────────────────────────────────────────────────────────

-- Coaches (quién es administrador)
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security; -- sin políticas: solo vía funciones

-- Cada atleta queda unido a su cuenta de acceso
alter table public.clients add column if not exists auth_user_id uuid unique references auth.users(id) on delete set null;

-- ¿Quién soy?
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.admins where user_id = auth.uid())
$$;
create or replace function public.my_client_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.clients where auth_user_id = auth.uid() limit 1
$$;
create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin() or public.my_client_id() is not null
$$;

-- Activación de la cuenta del atleta (nombre + código), con límite de intentos
create table if not exists public.claim_attempts (
  id bigserial primary key, code text, user_id uuid, ok boolean, at timestamptz not null default now()
);
alter table public.claim_attempts enable row level security;

create or replace function public.norm_txt(t text) returns text language sql immutable as $$
  select translate(lower(trim(coalesce(t,''))), 'áéíóúüñàèìòù', 'aeiouunaeiou')
$$;

create or replace function public.claim_client(p_name text, p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid; fails int; expected text;
begin
  if auth.uid() is null then raise exception 'no autenticado'; end if;
  select count(*) into fails from public.claim_attempts
   where (upper(code) = upper(trim(p_code)) or user_id = auth.uid()) and not ok and at > now() - interval '1 hour';
  if fails >= 5 then raise exception 'demasiados intentos, espera una hora'; end if;
  expected := lower(regexp_replace(coalesce(p_code,''), '[^a-zA-Z0-9]', '', 'g')) || '@atleta.kikotegym.app';
  if lower(coalesce(auth.jwt() ->> 'email', '')) <> expected then raise exception 'cuenta no válida para ese código'; end if;
  select id into cid from public.clients
   where upper(trim(code)) = upper(trim(p_code)) and public.norm_txt(name) = public.norm_txt(p_name) and auth_user_id is null;
  insert into public.claim_attempts(code, user_id, ok) values (upper(trim(p_code)), auth.uid(), cid is not null);
  if cid is null then return null; end if;
  update public.clients set auth_user_id = auth.uid() where id = cid;
  return cid;
end $$;

-- El coach restablece el acceso de un atleta (p. ej. si olvida la contraseña):
-- borra su cuenta de acceso y el atleta vuelve a activarla.
create or replace function public.admin_reset_access(p_client uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid; c text;
begin
  if not public.is_admin() then raise exception 'solo el coach'; end if;
  select auth_user_id, code into uid, c from public.clients where id = p_client;
  update public.clients set auth_user_id = null where id = p_client;
  if uid is not null then delete from auth.users where id = uid; end if;
  -- libera también una cuenta «huérfana» creada con ese código
  delete from auth.users where lower(email) = lower(regexp_replace(coalesce(c,''), '[^a-zA-Z0-9]', '', 'g')) || '@atleta.kikotegym.app'
    and id not in (select auth_user_id from public.clients where auth_user_id is not null);
end $$;

-- Aforo de las clases para los atletas (sin ver los datos de los demás:
-- solo nombre de pila, color y foto de perfil).
create or replace function public.slot_roster(p_from text, p_to text)
returns table(date text, "time" text, client_id uuid, first_name text, color text, avatar_url text)
language sql stable security definer set search_path = public as $$
  select s.date::text, s.time::text, s.client_id, split_part(c.name, ' ', 1), c.color, c.avatar_url
    from public.sessions s join public.clients c on c.id = s.client_id
   where public.is_member() and s.date::text between p_from and p_to
$$;

-- Comunidad: nombre e inicial, color y foto de perfil de los atletas.
create or replace function public.community_members()
returns table(id uuid, name text, color text, avatar_url text)
language sql stable security definer set search_path = public as $$
  select c.id,
         split_part(c.name, ' ', 1) || coalesce(nullif(' ' || left(split_part(c.name, ' ', 2), 1) || '.', ' .'), ''),
         c.color, c.avatar_url
    from public.clients c
   where public.is_member()
$$;

-- «Me gusta» en la comunidad sin poder editar las publicaciones de otros.
create or replace function public.toggle_like(p_post uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me text; cur jsonb; newj jsonb; typ text; udt text;
begin
  me := coalesce(public.my_client_id()::text, case when public.is_admin() then 'coach' end);
  if me is null then raise exception 'sin acceso'; end if;
  select data_type, udt_name into typ, udt from information_schema.columns
   where table_schema = 'public' and table_name = 'forum_posts' and column_name = 'liked_by';
  execute 'select to_jsonb(liked_by) from public.forum_posts where id = $1' into cur using p_post;
  cur := coalesce(cur, '[]'::jsonb);
  if cur ? me then newj := cur - me; else newj := cur || to_jsonb(me); end if;
  if typ in ('jsonb','json') then
    execute 'update public.forum_posts set liked_by = $1, likes = $2 where id = $3' using newj, jsonb_array_length(newj), p_post;
  else
    execute format('update public.forum_posts set liked_by = (select coalesce(array_agg(x), ''{}'')::%s[] from jsonb_array_elements_text($1) x), likes = $2 where id = $3', substr(udt, 2))
      using newj, jsonb_array_length(newj), p_post;
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- DESPUÉS de crear tu usuario de coach en Authentication → Users,
-- cambia el email y ejecuta esta línea para hacerte administrador:
--
--   insert into public.admins(user_id) select id from auth.users where email = 'TU_EMAIL@ejemplo.com' on conflict do nothing;
-- ─────────────────────────────────────────────────────────────────────────
