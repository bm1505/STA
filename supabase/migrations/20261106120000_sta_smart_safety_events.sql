-- Detect abnormal driver telemetry during an active trip and alert admins.
create table if not exists public.ride_safety_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  ride_id uuid references public.ride_requests(id),
  event_type text not null check (event_type in ('speed_anomaly','gps_jump','location_gap')),
  severity text not null check (severity in ('low','medium','high','critical')),
  details jsonb not null default '{}'::jsonb,
  latitude double precision,
  longitude double precision,
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id)
);
create index if not exists ride_safety_events_created_idx
  on public.ride_safety_events(created_at desc);
create index if not exists ride_safety_events_user_status_idx
  on public.ride_safety_events(user_id,status);

do $
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'ride_safety_events'
     ) then
    alter publication supabase_realtime add table public.ride_safety_events;
  end if;
end;
$;

alter table public.ride_safety_events enable row level security;
drop policy if exists ride_safety_events_owner_select on public.ride_safety_events;
create policy ride_safety_events_owner_select on public.ride_safety_events
  for select to authenticated using (user_id = auth.uid());
drop policy if exists ride_safety_events_admin_select on public.ride_safety_events;
create policy ride_safety_events_admin_select on public.ride_safety_events
  for select to authenticated using (public.sta_is_active_admin());

create or replace function public.sta_detect_driver_safety_event()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ride_id uuid;
  v_event_type text;
  v_severity text;
  v_details jsonb;
  v_distance_meters double precision;
begin
  select id into v_ride_id
  from public.ride_requests
  where driver_id = new.driver_id and status = 'in_progress'
  order by updated_at desc limit 1;

  if v_ride_id is null then return new; end if;

  if coalesce(new.speed_mps,0) > 45 then
    v_event_type := 'speed_anomaly';
    v_severity := case when new.speed_mps > 60 then 'critical' else 'high' end;
    v_details := jsonb_build_object('speed_mps',new.speed_mps,'speed_kmh',round(new.speed_mps * 3.6,1));
  elsif tg_op = 'UPDATE' and old.recorded_at > now() - interval '30 seconds'
        and new.recorded_at - old.recorded_at <= interval '30 seconds' then
    v_distance_meters := 2 * 6371000 * asin(sqrt(least(1.0,
      power(sin(radians(new.latitude - old.latitude) / 2), 2) +
      cos(radians(old.latitude)) * cos(radians(new.latitude)) *
      power(sin(radians(new.longitude - old.longitude) / 2), 2)
    )));
    if v_distance_meters > 1000 then
      v_event_type := 'gps_jump';
      v_severity := 'high';
      v_details := jsonb_build_object(
        'distance_meters',round(v_distance_meters,1),
        'interval_seconds',extract(epoch from (new.recorded_at-old.recorded_at))
      );
    end if;
  elsif tg_op = 'UPDATE' and old.recorded_at < now() - interval '3 minutes' then
    v_event_type := 'location_gap';
    v_severity := 'medium';
    v_details := jsonb_build_object(
      'gap_seconds',extract(epoch from (new.recorded_at-old.recorded_at))
    );
  end if;

  if v_event_type is null then return new; end if;
  if exists (
    select 1 from public.ride_safety_events e
    where e.user_id = new.driver_id
      and e.ride_id = v_ride_id
      and e.event_type = v_event_type
      and e.created_at > now() - interval '10 minutes'
  ) then return new; end if;

  insert into public.ride_safety_events(
    user_id,ride_id,event_type,severity,details,latitude,longitude
  ) values (
    new.driver_id,v_ride_id,v_event_type,v_severity,v_details,new.latitude,new.longitude
  );

  insert into public.user_notifications(user_id,notification_type,title,body,payload)
  select p.id,'safety_alert','STA safety alert',
    case v_event_type
      when 'speed_anomaly' then 'Unusual vehicle speed detected during an active trip.'
      when 'gps_jump' then 'An unusual GPS location jump was detected during an active trip.'
      else 'Driver location updates were interrupted during an active trip.'
    end,
    jsonb_build_object('ride_id',v_ride_id,'event_type',v_event_type,'severity',v_severity)
  from public.profiles p
  where p.role = 'admin' and p.is_active = true;

  if v_severity in ('high','critical') then
    insert into public.user_notifications(user_id,notification_type,title,body,payload)
    select r.rider_id,'safety_alert','Trip safety monitoring',
      'The system detected an unusual trip movement pattern. STA safety support has been alerted.',
      jsonb_build_object('ride_id',v_ride_id,'event_type',v_event_type)
    from public.ride_requests r where r.id = v_ride_id;
  end if;

  return new;
end;
$$;

drop trigger if exists sta_driver_safety_detection on public.driver_locations;
create trigger sta_driver_safety_detection
after insert or update on public.driver_locations
for each row execute function public.sta_detect_driver_safety_event();

create or replace function public.sta_resolve_safety_event(
  p_event_id uuid,
  p_status text default 'resolved'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.sta_is_active_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_status not in ('reviewing','resolved','dismissed') then
    raise exception 'Invalid safety event status';
  end if;
  update public.ride_safety_events
  set status = p_status,
      resolved_at = case when p_status in ('resolved','dismissed') then now() else null end,
      resolved_by = auth.uid()
  where id = p_event_id and status in ('open','reviewing');
  if not found then raise exception 'Open safety event not found'; end if;
end;
$$;
revoke all on function public.sta_resolve_safety_event(uuid,text) from public;
grant execute on function public.sta_resolve_safety_event(uuid,text) to authenticated;
