-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Objetivo del cliente
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
-- Añade el objetivo de cada persona para adaptar su programación.
--   'salud'    → entrenamiento concurrente (fuerza + cardio/circuitos)
--   'estetica' → más volumen de fuerza/hipertrofia y estabilidad
-- ─────────────────────────────────────────────────────────────────────────

alter table public.clients
  add column if not exists goal text;
