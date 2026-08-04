-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Configuración de horario y capacidad (atletas por hora)
--
-- Ejecuta esto UNA vez en Supabase → SQL Editor.
-- Crea la tabla donde se guarda tu horario de trabajo y los atletas por hora.
-- Mientras no la crees, la app usa los valores por defecto (mañana 10-13,
-- tarde 17-20, 1 atleta/hora) pero no podrás guardar cambios.
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.app_settings (
  id         int primary key default 1,
  config     jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- Fila inicial con tu horario (mañana 10-13, tarde 17-20, 1 atleta/hora).
insert into public.app_settings (id, config)
values (1, jsonb_build_object(
  'morningFrom','10:00','morningTo','13:00',
  'afternoonFrom','17:00','afternoonTo','20:00',
  'defaultCapacity',1,'capacity','{}'::jsonb
))
on conflict (id) do nothing;

-- La app usa la clave pública (anon) desde el navegador, igual que con el resto
-- de tus tablas. Activamos RLS y permitimos lectura/escritura para que funcione.
alter table public.app_settings enable row level security;

drop policy if exists app_settings_all on public.app_settings;
create policy app_settings_all on public.app_settings
  for all using (true) with check (true);
