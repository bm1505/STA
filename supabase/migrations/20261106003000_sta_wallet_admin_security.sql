-- Secure wallet requests and grant narrowly-scoped administrative read access.
-- Existing balances and transaction history are preserved.

alter table public.withdrawal_requests
  add column if not exists payout_method text,
  add column if not exists payout_provider text;

create or replace function public.sta_is_active_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and is_active = true
  );
$$;
revoke all on function public.sta_is_active_admin() from public;
grant execute on function public.sta_is_active_admin() to authenticated;

drop policy if exists profiles_admin_select on public.profiles;
create policy profiles_admin_select on public.profiles
  for select to authenticated using (public.sta_is_active_admin());

drop policy if exists driver_profiles_admin_select on public.driver_profiles;
create policy driver_profiles_admin_select on public.driver_profiles
  for select to authenticated using (public.sta_is_active_admin());

drop policy if exists ride_requests_admin_select on public.ride_requests;
create policy ride_requests_admin_select on public.ride_requests
  for select to authenticated using (public.sta_is_active_admin());

drop policy if exists wallets_admin_select on public.wallets;
create policy wallets_admin_select on public.wallets
  for select to authenticated using (public.sta_is_active_admin());

drop policy if exists payments_admin_select on public.payments;
create policy payments_admin_select on public.payments
  for select to authenticated using (public.sta_is_active_admin());

drop policy if exists withdrawal_requests_admin_select on public.withdrawal_requests;
create policy withdrawal_requests_admin_select on public.withdrawal_requests
  for select to authenticated using (public.sta_is_active_admin());

create or replace function public.sta_create_payment_request(
  p_phone_number text,
  p_amount numeric,
  p_ride_id uuid default null,
  p_payment_type text default 'topup'
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payment_id uuid;
  v_role text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 100000000 then
    raise exception 'Invalid payment amount';
  end if;
  if p_phone_number is null or length(regexp_replace(p_phone_number, '[^0-9]', '', 'g')) < 9
     or length(regexp_replace(p_phone_number, '[^0-9]', '', 'g')) > 15 then
    raise exception 'Enter a valid mobile money phone number';
  end if;
  if p_payment_type not in ('topup', 'ride_payment') then
    raise exception 'Unsupported payment type';
  end if;
  if p_payment_type = 'topup' and p_ride_id is not null then
    raise exception 'Top-up cannot reference a ride';
  end if;
  if p_payment_type = 'ride_payment' and (
    p_ride_id is null or not exists (
      select 1 from public.ride_requests
      where id = p_ride_id and rider_id = auth.uid() and status = 'completed'
    )
  ) then
    raise exception 'Completed ride belonging to this account is required';
  end if;

  select role into v_role from public.profiles
  where id = auth.uid() and is_active = true;
  if not found then raise exception 'Active account required' using errcode = '42501'; end if;

  insert into public.payments(
    user_id, ride_request_id, provider, amount, currency, status,
    phone_number, provider_payload
  ) values (
    auth.uid(), p_ride_id, 'mpesa', p_amount, 'TZS', 'pending',
    trim(p_phone_number),
    jsonb_build_object('type', p_payment_type, 'user_role', v_role, 'initiation', 'awaiting_provider_configuration')
  ) returning id into v_payment_id;

  return v_payment_id;
end;
$$;
revoke all on function public.sta_create_payment_request(text,numeric,uuid,text) from public;
grant execute on function public.sta_create_payment_request(text,numeric,uuid,text) to authenticated;

create or replace function public.sta_request_withdrawal(
  p_amount numeric,
  p_phone_number text,
  p_payout_method text,
  p_payout_provider text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_balance numeric(14,2);
  v_reserved numeric(14,2);
  v_request_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_amount is null or p_amount < 1000 then
    raise exception 'Minimum withdrawal is TZS 1,000';
  end if;
  if p_phone_number is null or length(trim(p_phone_number)) < 5 then
    raise exception 'Payout destination is required';
  end if;
  if p_payout_method not in ('Mobile Money', 'Bank Transfer') then
    raise exception 'Invalid payout method';
  end if;
  if p_payout_provider not in (
    'M-Pesa', 'Tigo Pesa', 'Airtel Money', 'Halo Pesa',
    'CRDB Bank', 'NMB Bank', 'NBC Bank', 'Absa Bank', 'Stanbic Bank', 'Equity Bank'
  ) then
    raise exception 'Unsupported payout provider';
  end if;

  select balance into v_balance
  from public.wallets where user_id = auth.uid() for update;
  if not found then raise exception 'Wallet not found'; end if;

  select coalesce(sum(amount), 0) into v_reserved
  from public.withdrawal_requests
  where user_id = auth.uid() and status in ('pending', 'processing');
  if p_amount > v_balance - v_reserved then
    raise exception 'Insufficient available wallet balance';
  end if;

  insert into public.withdrawal_requests(
    user_id, amount, status, phone_number, payout_method, payout_provider
  ) values (
    auth.uid(), p_amount, 'pending', trim(p_phone_number), p_payout_method, p_payout_provider
  ) returning id into v_request_id;

  update public.profiles
  set user_data = coalesce(user_data, '{}'::jsonb) ||
      jsonb_build_object('payoutMethod', p_payout_provider, 'payoutNumber', trim(p_phone_number)),
      updated_at = now()
  where id = auth.uid();

  return v_request_id;
end;
$$;
revoke all on function public.sta_request_withdrawal(numeric,text,text,text) from public;
grant execute on function public.sta_request_withdrawal(numeric,text,text,text) to authenticated;

create or replace function public.sta_reject_payment(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payment public.payments;
begin
  if not public.sta_is_active_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  select * into v_payment from public.payments where id = p_payment_id for update;
  if not found or v_payment.status <> 'pending' then
    raise exception 'Payment request is not pending';
  end if;
  update public.payments set status = 'failed', updated_at = now()
  where id = p_payment_id;
end;
$$;
revoke all on function public.sta_reject_payment(uuid) from public;
grant execute on function public.sta_reject_payment(uuid) to authenticated;
