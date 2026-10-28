-- Настройки сайта, которые видят только вошедшие сотрудники (например, ключ Mapbox).
-- Вставьте целиком в Supabase → SQL Editor, подставьте ключ и нажмите Run.
create table if not exists public.app_settings (key text primary key, value text);
alter table public.app_settings enable row level security;
drop policy if exists "team reads settings" on public.app_settings;
create policy "team reads settings" on public.app_settings for select to authenticated using (true);
drop policy if exists "admin edits settings" on public.app_settings;
create policy "admin edits settings" on public.app_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());

insert into public.app_settings (key, value) values ('mapbox_token', 'pk.ВАШ_КЛЮЧ')
on conflict (key) do update set value = excluded.value;
