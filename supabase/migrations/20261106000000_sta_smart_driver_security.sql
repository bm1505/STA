-- STA Smart Transport: protect driver verification and route live telemetry through trusted RPCs.
-- Apply after 20261105000000_sta_backend_foundation.sql.

create or replace function public.sta_protect_driver_profile_fields()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is not null
     and not exists (
       select 1 from public.profiles p
       where p.id = auth.uid() and p.role = 'admin'
     )
     and (
       new.verification_status is distinct from old.verification_status
       or new.total_rides is distinct from old.total_rides
     ) then
    raise exception 'Driver verification and ride totals are managed by STA'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists sta_protect_driver_profile_fields_trigger on public.driver_profiles;
create trigger sta_protect_driver_profile_fields_trigger
before update on public.driver_profiles
for each row execute function public.sta_protect_driver_profile_fields();

create or replace function public.sta_set_driver_presence(
  p_status text,
  p_vehicle_type text default null,
  p_region text default null,
  p_city text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_driver public.driver_profiles;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if p_status not in ('offline', 'idle', 'on_trip') then
    raise exception 'Invalid driver availability status';
  end if;

  select * into v_driver
  from public.driver_profiles
  where user_id = auth.uid()
  for update;

  if not found then
    raise exception 'Driver profile not found' using errcode = 'P0002';
  end if;

  if p_status <> 'offline' and v_driver.verification_status <> 'verified' then
    raise exception 'Driver verification is required' using errcode = '42501';
  end if;

  if p_status = 'on_trip' and not exists (
    select 1 from public.ride_requests
    where driver_id = auth.uid()
      and status in ('accepted', 'driver_arrived', 'in_progress')
  ) then
    raise exception 'No active ride found for this driver';
  end if;

  if p_status = 'idle' and exists (
    select 1 from public.ride_requests
    where driver_id = auth.uid()
      and status in ('accepted', 'driver_arrived', 'in_progress')
  ) then
    raise exception 'Driver has an active ride and cannot become idle';
  end if;

  update public.driver_profiles
  set is_online = (p_status <> 'offline'),
      availability_status = p_status,
      vehicle_type = coalesce(p_vehicle_type, vehicle_type),
      region = coalesce(p_region, region),
      city = coalesce(p_city, city),
      updated_at = now()
  where user_id = auth.uid();

  if p_status = 'offline' then
    delete from public.driver_locations where driver_id = auth.uid();
  end if;
end;
$$;

revoke all on function public.sta_set_driver_presence(text,text,text,text) from public;
grant execute on function public.sta_set_driver_presence(text,text,text,text) to authenticated;

create or replace function public.sta_update_driver_location(
  p_latitude double precision,
  p_longitude double precision,
  p_heading double precision default null,
  p_speed_mps double precision default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if p_latitude is null or p_longitude is null
     or p_latitude not between -90 and 90
     or p_longitude not between -180 and 180 then
    raise exception 'Invalid GPS coordinates';
  end if;

  if p_heading is not null and (p_heading < 0 or p_heading >= 360) then
    raise exception 'Invalid heading';
  end if;

  if p_speed_mps is not null and p_speed_mps < 0 then
    raise exception 'Invalid speed';
  end if;

  select availability_status into v_status
  from public.driver_profiles
  where user_id = auth.uid()
    and verification_status = 'verified'
    and is_online = true
  for update;

  if not found or v_status not in ('idle', 'on_trip') then
    raise exception 'Verified online driver profile required' using errcode = '42501';
  end if;

  insert into public.driver_locations(
    driver_id, latitude, longitude, heading, speed_mps, recorded_at
  ) values (
    auth.uid(), p_latitude, p_longitude, p_heading, p_speed_mps, now()
  )
  on conflict (driver_id) do update set
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    heading = excluded.heading,
    speed_mps = excluded.speed_mps,
    recorded_at = excluded.recorded_at;

  update public.ride_requests
  set driver_latitude = p_latitude,
      driver_longitude = p_longitude,
      driver_heading = p_heading,
      updated_at = now()
  where driver_id = auth.uid()
    and status in ('accepted', 'driver_arrived', 'in_progress');
end;
$$;

revoke all on function public.sta_update_driver_location(double precision,double precision,double precision,double precision) from public;
grant execute on function public.sta_update_driver_location(double precision,double precision,double precision,double precision) to authenticated;
