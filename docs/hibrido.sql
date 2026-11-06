-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Modalidad híbrida: clases con el coach + sesiones «open»
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
--   · Tabla open_sessions: los días que el atleta entrena por su cuenta.
--     El atleta crea, cambia y borra las suyas; el coach lo ve y gestiona todo.
--   · La modalidad (clases / híbrido) y las sesiones open por semana se
--     guardan en la ficha del cliente (clients.profile), sin columnas nuevas.
-- Necesita las funciones de docs/seguridad-1.sql (is_admin, my_client_id).
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.open_sessions (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references public.clients(id) on delete cascade,
  date       date not null,
  time       text,                                   -- hora aproximada (opcional)
  status     text not null default 'planned' check (status in ('planned','done')),
  note       text,
  created_at timestamptz not null default now()
);
create index if not exists open_sessions_client_date on public.open_sessions (client_id, date);

alter table public.open_sessions enable row level security;
drop policy if exists coach_todo    on public.open_sessions;
drop policy if exists atleta_lee    on public.open_sessions;
drop policy if exists atleta_crea   on public.open_sessions;
drop policy if exists atleta_cambia on public.open_sessions;
drop policy if exists atleta_borra  on public.open_sessions;
create policy coach_todo    on public.open_sessions for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy atleta_lee    on public.open_sessions for select to authenticated using (client_id = public.my_client_id());
create policy atleta_crea   on public.open_sessions for insert to authenticated with check (client_id = public.my_client_id());
create policy atleta_cambia on public.open_sessions for update to authenticated using (client_id = public.my_client_id()) with check (client_id = public.my_client_id());
create policy atleta_borra  on public.open_sessions for delete to authenticated using (client_id = public.my_client_id());
