-- Remove o cadastro auxiliar do Supabase Auth. A identidade é o usuário e o host
-- confirmados pelo AVA; nenhum usuário fictício ou senha social é criado.
drop policy if exists "members can view conversations" on public.social_conversations;
drop policy if exists "members can see members of their conversations" on public.social_members;
drop policy if exists "creator adds themselves to a new conversation" on public.social_members;
drop policy if exists "members may leave conversations" on public.social_members;
drop policy if exists "members can read encrypted messages" on public.social_messages;
drop policy if exists "members can send encrypted messages as themselves" on public.social_messages;
drop policy if exists "senders may delete their own encrypted messages" on public.social_messages;
drop policy if exists "social profiles visible to signed-in users" on public.social_profiles;
drop policy if exists "users create their own social profile" on public.social_profiles;
drop policy if exists "users update their own social profile" on public.social_profiles;
drop policy if exists "conversation owner may update title and invite" on public.social_conversations;

drop function if exists social_private.is_member(uuid, uuid);
drop function if exists social_private.is_owner(uuid, uuid);
drop schema if exists social_private;

drop table if exists public.social_messages;
drop table if exists public.social_members;
drop table if exists public.social_conversations;
drop table if exists public.social_profiles;
drop table if exists public.social_moodle_accounts;

create table public.social_profiles (
  user_key text primary key,
  username text not null unique check (username ~ '^[a-z0-9_]{3,24}$'),
  display_name text not null check (char_length(display_name) between 1 and 48),
  created_at timestamptz not null default now()
);

create table public.social_conversations (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 64),
  created_by text not null references public.social_profiles(user_key) on delete cascade,
  invite_hash text not null,
  group_kind text not null default 'friends' check (group_kind in ('friends', 'course')),
  moodle_course_id bigint,
  moodle_course_name text,
  created_at timestamptz not null default now()
);

create table public.social_members (
  conversation_id uuid not null references public.social_conversations(id) on delete cascade,
  user_key text not null references public.social_profiles(user_key) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_key)
);

create table public.social_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.social_conversations(id) on delete cascade,
  sender_id text not null references public.social_profiles(user_key) on delete cascade,
  ciphertext text not null,
  nonce text not null,
  mac text not null,
  created_at timestamptz not null default now(),
  constraint social_message_ciphertext_size check (octet_length(ciphertext) <= 24000)
);

create index social_messages_conversation_created_idx on public.social_messages (conversation_id, created_at desc);
create index social_members_user_idx on public.social_members (user_key, conversation_id);
create index social_conversations_course_idx on public.social_conversations (moodle_course_id, created_at desc)
  where group_kind = 'course';

alter table public.social_profiles enable row level security;
alter table public.social_conversations enable row level security;
alter table public.social_members enable row level security;
alter table public.social_messages enable row level security;

revoke all on public.social_profiles, public.social_conversations, public.social_members, public.social_messages
  from public, anon, authenticated;
grant select, insert, update, delete on public.social_profiles, public.social_conversations, public.social_members, public.social_messages
  to service_role;
