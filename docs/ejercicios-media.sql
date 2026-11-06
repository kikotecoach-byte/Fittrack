-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Fotos y vídeos explicativos de cada ejercicio
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
--   · Tabla exercise_media: fotos, vídeos y enlaces (YouTube, Instagram…) por
--     ejercicio. Los ven el coach y los atletas con sesión; solo el coach
--     puede añadir o borrar.
--   · Almacén «exercise-media» (público, máx. 50 MB por archivo) para subir
--     las fotos y los vídeos desde la app.
-- Necesita las funciones de docs/seguridad-1.sql (is_admin, is_member).
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.exercise_media (
  id           uuid primary key default gen_random_uuid(),
  exercise_key text not null,                 -- nombre del ejercicio en minúsculas
  kind         text not null check (kind in ('image','video','link')),
  url          text not null,
  path         text,                          -- ruta en el almacén (para poder borrarlo)
  caption      text,
  created_at   timestamptz not null default now()
);
create index if not exists exercise_media_key on public.exercise_media (exercise_key);

alter table public.exercise_media enable row level security;
drop policy if exists exercise_media_ver     on public.exercise_media;
drop policy if exists exercise_media_coach   on public.exercise_media;
create policy exercise_media_ver   on public.exercise_media for select to authenticated using (public.is_member());
create policy exercise_media_coach on public.exercise_media for all    to authenticated using (public.is_admin()) with check (public.is_admin());

-- Almacén de archivos (público para que los vídeos se reproduzcan directamente)
insert into storage.buckets (id, name, public, file_size_limit)
values ('exercise-media', 'exercise-media', true, 52428800)
on conflict (id) do update set public = true, file_size_limit = 52428800, allowed_mime_types = null;

drop policy if exists kikote_media_ver    on storage.objects;
drop policy if exists kikote_media_subir  on storage.objects;
drop policy if exists kikote_media_editar on storage.objects;
drop policy if exists kikote_media_borrar on storage.objects;
create policy kikote_media_ver    on storage.objects for select to authenticated using (bucket_id = 'exercise-media' and public.is_member());
create policy kikote_media_subir  on storage.objects for insert to authenticated with check (bucket_id = 'exercise-media' and public.is_admin());
create policy kikote_media_editar on storage.objects for update to authenticated using (bucket_id = 'exercise-media' and public.is_admin());
create policy kikote_media_borrar on storage.objects for delete to authenticated using (bucket_id = 'exercise-media' and public.is_admin());
