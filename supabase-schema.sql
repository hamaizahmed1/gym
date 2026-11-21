-- LiftLog shared-profile migration (passwordless, cross-device)
-- Run this in Supabase SQL Editor. It preserves existing workout rows.
-- WARNING: these are shared public profiles, not private user accounts.

create extension if not exists pgcrypto;

-- Keep existing table structures, but remove the auth.users ownership requirement.
do $$
declare r record;
begin
  for r in
    select conrelid::regclass as tbl, conname
    from pg_constraint
    where contype='f'
      and confrelid='auth.users'::regclass
      and conrelid in ('public.workout_templates'::regclass,'public.workout_sessions'::regclass,'public.body_measurements'::regclass,'public.user_settings'::regclass)
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
  end loop;
end $$;

alter table public.workout_templates alter column user_id drop not null;
alter table public.workout_sessions alter column user_id drop not null;
alter table public.body_measurements alter column user_id drop not null;
alter table public.user_settings alter column user_id drop not null;

-- Ensure profile labels and existing rows are normalized before assigning stable IDs.
alter table public.workout_templates add column if not exists profile_name text not null default 'Hamaiz';
alter table public.workout_sessions add column if not exists profile_name text not null default 'Hamaiz';
alter table public.body_measurements add column if not exists profile_name text not null default 'Hamaiz';
alter table public.user_settings add column if not exists profile_name text not null default 'Hamaiz';

-- Merge settings from multiple old device/user IDs without discarding individual keys.
create temporary table liftlog_merged_settings on commit drop as
select p.profile_name,
       coalesce((
         select jsonb_object_agg(k, v)
         from (
           select distinct on (e.key) e.key as k, e.value as v
           from public.user_settings u
           cross join lateral jsonb_each(coalesce(u.settings, '{}'::jsonb)) e
           where u.profile_name=p.profile_name
           order by e.key, u.updated_at desc nulls last
         ) merged_keys
       ), '{}'::jsonb) as settings,
       max(p.updated_at) as updated_at
from public.user_settings p
group by p.profile_name;
delete from public.user_settings;
insert into public.user_settings(user_id, profile_name, settings, updated_at)
select case profile_name when 'Khizar' then '00000000-0000-4000-8000-000000000002'::uuid else '00000000-0000-4000-8000-000000000001'::uuid end,
       profile_name, settings, coalesce(updated_at, now())
from liftlog_merged_settings;

update public.workout_templates set user_id=case profile_name when 'Khizar' then '00000000-0000-4000-8000-000000000002'::uuid else '00000000-0000-4000-8000-000000000001'::uuid end;
update public.workout_sessions set user_id=case profile_name when 'Khizar' then '00000000-0000-4000-8000-000000000002'::uuid else '00000000-0000-4000-8000-000000000001'::uuid end;
update public.body_measurements set user_id=case profile_name when 'Khizar' then '00000000-0000-4000-8000-000000000002'::uuid else '00000000-0000-4000-8000-000000000001'::uuid end;
update public.user_settings set user_id=case profile_name when 'Khizar' then '00000000-0000-4000-8000-000000000002'::uuid else '00000000-0000-4000-8000-000000000001'::uuid end;

alter table public.user_settings drop constraint if exists user_settings_pkey;
alter table public.user_settings add constraint user_settings_pkey primary key (user_id, profile_name);

create index if not exists workout_sessions_user_started_idx on public.workout_sessions(user_id, profile_name, started_at desc);
create index if not exists body_measurements_user_date_idx on public.body_measurements(user_id, profile_name, measured_at desc);
create index if not exists workout_templates_user_idx on public.workout_templates(user_id, profile_name);

-- Restrict anonymous API access to the two fixed profile partitions only.
alter table public.workout_templates enable row level security;
alter table public.workout_sessions enable row level security;
alter table public.body_measurements enable row level security;
alter table public.user_settings enable row level security;

drop policy if exists "template owner access" on public.workout_templates;
drop policy if exists "session owner access" on public.workout_sessions;
drop policy if exists "measurement owner access" on public.body_measurements;
drop policy if exists "settings owner access" on public.user_settings;
drop policy if exists "LiftLog shared profiles" on public.workout_templates;
drop policy if exists "LiftLog shared profiles" on public.workout_sessions;
drop policy if exists "LiftLog shared profiles" on public.body_measurements;
drop policy if exists "LiftLog shared profiles" on public.user_settings;

create policy "LiftLog shared profiles" on public.workout_templates for all to anon
  using (user_id in ('00000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000002'::uuid))
  with check (user_id in ('00000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000002'::uuid));
create policy "LiftLog shared profiles" on public.workout_sessions for all to anon
  using (user_id in ('00000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000002'::uuid))
  with check (user_id in ('00000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000002'::uuid));
create policy "LiftLog shared profiles" on public.body_measurements for all to anon
  using (user_id in ('00000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000002'::uuid))
  with check (user_id in ('00000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000002'::uuid));
create policy "LiftLog shared profiles" on public.user_settings for all to anon
  using (user_id in ('00000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000002'::uuid))
  with check (user_id in ('00000000-0000-4000-8000-000000000001'::uuid,'00000000-0000-4000-8000-000000000002'::uuid));

grant usage on schema public to anon;
grant select, insert, update, delete on public.workout_templates, public.workout_sessions, public.body_measurements, public.user_settings to anon;

-- Authenticated users may also access these same shared partitions if they happen to be signed in.
grant select, insert, update, delete on public.workout_templates, public.workout_sessions, public.body_measurements, public.user_settings to authenticated;
