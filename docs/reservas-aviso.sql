-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Aviso al momento de cada reserva (para aprobarla)
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
--   · Activa «Realtime» en la tabla sessions: en cuanto un cliente reserva, la
--     app del coach lo recibe al instante (aviso + notificación del sistema).
--   · Sin esto la app también avisa, pero revisando cada 45 s y al volver a abrirla.
-- ─────────────────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'sessions') then
    alter publication supabase_realtime add table public.sessions;
  end if;
end $$;
