-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Lista de espera
--
-- Ejecuta esto UNA vez en Supabase → SQL Editor.
-- Guarda las personas apuntadas a una clase que estaba llena, para avisarlas
-- cuando se libere un hueco a esa misma hora.
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.waitlist (
  id         bigint generated always as identity primary key,
  client_id  uuid references public.clients(id) on delete cascade,
  date       date not null,
  time       text not null,
  notified   boolean not null default false,   -- si ya se avisó del hueco
  created_at timestamptz not null default now()
);

create index if not exists waitlist_slot_idx on public.waitlist (date, time);

-- Igual que el resto de tablas: se usa desde el navegador con la clave pública.
alter table public.waitlist enable row level security;
drop policy if exists waitlist_all on public.waitlist;
create policy waitlist_all on public.waitlist for all using (true) with check (true);
