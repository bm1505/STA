-- Remove obsolete Firebase Cloud Messaging tokens from profile JSON.
-- STA no longer uses Firebase Cloud Messaging; Supabase-backed notifications are separate.
update public.profiles
set user_data = user_data - 'fcmToken'
where user_data ? 'fcmToken';
