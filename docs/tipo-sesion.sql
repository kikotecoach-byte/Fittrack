-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Tipo de sesión en el entreno asignado
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
-- Guarda qué tipo de día es cada entreno generado (Fuerza inf/sup, Push,
-- Pull, Legs, Small muscles, Fullbody, HIIT, Movilidad…) para que la vista
-- de clase muestre el tipo real y el selector "Cambiar tipo" lo refleje.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.assigned_sessions
  add column if not exists day_type text;
