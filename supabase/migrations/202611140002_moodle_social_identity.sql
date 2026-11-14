-- Social usa a identidade já autenticada no AVA. A associação Moodle -> UUID interno
-- fica acessível somente à Edge Function com service role; tokens Moodle nunca são gravados.
create table if not exists public.social_moodle_accounts (
  moodle_host text not null,
  moodle_user_id bigint not null,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (moodle_host, moodle_user_id)
);

alter table public.social_moodle_accounts enable row level security;
revoke all on public.social_moodle_accounts from public, anon, authenticated;
grant all on public.social_moodle_accounts to service_role;

alter table public.social_conversations
  add column if not exists group_kind text not null default 'friends'
    check (group_kind in ('friends', 'course')),
  add column if not exists moodle_course_id bigint,
  add column if not exists moodle_course_name text;

create index if not exists social_conversations_course_idx
  on public.social_conversations (moodle_course_id, created_at desc)
  where group_kind = 'course';

-- As operações de escrita agora passam pela Edge Function, que valida o token AVA.
-- Remova os RPCs públicos SECURITY DEFINER antigos para evitar um segundo caminho de auth.
drop policy if exists "members can view conversations" on public.social_conversations;
drop policy if exists "members can see members of their conversations" on public.social_members;
drop policy if exists "creator adds themselves to a new conversation" on public.social_members;
drop policy if exists "members may leave conversations" on public.social_members;
drop policy if exists "members can read encrypted messages" on public.social_messages;
drop policy if exists "members can send encrypted messages as themselves" on public.social_messages;
drop policy if exists "senders may delete their own messages" on public.social_messages;
drop policy if exists "senders may delete their own encrypted messages" on public.social_messages;

drop function if exists public.social_create_conversation(text, text);
drop function if exists public.social_join_conversation(uuid, text);
drop function if exists public.social_is_member(uuid, uuid);
drop function if exists public.social_is_owner(uuid, uuid);

create schema if not exists social_private;
revoke all on schema social_private from public, anon;
grant usage on schema social_private to authenticated;

create or replace function social_private.is_member(p_conversation_id uuid, p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.social_members m
    where m.conversation_id = p_conversation_id
      and m.user_id = p_user_id
      and p_user_id = auth.uid()
  );
$$;

create or replace function social_private.is_owner(p_conversation_id uuid, p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.social_conversations c
    where c.id = p_conversation_id and c.created_by = p_user_id and p_user_id = auth.uid()
  );
$$;

revoke all on function social_private.is_member(uuid, uuid) from public, anon;
revoke all on function social_private.is_owner(uuid, uuid) from public, anon;
grant execute on function social_private.is_member(uuid, uuid) to authenticated;
grant execute on function social_private.is_owner(uuid, uuid) to authenticated;

create policy "members can view conversations"
  on public.social_conversations for select to authenticated
  using (social_private.is_member(id, (select auth.uid())));
create policy "members can see members of their conversations"
  on public.social_members for select to authenticated
  using (social_private.is_member(conversation_id, (select auth.uid())));
create policy "creator adds themselves to a new conversation"
  on public.social_members for insert to authenticated
  with check (user_id = (select auth.uid()) and social_private.is_owner(conversation_id, (select auth.uid())));
create policy "members may leave conversations"
  on public.social_members for delete to authenticated using (user_id = (select auth.uid()));
create policy "members can read encrypted messages"
  on public.social_messages for select to authenticated
  using (social_private.is_member(conversation_id, (select auth.uid())));
create policy "members can send encrypted messages as themselves"
  on public.social_messages for insert to authenticated
  with check (sender_id = (select auth.uid()) and social_private.is_member(conversation_id, (select auth.uid())));
create policy "senders may delete their own encrypted messages"
  on public.social_messages for delete to authenticated using (sender_id = (select auth.uid()));
