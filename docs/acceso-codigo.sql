-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Acceso del atleta con su NOMBRE + su CÓDIGO (sin contraseña)
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
-- Requiere docs/seguridad-1.sql (ya ejecutado).
--
--   · El atleta entra escribiendo su nombre (tal como lo tienes en su ficha; da
--     igual mayúsculas y tildes) y el código que le das. La primera vez su cuenta
--     se activa sola.
--   · Los atletas que ya activaron su app con contraseña pasan a entrar también
--     con nombre + código (su contraseña antigua deja de valer).
--   · Si cambias el nombre o el código de un atleta en su ficha, su acceso cambia
--     solo: entra con los datos nuevos, sin volver a activar nada.
--   · La seguridad depende del código: usa códigos de 6 caracteres (botón 🎲 en
--     la ficha) y no los repitas.
-- ─────────────────────────────────────────────────────────────────────────

create extension if not exists pgcrypto with schema extensions;

-- Nombre normalizado (minúsculas, sin tildes, espacios simples) y credenciales
-- que calcula también la app al entrar.
create or replace function public.athlete_key(t text) returns text language sql immutable as $$
  select regexp_replace(translate(lower(trim(coalesce(t,''))), 'áéíóúüñàèìòùÁÉÍÓÚÜÑÀÈÌÒÙ', 'aeiouunaeiouaeiouunaeiou'), '\s+', ' ', 'g')
$$;
create or replace function public.athlete_pw(p_name text, p_code text) returns text language sql immutable as $$
  select 'kk1|' || public.athlete_key(p_name) || '|' || upper(regexp_replace(coalesce(p_code,''), '[^a-zA-Z0-9]', '', 'g'))
$$;
create or replace function public.athlete_mail(p_code text) returns text language sql immutable as $$
  select lower(regexp_replace(coalesce(p_code,''), '[^a-zA-Z0-9]', '', 'g')) || '@atleta.kikotegym.app'
$$;

-- Activación (la hace la app sola la primera vez): nombre + código.
create or replace function public.claim_client(p_name text, p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid; fails int;
begin
  if auth.uid() is null then raise exception 'no autenticado'; end if;
  select count(*) into fails from public.claim_attempts
   where (upper(code) = upper(trim(p_code)) or user_id = auth.uid()) and not ok and at > now() - interval '1 hour';
  if fails >= 5 then raise exception 'demasiados intentos, espera una hora'; end if;
  if lower(coalesce(auth.jwt() ->> 'email', '')) <> public.athlete_mail(p_code) then raise exception 'cuenta no válida para ese código'; end if;
  select id into cid from public.clients
   where upper(regexp_replace(coalesce(code,''), '[^a-zA-Z0-9]', '', 'g')) = upper(regexp_replace(coalesce(p_code,''), '[^a-zA-Z0-9]', '', 'g'))
     and public.athlete_key(name) = public.athlete_key(p_name) and auth_user_id is null;
  insert into public.claim_attempts(code, user_id, ok) values (upper(trim(p_code)), auth.uid(), cid is not null);
  if cid is null then return null; end if;
  update public.clients set auth_user_id = auth.uid() where id = cid;
  return cid;
end $$;

-- Si alguien escribe un código bien y el nombre mal, la cuenta que se creó al
-- intentarlo se borra (para no bloquear al atleta de verdad).
create or replace function public.drop_unclaimed_me() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then return; end if;
  if exists (select 1 from public.clients where auth_user_id = auth.uid()) then return; end if;
  if exists (select 1 from public.admins where user_id = auth.uid()) then return; end if;
  delete from auth.users where id = auth.uid() and email like '%@atleta.kikotegym.app';
end $$;
grant execute on function public.drop_unclaimed_me() to authenticated;
grant execute on function public.claim_client(text, text) to authenticated;

-- Pone el acceso de una cuenta de atleta en nombre + código.
create or replace function public.set_athlete_login(p_uid uuid, p_name text, p_code text) returns void
language plpgsql security definer set search_path = public, auth, extensions as $$
declare m text := public.athlete_mail(p_code);
begin
  if p_uid is null then return; end if;
  -- libera el email nuevo si lo tenía una cuenta huérfana (sin atleta)
  delete from auth.users where lower(email) = m and id <> p_uid
    and id not in (select auth_user_id from public.clients where auth_user_id is not null)
    and id not in (select user_id from public.admins);
  update auth.users set email = m,
         encrypted_password = extensions.crypt(public.athlete_pw(p_name, p_code), extensions.gen_salt('bf')),
         updated_at = now()
   where id = p_uid;
  update auth.identities set identity_data = coalesce(identity_data, '{}'::jsonb) || jsonb_build_object('email', m)
   where user_id = p_uid and provider = 'email';
end $$;
revoke all on function public.set_athlete_login(uuid, text, text) from public, anon, authenticated;

-- Al cambiar el nombre o el código en la ficha, su acceso cambia solo.
create or replace function public.sync_athlete_login() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.auth_user_id is not null and (new.code is distinct from old.code or new.name is distinct from old.name) then
    perform public.set_athlete_login(new.auth_user_id, new.name, new.code);
  end if;
  return new;
end $$;
drop trigger if exists sync_athlete_login on public.clients;
create trigger sync_athlete_login after update of code, name on public.clients
  for each row execute function public.sync_athlete_login();

-- Atletas que ya activaron su app: pasan a nombre + código.
do $$ declare r record; begin
  for r in select id, name, code, auth_user_id from public.clients where auth_user_id is not null loop
    perform public.set_athlete_login(r.auth_user_id, r.name, r.code);
  end loop;
end $$;
