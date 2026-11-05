-- Provider delivery ledger for idempotent server-side email and SMS dispatch.
-- Additive only; no existing user/payment data is modified.
create table if not exists public.provider_delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('swalasms', 'resend')),
  idempotency_key text not null check (length(idempotency_key) between 1 and 200),
  recipient_hash text not null,
  status text not null default 'processing'
    check (status in ('processing', 'accepted', 'failed', 'unknown')),
  provider_message_id text,
  attempt_count integer not null default 1 check (attempt_count > 0),
  error_code text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, idempotency_key)
);

alter table public.provider_delivery_jobs enable row level security;
revoke all on public.provider_delivery_jobs from anon, authenticated;
grant all on public.provider_delivery_jobs to service_role;

create index if not exists provider_delivery_jobs_status_created_idx
  on public.provider_delivery_jobs(status, created_at);
