-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Dieta: registro diario de comidas y agua del atleta
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
--   · El plan (kcal, macros, agua, comidas y notas) lo pone el coach en la
--     ficha del cliente (clients.profile.diet), sin columnas nuevas.
--   · diet_logs guarda, por día, qué comidas del plan ha marcado y cuántos
--     vasos de agua lleva. Cada atleta ve y cambia lo suyo; el coach lo ve todo.
-- Necesita las funciones de docs/seguridad-1.sql (is_admin, my_client_id).
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.diet_logs (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references public.clients(id) on delete cascade,
  date       date not null,
  meals      int[] not null default '{}',   -- posiciones de las comidas del plan hechas ese día
  water      int not null default 0,        -- vasos de agua (250 ml)
  updated_at timestamptz not null default now(),
  unique (client_id, date)
);

alter table public.diet_logs enable row level security;
drop policy if exists coach_todo    on public.diet_logs;
drop policy if exists atleta_lee    on public.diet_logs;
drop policy if exists atleta_crea   on public.diet_logs;
drop policy if exists atleta_cambia on public.diet_logs;
create policy coach_todo    on public.diet_logs for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy atleta_lee    on public.diet_logs for select to authenticated using (client_id = public.my_client_id());
create policy atleta_crea   on public.diet_logs for insert to authenticated with check (client_id = public.my_client_id());
create policy atleta_cambia on public.diet_logs for update to authenticated using (client_id = public.my_client_id()) with check (client_id = public.my_client_id());
