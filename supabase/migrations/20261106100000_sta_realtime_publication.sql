-- Ensure all Supabase Realtime streams used by STA are published.
do $$
declare
  v_table text;
  v_tables text[] := array[
    'profiles',
    'driver_profiles',
    'driver_locations',
    'ride_requests',
    'trips',
    'wallets',
    'wallet_transactions',
    'payments',
    'withdrawal_requests',
    'chat_messages',
    'sos_alerts',
    'ride_ratings',
    'notification_broadcasts',
    'app_settings',
    'user_notifications',
    'ride_safety_events'
  ];
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise exception 'Supabase Realtime publication is not available in this project';
  end if;
  foreach v_table in array v_tables loop
    if to_regclass(format('public.%I', v_table)) is not null
       and not exists (
         select 1 from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public'
           and tablename = v_table
       ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end;
$$;
