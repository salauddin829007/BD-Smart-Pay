-- BD Smart Pay: Locations, location blocking, limits, admin activity log
-- Supabase Dashboard -> SQL Editor -> paste this -> Run (safe to run more than once)

-- 1) User location (division + district)
alter table public.app_users add column if not exists division text;
alter table public.app_users add column if not exists district text;
create index if not exists app_users_division_idx on public.app_users (division);
create index if not exists app_users_district_idx on public.app_users (district);

-- 2) Blocked locations (the user app can read this to refuse sign-up/login)
create table if not exists public.blocked_locations (
  level      text not null check (level in ('division','district')),
  name       text not null,
  reason     text,
  created_at timestamptz not null default now(),
  primary key (level, name)
);
alter table public.blocked_locations enable row level security;
drop policy if exists "blocked_locations read" on public.blocked_locations;
create policy "blocked_locations read" on public.blocked_locations for select using (true);
drop policy if exists "blocked_locations admin insert" on public.blocked_locations;
create policy "blocked_locations admin insert" on public.blocked_locations for insert with check (public.is_admin());
drop policy if exists "blocked_locations admin delete" on public.blocked_locations;
create policy "blocked_locations admin delete" on public.blocked_locations for delete using (public.is_admin());

-- 3) Daily / weekly / monthly limits (money out, per user). Change the numbers from the Limit Report page.
create table if not exists public.tx_limits (
  period     text primary key check (period in ('daily','weekly','monthly')),
  amount     numeric not null check (amount >= 0),
  updated_at timestamptz not null default now()
);
alter table public.tx_limits enable row level security;
drop policy if exists "tx_limits read" on public.tx_limits;
create policy "tx_limits read" on public.tx_limits for select using (true);
drop policy if exists "tx_limits admin update" on public.tx_limits;
create policy "tx_limits admin update" on public.tx_limits for update using (public.is_admin()) with check (public.is_admin());
insert into public.tx_limits (period, amount) values ('daily',25000),('weekly',100000),('monthly',300000)
on conflict (period) do nothing;

-- 4) Admin activity log
create table if not exists public.admin_logs (
  id          bigint generated always as identity primary key,
  admin_email text,
  action      text not null,
  target      text,
  detail      text,
  created_at  timestamptz not null default now()
);
alter table public.admin_logs enable row level security;
drop policy if exists "admin_logs admin read" on public.admin_logs;
create policy "admin_logs admin read" on public.admin_logs for select using (public.is_admin());
drop policy if exists "admin_logs admin insert" on public.admin_logs;
create policy "admin_logs admin insert" on public.admin_logs for insert with check (public.is_admin());
