-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Cambios del coach al momento en la app del cliente
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
--   · Activa «Realtime» en las tablas de entrenos, clases, opens, horario y
--     bloqueos: en cuanto el coach ajusta una sesión (ejercicios, cargas,
--     orden, hora de la clase o del open), la app del cliente se actualiza sola.
--   · Cada cliente solo recibe sus propias filas (lo deciden las políticas de
--     seguridad que ya tienes, docs/seguridad-1.sql y seguridad-2.sql).
--   · Sin esto la app también se actualiza, pero cada 45 s y al volver a abrirla.
-- ─────────────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach t in array array['assigned_sessions','assigned_exercises','sessions','open_sessions','app_settings','blocked_slots'] loop
    if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = t)
       and not exists (select 1 from pg_publication_tables
                       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
