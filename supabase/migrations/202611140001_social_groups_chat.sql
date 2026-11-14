-- Ava Sync Social v1
-- Mensagens armazenadas somente como ciphertext autenticado (AES-GCM).
-- A chave da conversa deve permanecer nos dispositivos participantes.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.social_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_]{3,24}$'),
  display_name text not null check (char_length(display_name) between 1 and 48),
  created_at timestamptz not null default now()
);

create table if not exists public.social_conversations (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 64),
  created_by uuid not null references auth.users(id) on delete cascade,
  invite_hash text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.social_members (
  conversation_id uuid not null references public.social_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table if not exists public.social_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.social_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  ciphertext text not null,
  nonce text not null,
  mac text not null,
  created_at timestamptz not null default now(),
  constraint social_message_ciphertext_size check (octet_length(ciphertext) <= 24000)
);

create index if not exists social_messages_conversation_created_idx
  on public.social_messages (conversation_id, created_at desc);
create index if not exists social_members_user_idx on public.social_members (user_id, conversation_id);

alter table public.social_profiles enable row level security;
alter table public.social_conversations enable row level security;
alter table public.social_members enable row level security;
alter table public.social_messages enable row level security;

-- Helpers SECURITY DEFINER evitam políticas recursivas ao consultar membership.
create or replace function public.social_is_member(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.social_members m
    where m.conversation_id = p_conversation_id
      and m.user_id = p_user_id
      and p_user_id = auth.uid()
  );
$$;

create or replace function public.social_is_owner(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.social_conversations c
    where c.id = p_conversation_id and c.created_by = p_user_id and p_user_id = auth.uid()
  );
$$;

revoke all on function public.social_is_member(uuid, uuid) from public, anon;
revoke all on function public.social_is_owner(uuid, uuid) from public, anon;
grant execute on function public.social_is_member(uuid, uuid) to authenticated;
grant execute on function public.social_is_owner(uuid, uuid) to authenticated;

drop policy if exists "social profiles visible to signed-in users" on public.social_profiles;
create policy "social profiles visible to signed-in users"
  on public.social_profiles for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (
      select 1
      from public.social_members mine
      join public.social_members other on other.conversation_id = mine.conversation_id
      where mine.user_id = (select auth.uid()) and other.user_id = social_profiles.user_id
    )
  );
drop policy if exists "users create their own social profile" on public.social_profiles;
create policy "users create their own social profile"
  on public.social_profiles for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "users update their own social profile" on public.social_profiles;
create policy "users update their own social profile"
  on public.social_profiles for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "members can view conversations" on public.social_conversations;
create policy "members can view conversations"
  on public.social_conversations for select to authenticated
  using (public.social_is_member(id, (select auth.uid())));
drop policy if exists "authenticated users create conversations" on public.social_conversations;
drop policy if exists "conversation owner may update title and invite" on public.social_conversations;
create policy "conversation owner may update title and invite"
  on public.social_conversations for update to authenticated
  using (created_by = (select auth.uid())) with check (created_by = (select auth.uid()));

drop policy if exists "members can see members of their conversations" on public.social_members;
create policy "members can see members of their conversations"
  on public.social_members for select to authenticated
  using (public.social_is_member(conversation_id, (select auth.uid())));
drop policy if exists "creator adds themselves to a new conversation" on public.social_members;
create policy "creator adds themselves to a new conversation"
  on public.social_members for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and public.social_is_owner(conversation_id, (select auth.uid()))
  );
drop policy if exists "members may leave conversations" on public.social_members;
create policy "members may leave conversations"
  on public.social_members for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists "members can read encrypted messages" on public.social_messages;
create policy "members can read encrypted messages"
  on public.social_messages for select to authenticated
  using (public.social_is_member(conversation_id, (select auth.uid())));
drop policy if exists "members can send encrypted messages as themselves" on public.social_messages;
create policy "members can send encrypted messages as themselves"
  on public.social_messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and public.social_is_member(conversation_id, (select auth.uid()))
  );
drop policy if exists "senders may delete their own encrypted messages" on public.social_messages;
create policy "senders may delete their own encrypted messages"
  on public.social_messages for delete to authenticated using (sender_id = (select auth.uid()));

create or replace function public.social_create_conversation(p_title text, p_invite_secret text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_conversation_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if length(p_invite_secret) < 32 or length(p_invite_secret) > 128 then
    raise exception 'invalid invitation secret' using errcode = '22023';
  end if;
  insert into public.social_conversations (title, created_by, invite_hash)
    values (p_title, v_user_id, encode(extensions.digest(p_invite_secret, 'sha256'), 'hex'))
    returning id into v_conversation_id;
  insert into public.social_members (conversation_id, user_id)
    values (v_conversation_id, v_user_id);
  return v_conversation_id;
end;
$$;

create or replace function public.social_join_conversation(p_conversation_id uuid, p_invite_secret text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_expected_hash text;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if length(p_invite_secret) < 32 or length(p_invite_secret) > 128 then
    raise exception 'invalid invitation' using errcode = '22023';
  end if;
  select c.invite_hash into v_expected_hash
    from public.social_conversations c where c.id = p_conversation_id;
  if v_expected_hash is null or v_expected_hash <> encode(extensions.digest(p_invite_secret, 'sha256'), 'hex') then
    raise exception 'invalid invitation' using errcode = '42501';
  end if;
  insert into public.social_members (conversation_id, user_id)
    values (p_conversation_id, v_user_id) on conflict do nothing;
end;
$$;

revoke all on function public.social_create_conversation(text, text) from public, anon;
grant execute on function public.social_create_conversation(text, text) to authenticated;
revoke all on function public.social_join_conversation(uuid, text) from public, anon;
grant execute on function public.social_join_conversation(uuid, text) to authenticated;

grant select, insert, update on public.social_profiles to authenticated;
grant select, update on public.social_conversations to authenticated;
grant select, insert, delete on public.social_members to authenticated;
grant select, insert, delete on public.social_messages to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'social_messages'
  ) then
    alter publication supabase_realtime add table public.social_messages;
  end if;
end;
$$;
