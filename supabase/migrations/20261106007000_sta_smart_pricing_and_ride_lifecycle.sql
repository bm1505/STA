-- Server-authoritative pricing and ride state transitions.
-- Existing vehicle prices are retained as editable configuration, not client-side constants.

alter table public.ride_requests
  add column if not exists estimated_distance_meters numeric(14,2),
  add column if not exists estimated_duration_seconds integer,
  add column if not exists demand_multiplier numeric(5,2) not null default 1.00,
  add column if not exists payment_method text not null default 'cash';

create table if not exists public.vehicle_fare_rules (
  vehicle_type text primary key,
  base_fare numeric(14,2) not null check (base_fare >= 0),
  per_km_rate numeric(14,2) not null check (per_km_rate >= 0),
  per_minute_rate numeric(14,2) not null check (per_minute_rate >= 0),
  minimum_fare numeric(14,2) not null default 0 check (minimum_fare >= 0),
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.vehicle_fare_rules enable row level security;

insert into public.vehicle_fare_rules(vehicle_type,base_fare,per_km_rate,per_minute_rate,minimum_fare)
values
  ('Bodaboda',1500,500,50,1500),
  ('Bajaji',2500,700,80,2500),
  ('Car',3500,1000,120,3500),
  ('XL',5000,1500,180,5000),
  ('STA Send',2000,600,60,2000)
on conflict (vehicle_type) do nothing;

drop policy if exists vehicle_fare_rules_read on public.vehicle_fare_rules;
create policy vehicle_fare_rules_read on public.vehicle_fare_rules
  for select to authenticated using (is_active = true or public.sta_is_active_admin());
drop policy if exists vehicle_fare_rules_admin_write on public.vehicle_fare_rules;
create policy vehicle_fare_rules_admin_write on public.vehicle_fare_rules
  for all to authenticated using (public.sta_is_active_admin())
  with check (public.sta_is_active_admin());

-- Replace the old client-insert path: fare and demand multiplier are calculated here.
drop policy if exists "ride_requests_insert_rider" on public.ride_requests;

create or replace function public.sta_estimate_fare(
  p_vehicle_type text,
  p_distance_meters numeric,
  p_duration_seconds integer,
  p_pickup_latitude double precision,
  p_pickup_longitude double precision
)
returns table (
  estimated_fare numeric,
  demand_multiplier numeric,
  demand_level text,
  nearby_requests integer,
  nearby_available_drivers integer
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rule public.vehicle_fare_rules;
  v_requests integer := 0;
  v_drivers integer := 0;
  v_ratio numeric := 0;
  v_multiplier numeric := 1.00;
  v_raw_fare numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_distance_meters is null or p_distance_meters <= 0
     or p_duration_seconds is null or p_duration_seconds <= 0 then
    raise exception 'A valid road distance and duration are required';
  end if;
  if p_pickup_latitude is null or p_pickup_latitude not between -90 and 90
     or p_pickup_longitude is null or p_pickup_longitude not between -180 and 180 then
    raise exception 'Invalid pickup coordinates';
  end if;

  select * into v_rule from public.vehicle_fare_rules
  where vehicle_type = p_vehicle_type and is_active = true;
  if not found then raise exception 'Fare rules are not configured for this vehicle'; end if;

  select count(*)::integer into v_requests
  from public.ride_requests r
  where r.status = 'requesting'
    and r.created_at > now() - interval '15 minutes'
    and 6371000 * 2 * asin(sqrt(least(1.0,
      power(sin(radians(r.pickup_latitude - p_pickup_latitude) / 2), 2) +
      cos(radians(p_pickup_latitude)) * cos(radians(r.pickup_latitude)) *
      power(sin(radians(r.pickup_longitude - p_pickup_longitude) / 2), 2)
    ))) <= 3000;

  select count(*)::integer into v_drivers
  from public.driver_profiles dp
  join public.driver_locations dl on dl.driver_id = dp.user_id
  where dp.is_online = true
    and dp.availability_status = 'idle'
    and dp.verification_status = 'verified'
    and dl.recorded_at > now() - interval '90 seconds'
    and 6371000 * 2 * asin(sqrt(least(1.0,
      power(sin(radians(dl.latitude - p_pickup_latitude) / 2), 2) +
      cos(radians(p_pickup_latitude)) * cos(radians(dl.latitude)) *
      power(sin(radians(dl.longitude - p_pickup_longitude) / 2), 2)
    ))) <= 3000;

  v_ratio := v_requests::numeric / greatest(v_drivers, 1);
  if v_ratio >= 3 then v_multiplier := 1.50;
  elsif v_ratio >= 2 then v_multiplier := 1.30;
  elsif v_ratio >= 1.2 then v_multiplier := 1.15;
  else v_multiplier := 1.00;
  end if;

  v_raw_fare := greatest(
    v_rule.minimum_fare,
    v_rule.base_fare +
      (p_distance_meters / 1000.0 * v_rule.per_km_rate) +
      (p_duration_seconds / 60.0 * v_rule.per_minute_rate)
  ) * v_multiplier;

  return query select
    round(v_raw_fare / 100.0) * 100.0,
    v_multiplier,
    case when v_multiplier >= 1.5 then 'high'
         when v_multiplier >= 1.15 then 'busy'
         else 'normal' end,
    v_requests,
    v_drivers;
end;
$$;
revoke all on function public.sta_estimate_fare(text,numeric,integer,double precision,double precision) from public;
grant execute on function public.sta_estimate_fare(text,numeric,integer,double precision,double precision) to authenticated;

create or replace function public.sta_create_ride_request(
  p_pickup_latitude double precision,
  p_pickup_longitude double precision,
  p_pickup_label text,
  p_dropoff_latitude double precision,
  p_dropoff_longitude double precision,
  p_dropoff_label text,
  p_vehicle_type text,
  p_distance_meters numeric,
  p_duration_seconds integer,
  p_ride_data jsonb default '{}'::jsonb
)
returns public.ride_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.profiles;
  v_estimate record;
  v_ride public.ride_requests;
  v_data jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  select * into v_profile from public.profiles
  where id = auth.uid() and role = 'rider' and is_active = true;
  if not found then raise exception 'An active rider account is required' using errcode = '42501'; end if;
  if p_pickup_latitude not between -90 and 90 or p_dropoff_latitude not between -90 and 90
     or p_pickup_longitude not between -180 and 180 or p_dropoff_longitude not between -180 and 180 then
    raise exception 'Invalid pickup or destination coordinates';
  end if;
  if coalesce(trim(p_pickup_label),'') = '' or coalesce(trim(p_dropoff_label),'') = '' then
    raise exception 'Pickup and destination addresses are required';
  end if;

  select * into v_estimate from public.sta_estimate_fare(
    p_vehicle_type, p_distance_meters, p_duration_seconds,
    p_pickup_latitude, p_pickup_longitude
  );
  v_data := coalesce(p_ride_data, '{}'::jsonb) ||
    jsonb_build_object(
      'riderName', coalesce(v_profile.user_data ->> 'name', v_profile.full_name),
      'riderPhone', coalesce(v_profile.phone_number, ''),
      'demandLevel', v_estimate.demand_level
    );

  insert into public.ride_requests(
    rider_id, pickup_latitude, pickup_longitude, pickup_label,
    dropoff_latitude, dropoff_longitude, dropoff_label, vehicle_type,
    estimated_fare, estimated_distance_meters, estimated_duration_seconds,
    demand_multiplier, ride_data
  ) values (
    auth.uid(), p_pickup_latitude, p_pickup_longitude, trim(p_pickup_label),
    p_dropoff_latitude, p_dropoff_longitude, trim(p_dropoff_label), p_vehicle_type,
    v_estimate.estimated_fare, p_distance_meters, p_duration_seconds,
    v_estimate.demand_multiplier, v_data
  ) returning * into v_ride;
  return v_ride;
end;
$$;
revoke all on function public.sta_create_ride_request(double precision,double precision,text,double precision,double precision,text,text,numeric,integer,jsonb) from public;
grant execute on function public.sta_create_ride_request(double precision,double precision,text,double precision,double precision,text,text,numeric,integer,jsonb) to authenticated;

create or replace function public.sta_set_ride_payment_method(
  p_ride_id uuid,
  p_payment_method text
)
returns public.ride_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_ride public.ride_requests;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_payment_method not in ('cash','mpesa') then raise exception 'Unsupported payment method'; end if;
  select * into v_ride from public.ride_requests where id = p_ride_id for update;
  if not found or v_ride.rider_id <> auth.uid() then
    raise exception 'Ride not found for this account' using errcode = '42501';
  end if;
  if v_ride.status not in ('requesting','accepted','driver_arrived','in_progress','completed')
     or (v_ride.status = 'completed' and coalesce(v_ride.payment_status,'pending') <> 'pending') then
    raise exception 'Payment method can no longer be changed';
  end if;
  update public.ride_requests set payment_method = p_payment_method, updated_at = now()
  where id = p_ride_id returning * into v_ride;
  return v_ride;
end;
$$;
revoke all on function public.sta_set_ride_payment_method(uuid,text) from public;
grant execute on function public.sta_set_ride_payment_method(uuid,text) to authenticated;

create or replace function public.sta_set_ride_status(
  p_ride_id uuid,
  p_status text,
  p_fare numeric default null,
  p_distance_meters numeric default null,
  p_duration_seconds integer default null,
  p_payment_status text default null
)
returns public.ride_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ride public.ride_requests;
  v_rule public.vehicle_fare_rules;
  v_distance numeric(14,2);
  v_duration integer;
  v_final_fare numeric(14,2);
  v_is_admin boolean := public.sta_is_active_admin();
  v_is_service boolean := coalesce(auth.role(), '') = 'service_role';
  v_was_recorded boolean := false;
begin
  select * into v_ride from public.ride_requests where id = p_ride_id for update;
  if not found then raise exception 'Ride not found'; end if;
  if not v_is_service and not v_is_admin
     and auth.uid() not in (v_ride.rider_id, v_ride.driver_id) then
    raise exception 'Not authorized to change this ride' using errcode = '42501';
  end if;

  if p_status = 'driver_arrived' then
    if auth.uid() is distinct from v_ride.driver_id or v_ride.status <> 'accepted' then
      raise exception 'Driver cannot mark this ride as arrived';
    end if;
    update public.ride_requests set status = 'driver_arrived', updated_at = now()
    where id = p_ride_id returning * into v_ride;

  elsif p_status = 'in_progress' then
    if auth.uid() is distinct from v_ride.driver_id or v_ride.status <> 'driver_arrived' then
      raise exception 'Ride must be accepted and driver must arrive first';
    end if;
    update public.ride_requests set status = 'in_progress', updated_at = now()
    where id = p_ride_id returning * into v_ride;

  elsif p_status = 'completed' then
    if v_ride.status not in ('in_progress','completed')
       or (not v_is_service and not v_is_admin and auth.uid() is distinct from v_ride.driver_id) then
      raise exception 'Only the assigned driver can complete an active ride';
    end if;
    if v_ride.status <> 'completed' then
      select * into v_rule from public.vehicle_fare_rules
      where vehicle_type = v_ride.vehicle_type and is_active = true;
      if not found then raise exception 'Fare rules are unavailable for this vehicle'; end if;
      v_distance := greatest(coalesce(p_distance_meters,0),0);
      if v_distance < 1 then v_distance := coalesce(v_ride.estimated_distance_meters,0); end if;
      v_duration := greatest(coalesce(p_duration_seconds,0),0);
      if v_duration < 1 then v_duration := coalesce(v_ride.estimated_duration_seconds,0); end if;
      if v_distance <= 0 or v_duration <= 0 then
        raise exception 'Actual or estimated route distance and duration are required';
      end if;
      v_final_fare := round(greatest(
        v_rule.minimum_fare,
        v_rule.base_fare +
          (v_distance / 1000.0 * v_rule.per_km_rate) +
          (v_duration / 60.0 * v_rule.per_minute_rate)
      ) * coalesce(v_ride.demand_multiplier,1.0) / 100.0) * 100.0;
      update public.ride_requests
      set status = 'completed',
          distance_meters = v_distance,
          duration_seconds = v_duration,
          final_fare = v_final_fare,
          payment_status = 'pending',
          completed_at = now(),
          updated_at = now()
      where id = p_ride_id returning * into v_ride;
    end if;

  elsif p_status = 'cancelled' then
    if v_ride.status not in ('requesting','accepted','driver_arrived') then
      raise exception 'This ride can no longer be cancelled';
    end if;
    if not v_is_admin and not v_is_service
       and auth.uid() not in (v_ride.rider_id, v_ride.driver_id) then
      raise exception 'Not authorized to cancel this ride' using errcode = '42501';
    end if;
    update public.ride_requests set status = 'cancelled', cancelled_at = now(), updated_at = now()
    where id = p_ride_id returning * into v_ride;
    if v_ride.driver_id is not null then
      update public.driver_profiles set availability_status = 'idle', updated_at = now()
      where user_id = v_ride.driver_id;
    end if;
  else
    raise exception 'Unsupported ride status transition';
  end if;

  if p_payment_status is not null then
    if p_payment_status <> 'paid' then
      raise exception 'Only verified payment completion can update payment status';
    end if;
    if v_ride.status <> 'completed' or coalesce(v_ride.payment_status,'pending') = 'paid' then
      if coalesce(v_ride.payment_status,'pending') = 'paid' then return v_ride; end if;
      raise exception 'Ride must be completed before payment confirmation';
    end if;
    if not v_is_service and not v_is_admin
       and (auth.uid() is distinct from v_ride.driver_id or v_ride.payment_method <> 'cash') then
      raise exception 'Digital payments must be confirmed by the payment provider';
    end if;
    update public.ride_requests set payment_status = 'paid', updated_at = now()
    where id = p_ride_id returning * into v_ride;

    select exists(select 1 from public.trips where ride_request_id = p_ride_id)
      into v_was_recorded;
    if not v_was_recorded then
      perform public.sta_record_trip(jsonb_build_object(
        'id', p_ride_id,
        'driverId', v_ride.driver_id,
        'fare', v_ride.final_fare,
        'paymentMethod', v_ride.payment_method
      ));
      update public.driver_profiles
      set total_rides = total_rides + 1,
          availability_status = 'idle',
          updated_at = now()
      where user_id = v_ride.driver_id;
    end if;
  end if;

  return v_ride;
end;
$$;
revoke all on function public.sta_set_ride_status(uuid,text,numeric,numeric,integer,text) from public;
grant execute on function public.sta_set_ride_status(uuid,text,numeric,numeric,integer,text) to authenticated, service_role;

-- Server-side trip ledger: one trip and one wallet entry per completed, paid ride.
create or replace function public.sta_record_trip(p_trip_data jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ride_id uuid := (p_trip_data ->> 'id')::uuid;
  v_driver_id uuid := (p_trip_data ->> 'driverId')::uuid;
  v_ride public.ride_requests;
  v_fare numeric(14,2);
  v_commission numeric(14,2);
  v_driver_share numeric(14,2);
  v_method text;
  v_role text := coalesce(auth.role(), '');
begin
  if auth.uid() is distinct from v_driver_id
     and not public.sta_is_active_admin()
     and v_role <> 'service_role' then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  select * into v_ride from public.ride_requests where id = v_ride_id for update;
  if not found or v_ride.driver_id is distinct from v_driver_id then
    raise exception 'Ride not found or driver mismatch';
  end if;
  if v_ride.status <> 'completed' or v_ride.payment_status <> 'paid' then
    raise exception 'Ride must be completed and payment verified before ledger posting';
  end if;
  if exists (select 1 from public.trips where ride_request_id = v_ride_id) then return; end if;

  v_fare := coalesce(v_ride.final_fare, (p_trip_data ->> 'fare')::numeric, 0);
  if v_fare <= 0 then raise exception 'Invalid trip fare'; end if;
  v_commission := round(v_fare * 0.20, 2);
  v_driver_share := round(v_fare * 0.80, 2);
  v_method := coalesce(v_ride.payment_method, 'cash');

  insert into public.trips (
    ride_request_id, rider_id, driver_id, started_at, completed_at,
    distance_meters, duration_seconds, fare
  ) values (
    v_ride_id, v_ride.rider_id, v_driver_id, v_ride.accepted_at, v_ride.completed_at,
    v_ride.distance_meters, v_ride.duration_seconds, v_fare
  );

  insert into public.wallets(user_id, balance)
  values (v_driver_id, case when v_method = 'cash' then -v_commission else v_driver_share end)
  on conflict (user_id) do update
    set balance = public.wallets.balance +
      case when v_method = 'cash' then -v_commission else v_driver_share end,
      updated_at = now();

  insert into public.wallet_transactions(
    user_id, amount, direction, transaction_type, status, reference, description
  ) values (
    v_driver_id,
    case when v_method = 'cash' then v_commission else v_driver_share end,
    case when v_method = 'cash' then 'debit' else 'credit' end,
    case when v_method = 'cash' then 'commission_deduction' else 'ride_earning' end,
    'completed', v_ride_id::text,
    case when v_method = 'cash' then 'Trip commission (cash)' else 'Trip earnings (digital)' end
  );
end;
$$;
revoke all on function public.sta_record_trip(jsonb) from public;
grant execute on function public.sta_record_trip(jsonb) to authenticated, service_role;
