-- Social v2: perfis, presença, amizades, canais, papéis, convites, reações,
-- respostas, edição, fixados, digitando, leitura, chaves por envelope e anexos.
-- Migração aditiva: conversas e mensagens existentes continuam válidas.

-- Perfis --------------------------------------------------------------------
alter table public.social_profiles drop constraint if exists social_profiles_username_check;
alter table public.social_profiles
  add constraint social_profiles_username_check check (username ~ '^[a-z0-9_.]{3,24}$'),
  add column if not exists bio text check (char_length(bio) <= 190),
  add column if not exists avatar_path text check (char_length(avatar_path) <= 200),
  add column if not exists banner_color integer,
  add column if not exists status text not null default 'online' check (status in ('online', 'busy', 'away', 'invisible')),
  add column if not exists custom_status text check (char_length(custom_status) <= 64),
  add column if not exists custom_emoji text check (char_length(custom_emoji) <= 16),
  add column if not exists public_key text check (char_length(public_key) <= 64),
  add column if not exists last_seen timestamptz,
  add column if not exists name_locked boolean not null default false,
  add column if not exists updated_at timestamptz not null default now();

-- Conversas (grupos, matérias e mensagens diretas) ----------------------------
alter table public.social_conversations drop constraint if exists social_conversations_group_kind_check;
alter table public.social_conversations
  add constraint social_conversations_group_kind_check check (group_kind in ('friends', 'course', 'dm')),
  alter column invite_hash drop not null,
  add column if not exists description text check (char_length(description) <= 300),
  add column if not exists icon_path text check (char_length(icon_path) <= 200),
  add column if not exists dm_key text unique,
  add column if not exists updated_at timestamptz not null default now();

-- Canais -------------------------------------------------------------------
create table if not exists public.social_channels (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.social_conversations(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 32),
  topic text check (char_length(topic) <= 200),
  position integer not null default 0,
  only_admins boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists social_channels_conversation_idx on public.social_channels (conversation_id, position);

insert into public.social_channels (conversation_id, name, position)
select c.id, 'geral', 0 from public.social_conversations c
where not exists (select 1 from public.social_channels ch where ch.conversation_id = c.id);

-- Membros ------------------------------------------------------------------
alter table public.social_members
  add column if not exists role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  add column if not exists nickname text check (char_length(nickname) <= 32),
  add column if not exists muted boolean not null default false;

update public.social_members m set role = 'owner'
from public.social_conversations c
where c.id = m.conversation_id and c.created_by = m.user_key and m.role = 'member';

create table if not exists public.social_bans (
  conversation_id uuid not null references public.social_conversations(id) on delete cascade,
  user_key text not null references public.social_profiles(user_key) on delete cascade,
  banned_by text references public.social_profiles(user_key) on delete set null,
  created_at timestamptz not null default now(),
  primary key (conversation_id, user_key)
);

create table if not exists public.social_invites (
  invite_hash text primary key,
  conversation_id uuid not null references public.social_conversations(id) on delete cascade,
  created_by text not null references public.social_profiles(user_key) on delete cascade,
  expires_at timestamptz,
  max_uses integer check (max_uses is null or max_uses > 0),
  uses integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists social_invites_conversation_idx on public.social_invites (conversation_id);

-- Mensagens ----------------------------------------------------------------
create sequence if not exists public.social_change_seq;

alter table public.social_messages
  add column if not exists channel_id uuid references public.social_channels(id) on delete cascade,
  add column if not exists format smallint not null default 1,
  add column if not exists reply_to uuid references public.social_messages(id) on delete set null,
  add column if not exists mentions text[] not null default '{}',
  add column if not exists edited_at timestamptz,
  add column if not exists deleted_at timestamptz,
  add column if not exists pinned_at timestamptz,
  add column if not exists pinned_by text,
  add column if not exists rev bigint not null default nextval('public.social_change_seq');

update public.social_messages m set channel_id = (
  select ch.id from public.social_channels ch where ch.conversation_id = m.conversation_id order by ch.position, ch.created_at limit 1
) where m.channel_id is null;
alter table public.social_messages alter column channel_id set not null;

create index if not exists social_messages_channel_created_idx on public.social_messages (channel_id, created_at desc);
create index if not exists social_messages_channel_rev_idx on public.social_messages (channel_id, rev);

create or replace function public.social_bump_rev() returns trigger language plpgsql as $$
begin
  new.rev := nextval('public.social_change_seq');
  return new;
end $$;
drop trigger if exists social_messages_bump_rev on public.social_messages;
create trigger social_messages_bump_rev before update on public.social_messages
  for each row execute function public.social_bump_rev();

create table if not exists public.social_reactions (
  message_id uuid not null references public.social_messages(id) on delete cascade,
  user_key text not null references public.social_profiles(user_key) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_key, emoji)
);

create or replace function public.social_reaction_touch() returns trigger language plpgsql as $$
begin
  update public.social_messages set rev = rev where id = coalesce(new.message_id, old.message_id);
  return null;
end $$;
drop trigger if exists social_reactions_touch on public.social_reactions;
create trigger social_reactions_touch after insert or delete on public.social_reactions
  for each row execute function public.social_reaction_touch();

-- Leitura e digitando ------------------------------------------------------
create table if not exists public.social_reads (
  channel_id uuid not null references public.social_channels(id) on delete cascade,
  user_key text not null references public.social_profiles(user_key) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (channel_id, user_key)
);

create table if not exists public.social_typing (
  channel_id uuid not null references public.social_channels(id) on delete cascade,
  user_key text not null references public.social_profiles(user_key) on delete cascade,
  expires_at timestamptz not null,
  primary key (channel_id, user_key)
);

-- Amizades e bloqueios -----------------------------------------------------
create table if not exists public.social_friendships (
  user_a text not null references public.social_profiles(user_key) on delete cascade,
  user_b text not null references public.social_profiles(user_key) on delete cascade,
  requested_by text not null references public.social_profiles(user_key) on delete cascade,
  status text not null check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index if not exists social_friendships_b_idx on public.social_friendships (user_b);

create table if not exists public.social_blocks (
  blocker text not null references public.social_profiles(user_key) on delete cascade,
  blocked text not null references public.social_profiles(user_key) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked)
);

-- Chave da conversa embrulhada para cada aparelho (X25519 + AES-GCM) --------
create table if not exists public.social_key_envelopes (
  conversation_id uuid not null references public.social_conversations(id) on delete cascade,
  user_key text not null references public.social_profiles(user_key) on delete cascade,
  recipient_public text not null,
  sender_public text not null,
  sealed text not null check (char_length(sealed) <= 200),
  nonce text not null,
  mac text not null,
  created_at timestamptz not null default now(),
  primary key (conversation_id, user_key, recipient_public)
);

-- Resumo das conversas de uma pessoa (uma chamada só) ------------------------
create or replace function public.social_overview(p_user text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_at desc), '[]'::jsonb) from (
    select c.id, c.title, c.description, c.icon_path, c.group_kind, c.moodle_course_id, c.moodle_course_name, c.created_at,
      m.role, m.muted, m.nickname,
      (select count(*) from public.social_members mm where mm.conversation_id = c.id) as member_count,
      (select coalesce(jsonb_agg(jsonb_build_object(
          'id', ch.id, 'name', ch.name, 'topic', ch.topic, 'position', ch.position, 'only_admins', ch.only_admins,
          'unread', (select count(*) from public.social_messages sm where sm.channel_id = ch.id and sm.deleted_at is null
                      and sm.sender_id <> p_user and sm.created_at > coalesce(r.last_read_at, m.joined_at)),
          'mentions', (select count(*) from public.social_messages sm where sm.channel_id = ch.id and sm.deleted_at is null
                      and sm.sender_id <> p_user and sm.created_at > coalesce(r.last_read_at, m.joined_at)
                      and (p_user = any(sm.mentions) or 'everyone' = any(sm.mentions))),
          'last_at', (select max(sm.created_at) from public.social_messages sm where sm.channel_id = ch.id)
        ) order by ch.position, ch.created_at), '[]'::jsonb)
        from public.social_channels ch
        left join public.social_reads r on r.channel_id = ch.id and r.user_key = p_user
        where ch.conversation_id = c.id) as channels,
      (select to_jsonb(lm) from (
          select sm.id, sm.channel_id, sm.sender_id, sm.ciphertext, sm.nonce, sm.mac, sm.format, sm.created_at, sm.deleted_at,
                 p.display_name as sender_name
          from public.social_messages sm join public.social_profiles p on p.user_key = sm.sender_id
          where sm.conversation_id = c.id order by sm.created_at desc limit 1) lm) as last_message,
      case when c.group_kind = 'dm' then (select to_jsonb(pp) from (
          select p.user_key, p.username, p.display_name, p.avatar_path, p.status, p.custom_status, p.custom_emoji,
                 p.last_seen, p.banner_color
          from public.social_members o join public.social_profiles p on p.user_key = o.user_key
          where o.conversation_id = c.id and o.user_key <> p_user limit 1) pp) end as peer,
      greatest(c.created_at, (select max(sm.created_at) from public.social_messages sm where sm.conversation_id = c.id)) as sort_at
    from public.social_members m
    join public.social_conversations c on c.id = m.conversation_id
    where m.user_key = p_user
  ) x;
$$;

-- Membros que ainda não têm a chave da conversa para o aparelho atual
create or replace function public.social_key_requests(p_user text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('conversation_id', o.conversation_id, 'user_key', o.user_key, 'public_key', p.public_key)), '[]'::jsonb)
  from public.social_members mine
  join public.social_members o on o.conversation_id = mine.conversation_id and o.user_key <> p_user
  join public.social_profiles p on p.user_key = o.user_key and p.public_key is not null
  where mine.user_key = p_user
    and not exists (select 1 from public.social_key_envelopes e
                    where e.conversation_id = o.conversation_id and e.user_key = o.user_key and e.recipient_public = p.public_key);
$$;

-- Permissões: só a Edge Function (service_role) acessa -------------------------
alter table public.social_channels enable row level security;
alter table public.social_bans enable row level security;
alter table public.social_invites enable row level security;
alter table public.social_reactions enable row level security;
alter table public.social_reads enable row level security;
alter table public.social_typing enable row level security;
alter table public.social_friendships enable row level security;
alter table public.social_blocks enable row level security;
alter table public.social_key_envelopes enable row level security;

revoke all on public.social_channels, public.social_bans, public.social_invites, public.social_reactions,
  public.social_reads, public.social_typing, public.social_friendships, public.social_blocks, public.social_key_envelopes
  from public, anon, authenticated;
grant select, insert, update, delete on public.social_channels, public.social_bans, public.social_invites, public.social_reactions,
  public.social_reads, public.social_typing, public.social_friendships, public.social_blocks, public.social_key_envelopes
  to service_role;
revoke all on sequence public.social_change_seq from public, anon, authenticated;
grant usage, select on sequence public.social_change_seq to service_role;

revoke all on function public.social_overview(text) from public, anon, authenticated;
revoke all on function public.social_key_requests(text) from public, anon, authenticated;
revoke all on function public.social_bump_rev() from public, anon, authenticated;
revoke all on function public.social_reaction_touch() from public, anon, authenticated;
grant execute on function public.social_overview(text), public.social_key_requests(text) to service_role;

-- Arquivos: bucket privado; acesso só por URL assinada emitida pela função ----
insert into storage.buckets (id, name, public, file_size_limit)
values ('social', 'social', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = 10485760;

-- Mensagem sem canal (app 0.7.0) cai no primeiro canal da conversa
create or replace function public.social_message_defaults() returns trigger language plpgsql as $$
begin
  if new.channel_id is null then
    select ch.id into new.channel_id from public.social_channels ch
    where ch.conversation_id = new.conversation_id order by ch.position, ch.created_at limit 1;
  end if;
  return new;
end $$;
drop trigger if exists social_messages_defaults on public.social_messages;
create trigger social_messages_defaults before insert on public.social_messages
  for each row execute function public.social_message_defaults();
revoke all on function public.social_message_defaults() from public, anon, authenticated;

-- Gatilhos com search_path fixo (alerta do Supabase). RLS sem políticas é proposital:
-- ninguém além da Edge Function (service_role) lê ou escreve nas tabelas.
alter function public.social_bump_rev() set search_path = public;
alter function public.social_reaction_touch() set search_path = public;
alter function public.social_message_defaults() set search_path = public;
