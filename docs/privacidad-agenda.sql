-- ─────────────────────────────────────────────────────────────────────────
-- Kikote Gym — Privacidad en la agenda
-- Ejecuta una vez en Supabase → SQL Editor (proyecto Fittrack). Se puede repetir.
-- Requiere docs/seguridad-1.sql.
--
--   · Por defecto, en la agenda los atletas ven quién va a cada clase (nombre
--     de pila, color y foto).
--   · Quien quiera privacidad (lo activa el atleta en «Reservar», o tú en su
--     ficha) aparece para los demás como «Atleta»: sin nombre, foto ni color, y
--     con un identificador distinto en cada clase, así no se le puede seguir.
--   · Tú (coach) sigues viendo a todos con su nombre, y el propio atleta se ve
--     a sí mismo como siempre.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.clients add column if not exists agenda_private boolean not null default false;

-- El atleta cambia SOLO su propia preferencia.
create or replace function public.set_agenda_private(p_private boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.my_client_id() is null then raise exception 'solo para atletas'; end if;
  update public.clients set agenda_private = coalesce(p_private, false) where id = public.my_client_id();
end $$;
revoke all on function public.set_agenda_private(boolean) from public, anon;
grant execute on function public.set_agenda_private(boolean) to authenticated;

-- Quién va a cada clase, respetando la privacidad.
create or replace function public.slot_roster(p_from text, p_to text)
returns table(date text, "time" text, client_id uuid, first_name text, color text, avatar_url text)
language sql stable security definer set search_path = public as $$
  select s.date::text, s.time::text,
         case when x.oculto then md5('kk-agenda-' || s.id::text)::uuid else s.client_id end,
         case when x.oculto then 'Atleta' else split_part(c.name, ' ', 1) end,
         case when x.oculto then null else c.color end,
         case when x.oculto then null else c.avatar_url end
    from public.sessions s
    join public.clients c on c.id = s.client_id
    cross join lateral (select (c.agenda_private and c.id is distinct from public.my_client_id())
                               and not coalesce(public.is_admin(), false) as oculto) x
   where public.is_member() and s.date::text between p_from and p_to
$$;

-- Opens por hora (solo recuento): tampoco se puede seguir a quien es privado.
do $$ begin
  if to_regclass('public.open_sessions') is not null then
    execute $f$
      create or replace function public.open_roster(p_from text, p_to text)
      returns table(date text, "time" text, client_id uuid)
      language sql stable security definer set search_path = public as $q$
        select o.date::text, o.time,
               case when c.agenda_private and c.id is distinct from public.my_client_id()
                         and not coalesce(public.is_admin(), false)
                    then md5('kk-open-' || o.id::text)::uuid else o.client_id end
          from public.open_sessions o
          left join public.clients c on c.id = o.client_id
         where public.is_member() and o.date::text between p_from and p_to
      $q$;
    $f$;
  end if;
end $$;
