-- BD Smart Pay: Upazila + village, and upazila blocking
-- Run AFTER location_security.sql.
-- Supabase Dashboard -> SQL Editor -> paste this -> Run (safe to run more than once)

alter table public.app_users add column if not exists upazila text;
alter table public.app_users add column if not exists village text;
create index if not exists app_users_upazila_idx on public.app_users (district, upazila);

-- allow blocking at upazila level (stored as 'District|Upazila')
alter table public.blocked_locations drop constraint if exists blocked_locations_level_check;
alter table public.blocked_locations
  add constraint blocked_locations_level_check check (level in ('division','district','upazila'));
