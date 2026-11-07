-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — La valoración recoge toda la ficha del cliente
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
-- Añade a la valoración un hueco para el resto de datos de la ficha
-- (teléfono, email, nacimiento, sexo, altura, medicación, objetivo, nivel,
-- contacto de emergencia…), que pasan solos al cliente al convertirlo.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.leads add column if not exists profile jsonb not null default '{}'::jsonb;
