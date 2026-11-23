-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Aviso al móvil del coach cuando un cliente RESERVA una clase
-- Ejecuta en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
-- Necesita antes docs/avisos-push.sql (tablas de avisos y pg_net) y la
-- función «avisar-coach» actualizada (supabase/functions/avisar-coach/index.ts).
--
--   · Cuando un CLIENTE reserva una o varias clases a la vez, te llega UN aviso
--     con el día y la hora (y si está pendiente de confirmar). Si la creas tú
--     (coach), no te avisa.
--   · Por ahora quita el aviso de «entreno terminado». Para volver a tenerlo,
--     ejecuta otra vez docs/avisos-push.sql.
-- ─────────────────────────────────────────────────────────────────────────

-- Fuera el aviso de entreno terminado (por ahora).
drop trigger if exists push_on_done on public.assigned_sessions;
do $$ begin
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='open_sessions') then
    execute 'drop trigger if exists push_on_done on public.open_sessions';
  end if;
end $$;

-- Llama a la función con todas las clases que se acaban de reservar.
create or replace function public.push_on_book() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare ids jsonb;
begin
  if coalesce(public.is_admin(), false) then return null; end if;      -- la crea el coach: sin aviso
  select jsonb_agg(id::text) into ids from new_rows
   where coalesce(type,'') <> 'Clase privada';
  if ids is null then return null; end if;
  begin
    perform net.http_post(
      url     := 'https://enknfffiyexuvodqlfmh.supabase.co/functions/v1/avisar-coach',
      body    := jsonb_build_object('action','booking','ids',ids),
      headers := jsonb_build_object(
        'Content-Type','application/json',
        -- clave pública (anon) de la app: la misma que ya va en index.html
        'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVua25mZmZpeWV4dXZvZHFsZm1oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3MTE4NTUsImV4cCI6MjA5MjI4Nzg1NX0.9VvbzXpPiKBJAnbwHIbIivixfnhENoL4LR_s2KtX7yY')
    );
  exception when others then null;                                     -- un fallo del aviso nunca bloquea la reserva
  end;
  return null;
end $$;

drop trigger if exists push_on_book on public.sessions;
create trigger push_on_book after insert on public.sessions
  referencing new table as new_rows
  for each statement execute function public.push_on_book();

-- Comprobación: debe salir «push_on_book» en sessions y ningún push_on_done.
select tgname, tgrelid::regclass as tabla from pg_trigger where tgname in ('push_on_book','push_on_done');

-- Vuelta atrás (si quisieras quitarlo):
-- drop trigger if exists push_on_book on public.sessions;
-- drop function if exists public.push_on_book();
