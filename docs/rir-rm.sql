-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Intensidad relativa (RIR) y RM estimado
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
--   rir        : RIR objetivo prescrito para el ejercicio (reps en reserva)
--   actual_rir : RIR real que dejó la persona en la serie
--   rm_tests   : tests de RM hechos a mano (kg × reps @RIR, con fecha)
-- El RM estimado se calcula con kg ÷ %RM(reps + RIR).
-- ─────────────────────────────────────────────────────────────────────────

alter table public.assigned_exercises
  add column if not exists rir smallint,
  add column if not exists actual_rir smallint;

create table if not exists public.rm_tests (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid references public.clients(id) on delete cascade,
  exercise_name text not null,
  kg            numeric not null,
  reps          smallint not null default 1,
  rir           smallint not null default 0,
  tested_on     date not null default current_date,
  created_at    timestamptz not null default now()
);
create index if not exists rm_tests_client_idx on public.rm_tests (client_id, exercise_name);

alter table public.rm_tests enable row level security;
drop policy if exists rm_tests_all on public.rm_tests;
create policy rm_tests_all on public.rm_tests for all using (true) with check (true);
