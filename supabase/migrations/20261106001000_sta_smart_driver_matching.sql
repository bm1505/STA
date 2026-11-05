-- Accurate, freshness-aware nearby-driver matching. Existing RPC is retained for rollback compatibility.
create or replace function public.sta_nearby_drivers_v2(
  p_latitude double precision,
  p_longitude double precision,
  p_vehicle_type text default null,
  p_region text default null,
  p_radius_meters double precision default 15000
)
returns table(
  driver_id uuid,
  latitude double precision,
  longitude double precision,
  distance_meters double precision,
  location_age_seconds integer
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_latitude is null or p_longitude is null
     or p_latitude not between -90 and 90
     or p_longitude not between -180 and 180 then
    raise exception 'Invalid pickup coordinates';
  end if;
  if p_radius_meters is null or p_radius_meters <= 0 or p_radius_meters > 100000 then
    raise exception 'Search radius must be between 1 and 100000 metres';
  end if;

  return query
  with candidates as (
    select
      dp.user_id as id,
      dl.latitude as lat,
      dl.longitude as lng,
      extract(epoch from (now() - dl.recorded_at))::integer as age_seconds,
      2 * 6371000 * asin(sqrt(least(1.0, greatest(0.0,
        power(sin(radians(dl.latitude - p_latitude) / 2), 2)
        + cos(radians(p_latitude)) * cos(radians(dl.latitude))
        * power(sin(radians(dl.longitude - p_longitude) / 2), 2)
      )))) as metres
    from public.driver_profiles dp
    join public.driver_locations dl on dl.driver_id = dp.user_id
    where dp.is_online = true
      and dp.availability_status = 'idle'
      and dp.verification_status = 'verified'
      and (p_vehicle_type is null or dp.vehicle_type = p_vehicle_type)
      and (p_region is null or dp.region = p_region)
      and dl.recorded_at > now() - interval '90 seconds'
  )
  select c.id, c.lat, c.lng, c.metres, c.age_seconds
  from candidates c
  where c.metres <= p_radius_meters
  order by c.metres asc, c.age_seconds asc
  limit 50;
end;
$$;

revoke all on function public.sta_nearby_drivers_v2(double precision,double precision,text,text,double precision) from public;
grant execute on function public.sta_nearby_drivers_v2(double precision,double precision,text,text,double precision) to authenticated;
