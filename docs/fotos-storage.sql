-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Arreglo de la subida de fotos
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
--   · Crea (o corrige) los almacenes «avatars» (perfil y progreso) y «forum»
--     (comunidad) como públicos, sin límite de tamaño ni de tipo de imagen.
--   · Da permiso para subir, ver, cambiar y borrar fotos en esos almacenes.
--   · Crea la tabla de fotos de progreso si no existe.
-- Si más adelante ejecutas seguridad-2.sql, estos permisos se sustituyen por
-- los de «solo usuarios con sesión».
-- ─────────────────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true), ('forum', 'forum', true)
on conflict (id) do update set public = true;
update storage.buckets set file_size_limit = null, allowed_mime_types = null where id in ('avatars', 'forum');

drop policy if exists kikote_fotos_ver    on storage.objects;
drop policy if exists kikote_fotos_subir  on storage.objects;
drop policy if exists kikote_fotos_editar on storage.objects;
drop policy if exists kikote_fotos_borrar on storage.objects;
create policy kikote_fotos_ver    on storage.objects for select using (bucket_id in ('avatars', 'forum'));
create policy kikote_fotos_subir  on storage.objects for insert with check (bucket_id in ('avatars', 'forum'));
create policy kikote_fotos_editar on storage.objects for update using (bucket_id in ('avatars', 'forum')) with check (bucket_id in ('avatars', 'forum'));
create policy kikote_fotos_borrar on storage.objects for delete using (bucket_id in ('avatars', 'forum'));

create table if not exists public.client_photos (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid references public.clients(id) on delete cascade,
  url        text not null,
  note       text,
  taken_on   date,
  created_at timestamptz not null default now()
);
alter table public.client_photos enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'client_photos') then
    create policy client_photos_all on public.client_photos for all using (true) with check (true);
  end if;
end $$;
