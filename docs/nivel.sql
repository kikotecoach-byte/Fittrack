-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Nivel del cliente (principiante / intermedio / avanzado)
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
-- El generador y el botón "Ajustar a su nivel" adaptan cada sesión según el
-- nivel: complejidad de los ejercicios y volumen total de series.
-- Sin valor = intermedio.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.clients
  add column if not exists level text;
