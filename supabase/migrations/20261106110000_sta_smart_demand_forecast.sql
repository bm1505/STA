-- Historical demand forecast by approximate 2 km map cell and next-hour time window.
create or replace function public.sta_demand_forecast(p_limit integer default 50)
returns table (
  latitude double precision,
  longitude double precision,
  predicted_requests numeric,
  current_requests integer,
  available_drivers integer,
  sample_days integer,
  demand_level text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.sta_is_active_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'Limit must be between 1 and 100';
  end if;

  return query
  with target_time as (
    select extract(dow from now() + interval '1 hour')::integer as dow,
           extract(hour from now() + interval '1 hour')::integer as hour
  ),
  daily_counts as (
    select
      floor(r.pickup_latitude / 0.02)::integer as lat_cell,
      floor(r.pickup_longitude / 0.02)::integer as lng_cell,
      r.created_at::date as ride_day,
      count(*)::numeric as rides
    from public.ride_requests r
    cross join target_time t
    where r.created_at >= now() - interval '28 days'
      and r.created_at < date_trunc('hour', now())
      and extract(dow from r.created_at)::integer = t.dow
      and extract(hour from r.created_at)::integer = t.hour
    group by 1,2,3
  ),
  forecast as (
    select lat_cell, lng_cell, avg(rides) as expected, count(*)::integer as samples
    from daily_counts
    group by lat_cell, lng_cell
  ),
  current_demand as (
    select
      floor(r.pickup_latitude / 0.02)::integer as lat_cell,
      floor(r.pickup_longitude / 0.02)::integer as lng_cell,
      count(*)::integer as requests
    from public.ride_requests r
    where r.status = 'requesting'
      and r.created_at >= now() - interval '15 minutes'
    group by 1,2
  ),
  supply as (
    select
      floor(dl.latitude / 0.02)::integer as lat_cell,
      floor(dl.longitude / 0.02)::integer as lng_cell,
      count(*)::integer as drivers
    from public.driver_profiles dp
    join public.driver_locations dl on dl.driver_id = dp.user_id
    where dp.is_online = true
      and dp.availability_status = 'idle'
      and dp.verification_status = 'verified'
      and dl.recorded_at >= now() - interval '90 seconds'
    group by 1,2
  ),
  cells as (
    select
      coalesce(f.lat_cell, d.lat_cell, s.lat_cell) as lat_cell,
      coalesce(f.lng_cell, d.lng_cell, s.lng_cell) as lng_cell,
      coalesce(f.expected, 0) as expected,
      coalesce(d.requests, 0) as requests,
      coalesce(s.drivers, 0) as drivers,
      coalesce(f.samples, 0) as samples
    from forecast f
    full join current_demand d using (lat_cell,lng_cell)
    full join supply s using (lat_cell,lng_cell)
  )
  select
    (c.lat_cell * 0.02 + 0.01)::double precision,
    (c.lng_cell * 0.02 + 0.01)::double precision,
    round(c.expected, 2),
    c.requests,
    c.drivers,
    c.samples,
    case
      when c.expected >= greatest(c.drivers,1) * 2 then 'high'
      when c.expected >= greatest(c.drivers,1) then 'busy'
      else 'normal'
    end
  from cells c
  order by (c.expected + c.requests)::numeric desc
  limit p_limit;
end;
$$;
revoke all on function public.sta_demand_forecast(integer) from public;
grant execute on function public.sta_demand_forecast(integer) to authenticated;
