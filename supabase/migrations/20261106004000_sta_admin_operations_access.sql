-- Complete administrative visibility for live operations and SOS response.
drop policy if exists driver_locations_admin_select on public.driver_locations;
create policy driver_locations_admin_select on public.driver_locations
  for select to authenticated using (public.sta_is_active_admin());

drop policy if exists trips_admin_select on public.trips;
create policy trips_admin_select on public.trips
  for select to authenticated using (public.sta_is_active_admin());

drop policy if exists sos_alerts_admin_select on public.sos_alerts;
create policy sos_alerts_admin_select on public.sos_alerts
  for select to authenticated using (public.sta_is_active_admin());

create or replace function public.sta_resolve_sos(p_alert_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.sta_is_active_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  update public.sos_alerts set status = 'resolved'
  where id = p_alert_id and status = 'active';
  if not found then raise exception 'Active SOS alert not found'; end if;
end;
$$;
revoke all on function public.sta_resolve_sos(uuid) from public;
grant execute on function public.sta_resolve_sos(uuid) to authenticated;
