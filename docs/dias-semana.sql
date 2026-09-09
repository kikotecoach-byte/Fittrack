-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Días de entrenamiento por semana (microciclo)
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
--   days_week  = nº de sesiones/semana (para dimensionar el microciclo).
--   train_days = días concretos que entrena, como texto "1,3,5"
--                (0=Dom, 1=Lun, 2=Mar, 3=Mié, 4=Jue, 5=Vie, 6=Sáb).
-- La app usa estos datos para ordenar el microciclo automático y para la
-- vista semanal de cada cliente (qué le toca y qué ha hecho).
-- ─────────────────────────────────────────────────────────────────────────

alter table public.clients
  add column if not exists days_week  int  not null default 4,
  add column if not exists train_days text;
