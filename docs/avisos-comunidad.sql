-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Comunidad: el coach publica y los atletas reciben avisos
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
-- Necesita docs/avisos-push.sql (tablas de avisos y pg_net) y la función
-- «avisar-coach» actualizada (supabase/functions/avisar-coach/index.ts).
--
--   · El coach puede publicar en la comunidad (sus publicaciones no tienen
--     atleta: client_id vacío).
--   · Cada publicación nueva llega como aviso al móvil de los atletas que los
--     activaron (no a quien publica) y, si la escribe un atleta, también al coach.
--   · Con la app abierta, la comunidad se actualiza al momento (Realtime).
-- ─────────────────────────────────────────────────────────────────────────

-- Publicaciones del coach (sin atleta)
alter table public.forum_posts alter column client_id drop not null;

-- Móviles de los atletas (los del coach quedan con client_id vacío)
alter table public.push_subs add column if not exists client_id uuid references public.clients(id) on delete cascade;

-- Aviso al publicar
create or replace function public.push_on_forum() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  begin
    perform net.http_post(
      url     := 'https://enknfffiyexuvodqlfmh.supabase.co/functions/v1/avisar-coach',
      body    := jsonb_build_object('action','forum','id',new.id),
      headers := jsonb_build_object(
        'Content-Type','application/json',
        -- clave pública (anon) de la app: la misma que ya va en index.html
        'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVua25mZmZpeWV4dXZvZHFsZm1oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3MTE4NTUsImV4cCI6MjA5MjI4Nzg1NX0.9VvbzXpPiKBJAnbwHIbIivixfnhENoL4LR_s2KtX7yY')
    );
  exception when others then null;   -- un fallo del aviso nunca bloquea la publicación
  end;
  return new;
end $$;
drop trigger if exists push_on_forum on public.forum_posts;
create trigger push_on_forum after insert on public.forum_posts
  for each row execute function public.push_on_forum();

-- Comunidad en tiempo real
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'forum_posts') then
    execute 'alter publication supabase_realtime add table public.forum_posts';
  end if;
end $$;
