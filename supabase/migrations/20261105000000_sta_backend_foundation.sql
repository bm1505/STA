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
as $
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
$;

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
  balance numeric(14,2) not null default 0 check (balance >= 0),
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
