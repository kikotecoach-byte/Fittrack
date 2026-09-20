-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Valoraciones / Leads
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack).
-- Guarda las valoraciones iniciales (perfil de lead). Si el lead compra,
-- se convierte en cliente desde la app (status = 'cliente').
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.leads (
  id                  uuid primary key default gen_random_uuid(),
  name                text,
  age                 int,
  job                 text,
  experience          text,
  diet                text,
  injuries            text,
  availability        text,
  weight              numeric,
  date                date,
  time                text,
  tests               jsonb,          -- tests de movilidad/estabilidad {clave:{done,obs}}
  notes               text,
  status              text not null default 'lead',   -- lead | cliente | descartado
  converted_client_id uuid,
  created_at          timestamptz not null default now()
);

alter table public.leads enable row level security;
drop policy if exists leads_all on public.leads;
create policy leads_all on public.leads for all using (true) with check (true);
