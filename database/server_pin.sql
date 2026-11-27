-- BD Smart Pay: server-side PIN check (ADDITIVE and backward compatible)
-- Run on a COPY / Supabase branch first, then on the live project.
-- It does not change any existing table policy, so the current app keeps working.

create extension if not exists pgcrypto;

alter table public.app_users add column if not exists pin_bcrypt text;

-- Settings (readable by all, editable only from the SQL editor)
create table if not exists public.app_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;
drop policy if exists "app_settings read" on public.app_settings;
create policy "app_settings read" on public.app_settings for select using (true);
insert into public.app_settings (key, value) values ('max_pin_attempts', '5')
on conflict (key) do nothing;

-- The app calls this instead of comparing a hash on the phone.
-- Returns {"ok":true} or {"ok":false,"reason":"locked"|"wrong"|"invalid","left":n}
create or replace function public.app_verify_pin(p_phone text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  u public.app_users%rowtype;
  max_try int;
  good boolean := false;
  tries int;
begin
  if p_phone is null or p_pin is null or p_pin !~ '^[0-9]{4}$' then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  select coalesce((select value::int from public.app_settings where key = 'max_pin_attempts'), 5)
    into max_try;

  select * into u from public.app_users where phone = p_phone for update;
  if not found then
    perform crypt(p_pin, gen_salt('bf', 10));        -- similar timing for unknown numbers
    return jsonb_build_object('ok', false, 'reason', 'wrong');
  end if;

  if u.blocked then
    return jsonb_build_object('ok', false, 'reason', 'locked');
  end if;

  if u.pin_bcrypt is not null then
    good := (u.pin_bcrypt = crypt(p_pin, u.pin_bcrypt));
  else
    -- old users: same hash the current app uses (sha256 of phone:pin); upgrade on first good login
    good := (u.pin_hash = encode(digest(p_phone || ':' || p_pin, 'sha256'), 'hex'));
    if good then
      update public.app_users set pin_bcrypt = crypt(p_pin, gen_salt('bf', 10)) where phone = p_phone;
    end if;
  end if;

  if good then
    update public.app_users set failed = 0 where phone = p_phone;
    return jsonb_build_object('ok', true);
  end if;

  tries := coalesce(u.failed, 0) + 1;
  update public.app_users set failed = tries, blocked = (tries >= max_try) where phone = p_phone;
  if tries >= max_try then
    return jsonb_build_object('ok', false, 'reason', 'locked');
  end if;
  return jsonb_build_object('ok', false, 'reason', 'wrong', 'left', max_try - tries);
end;
$$;

-- Admin page: set a new PIN (hashing happens on the server, not in the browser)
create or replace function public.admin_set_pin(p_phone text, p_pin text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  if p_pin is null or p_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;
  update public.app_users
     set pin_bcrypt = crypt(p_pin, gen_salt('bf', 10)),
         pin_hash   = encode(digest(p_phone || ':' || p_pin, 'sha256'), 'hex'),  -- keeps the current app working until it is migrated
         blocked    = false,
         failed     = 0
   where phone = p_phone;
  if not found then
    raise exception 'user not found';
  end if;
  update public.pin_requests set done = true where phone = p_phone and done = false;
end;
$$;

revoke all on function public.app_verify_pin(text, text) from public;
revoke all on function public.admin_set_pin(text, text) from public;
grant execute on function public.app_verify_pin(text, text) to anon, authenticated;
grant execute on function public.admin_set_pin(text, text) to authenticated;

-- PHASE 2 (ONLY after the user app calls app_verify_pin and has been released and tested):
--   * stop the app reading/writing pin_hash directly (revoke column access / tighten the app_users policies)
--   * then drop the weak legacy hash:  update public.app_users set pin_hash = null;
--     and change admin_set_pin to stop writing pin_hash.
