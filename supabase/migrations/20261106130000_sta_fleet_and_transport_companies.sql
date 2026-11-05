-- Fleet, vehicle owner and transport company foundation with tenant-scoped access.
create table if not exists public.transport_organizations (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id),
  name text not null,
  organization_type text not null check (organization_type in ('vehicle_owner','transport_company')),
  country_code text not null default 'TZ',
  phone_number text,
  email text,
  status text not null default 'active' check (status in ('active','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.organization_members (
  organization_id uuid not null references public.transport_organizations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner','manager','fleet_manager','finance','dispatcher','driver','viewer')),
  status text not null default 'active' check (status in ('invited','active','suspended')),
  joined_at timestamptz not null default now(),
  primary key (organization_id,user_id)
);

create table if not exists public.transport_branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.transport_organizations(id) on delete cascade,
  name text not null,
  region text,
  city text,
  address text,
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now()
);

create table if not exists public.fleet_vehicles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.transport_organizations(id) on delete cascade,
  branch_id uuid references public.transport_branches(id) on delete set null,
  registration_number text not null,
  make text,
  model text,
  vehicle_type text not null,
  manufacture_year integer,
  passenger_capacity integer not null default 4 check (passenger_capacity > 0),
  current_odometer_km numeric(14,2),
  color text,
  status text not null default 'active' check (status in ('active','maintenance','inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,registration_number)
);

create table if not exists public.fleet_vehicle_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.transport_organizations(id) on delete cascade,
  vehicle_id uuid not null references public.fleet_vehicles(id) on delete cascade,
  driver_id uuid not null references public.profiles(id),
  assigned_by uuid not null references public.profiles(id),
  assigned_at timestamptz not null default now(),
  unassigned_at timestamptz,
  status text not null default 'active' check (status in ('active','ended'))
);
create unique index if not exists fleet_one_active_vehicle_per_driver
  on public.fleet_vehicle_assignments(driver_id) where status = 'active';
create unique index if not exists fleet_one_active_driver_per_vehicle
  on public.fleet_vehicle_assignments(vehicle_id) where status = 'active';

alter table public.fleet_vehicle_assignments
  add column if not exists previous_vehicle_type text,
  add column if not exists previous_vehicle_plate text;

create table if not exists public.fleet_fuel_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.transport_organizations(id) on delete cascade,
  vehicle_id uuid not null references public.fleet_vehicles(id) on delete cascade,
  driver_id uuid references public.profiles(id),
  quantity_liters numeric(12,2) not null check (quantity_liters > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  total_cost numeric(14,2) generated always as (quantity_liters * unit_price) stored,
  odometer_km numeric(14,2),
  fuel_station text,
  logged_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.fleet_maintenance_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.transport_organizations(id) on delete cascade,
  vehicle_id uuid not null references public.fleet_vehicles(id) on delete cascade,
  maintenance_type text not null,
  description text,
  cost numeric(14,2) not null default 0 check (cost >= 0),
  odometer_km numeric(14,2),
  scheduled_at timestamptz,
  completed_at timestamptz,
  status text not null default 'scheduled' check (status in ('scheduled','in_progress','completed','cancelled')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.transport_contracts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.transport_organizations(id) on delete cascade,
  client_name text not null,
  contract_reference text,
  start_date date,
  end_date date,
  contract_value numeric(14,2),
  details jsonb not null default '{}'::jsonb,
  status text not null default 'active' check (status in ('draft','active','completed','cancelled')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.driver_profiles
  add column if not exists vehicle_id uuid references public.fleet_vehicles(id) on delete set null;
alter table public.ride_requests
  add column if not exists vehicle_id uuid references public.fleet_vehicles(id) on delete set null;
alter table public.trips
  add column if not exists vehicle_id uuid references public.fleet_vehicles(id) on delete set null;

create or replace function public.sta_is_org_member(p_org_id uuid, p_roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.sta_is_active_admin() or exists (
    select 1 from public.organization_members m
    where m.organization_id = p_org_id and m.user_id = auth.uid()
      and m.status = 'active'
      and (p_roles is null or m.role = any(p_roles))
  ) or exists (
    select 1 from public.transport_organizations o
    where o.id = p_org_id and o.owner_user_id = auth.uid()
  );
$$;
revoke all on function public.sta_is_org_member(uuid,text[]) from public;
grant execute on function public.sta_is_org_member(uuid,text[]) to authenticated;

alter table public.transport_organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.transport_branches enable row level security;
alter table public.fleet_vehicles enable row level security;
alter table public.fleet_vehicle_assignments enable row level security;
alter table public.fleet_fuel_logs enable row level security;
alter table public.fleet_maintenance_records enable row level security;
alter table public.transport_contracts enable row level security;

create policy transport_orgs_member_read on public.transport_organizations
  for select to authenticated using (public.sta_is_org_member(id));
create policy transport_orgs_owner_update on public.transport_organizations
  for update to authenticated using (owner_user_id = auth.uid() or public.sta_is_active_admin())
  with check (owner_user_id = auth.uid() or public.sta_is_active_admin());
create policy transport_orgs_admin_read on public.transport_organizations
  for select to authenticated using (public.sta_is_active_admin());

drop policy if exists org_members_member_read on public.organization_members;
create policy org_members_member_read on public.organization_members
  for select to authenticated using (
    user_id = auth.uid()
    or public.sta_is_org_member(organization_id,array['owner','manager','fleet_manager','finance','dispatcher','viewer'])
  );
drop policy if exists transport_branches_member_read on public.transport_branches;
create policy transport_branches_member_read on public.transport_branches
  for select to authenticated using (
    public.sta_is_org_member(organization_id,array['owner','manager','fleet_manager','dispatcher','viewer','finance'])
  );
drop policy if exists fleet_vehicles_member_read on public.fleet_vehicles;
create policy fleet_vehicles_member_read on public.fleet_vehicles
  for select to authenticated using (
    public.sta_is_org_member(organization_id,array['owner','manager','fleet_manager','dispatcher','viewer','finance'])
    or exists (
      select 1 from public.fleet_vehicle_assignments a
      where a.vehicle_id=fleet_vehicles.id and a.driver_id=auth.uid() and a.status='active'
    )
  );
drop policy if exists fleet_assignments_member_read on public.fleet_vehicle_assignments;
create policy fleet_assignments_member_read on public.fleet_vehicle_assignments
  for select to authenticated using (
    driver_id=auth.uid()
    or public.sta_is_org_member(organization_id,array['owner','manager','fleet_manager','dispatcher','viewer','finance'])
  );
drop policy if exists fleet_fuel_member_read on public.fleet_fuel_logs;
create policy fleet_fuel_member_read on public.fleet_fuel_logs
  for select to authenticated using (
    public.sta_is_org_member(organization_id,array['owner','manager','fleet_manager','finance','viewer'])
  );
drop policy if exists fleet_maintenance_member_read on public.fleet_maintenance_records;
create policy fleet_maintenance_member_read on public.fleet_maintenance_records
  for select to authenticated using (
    public.sta_is_org_member(organization_id,array['owner','manager','fleet_manager','viewer','finance'])
  );
drop policy if exists transport_contracts_member_read on public.transport_contracts;
create policy transport_contracts_member_read on public.transport_contracts
  for select to authenticated using (
    public.sta_is_org_member(organization_id,array['owner','manager','finance','viewer'])
  );
create or replace function public.sta_create_transport_organization(
  p_name text,
  p_organization_type text,
  p_country_code text default 'TZ',
  p_phone_number text default null,
  p_email text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if coalesce(trim(p_name),'') = '' or p_organization_type not in ('vehicle_owner','transport_company') then
    raise exception 'Valid organization name and type are required';
  end if;
  insert into public.transport_organizations(owner_user_id,name,organization_type,country_code,phone_number,email)
  values(auth.uid(),trim(p_name),p_organization_type,upper(coalesce(p_country_code,'TZ')),p_phone_number,p_email)
  returning id into v_id;
  insert into public.organization_members(organization_id,user_id,role,status)
  values(v_id,auth.uid(),'owner','active');
  return v_id;
end;
$$;
revoke all on function public.sta_create_transport_organization(text,text,text,text,text) from public;
grant execute on function public.sta_create_transport_organization(text,text,text,text,text) to authenticated;

create or replace function public.sta_list_org_members(p_org_id uuid)
returns table(user_id uuid,member_name text,phone_number text,member_role text,member_status text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.sta_is_org_member(p_org_id,array['owner','manager','fleet_manager','finance','dispatcher','viewer']) then
    raise exception 'Organization management access required' using errcode = '42501';
  end if;
  return query
  select m.user_id,
    coalesce(p.user_data->>'name',p.full_name,'STA user'),
    p.phone_number,m.role,m.status
  from public.organization_members m
  join public.profiles p on p.id=m.user_id
  where m.organization_id=p_org_id
  order by case when m.role='owner' then 0 when m.role='manager' then 1 else 2 end,m.joined_at;
end;
$$;
revoke all on function public.sta_list_org_members(uuid) from public;
grant execute on function public.sta_list_org_members(uuid) to authenticated;

create or replace function public.sta_search_org_users(p_org_id uuid,p_query text)
returns table(user_id uuid,display_name text,email text,phone_number text,account_role text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.sta_is_org_member(p_org_id,array['owner','manager']) then
    raise exception 'Organization manager access required' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_query,''))) < 3 then
    raise exception 'Enter at least three characters to search';
  end if;
  return query
  select p.id,coalesce(p.user_data->>'name',p.full_name,'STA user'),p.email,p.phone_number,p.role
  from public.profiles p
  where p.is_active=true
    and p.id <> auth.uid()
    and not exists(select 1 from public.organization_members m where m.organization_id=p_org_id and m.user_id=p.id)
    and (
      coalesce(p.email,'') ilike '%'||trim(p_query)||'%'
      or coalesce(p.phone_number,'') ilike '%'||trim(p_query)||'%'
      or coalesce(p.full_name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(p.user_data->>'name','') ilike '%'||trim(p_query)||'%'
    )
  order by p.full_name
  limit 20;
end;
$$;
revoke all on function public.sta_search_org_users(uuid,text) from public;
grant execute on function public.sta_search_org_users(uuid,text) to authenticated;

create or replace function public.sta_add_org_member(
  p_org_id uuid,p_user_id uuid,p_role text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.sta_is_org_member(p_org_id,array['owner','manager']) then
    raise exception 'Organization owner or manager access required' using errcode = '42501';
  end if;
  if p_role not in ('manager','fleet_manager','finance','dispatcher','viewer') then
    raise exception 'Unsupported organization member role';
  end if;
  if not exists(select 1 from public.profiles where id=p_user_id and is_active=true) then
    raise exception 'Active STA account not found';
  end if;
  insert into public.organization_members(organization_id,user_id,role,status)
  values(p_org_id,p_user_id,p_role,'active')
  on conflict(organization_id,user_id) do update set role=excluded.role,status='active';
end;
$$;
revoke all on function public.sta_add_org_member(uuid,uuid,text) from public;
grant execute on function public.sta_add_org_member(uuid,uuid,text) to authenticated;

create or replace function public.sta_list_my_organizations()
returns table(id uuid,name text,organization_type text,role text,created_at timestamptz)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select o.id,o.name,o.organization_type,
    case when public.sta_is_active_admin() then 'admin'
         when o.owner_user_id = auth.uid() then 'owner' else m.role end,
    o.created_at
  from public.transport_organizations o
  left join public.organization_members m
    on m.organization_id = o.id and m.user_id = auth.uid() and m.status = 'active'
  where o.owner_user_id = auth.uid() or m.user_id = auth.uid() or public.sta_is_active_admin()
  order by o.created_at desc;
$$;
revoke all on function public.sta_list_my_organizations() from public;
grant execute on function public.sta_list_my_organizations() to authenticated;

create or replace function public.sta_create_transport_branch(
  p_org_id uuid,p_name text,p_region text default null,p_city text default null,p_address text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if not public.sta_is_org_member(p_org_id,array['owner','manager']) then
    raise exception 'Organization manager access required' using errcode = '42501';
  end if;
  insert into public.transport_branches(organization_id,name,region,city,address)
  values(p_org_id,trim(p_name),p_region,p_city,p_address) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.sta_create_transport_branch(uuid,text,text,text,text) from public;
grant execute on function public.sta_create_transport_branch(uuid,text,text,text,text) to authenticated;

create or replace function public.sta_create_fleet_vehicle(
  p_org_id uuid,p_registration_number text,p_vehicle_type text,
  p_make text default null,p_model text default null,p_year integer default null,
  p_capacity integer default 4,p_branch_id uuid default null,p_color text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if not public.sta_is_org_member(p_org_id,array['owner','manager','fleet_manager']) then
    raise exception 'Fleet manager access required' using errcode = '42501';
  end if;
  if coalesce(trim(p_registration_number),'') = '' or coalesce(trim(p_vehicle_type),'') = '' then
    raise exception 'Registration number and vehicle type are required';
  end if;
  if p_branch_id is not null and not exists(
    select 1 from public.transport_branches b where b.id=p_branch_id and b.organization_id=p_org_id
  ) then raise exception 'Branch does not belong to this organization'; end if;
  insert into public.fleet_vehicles(
    organization_id,branch_id,registration_number,make,model,vehicle_type,manufacture_year,passenger_capacity,color
  ) values (
    p_org_id,p_branch_id,upper(trim(p_registration_number)),p_make,p_model,p_vehicle_type,p_year,greatest(p_capacity,1),p_color
  ) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.sta_create_fleet_vehicle(uuid,text,text,text,text,integer,integer,uuid,text) from public;
grant execute on function public.sta_create_fleet_vehicle(uuid,text,text,text,text,integer,integer,uuid,text) to authenticated;

create or replace function public.sta_search_available_drivers(p_org_id uuid,p_query text default '')
returns table(driver_id uuid,driver_name text,phone_number text,vehicle_type text,is_online boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.sta_is_org_member(p_org_id,array['owner','manager','fleet_manager']) then
    raise exception 'Fleet manager access required' using errcode = '42501';
  end if;
  return query
  select dp.user_id,
    coalesce(p.user_data->>'name',p.full_name,'Driver'),
    p.phone_number,dp.vehicle_type,dp.is_online
  from public.driver_profiles dp
  join public.profiles p on p.id=dp.user_id
  where dp.verification_status='verified' and p.is_active=true
    and not exists(select 1 from public.fleet_vehicle_assignments a where a.driver_id=dp.user_id and a.status='active')
    and (
      coalesce(trim(p_query),'') = ''
      or coalesce(p.user_data->>'name',p.full_name,'') ilike '%'||p_query||'%'
      or coalesce(p.phone_number,'') ilike '%'||p_query||'%'
    )
  order by dp.is_online desc,dp.total_rides desc
  limit 50;
end;
$$;
revoke all on function public.sta_search_available_drivers(uuid,text) from public;
grant execute on function public.sta_search_available_drivers(uuid,text) to authenticated;

create or replace function public.sta_assign_driver_vehicle(p_org_id uuid,p_vehicle_id uuid,p_driver_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_assignment uuid;
  v_vehicle public.fleet_vehicles;
  v_previous_vehicle_type text;
  v_previous_vehicle_plate text;
begin
  if not public.sta_is_org_member(p_org_id,array['owner','manager','fleet_manager']) then
    raise exception 'Fleet manager access required' using errcode = '42501';
  end if;
  select * into v_vehicle from public.fleet_vehicles where id=p_vehicle_id and organization_id=p_org_id and status='active';
  if not found then raise exception 'Active vehicle not found in this organization'; end if;
  if not exists(
    select 1 from public.driver_profiles dp
    join public.profiles p on p.id=dp.user_id
    where dp.user_id=p_driver_id and dp.verification_status='verified'
      and p.role='driver' and p.is_active=true
  ) then
    raise exception 'Only active verified drivers can be assigned';
  end if;
  if exists(select 1 from public.fleet_vehicle_assignments where driver_id=p_driver_id and status='active') then
    raise exception 'Driver already has an active vehicle assignment';
  end if;
  if exists(select 1 from public.ride_requests where driver_id=p_driver_id and status in ('accepted','driver_arrived','in_progress')) then
    raise exception 'Driver must finish the active ride before vehicle assignment';
  end if;
  select vehicle_type,vehicle_plate into v_previous_vehicle_type,v_previous_vehicle_plate
  from public.driver_profiles where user_id=p_driver_id for update;
  insert into public.fleet_vehicle_assignments(
    organization_id,vehicle_id,driver_id,assigned_by,previous_vehicle_type,previous_vehicle_plate
  ) values(
    p_org_id,p_vehicle_id,p_driver_id,auth.uid(),v_previous_vehicle_type,v_previous_vehicle_plate
  ) returning id into v_assignment;
  insert into public.organization_members(organization_id,user_id,role,status)
  values(p_org_id,p_driver_id,'driver','active')
  on conflict(organization_id,user_id) do update set status='active';
  update public.driver_profiles
  set vehicle_id=p_vehicle_id,
      vehicle_type=v_vehicle.vehicle_type,
      vehicle_plate=v_vehicle.registration_number,
      is_online=false,
      availability_status='offline',
      updated_at=now()
  where user_id=p_driver_id;
  delete from public.driver_locations where driver_id=p_driver_id;
  return v_assignment;
end;
$$;
revoke all on function public.sta_assign_driver_vehicle(uuid,uuid,uuid) from public;
grant execute on function public.sta_assign_driver_vehicle(uuid,uuid,uuid) to authenticated;

create or replace function public.sta_list_org_assignments(p_org_id uuid)
returns table(
  assignment_id uuid,
  driver_id uuid,
  driver_name text,
  driver_phone text,
  vehicle_id uuid,
  vehicle_plate text,
  assigned_at timestamptz,
  is_online boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.sta_is_org_member(p_org_id,array['owner','manager','fleet_manager','dispatcher','viewer','finance']) then
    raise exception 'Fleet monitoring access required' using errcode = '42501';
  end if;
  return query
  select a.id,a.driver_id,
    coalesce(p.user_data->>'name',p.full_name,'Driver'),
    p.phone_number,a.vehicle_id,v.registration_number,a.assigned_at,dp.is_online
  from public.fleet_vehicle_assignments a
  join public.fleet_vehicles v on v.id=a.vehicle_id
  join public.driver_profiles dp on dp.user_id=a.driver_id
  join public.profiles p on p.id=a.driver_id
  where a.organization_id=p_org_id and a.status='active'
  order by a.assigned_at desc;
end;
$$;
revoke all on function public.sta_list_org_assignments(uuid) from public;
grant execute on function public.sta_list_org_assignments(uuid) to authenticated;

create or replace function public.sta_unassign_driver_vehicle(p_assignment_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_assignment public.fleet_vehicle_assignments;
begin
  select * into v_assignment from public.fleet_vehicle_assignments
  where id=p_assignment_id and status='active' for update;
  if not found then raise exception 'Active assignment not found'; end if;
  if not public.sta_is_org_member(v_assignment.organization_id,array['owner','manager','fleet_manager']) then
    raise exception 'Fleet manager access required' using errcode = '42501';
  end if;
  if exists(
    select 1 from public.ride_requests
    where driver_id=v_assignment.driver_id and status in ('accepted','driver_arrived','in_progress')
  ) then raise exception 'Driver must finish the active ride before unassignment'; end if;
  update public.fleet_vehicle_assignments
  set status='ended',unassigned_at=now()
  where id=p_assignment_id;
  update public.driver_profiles
  set vehicle_id=null,
      vehicle_type=v_assignment.previous_vehicle_type,
      vehicle_plate=v_assignment.previous_vehicle_plate,
      is_online=false,
      availability_status='offline',
      updated_at=now()
  where user_id=v_assignment.driver_id and vehicle_id=v_assignment.vehicle_id;
  delete from public.driver_locations where driver_id=v_assignment.driver_id;
  update public.organization_members
  set status='suspended'
  where organization_id=v_assignment.organization_id
    and user_id=v_assignment.driver_id and role='driver';
end;
$$;
revoke all on function public.sta_unassign_driver_vehicle(uuid) from public;
grant execute on function public.sta_unassign_driver_vehicle(uuid) to authenticated;

create or replace function public.sta_log_vehicle_fuel(
  p_org_id uuid,p_vehicle_id uuid,p_quantity_liters numeric,p_unit_price numeric,
  p_odometer_km numeric default null,p_fuel_station text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid; v_driver uuid;
begin
  if not public.sta_is_org_member(p_org_id,array['owner','manager','fleet_manager','finance']) then
    raise exception 'Fleet or finance access required' using errcode = '42501';
  end if;
  if not exists(select 1 from public.fleet_vehicles where id=p_vehicle_id and organization_id=p_org_id) then
    raise exception 'Vehicle not found';
  end if;
  select driver_id into v_driver from public.fleet_vehicle_assignments
  where vehicle_id=p_vehicle_id and status='active' limit 1;
  if p_odometer_km is not null and exists(
    select 1 from public.fleet_vehicles
    where id=p_vehicle_id and current_odometer_km is not null and p_odometer_km < current_odometer_km
  ) then raise exception 'Odometer reading cannot decrease'; end if;
  insert into public.fleet_fuel_logs(organization_id,vehicle_id,driver_id,quantity_liters,unit_price,odometer_km,fuel_station,logged_by)
  values(p_org_id,p_vehicle_id,v_driver,p_quantity_liters,p_unit_price,p_odometer_km,p_fuel_station,auth.uid())
  returning id into v_id;
  if p_odometer_km is not null then
    update public.fleet_vehicles set current_odometer_km=p_odometer_km,updated_at=now()
    where id=p_vehicle_id;
  end if;
  return v_id;
end;
$$;
revoke all on function public.sta_log_vehicle_fuel(uuid,uuid,numeric,numeric,numeric,text) from public;
grant execute on function public.sta_log_vehicle_fuel(uuid,uuid,numeric,numeric,numeric,text) to authenticated;

create or replace function public.sta_create_maintenance_record(
  p_org_id uuid,p_vehicle_id uuid,p_maintenance_type text,p_description text default null,
  p_cost numeric default 0,p_odometer_km numeric default null,p_scheduled_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if not public.sta_is_org_member(p_org_id,array['owner','manager','fleet_manager']) then
    raise exception 'Fleet manager access required' using errcode = '42501';
  end if;
  if not exists(select 1 from public.fleet_vehicles where id=p_vehicle_id and organization_id=p_org_id) then
    raise exception 'Vehicle not found';
  end if;
  insert into public.fleet_maintenance_records(
    organization_id,vehicle_id,maintenance_type,description,cost,odometer_km,scheduled_at,created_by
  ) values (
    p_org_id,p_vehicle_id,trim(p_maintenance_type),p_description,greatest(coalesce(p_cost,0),0),p_odometer_km,p_scheduled_at,auth.uid()
  ) returning id into v_id;
  if p_scheduled_at is null or p_scheduled_at <= now() then
    update public.fleet_vehicles set status='maintenance',updated_at=now()
    where id=p_vehicle_id;
  end if;
  return v_id;
end;
$$;
revoke all on function public.sta_create_maintenance_record(uuid,uuid,text,text,numeric,numeric,timestamptz) from public;
grant execute on function public.sta_create_maintenance_record(uuid,uuid,text,text,numeric,numeric,timestamptz) to authenticated;

create or replace function public.sta_create_transport_contract(
  p_org_id uuid,p_client_name text,p_contract_reference text default null,
  p_start_date date default null,p_end_date date default null,p_contract_value numeric default null,
  p_details jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if not public.sta_is_org_member(p_org_id,array['owner','manager','finance']) then
    raise exception 'Organization finance or manager access required' using errcode = '42501';
  end if;
  if coalesce(trim(p_client_name),'')='' then raise exception 'Client name is required'; end if;
  insert into public.transport_contracts(
    organization_id,client_name,contract_reference,start_date,end_date,contract_value,details,created_by
  ) values (
    p_org_id,trim(p_client_name),p_contract_reference,p_start_date,p_end_date,p_contract_value,coalesce(p_details,'{}'::jsonb),auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.sta_create_transport_contract(uuid,text,text,date,date,numeric,jsonb) from public;
grant execute on function public.sta_create_transport_contract(uuid,text,text,date,date,numeric,jsonb) to authenticated;

-- Organization members can see telemetry only for drivers assigned to their own fleet.
create policy driver_locations_org_member_select on public.driver_locations
  for select to authenticated using (
    exists (
      select 1 from public.fleet_vehicle_assignments a
      where a.driver_id = driver_locations.driver_id
        and a.organization_id in (
          select m.organization_id from public.organization_members m
          where m.user_id = auth.uid() and m.status = 'active'
            and m.role in ('owner','manager','fleet_manager','dispatcher')
        )
        and a.status = 'active'
    )
  );

create or replace function public.sta_org_live_locations(p_org_id uuid)
returns table(
  driver_id uuid,
  driver_name text,
  vehicle_plate text,
  latitude double precision,
  longitude double precision,
  heading double precision,
  recorded_at timestamptz,
  availability_status text,
  active_ride_status text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.sta_is_org_member(p_org_id,array['owner','manager','fleet_manager','dispatcher','viewer']) then
    raise exception 'Fleet monitoring access required' using errcode = '42501';
  end if;
  return query
  select a.driver_id,
    coalesce(p.user_data->>'name',p.full_name,'Driver'),
    v.registration_number,
    dl.latitude,dl.longitude,dl.heading,dl.recorded_at,dp.availability_status,
    (select r.status from public.ride_requests r
      where r.driver_id=a.driver_id and r.status in ('accepted','driver_arrived','in_progress')
      order by r.updated_at desc limit 1)
  from public.fleet_vehicle_assignments a
  join public.fleet_vehicles v on v.id=a.vehicle_id
  join public.driver_profiles dp on dp.user_id=a.driver_id
  join public.profiles p on p.id=a.driver_id
  join public.driver_locations dl on dl.driver_id=a.driver_id
  where a.organization_id=p_org_id and a.status='active'
    and dp.is_online=true and dl.recorded_at > now()-interval '5 minutes'
  order by dl.recorded_at desc;
end;
$$;
revoke all on function public.sta_org_live_locations(uuid) from public;
grant execute on function public.sta_org_live_locations(uuid) to authenticated;

create or replace function public.sta_owner_dashboard(p_org_id uuid)
returns table(
  vehicle_count bigint,
  active_vehicle_count bigint,
  assigned_driver_count bigint,
  trip_count bigint,
  gross_revenue numeric,
  fuel_cost numeric,
  maintenance_cost numeric,
  operating_balance numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.sta_is_org_member(p_org_id,array['owner','manager','fleet_manager','finance','viewer']) then
    raise exception 'Organization access required' using errcode = '42501';
  end if;
  return query
  with vehicles as (
    select count(*)::bigint total,count(*) filter(where status='active')::bigint active
    from public.fleet_vehicles where organization_id=p_org_id
  ),
  drivers as (
    select count(distinct driver_id)::bigint total
    from public.fleet_vehicle_assignments where organization_id=p_org_id and status='active'
  ),
  revenue as (
    select count(*)::bigint trips,coalesce(sum(t.fare),0)::numeric amount
    from public.trips t join public.fleet_vehicles v on v.id=t.vehicle_id
    where v.organization_id=p_org_id
  ),
  fuel as (
    select coalesce(sum(total_cost),0)::numeric amount
    from public.fleet_fuel_logs where organization_id=p_org_id
  ),
  maintenance as (
    select coalesce(sum(cost),0)::numeric amount
    from public.fleet_maintenance_records where organization_id=p_org_id and status='completed'
  )
  select vehicles.total,vehicles.active,drivers.total,revenue.trips,revenue.amount,
         fuel.amount,maintenance.amount,revenue.amount-fuel.amount-maintenance.amount
  from vehicles,drivers,revenue,fuel,maintenance;
end;
$$;
revoke all on function public.sta_owner_dashboard(uuid) from public;
grant execute on function public.sta_owner_dashboard(uuid) to authenticated;

create or replace function public.sta_set_vehicle_maintenance_status(p_record_id uuid,p_status text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_org uuid;
begin
  select organization_id into v_org from public.fleet_maintenance_records where id=p_record_id;
  if v_org is null or not public.sta_is_org_member(v_org,array['owner','manager','fleet_manager']) then
    raise exception 'Fleet manager access required' using errcode = '42501';
  end if;
  if p_status not in ('scheduled','in_progress','completed','cancelled') then raise exception 'Invalid maintenance status'; end if;
  update public.fleet_maintenance_records
  set status=p_status,completed_at=case when p_status='completed' then now() else completed_at end
  where id=p_record_id;
  if p_status='in_progress' then
    update public.fleet_vehicles v set status='maintenance',updated_at=now()
    where v.id=(select vehicle_id from public.fleet_maintenance_records where id=p_record_id);
  elsif p_status in ('completed','cancelled') then
    update public.fleet_vehicles v
    set status=case when exists(
      select 1 from public.fleet_maintenance_records m
      where m.vehicle_id=v.id and (
        m.status='in_progress' or (m.status='scheduled' and (m.scheduled_at is null or m.scheduled_at <= now()))
      )
    ) then 'maintenance' else 'active' end,
    updated_at=now()
    where v.id=(select vehicle_id from public.fleet_maintenance_records where id=p_record_id);
  end if;
end;
$$;
revoke all on function public.sta_set_vehicle_maintenance_status(uuid,text) from public;
grant execute on function public.sta_set_vehicle_maintenance_status(uuid,text) to authenticated;

create or replace function public.sta_sync_ride_vehicle()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.driver_id is not null and new.driver_id is distinct from old.driver_id then
    new.vehicle_id := (select dp.vehicle_id from public.driver_profiles dp where dp.user_id=new.driver_id);
  end if;
  return new;
end;
$$;
drop trigger if exists sta_sync_ride_vehicle_trigger on public.ride_requests;
create trigger sta_sync_ride_vehicle_trigger
before update of driver_id on public.ride_requests
for each row execute function public.sta_sync_ride_vehicle();

create or replace function public.sta_sync_trip_vehicle()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.vehicle_id is null then
    select coalesce(r.vehicle_id,dp.vehicle_id) into new.vehicle_id
    from public.ride_requests r
    left join public.driver_profiles dp on dp.user_id=new.driver_id
    where r.id=new.ride_request_id;
  end if;
  return new;
end;
$$;
drop trigger if exists sta_sync_trip_vehicle_trigger on public.trips;
create trigger sta_sync_trip_vehicle_trigger
before insert on public.trips
for each row execute function public.sta_sync_trip_vehicle();

-- Platform administrators can audit fleet records without becoming organization members.
create policy org_members_admin_read on public.organization_members
  for select to authenticated using (public.sta_is_active_admin());
create policy transport_branches_admin_read on public.transport_branches
  for select to authenticated using (public.sta_is_active_admin());
create policy fleet_vehicles_admin_read on public.fleet_vehicles
  for select to authenticated using (public.sta_is_active_admin());
create policy fleet_assignments_admin_read on public.fleet_vehicle_assignments
  for select to authenticated using (public.sta_is_active_admin());
create policy fleet_fuel_admin_read on public.fleet_fuel_logs
  for select to authenticated using (public.sta_is_active_admin());
create policy fleet_maintenance_admin_read on public.fleet_maintenance_records
  for select to authenticated using (public.sta_is_active_admin());
create policy transport_contracts_admin_read on public.transport_contracts
  for select to authenticated using (public.sta_is_active_admin());

-- Fleet assignment controls which vehicle type a managed driver may operate.
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
  v_assigned_vehicle public.fleet_vehicles;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_status not in ('offline','idle','on_trip') then raise exception 'Invalid driver availability status'; end if;

  select * into v_driver from public.driver_profiles where user_id=auth.uid() for update;
  if not found then raise exception 'Driver profile not found' using errcode = 'P0002'; end if;
  if p_status <> 'offline' and v_driver.verification_status <> 'verified' then
    raise exception 'Driver verification is required' using errcode = '42501';
  end if;
  if p_status = 'offline' and exists(
    select 1 from public.ride_requests
    where driver_id=auth.uid() and status in ('accepted','driver_arrived','in_progress')
  ) then raise exception 'Complete or cancel the active ride before going offline'; end if;
  if p_status = 'on_trip' and not exists(
    select 1 from public.ride_requests
    where driver_id=auth.uid() and status in ('accepted','driver_arrived','in_progress')
  ) then raise exception 'No active ride found for this driver'; end if;
  if p_status = 'idle' and exists(
    select 1 from public.ride_requests
    where driver_id=auth.uid() and status in ('accepted','driver_arrived','in_progress')
  ) then raise exception 'Driver has an active ride and cannot become idle'; end if;

  if v_driver.vehicle_id is not null then
    select * into v_assigned_vehicle from public.fleet_vehicles
    where id=v_driver.vehicle_id and status='active';
    if p_status <> 'offline' and not found then
      raise exception 'Your assigned fleet vehicle is not active. Contact your fleet manager.';
    end if;
  end if;

  update public.driver_profiles
  set is_online=(p_status <> 'offline'),
      availability_status=p_status,
      vehicle_type=coalesce(v_assigned_vehicle.vehicle_type,p_vehicle_type,vehicle_type),
      vehicle_plate=coalesce(v_assigned_vehicle.registration_number,vehicle_plate),
      region=coalesce(p_region,region),
      city=coalesce(p_city,city),
      updated_at=now()
  where user_id=auth.uid();

  if p_status='offline' then
    delete from public.driver_locations where driver_id=auth.uid();
  end if;
end;
$$;
revoke all on function public.sta_set_driver_presence(text,text,text,text) from public;
grant execute on function public.sta_set_driver_presence(text,text,text,text) to authenticated;

-- Realtime streams for fleet dashboards.
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'transport_organizations','organization_members','transport_branches',
    'fleet_vehicles','fleet_vehicle_assignments','fleet_fuel_logs',
    'fleet_maintenance_records','transport_contracts'
  ] loop
    if exists (select 1 from pg_publication where pubname='supabase_realtime')
       and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=v_table) then
      execute format('alter publication supabase_realtime add table public.%I',v_table);
    end if;
  end loop;
end;
$$;
