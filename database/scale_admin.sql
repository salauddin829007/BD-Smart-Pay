-- BD Smart Pay: admin speed-ups (safe to run more than once)

create index if not exists app_users_created_idx on public.app_users (created_at desc);
create index if not exists pin_requests_pending_idx on public.pin_requests (created_at desc) where done = false;
create index if not exists notices_created_idx on public.notices (created_at desc);

-- Totals for the dashboard cards, computed in the database instead of in the browser
create or replace function public.admin_summary()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'users',   (select count(*) from public.app_users),
    'locked',  (select count(*) from public.app_users where blocked),
    'pending', (select count(*) from public.pin_requests where not done),
    'balance', (
      select coalesce(sum(b), 0) from (
        select case
          when jsonb_typeof(data::jsonb -> 'ac') = 'array' then
            (select coalesce(sum((x ->> 'bal')::numeric), 0) from jsonb_array_elements(data::jsonb -> 'ac') x)
          when jsonb_typeof(data::jsonb -> 'w') = 'object' then
            (select coalesce(sum(v::numeric), 0) from jsonb_each_text(data::jsonb -> 'w') e(k, v))
          else 0
        end as b
        from public.app_users
      ) s
    )
  );
end;
$$;

revoke all on function public.admin_summary() from public;
grant execute on function public.admin_summary() to authenticated;
