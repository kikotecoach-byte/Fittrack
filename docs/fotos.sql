-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Fotos de progreso por cliente
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
-- Guarda fotos de cada cliente (cambios físicos, comparativas de test) para
-- ver un antes y un después. Las imágenes se suben al bucket "avatars"
-- (ya público) bajo la ruta fotos/<client_id>/. Aquí sólo se guarda la URL.
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.client_photos (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid references public.clients(id) on delete cascade,
  url        text not null,
  note       text,
  taken_on   date,
  created_at timestamptz not null default now()
);

alter table public.client_photos enable row level security;
drop policy if exists client_photos_all on public.client_photos;
create policy client_photos_all on public.client_photos for all using (true) with check (true);
