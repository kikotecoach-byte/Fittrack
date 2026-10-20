-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Medidas corporales ampliadas
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
-- Además de peso, % grasa y cintura: masa muscular, cadera, pecho, brazo y muslo.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.progress
  add column if not exists muscle_mass numeric,
  add column if not exists hip numeric,
  add column if not exists chest numeric,
  add column if not exists arm numeric,
  add column if not exists thigh numeric;
