-- BD Smart Pay: Feature Control table
-- Supabase Dashboard -> SQL Editor -> paste this -> Run

create table if not exists public.feature_flags (
  key        text primary key,
  label      text not null,
  enabled    boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.feature_flags enable row level security;

-- Everyone (the user app too) can read the on/off values
drop policy if exists "feature_flags read" on public.feature_flags;
create policy "feature_flags read" on public.feature_flags
  for select using (true);

-- Only admins can change them
drop policy if exists "feature_flags admin update" on public.feature_flags;
create policy "feature_flags admin update" on public.feature_flags
  for update using (public.is_admin()) with check (public.is_admin());

insert into public.feature_flags (key, label) values
  ('add_money','Add Money'),
  ('send_money','Send Money'),
  ('cash_out','Cash Out'),
  ('recharge','Recharge'),
  ('scan_pay','Scan & Pay'),
  ('bill_pay','Bill Pay'),
  ('bank','Bank'),
  ('cards','Cards'),
  ('agent_center','Agent Center'),
  ('merchant_center','Merchant Center')
on conflict (key) do nothing;
