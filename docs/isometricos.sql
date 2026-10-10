-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Isométricos y readaptación (evolución de patologías)
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
-- En cada ejercicio isométrico se registran los segundos (actual_reps, p. ej.
-- "45s"), la carga y el dolor. Estas columnas guardan:
--   load_type: "pc" (peso corporal) · "pckg" (PC + lastre) · "kg" · "goma"
--   pain:      dolor percibido 0-10 (EVA)
-- ─────────────────────────────────────────────────────────────────────────

alter table public.assigned_exercises
  add column if not exists load_type text,
  add column if not exists pain smallint;
