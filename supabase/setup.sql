-- Карта: схема базы и права доступа. Вставьте целиком в Supabase → SQL Editor → Run. Данные в репозитории не хранятся.
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text,
  role text not null default 'member' check (role in ('admin','member')),
  can_delete_places boolean not null default false,
  created_at timestamptz default now()
);
create table if not exists public.places (
  id bigserial primary key,
  name text not null,
  type text not null,
  region text, address text,
  lat double precision, lon double precision,
  phone text, email text, website text, unp text,
  source text, source_id text,
  status text not null default 'new',
  owner uuid references public.profiles(id),
  notes text,
  hidden boolean not null default false,
  hidden_by uuid references public.profiles(id),
  hidden_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
-- для баз, созданных до появления скрытия точек
alter table public.profiles add column if not exists can_delete_places boolean not null default false;
alter table public.places add column if not exists hidden boolean not null default false;
alter table public.places add column if not exists hidden_by uuid references public.profiles(id);
alter table public.places add column if not exists hidden_at timestamptz;
create index if not exists places_hidden_idx on public.places(hidden);
create table if not exists public.place_comments (
  id bigserial primary key,
  place_id bigint not null references public.places(id) on delete cascade,
  author uuid references public.profiles(id),
  body text not null,
  created_at timestamptz default now()
);
create index if not exists places_type_idx on public.places(type);
create index if not exists comments_place_idx on public.place_comments(place_id);

-- профиль создаётся автоматически при регистрации пользователя
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, full_name) values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email));
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
$$;
create or replace function public.can_delete_places() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and (role = 'admin' or can_delete_places))
$$;

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
drop trigger if exists places_touch on public.places;
create trigger places_touch before update on public.places for each row execute function public.touch_updated_at();

-- роль меняет только админ (иначе сотрудник мог бы сделать себя админом через свой профиль)
create or replace function public.protect_role() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.role is distinct from old.role or new.can_delete_places is distinct from old.can_delete_places)
     and auth.uid() is not null and not public.is_admin() then
    raise exception 'Менять роль и права может только администратор';
  end if;
  return new;
end $$;
drop trigger if exists profiles_protect_role on public.profiles;
create trigger profiles_protect_role before update on public.profiles for each row execute function public.protect_role();

-- доступ: только вошедшие сотрудники; удалять точки может админ или сотрудник с правом can_delete_places
alter table public.profiles enable row level security;
alter table public.places enable row level security;
alter table public.place_comments enable row level security;
drop policy if exists "team reads profiles" on public.profiles;
create policy "team reads profiles" on public.profiles for select to authenticated using (true);
drop policy if exists "own profile update" on public.profiles;
create policy "own profile update" on public.profiles for update to authenticated using (id = auth.uid() or public.is_admin());
drop policy if exists "team reads places" on public.places;
create policy "team reads places" on public.places for select to authenticated using (true);
drop policy if exists "team adds places" on public.places;
create policy "team adds places" on public.places for insert to authenticated with check (true);
drop policy if exists "team edits places" on public.places;
create policy "team edits places" on public.places for update to authenticated using (true);
drop policy if exists "admin deletes places" on public.places;
create policy "admin deletes places" on public.places for delete to authenticated using (public.can_delete_places());
drop policy if exists "team reads comments" on public.place_comments;
create policy "team reads comments" on public.place_comments for select to authenticated using (true);
drop policy if exists "team adds comments" on public.place_comments;
create policy "team adds comments" on public.place_comments for insert to authenticated with check (author = auth.uid());
drop policy if exists "author or admin deletes comments" on public.place_comments;
create policy "author or admin deletes comments" on public.place_comments for delete to authenticated using (author = auth.uid() or public.is_admin());

-- визиты менеджеров (отчёт по командировкам)
create table if not exists public.visits (
  id bigserial primary key,
  place_id bigint not null references public.places(id) on delete cascade,
  author uuid not null default auth.uid() references public.profiles(id),
  visited_at timestamptz not null default now(),
  result text not null,
  contact_name text, contact_phone text,
  products text, volume text,
  next_step text, next_date date,
  notes text,
  lat double precision, lon double precision,
  created_at timestamptz default now()
);
create index if not exists visits_place_idx on public.visits(place_id);
create index if not exists visits_date_idx on public.visits(visited_at);
alter table public.visits enable row level security;
drop policy if exists "team reads visits" on public.visits;
create policy "team reads visits" on public.visits for select to authenticated using (true);
drop policy if exists "own visits insert" on public.visits;
create policy "own visits insert" on public.visits for insert to authenticated with check (author = auth.uid());
drop policy if exists "author or admin edits visits" on public.visits;
create policy "author or admin edits visits" on public.visits for update to authenticated using (author = auth.uid() or public.is_admin());
drop policy if exists "author or admin deletes visits" on public.visits;
create policy "author or admin deletes visits" on public.visits for delete to authenticated using (author = auth.uid() or public.is_admin());

create table if not exists public.app_settings (key text primary key, value text);
alter table public.app_settings enable row level security;
drop policy if exists "team reads settings" on public.app_settings;
create policy "team reads settings" on public.app_settings for select to authenticated using (true);
drop policy if exists "admin edits settings" on public.app_settings;
create policy "admin edits settings" on public.app_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());

