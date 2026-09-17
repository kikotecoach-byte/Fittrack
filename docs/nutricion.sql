-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Plan de nutrición por cliente
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
-- Guarda el plan de nutrición individualizado (objetivo, peso usado, kcal y
-- macros) para cada persona. Se calcula desde sus datos y es editable.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.clients
  add column if not exists nutrition jsonb;
