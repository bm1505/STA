-- Make driver identity documents private and authorize only their owner or an active STA admin.
-- Existing known public Storage URLs are converted to object references before the bucket is made private.
-- No Storage objects or profile records are deleted.

create or replace function public.sta_can_access_driver_document(p_owner_id text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and (
      p_owner_id = auth.uid()::text
      or exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.role = 'admin'
          and p.is_active = true
      )
    );
$$;

revoke all on function public.sta_can_access_driver_document(text) from public;
grant execute on function public.sta_can_access_driver_document(text) to authenticated;

-- Convert only URLs that unambiguously point to this Supabase bucket.
update public.profiles
set user_data =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        user_data,
        '{licenseUrl}',
        case
          when user_data->>'licenseUrl' ~ '/storage/v1/object/(public|sign)/driver-documents/'
          then to_jsonb('pg://' || regexp_replace(user_data->>'licenseUrl',
            '^.*storage/v1/object/(public|sign)/driver-documents/', ''))
          else coalesce(user_data->'licenseUrl', 'null'::jsonb)
        end,
        false
      ),
      '{insuranceUrl}',
      case
        when user_data->>'insuranceUrl' ~ '/storage/v1/object/(public|sign)/driver-documents/'
        then to_jsonb('pg://' || regexp_replace(user_data->>'insuranceUrl',
          '^.*storage/v1/object/(public|sign)/driver-documents/', ''))
        else coalesce(user_data->'insuranceUrl', 'null'::jsonb)
      end,
      false
    ),
    '{nationalIdUrl}',
    case
      when user_data->>'nationalIdUrl' ~ '/storage/v1/object/(public|sign)/driver-documents/'
      then to_jsonb('pg://' || regexp_replace(user_data->>'nationalIdUrl',
        '^.*storage/v1/object/(public|sign)/driver-documents/', ''))
      else coalesce(user_data->'nationalIdUrl', 'null'::jsonb)
    end,
    false
  )
where
  user_data->>'licenseUrl' ~ '/storage/v1/object/(public|sign)/driver-documents/'
  or user_data->>'insuranceUrl' ~ '/storage/v1/object/(public|sign)/driver-documents/'
  or user_data->>'nationalIdUrl' ~ '/storage/v1/object/(public|sign)/driver-documents/';

-- Ensure the existing bucket is private. Existing objects are retained.
insert into storage.buckets (id, name, public)
values ('driver-documents', 'driver-documents', false)
on conflict (id) do update set public = false;

drop policy if exists sta_driver_documents_select on storage.objects;
create policy sta_driver_documents_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'driver-documents'
  and public.sta_can_access_driver_document((storage.foldername(name))[1])
);

drop policy if exists sta_driver_documents_insert on storage.objects;
create policy sta_driver_documents_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'driver-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists sta_driver_documents_update on storage.objects;
create policy sta_driver_documents_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'driver-documents'
  and public.sta_can_access_driver_document((storage.foldername(name))[1])
)
with check (
  bucket_id = 'driver-documents'
  and public.sta_can_access_driver_document((storage.foldername(name))[1])
);

drop policy if exists sta_driver_documents_delete on storage.objects;
create policy sta_driver_documents_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'driver-documents'
  and public.sta_can_access_driver_document((storage.foldername(name))[1])
);
