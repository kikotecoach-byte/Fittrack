-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — TODO EN DIRECTO en todos los dispositivos (iPad, móviles…)
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
-- (Incluye y amplía docs/tiempo-real.sql: no hace falta ejecutar aquel.)
--
--   1. Activa «Realtime» en TODAS las tablas de la app: clientes, reservas,
--      asistencia, pagos, entrenos, cargas, programación, horario, comunidad,
--      valoraciones, notas, tests de RM, fotos… Cualquier cambio hecho en un
--      dispositivo aparece al momento en los demás (coach y atletas).
--   2. Guarda el progreso de cada serie al entrenar (series hechas y pesos de
--      cada serie), para que el iPad y el móvil vean exactamente lo mismo.
--   Cada atleta sigue recibiendo solo lo suyo: lo deciden las políticas de
--   seguridad que ya tienes (seguridad-1/2/3.sql).
--   Sin este SQL la app también se pone al día, pero cada 30 s y al volver a ella.
-- ─────────────────────────────────────────────────────────────────────────

-- 2) Progreso por serie
alter table public.assigned_exercises add column if not exists sets_done int;
alter table public.assigned_exercises add column if not exists set_weights jsonb;

-- 1) Realtime en todas las tablas que existan
do $$
declare t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach t in array array[
    'clients','sessions','history','payments','blocked_slots','forum_posts','forum_comments','exercises',
    'training_plans','client_plans','progress','personal_records','achievements','annual_blocks',
    'session_templates','template_exercises','client_weights','assigned_sessions','assigned_exercises',
    'weight_history','waitlist','leads','open_sessions','app_settings','rm_tests','exercise_notes',
    'exercise_media','client_photos'] loop
    if to_regclass('public.' || t) is not null
       and not exists (select 1 from pg_publication_tables
                       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Comprobación: tablas con Realtime activado
select tablename from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' order by 1;
