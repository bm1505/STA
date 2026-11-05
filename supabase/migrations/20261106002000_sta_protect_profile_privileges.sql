-- Prevent self-service profile updates from escalating privileges.
-- Additive and idempotent; ordinary profile details remain editable by their owner.

create or replace function public.sta_protect_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_is_admin boolean := false;
begin
  if auth.uid() is null or auth.uid() <> old.id then
    return new;
  end if;

  select exists (
    select 1
    from public.profiles actor
    where actor.id = auth.uid()
      and actor.role = 'admin'
      and actor.is_active = true
  ) into v_is_admin;

  if v_is_admin then
    return new;
  end if;

  if new.role is distinct from old.role
     or new.is_active is distinct from old.is_active
     or new.email_verified_at is distinct from old.email_verified_at
     or (new.user_data ->> 'role') is distinct from (old.user_data ->> 'role')
     or (new.user_data ->> 'isVerified') is distinct from (old.user_data ->> 'isVerified')
     or (new.user_data ->> 'verificationStatus') is distinct from (old.user_data ->> 'verificationStatus') then
    raise exception 'Account role, activation and verification are managed by STA administrators'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists sta_protect_profile_privileges_trigger on public.profiles;
create trigger sta_protect_profile_privileges_trigger
before update on public.profiles
for each row execute function public.sta_protect_profile_privileges();
