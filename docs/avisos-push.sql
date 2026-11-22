-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Avisos en el móvil del coach cuando un cliente termina su entreno
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
-- Antes (o después) despliega la función «avisar-coach»
-- (supabase/functions/avisar-coach/index.ts). Pasos en docs/avisos-push.md.
--
--   · push_config: claves del servicio de avisos (las crea la función sola).
--   · push_subs:   móviles/ordenadores del coach que reciben avisos.
--   · push_sent:   para no avisar dos veces del mismo entreno.
--   Las tres son privadas: solo la función (clave de servicio) las usa.
--
--   · Cuando un CLIENTE termina su entreno (todos los ejercicios marcados) o
--     marca su open como hecho, la base de datos llama a la función y te llega
--     el aviso al móvil aunque tengas la app cerrada. Si lo marcas tú (coach),
--     no te avisa.
-- ─────────────────────────────────────────────────────────────────────────

create extension if not exists pg_net with schema extensions;

create table if not exists public.push_config (
  id int primary key default 1 check (id = 1),
  public_key text not null,
  private_jwk jsonb not null,
  created_at timestamptz default now()
);
create table if not exists public.push_subs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  endpoint text unique not null,
  p256dh text not null,
  auth text not null,
  ua text,
  created_at timestamptz default now()
);
create table if not exists public.push_sent (
  key text primary key,
  at timestamptz default now()
);
alter table public.push_config enable row level security;
alter table public.push_subs   enable row level security;
alter table public.push_sent   enable row level security;
-- (sin políticas: nadie desde la app puede leerlas ni tocarlas, solo la función)

-- Llama a la función al terminar un entreno (clase u open).
create or replace function public.push_on_done() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status in ('done','completed')
     and coalesce(old.status,'') not in ('done','completed')
     and not coalesce(public.is_admin(), false) then          -- lo marca el cliente, no el coach
    begin
      perform net.http_post(
        url     := 'https://enknfffiyexuvodqlfmh.supabase.co/functions/v1/avisar-coach',
        body    := jsonb_build_object('action','event','table',TG_TABLE_NAME,'id',new.id),
        headers := jsonb_build_object(
          'Content-Type','application/json',
          -- clave pública (anon) de la app: la misma que ya va en index.html
          'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVua25mZmZpeWV4dXZvZHFsZm1oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3MTE4NTUsImV4cCI6MjA5MjI4Nzg1NX0.9VvbzXpPiKBJAnbwHIbIivixfnhENoL4LR_s2KtX7yY')
      );
    exception when others then null;                           -- un fallo del aviso nunca bloquea el guardado
    end;
  end if;
  return new;
end $$;

drop trigger if exists push_on_done on public.assigned_sessions;
create trigger push_on_done after update of status on public.assigned_sessions
  for each row execute function public.push_on_done();

do $$ begin
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='open_sessions') then
    execute 'drop trigger if exists push_on_done on public.open_sessions';
    execute 'create trigger push_on_done after update of status on public.open_sessions for each row execute function public.push_on_done()';
  end if;
end $$;

-- Vuelta atrás (si quisieras quitarlo):
-- drop trigger if exists push_on_done on public.assigned_sessions;
-- drop trigger if exists push_on_done on public.open_sessions;
-- drop function if exists public.push_on_done();
