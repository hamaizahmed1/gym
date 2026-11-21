-- LiftLog Supabase schema. Run in Supabase SQL Editor.
-- Enable RLS on all user-owned tables. Never use the service_role key in the browser.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.workout_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_name text not null default 'Hamaiz' check (profile_name in ('Hamaiz', 'Khizar')),
  name text not null,
  day_name text,
  exercises jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_name text not null default 'Hamaiz' check (profile_name in ('Hamaiz', 'Khizar')),
  name text not null,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  duration_seconds integer not null default 0 check (duration_seconds >= 0),
  total_volume numeric(12,2) not null default 0,
  sets_data jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.body_measurements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_name text not null default 'Hamaiz' check (profile_name in ('Hamaiz', 'Khizar')),
  measured_at date not null default current_date,
  weight_kg numeric(6,2) not null check (weight_kg > 0 and weight_kg < 500),
  created_at timestamptz not null default now()
);

create table if not exists public.user_settings (
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_name text not null default 'Hamaiz' check (profile_name in ('Hamaiz', 'Khizar')),
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, profile_name)
);

-- Upgrade existing installs: older records stay assigned to Hamaiz.
alter table public.workout_templates add column if not exists profile_name text not null default 'Hamaiz';
alter table public.workout_sessions add column if not exists profile_name text not null default 'Hamaiz';
alter table public.body_measurements add column if not exists profile_name text not null default 'Hamaiz';
alter table public.user_settings add column if not exists profile_name text not null default 'Hamaiz';
alter table public.user_settings drop constraint if exists user_settings_pkey;
alter table public.user_settings add constraint user_settings_pkey primary key (user_id, profile_name);

create index if not exists workout_sessions_user_started_idx on public.workout_sessions(user_id, profile_name, started_at desc);
create index if not exists body_measurements_user_date_idx on public.body_measurements(user_id, profile_name, measured_at desc);
create index if not exists workout_templates_user_idx on public.workout_templates(user_id, profile_name);

alter table public.profiles enable row level security;
alter table public.workout_templates enable row level security;
alter table public.workout_sessions enable row level security;
alter table public.body_measurements enable row level security;
alter table public.user_settings enable row level security;

drop policy if exists "profile owner access" on public.profiles;
create policy "profile owner access" on public.profiles for all using (auth.uid() = id) with check (auth.uid() = id);
drop policy if exists "template owner access" on public.workout_templates;
create policy "template owner access" on public.workout_templates for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "session owner access" on public.workout_sessions;
create policy "session owner access" on public.workout_sessions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "measurement owner access" on public.body_measurements;
create policy "measurement owner access" on public.body_measurements for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "settings owner access" on public.user_settings;
create policy "settings owner access" on public.user_settings for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Automatically create a private profile when a user registers.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();
