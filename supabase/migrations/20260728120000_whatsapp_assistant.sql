-- Asistente de WhatsApp de Kikote Gym
-- Tabla para el historial de conversaciones + cron diario de recordatorios.

-- ── Historial de conversación por número de WhatsApp ──
create table if not exists public.wa_conversations (
  id          bigint generated always as identity primary key,
  wa_id       text not null,                         -- número de WhatsApp del cliente
  client_id   uuid references public.clients(id) on delete set null,
  role        text not null check (role in ('user', 'assistant')),
  content     text not null,
  created_at  timestamptz not null default now()
);

create index if not exists wa_conversations_wa_id_idx
  on public.wa_conversations (wa_id, created_at);

-- La tabla la usa solo el backend (service_role). Activamos RLS y no creamos
-- políticas públicas: así el frontend anónimo no puede leer las conversaciones.
alter table public.wa_conversations enable row level security;

-- ── Cron diario de recordatorios proactivos ──
-- Requiere las extensiones pg_cron y pg_net (actívalas en el panel de Supabase:
-- Database → Extensions). Sustituye <PROJECT_REF> y <CRON_SECRET> por los tuyos.
--
-- Corre todos los días a las 09:00 UTC. Ajusta la hora a tu zona horaria
-- (España en invierno = UTC+1, en verano = UTC+2).

-- create extension if not exists pg_cron;
-- create extension if not exists pg_net;

-- select cron.schedule(
--   'recordatorios-kikote-diario',
--   '0 9 * * *',
--   $$
--   select net.http_post(
--     url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/send-reminders',
--     headers := jsonb_build_object(
--       'Content-Type',  'application/json',
--       'Authorization', 'Bearer <CRON_SECRET>'
--     )
--   );
--   $$
-- );
