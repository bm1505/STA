-- Per-user quota protects paid traffic routing credentials from abuse.
create table if not exists public.route_request_limits (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  window_start timestamptz not null,
  request_count integer not null default 0
);
alter table public.route_request_limits enable row level security;

create or replace function public.sta_consume_route_quota()
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer;
  v_window timestamptz := date_trunc('minute', now());
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  insert into public.route_request_limits(user_id,window_start,request_count)
  values(auth.uid(),v_window,1)
  on conflict(user_id) do update
  set window_start = case
        when public.route_request_limits.window_start < v_window then v_window
        else public.route_request_limits.window_start end,
      request_count = case
        when public.route_request_limits.window_start < v_window then 1
        else public.route_request_limits.request_count + 1 end
  returning request_count into v_count;
  return v_count <= 30;
end;
$$;
revoke all on function public.sta_consume_route_quota() from public;
grant execute on function public.sta_consume_route_quota() to authenticated;
