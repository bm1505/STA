-- Resolve a real support account for authenticated in-app conversations.
create or replace function public.sta_get_support_contact()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id
  from public.profiles
  where is_active = true and role in ('support', 'admin')
  order by case when role = 'support' then 0 else 1 end, created_at asc
  limit 1;
$$;
revoke all on function public.sta_get_support_contact() from public;
grant execute on function public.sta_get_support_contact() to authenticated;
