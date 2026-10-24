-- User FCM tokens for push notifications (multi-device support)

create table if not exists public.user_fcm_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null,
  platform text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

create index if not exists user_fcm_tokens_user_id_idx on public.user_fcm_tokens(user_id);

-- Row Level Security
alter table public.user_fcm_tokens enable row level security;

drop policy if exists "user_fcm_tokens own rows" on public.user_fcm_tokens;
create policy "user_fcm_tokens own rows"
  on public.user_fcm_tokens
  for all
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
