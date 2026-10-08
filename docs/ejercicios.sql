-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Ejercicios propios (crear ejercicios con músculos y material)
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
-- Añade a la biblioteca de ejercicios el material usado y las series, reps
-- y descanso por defecto. Sin esto también se pueden crear ejercicios, pero
-- el material se deduce del nombre.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.exercises
  add column if not exists equipment    text,
  add column if not exists default_sets int,
  add column if not exists default_reps text,
  add column if not exists rest_seconds int;
