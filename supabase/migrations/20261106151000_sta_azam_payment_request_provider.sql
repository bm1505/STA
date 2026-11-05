-- Switch newly created payment requests to the selected gateway.
-- This does not initiate checkout or confirm settlement; those require the
-- merchant-specific AzamPay contract and a verified server-side callback.
alter table public.payments
  add column if not exists initiated_at timestamptz,
  add column if not exists confirmed_at timestamptz,
  add column if not exists provider_status text,
  add column if not exists provider_checkout_url text;

create index if not exists payments_provider_status_created_idx
  on public.payments(provider, status, created_at desc);

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
    auth.uid(), p_ride_id, 'azampay', p_amount, 'TZS', 'pending',
    trim(p_phone_number),
    jsonb_build_object(
      'type', p_payment_type,
      'user_role', v_role,
      'initiation', 'awaiting_azampay_checkout',
      'settlement', 'unverified'
    )
  ) returning id into v_payment_id;

  update public.payments
  set provider_reference = 'STA-' || v_payment_id::text
  where id = v_payment_id;

  return v_payment_id;
end;
$$;

revoke all on function public.sta_create_payment_request(text,numeric,uuid,text) from public;
grant execute on function public.sta_create_payment_request(text,numeric,uuid,text) to authenticated;
