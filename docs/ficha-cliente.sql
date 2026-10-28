-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Ficha personal del cliente
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
-- Guarda los datos ampliados de cada cliente (fecha de nacimiento, sexo,
-- altura, profesión, lesiones, medicación, objetivo detallado, contacto de
-- emergencia, cómo nos conoció) en una sola columna.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.clients
  add column if not exists profile jsonb not null default '{}'::jsonb;
