-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Días de entrenamiento por semana (microciclo)
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
-- Define cuántas sesiones a la semana entrena cada persona; la app usa este
-- número para el microciclo automático (3 = split corto / fullbody,
-- 5 = split más específico). Por defecto 4.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.clients
  add column if not exists days_week int not null default 4;
