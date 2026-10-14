-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Notas del gesto (por cliente y ejercicio)
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
-- Cada nota queda con su fecha y aparece en todas las sesiones en las que ese
-- cliente haga ese ejercicio (técnica, molestias, ajustes, progresos…).
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.exercise_notes (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid references public.clients(id) on delete cascade,
  exercise_name text not null,
  note          text not null,
  created_at    timestamptz not null default now()
);
create index if not exists exercise_notes_client_idx on public.exercise_notes (client_id, exercise_name);

alter table public.exercise_notes enable row level security;
drop policy if exists exercise_notes_all on public.exercise_notes;
create policy exercise_notes_all on public.exercise_notes for all using (true) with check (true);
