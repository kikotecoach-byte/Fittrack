-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Ejecutar sesión (seguimiento de cargas)
--
-- Ejecuta esto UNA vez en Supabase → SQL Editor, en el proyecto Fittrack.
-- Añade a los ejercicios asignados los campos para registrar lo que la persona
-- hizo de verdad durante la sesión (hecho, carga real y reps reales).
-- ─────────────────────────────────────────────────────────────────────────

alter table public.assigned_exercises
  add column if not exists done          boolean not null default false,
  add column if not exists actual_weight  numeric,
  add column if not exists actual_reps    text,
  add column if not exists done_at        timestamptz;
