-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Comentarios en la comunidad (coach y atletas)
-- Ejecuta en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
-- Ejecútalo DESPUÉS de docs/avisos-comunidad.sql y, para los avisos al móvil,
-- vuelve a desplegar la función «avisar-coach» (supabase/functions/avisar-coach).
--
--   · Cada publicación de la comunidad admite comentarios. El coach comenta
--     como «Coach» (client_id vacío); cada atleta, con su nombre.
--   · Todos los miembros leen los comentarios; cada atleta solo crea y borra
--     los suyos; el coach puede todo.
--   · Al comentar, a quien publicó le llega un aviso al móvil (si lo activó).
-- ─────────────────────────────────────────────────────────────────────────

-- Tabla (post_id con el mismo tipo que el id de forum_posts)
do $$ declare t text; begin
  select format_type(atttypid, atttypmod) into t from pg_attribute
   where attrelid = 'public.forum_posts'::regclass and attname = 'id';
  execute format('create table if not exists public.forum_comments (
    id          uuid primary key default gen_random_uuid(),
    post_id     %s not null references public.forum_posts(id) on delete cascade,
    client_id   uuid references public.clients(id) on delete cascade,
    author_name text,
    content     text not null check (char_length(content) between 1 and 1000),
    created_at  timestamptz not null default now())', t);
end $$;
create index if not exists forum_comments_post on public.forum_comments(post_id);

alter table public.forum_comments enable row level security;
drop policy if exists coach_todo     on public.forum_comments;
drop policy if exists miembro_lee    on public.forum_comments;
drop policy if exists atleta_comenta on public.forum_comments;
drop policy if exists atleta_borra   on public.forum_comments;
create policy coach_todo     on public.forum_comments for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy miembro_lee    on public.forum_comments for select to authenticated using (public.is_member());
create policy atleta_comenta on public.forum_comments for insert to authenticated with check (client_id = public.my_client_id());
create policy atleta_borra   on public.forum_comments for delete to authenticated using (client_id = public.my_client_id());

-- Aviso al comentar
create or replace function public.push_on_comment() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  begin
    perform net.http_post(
      url     := 'https://enknfffiyexuvodqlfmh.supabase.co/functions/v1/avisar-coach',
      body    := jsonb_build_object('action','comment','id',new.id),
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVua25mZmZpeWV4dXZvZHFsZm1oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3MTE4NTUsImV4cCI6MjA5MjI4Nzg1NX0.9VvbzXpPiKBJAnbwHIbIivixfnhENoL4LR_s2KtX7yY')
    );
  exception when others then null;   -- un fallo del aviso nunca bloquea el comentario
  end;
  return new;
end $$;
drop trigger if exists push_on_comment on public.forum_comments;
create trigger push_on_comment after insert on public.forum_comments
  for each row execute function public.push_on_comment();

-- Comentarios en tiempo real
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'forum_comments') then
    execute 'alter publication supabase_realtime add table public.forum_comments';
  end if;
end $$;
