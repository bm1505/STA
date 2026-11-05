-- Persistent in-app notifications for ride events and administrator broadcasts.
create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  notification_type text not null,
  title text not null,
  body text not null,
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists user_notifications_user_created_idx
  on public.user_notifications(user_id, created_at desc);
alter table public.user_notifications enable row level security;

drop policy if exists user_notifications_select_owner on public.user_notifications;
create policy user_notifications_select_owner on public.user_notifications
  for select to authenticated using (user_id = auth.uid());
create or replace function public.sta_mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  update public.user_notifications set read_at = coalesce(read_at, now())
  where id = p_notification_id and user_id = auth.uid();
  if not found then raise exception 'Notification not found'; end if;
end;
$$;
revoke all on function public.sta_mark_notification_read(uuid) from public;
grant execute on function public.sta_mark_notification_read(uuid) to authenticated;

create or replace function public.sta_mark_all_notifications_read()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  update public.user_notifications set read_at = now()
  where user_id = auth.uid() and read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.sta_mark_all_notifications_read() from public;
grant execute on function public.sta_mark_all_notifications_read() to authenticated;

create or replace function public.sta_notify_ride_event()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_title text;
  v_body text;
begin
  if new.status is distinct from old.status then
    case new.status
      when 'accepted' then
        v_title := 'Driver accepted your ride';
        v_body := 'Your driver is on the way to the pickup point.';
      when 'driver_arrived' then
        v_title := 'Driver has arrived';
        v_body := 'Your driver has reached the pickup point.';
      when 'in_progress' then
        v_title := 'Ride started';
        v_body := 'Your trip is now in progress.';
      when 'completed' then
        v_title := 'Ride completed';
        v_body := 'Your trip is complete. Please confirm payment and rate your ride.';
      when 'cancelled' then
        v_title := 'Ride cancelled';
        v_body := 'This ride has been cancelled.';
      else
        v_title := null;
    end case;
    if v_title is not null then
      insert into public.user_notifications(user_id,notification_type,title,body,payload)
      values (new.rider_id,'ride_status',v_title,v_body,jsonb_build_object('ride_id',new.id,'status',new.status));
      if new.driver_id is not null then
        insert into public.user_notifications(user_id,notification_type,title,body,payload)
        values (
          new.driver_id,'ride_status',
          case new.status
            when 'accepted' then 'Ride assigned to you'
            when 'driver_arrived' then 'Pickup arrival recorded'
            when 'in_progress' then 'Trip started'
            when 'completed' then 'Trip completed'
            when 'cancelled' then 'Ride cancelled'
            else 'Ride updated'
          end,
          case new.status
            when 'accepted' then 'You have accepted a new ride.'
            when 'driver_arrived' then 'You marked arrival at the pickup point.'
            when 'in_progress' then 'Your trip is in progress.'
            when 'completed' then 'Trip completed. Confirm cash payment if applicable.'
            when 'cancelled' then 'The assigned ride was cancelled.'
            else 'Your ride status changed.'
          end,
          jsonb_build_object('ride_id',new.id,'status',new.status)
        );
      end if;
    end if;
  end if;

  if new.payment_status is distinct from old.payment_status and new.payment_status = 'paid' then
    insert into public.user_notifications(user_id,notification_type,title,body,payload)
    values (new.rider_id,'payment','Payment confirmed','Your ride payment has been confirmed.',
      jsonb_build_object('ride_id',new.id,'amount',new.final_fare));
    if new.driver_id is not null then
      insert into public.user_notifications(user_id,notification_type,title,body,payload)
      values (new.driver_id,'payment','Payment confirmed','The ride payment was verified and your wallet has been updated.',
        jsonb_build_object('ride_id',new.id,'amount',new.final_fare));
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists sta_ride_notification_trigger on public.ride_requests;
create trigger sta_ride_notification_trigger
after update of status, payment_status on public.ride_requests
for each row execute function public.sta_notify_ride_event();

create or replace function public.sta_deliver_notification_broadcast()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.user_notifications(user_id,notification_type,title,body,payload)
  select p.id,'broadcast',new.title,new.body,jsonb_build_object('broadcast_id',new.id)
  from public.profiles p
  where p.is_active = true
    and (
      new.target_group = 'System Wide'
      or (new.target_group = 'All Riders' and p.role = 'rider')
      or (new.target_group = 'All Drivers' and p.role = 'driver')
      or (new.target_group = 'All Staff' and p.role in ('staff','it','support','admin'))
    );
  update public.notification_broadcasts set status = 'sent' where id = new.id;
  return new;
end;
$$;

drop trigger if exists sta_notification_broadcast_trigger on public.notification_broadcasts;
create trigger sta_notification_broadcast_trigger
after insert on public.notification_broadcasts
for each row execute function public.sta_deliver_notification_broadcast();
