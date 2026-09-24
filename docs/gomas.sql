-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Gomas (bandas elásticas) como carga en ejercicios de peso corporal
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
-- En ejercicios sin carga externa (dominadas, fondos, plancha, burpees…) se
-- registra el color de la goma usada en vez de kg. Se guarda como texto.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.assigned_exercises
  add column if not exists load_band text;
