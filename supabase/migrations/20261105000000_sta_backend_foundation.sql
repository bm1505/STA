-- STA Supabase backend foundation.
-- Additive migration only: existing application data is not deleted or modified.
-- Review and apply in a Supabase project only after confirming the project is the intended target.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('rider', 'driver', 'admin', 'staff', 'it', 'support')),
  full_name text not null default '',
  email text,
  phone_number text,
  avatar_url text,
  user_data jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  email_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists profiles_email_lower_uidx
  on public.profiles (lower(email)) where email is not null;

-- Create the profile row when Supabase Auth creates an account. The profile
-- payload is supplied by the STA client as auth user metadata.
create or replace function public.sta_handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text;
  v_name text;
  v_phone text;
begin
  v_role := coalesce(new.raw_user_meta_data ->> 'role', 'rider');
  if v_role not in ('rider', 'driver', 'admin', 'staff', 'it', 'support') then
    v_role := 'rider';
  end if;
  v_name := coalesce(new.raw_user_meta_data ->> 'name', '');
  v_phone := coalesce(new.raw_user_meta_data ->> 'phone_number', '');

  insert into public.profiles (id, role, full_name, email, phone_number, user_data)
  values (
    new.id, v_role, v_name, new.email, v_phone,
    jsonb_build_object(
      'id', new.id, 'role', v_role, 'name', v_name,
      'email', coalesce(new.email, ''), 'phoneNumber', v_phone,
      'createdAt', now(), 'isVerified', false,
      'verificationStatus', case when v_role = 'driver' then 'pending' else 'verified' end
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists sta_on_auth_user_created on auth.users;
create trigger sta_on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.sta_handle_new_auth_user();

create table if not exists public.driver_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  verification_status text not null default 'pending'
    check (verification_status in ('pending', 'submitted', 'verified', 'rejected', 'suspended')),
  vehicle_type text,
  vehicle_make text,
  vehicle_model text,
  vehicle_plate text,
  vehicle_color text,
  vehicle_year text,
  region text,
  city text,
  is_online boolean not null default false,
  availability_status text not null default 'offline'
    check (availability_status in ('offline', 'idle', 'offered', 'on_trip')),
  total_rides integer not null default 0 check (total_rides >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.driver_locations (
  driver_id uuid primary key references public.driver_profiles(user_id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  heading double precision,
  speed_mps double precision,
  recorded_at timestamptz not null default now()
);
create index if not exists driver_locations_recorded_at_idx
  on public.driver_locations (recorded_at desc);

create table if not exists public.ride_requests (
  id uuid primary key default gen_random_uuid(),
  rider_id uuid not null references public.profiles(id),
  driver_id uuid references public.profiles(id),
  status text not null default 'requesting'
    check (status in ('requesting', 'accepted', 'driver_arrived', 'in_progress', 'completed', 'cancelled', 'expired')),
  pickup_label text,
  pickup_latitude double precision not null check (pickup_latitude between -90 and 90),
  pickup_longitude double precision not null check (pickup_longitude between -180 and 180),
  dropoff_label text,
  dropoff_latitude double precision not null check (dropoff_latitude between -90 and 90),
  dropoff_longitude double precision not null check (dropoff_longitude between -180 and 180),
  vehicle_type text,
  estimated_fare numeric(14,2) check (estimated_fare is null or estimated_fare >= 0),
  final_fare numeric(14,2) check (final_fare is null or final_fare >= 0),
  currency text not null default 'TZS',
  active_call jsonb,
  ride_data jsonb not null default '{}'::jsonb,
  driver_latitude double precision,
  driver_longitude double precision,
  driver_heading double precision,
  distance_meters numeric(14,2),
  duration_seconds integer,
  payment_status text,
  requested_at timestamptz not null default now(),
  accepted_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ride_requests_rider_created_idx
  on public.ride_requests (rider_id, created_at desc);
create index if not exists ride_requests_driver_status_idx
  on public.ride_requests (driver_id, status, created_at desc);
create index if not exists ride_requests_status_created_idx
  on public.ride_requests (status, created_at desc);

create table if not exists public.trips (
  id uuid primary key default gen_random_uuid(),
  ride_request_id uuid not null unique references public.ride_requests(id),
  rider_id uuid not null references public.profiles(id),
  driver_id uuid not null references public.profiles(id),
  started_at timestamptz,
  completed_at timestamptz,
  distance_meters numeric(14,2),
  duration_seconds integer,
  fare numeric(14,2) check (fare is null or fare >= 0),
  currency text not null default 'TZS',
  created_at timestamptz not null default now()
);
create index if not exists trips_rider_created_idx on public.trips (rider_id, created_at desc);
create index if not exists trips_driver_created_idx on public.trips (driver_id, created_at desc);

create table if not exists public.wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  currency text not null default 'TZS',
  balance numeric(14,2) not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  amount numeric(14,2) not null check (amount > 0),
  direction text not null check (direction in ('credit', 'debit')),
  transaction_type text not null,
  status text not null default 'pending'
    check (status in ('pending', 'completed', 'failed', 'reversed')),
  reference text unique,
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists wallet_transactions_user_created_idx
  on public.wallet_transactions (user_id, created_at desc);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  ride_request_id uuid references public.ride_requests(id),
  provider text not null,
  provider_reference text unique,
  amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'TZS',
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed', 'cancelled', 'reversed')),
  phone_number text,
  provider_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists payments_user_created_idx on public.payments (user_id, created_at desc);

create or replace function public.sta_accept_ride(p_ride_id uuid)
returns public.ride_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ride public.ride_requests;
  v_driver public.driver_profiles;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select * into v_driver
  from public.driver_profiles
  where user_id = auth.uid()
    and is_online = true
    and availability_status = 'idle'
    and verification_status = 'verified'
  for update;

  if not found then
    raise exception 'Driver is not eligible to accept rides' using errcode = '42501';
  end if;

  update public.ride_requests
  set driver_id = auth.uid(),
      status = 'accepted',
      accepted_at = now(),
      updated_at = now()
  where id = p_ride_id
    and status = 'requesting'
    and driver_id is null
  returning * into v_ride;

  if not found then
    raise exception 'Ride is no longer available' using errcode = '40001';
  end if;

  update public.driver_profiles
  set availability_status = 'on_trip', updated_at = now()
  where user_id = auth.uid();

  return v_ride;
end;
$$;

revoke all on function public.sta_accept_ride(uuid) from public;
grant execute on function public.sta_accept_ride(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.driver_profiles enable row level security;
alter table public.driver_locations enable row level security;
alter table public.ride_requests enable row level security;
alter table public.trips enable row level security;
alter table public.wallets enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.payments enable row level security;

create policy "profiles_select_self" on public.profiles
  for select to authenticated using (id = auth.uid());
create policy "profiles_update_self" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy "driver_profile_select_self" on public.driver_profiles
  for select to authenticated using (user_id = auth.uid());
create policy "driver_profile_update_self" on public.driver_profiles
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Drivers can read their own precise location only. Rider access to nearby driver
-- positions must be exposed through a bounded server-side query/RPC.
create policy "driver_locations_select_self" on public.driver_locations
  for select to authenticated using (driver_id = auth.uid());
create policy "driver_locations_insert_self" on public.driver_locations
  for insert to authenticated with check (driver_id = auth.uid());
create policy "driver_locations_update_self" on public.driver_locations
  for update to authenticated using (driver_id = auth.uid()) with check (driver_id = auth.uid());

create policy "ride_requests_select_participant" on public.ride_requests
  for select to authenticated using (rider_id = auth.uid() or driver_id = auth.uid());
create policy "ride_requests_insert_rider" on public.ride_requests
  for insert to authenticated with check (rider_id = auth.uid() and driver_id is null and status = 'requesting');

create policy "trips_select_participant" on public.trips
  for select to authenticated using (rider_id = auth.uid() or driver_id = auth.uid());

create policy "wallets_select_owner" on public.wallets
  for select to authenticated using (user_id = auth.uid());
create policy "wallet_transactions_select_owner" on public.wallet_transactions
  for select to authenticated using (user_id = auth.uid());
create policy "payments_select_owner" on public.payments
  for select to authenticated using (user_id = auth.uid());

-- No client policies are intentionally provided for wallet writes, payment writes,
-- ride status transitions, or trip creation. Those must be implemented through
-- validated server-side RPC/Edge Functions after mapping the complete current rules.


create table if not exists public.notification_broadcasts (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  target_group text not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);
alter table public.notification_broadcasts enable row level security;
create policy "notification_broadcasts_admin_insert"
  on public.notification_broadcasts for insert to authenticated
  with check (
    created_by = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin'
    )
  );
create policy "notification_broadcasts_admin_select"
  on public.notification_broadcasts for select to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin'
    )
  );


-- Supporting operational tables used by the STA mobile clients.
create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  chat_id text not null,
  sender_id uuid not null references public.profiles(id),
  receiver_id uuid not null references public.profiles(id),
  sender_name text not null default '',
  message text not null,
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_chat_created_idx
  on public.chat_messages (chat_id, created_at);

create table if not exists public.sos_alerts (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid references public.ride_requests(id),
  user_id uuid not null references public.profiles(id),
  role text not null,
  latitude double precision not null,
  longitude double precision not null,
  status text not null default 'active',
  created_at timestamptz not null default now()
);

create table if not exists public.ride_ratings (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.ride_requests(id),
  target_user_id uuid not null references public.profiles(id),
  driver_id uuid references public.profiles(id),
  from_role text not null,
  rider_name text,
  rating integer not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now()
);

create table if not exists public.app_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  amount numeric(14,2) not null check (amount > 0),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'rejected', 'failed')),
  phone_number text,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

alter table public.chat_messages enable row level security;
alter table public.sos_alerts enable row level security;
alter table public.ride_ratings enable row level security;
alter table public.app_settings enable row level security;
alter table public.withdrawal_requests enable row level security;

create policy "chat_messages_participant_access" on public.chat_messages
  for all to authenticated
  using (sender_id = auth.uid() or receiver_id = auth.uid())
  with check (sender_id = auth.uid());
create policy "sos_alerts_insert_owner" on public.sos_alerts
  for insert to authenticated with check (user_id = auth.uid());
create policy "sos_alerts_select_owner" on public.sos_alerts
  for select to authenticated using (user_id = auth.uid());
create policy "ride_ratings_insert_participant" on public.ride_ratings
  for insert to authenticated with check (
    exists (select 1 from public.ride_requests r
      where r.id = ride_id and (r.rider_id = auth.uid() or r.driver_id = auth.uid()))
  );
create policy "ride_ratings_select_participant" on public.ride_ratings
  for select to authenticated using (
    exists (select 1 from public.ride_requests r
      where r.id = ride_id and (r.rider_id = auth.uid() or r.driver_id = auth.uid()))
  );
create policy "app_settings_read_authenticated" on public.app_settings
  for select to authenticated using (true);
create policy "app_settings_admin_write" on public.app_settings
  for all to authenticated using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  ) with check (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );
create policy "withdrawal_requests_owner_read" on public.withdrawal_requests
  for select to authenticated using (user_id = auth.uid());

create or replace function public.sta_increment_driver_rides(p_driver_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is distinct from p_driver_id
     and not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  update public.driver_profiles
    set total_rides = total_rides + 1, updated_at = now()
    where user_id = p_driver_id;
end;
$$;

create or replace function public.sta_nearby_drivers(
  p_latitude double precision, p_longitude double precision,
  p_vehicle_type text default null, p_region text default null
)
returns table(driver_id uuid, latitude double precision, longitude double precision)
language sql stable security definer set search_path = public, pg_temp as $$
  select dp.user_id, dl.latitude, dl.longitude
  from public.driver_profiles dp
  join public.driver_locations dl on dl.driver_id = dp.user_id
  where dp.is_online = true
    and dp.availability_status = 'idle'
    and dp.verification_status = 'verified'
    and (p_vehicle_type is null or dp.vehicle_type = p_vehicle_type)
    and (p_region is null or dp.region = p_region)
    and dl.recorded_at > now() - interval '2 minutes'
    and abs(dl.latitude - p_latitude) <= 0.15
    and abs(dl.longitude - p_longitude) <= 0.15;
$$;
revoke all on function public.sta_nearby_drivers(double precision,double precision,text,text) from public;
grant execute on function public.sta_nearby_drivers(double precision,double precision,text,text) to authenticated;


-- Server-side wallet and trip accounting. Client apps cannot write balances directly.
create or replace function public.sta_record_trip(p_trip_data jsonb)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_ride_id uuid := (p_trip_data ->> 'id')::uuid;
  v_driver_id uuid := (p_trip_data ->> 'driverId')::uuid;
  v_ride public.ride_requests;
  v_fare numeric(14,2);
  v_commission numeric(14,2);
  v_driver_share numeric(14,2);
  v_method text;
begin
  if auth.uid() is distinct from v_driver_id
     and not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  select * into v_ride from public.ride_requests where id = v_ride_id for update;
  if not found or v_ride.driver_id is distinct from v_driver_id then
    raise exception 'Ride not found or driver mismatch';
  end if;
  if exists (select 1 from public.trips where ride_request_id = v_ride_id) then
    return;
  end if;
  v_fare := coalesce((p_trip_data ->> 'fare')::numeric, v_ride.final_fare, v_ride.estimated_fare, 0);
  if v_fare <= 0 then raise exception 'Invalid trip fare'; end if;
  v_commission := round(v_fare * 0.20, 2);
  v_driver_share := round(v_fare * 0.80, 2);
  v_method := lower(coalesce(p_trip_data ->> 'paymentMethod', 'cash'));

  insert into public.trips (
    ride_request_id, rider_id, driver_id, completed_at,
    distance_meters, duration_seconds, fare
  ) values (
    v_ride_id, v_ride.rider_id, v_driver_id, now(),
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
grant execute on function public.sta_record_trip(jsonb) to authenticated;

create or replace function public.sta_adjust_wallet(
  p_user_id uuid, p_amount numeric, p_type text
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if p_amount = 0 then raise exception 'Amount cannot be zero'; end if;
  insert into public.wallets(user_id, balance) values (p_user_id, p_amount)
  on conflict (user_id) do update set balance = public.wallets.balance + p_amount, updated_at = now();
  insert into public.wallet_transactions(user_id, amount, direction, transaction_type, status, description)
  values (p_user_id, abs(p_amount), case when p_amount > 0 then 'credit' else 'debit' end, p_type, 'completed', 'Admin wallet adjustment');
end;
$$;
revoke all on function public.sta_adjust_wallet(uuid,numeric,text) from public;
grant execute on function public.sta_adjust_wallet(uuid,numeric,text) to authenticated;

create or replace function public.sta_process_topup(
  p_payment_id uuid, p_user_id uuid, p_amount numeric
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_payment public.payments;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  select * into v_payment from public.payments where id = p_payment_id and user_id = p_user_id for update;
  if not found or v_payment.status <> 'pending' or v_payment.amount <> p_amount then
    raise exception 'Payment cannot be approved';
  end if;
  update public.payments set status = 'completed', updated_at = now() where id = p_payment_id;
  insert into public.wallets(user_id, balance) values (p_user_id, p_amount)
  on conflict (user_id) do update set balance = public.wallets.balance + p_amount, updated_at = now();
  insert into public.wallet_transactions(user_id, amount, direction, transaction_type, status, reference, description)
  values (p_user_id, p_amount, 'credit', 'topup', 'completed', p_payment_id::text, 'Wallet top-up');
end;
$$;
revoke all on function public.sta_process_topup(uuid,uuid,numeric) from public;
grant execute on function public.sta_process_topup(uuid,uuid,numeric) to authenticated;

create or replace function public.sta_manual_topup(p_user_id uuid, p_amount numeric)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if p_amount <= 0 then raise exception 'Invalid top-up amount'; end if;
  insert into public.wallets(user_id, balance) values (p_user_id, p_amount)
  on conflict (user_id) do update set balance = public.wallets.balance + p_amount, updated_at = now();
  insert into public.wallet_transactions(user_id, amount, direction, transaction_type, status, description)
  values (p_user_id, p_amount, 'credit', 'manual_topup', 'completed', 'Manual wallet top-up');
end;
$$;
revoke all on function public.sta_manual_topup(uuid,numeric) from public;
grant execute on function public.sta_manual_topup(uuid,numeric) to authenticated;

create or replace function public.sta_process_withdrawal(
  p_withdrawal_id uuid, p_user_id uuid, p_amount numeric, p_approve boolean
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_request public.withdrawal_requests;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  select * into v_request from public.withdrawal_requests
    where id = p_withdrawal_id and user_id = p_user_id for update;
  if not found or v_request.status <> 'pending' then raise exception 'Withdrawal is not pending'; end if;
  if p_approve then
    if v_request.amount <> p_amount then raise exception 'Withdrawal amount mismatch'; end if;
    update public.wallets set balance = balance - p_amount, updated_at = now()
      where user_id = p_user_id and balance >= p_amount;
    if not found then raise exception 'Insufficient wallet balance'; end if;
    insert into public.wallet_transactions(user_id, amount, direction, transaction_type, status, reference, description)
      values (p_user_id, p_amount, 'debit', 'withdrawal', 'completed', p_withdrawal_id::text, 'Withdrawal paid');
    update public.withdrawal_requests set status = 'completed', processed_at = now() where id = p_withdrawal_id;
  else
    update public.withdrawal_requests set status = 'rejected', processed_at = now() where id = p_withdrawal_id;
  end if;
end;
$$;
revoke all on function public.sta_process_withdrawal(uuid,uuid,numeric,boolean) from public;
grant execute on function public.sta_process_withdrawal(uuid,uuid,numeric,boolean) to authenticated;
