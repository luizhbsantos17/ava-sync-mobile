-- Social v3: cargos personalizados, categorias de canais, personalização com imagem,
-- eventos para notificação e correção da cor do perfil. Compatível com os apps 0.7/0.8.

-- #5: a cor do Flutter (0xAARRGGBB) passa de 2^31 e estourava o integer -------------
alter table public.social_profiles alter column banner_color type bigint;

-- #4: fundo com imagem no perfil e no grupo, e cor do grupo ---------------------------
alter table public.social_profiles add column if not exists banner_path text;
alter table public.social_conversations add column if not exists banner_path text;
alter table public.social_conversations add column if not exists accent_color bigint;

-- #2: categorias de canais ("Canais gerais", "Estudo"...) ------------------------------
create table if not exists public.social_categories (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.social_conversations(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 32),
  position integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists social_categories_conv on public.social_categories(conversation_id);
alter table public.social_channels
  add column if not exists category_id uuid references public.social_categories(id) on delete set null;

-- #2: cargos personalizados com cor, hierarquia e permissões ---------------------------
-- position maior = cargo mais alto. Dono e admin (social_members.role) continuam acima
-- de todos os cargos personalizados.
create table if not exists public.social_roles (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.social_conversations(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 32),
  color bigint,
  position integer not null default 1,
  permissions text[] not null default '{}',
  mentionable boolean not null default true,
  hoist boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists social_roles_conv on public.social_roles(conversation_id);

create table if not exists public.social_member_roles (
  role_id uuid not null references public.social_roles(id) on delete cascade,
  conversation_id uuid not null references public.social_conversations(id) on delete cascade,
  user_key text not null references public.social_profiles(user_key) on delete cascade,
  primary key (role_id, user_key)
);
create index if not exists social_member_roles_user on public.social_member_roles(conversation_id, user_key);

-- #1: eventos que viram notificação (pedido de amizade, removido do grupo, cargo...) ----
create table if not exists public.social_events (
  id uuid primary key default gen_random_uuid(),
  user_key text not null references public.social_profiles(user_key) on delete cascade,
  kind text not null,
  data jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists social_events_user on public.social_events(user_key, created_at desc);

-- Visão geral: categorias, cargos e menções a cargos ----------------------------------
create or replace function public.social_overview(p_user text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_at desc), '[]'::jsonb) from (
    select c.id, c.title, c.description, c.icon_path, c.banner_path, c.accent_color, c.group_kind,
      c.moodle_course_id, c.moodle_course_name, c.created_at,
      m.role, m.muted, m.nickname,
      (select count(*) from public.social_members mm where mm.conversation_id = c.id) as member_count,
      (select coalesce(jsonb_agg(mr.role_id), '[]'::jsonb) from public.social_member_roles mr
        where mr.conversation_id = c.id and mr.user_key = p_user) as my_roles,
      (select coalesce(jsonb_agg(distinct perm), '[]'::jsonb)
        from public.social_member_roles mr join public.social_roles ro on ro.id = mr.role_id,
             unnest(ro.permissions) as perm
        where mr.conversation_id = c.id and mr.user_key = p_user) as my_perms,
      (select coalesce(jsonb_agg(jsonb_build_object('id', cat.id, 'name', cat.name, 'position', cat.position)
          order by cat.position, cat.created_at), '[]'::jsonb)
        from public.social_categories cat where cat.conversation_id = c.id) as categories,
      (select coalesce(jsonb_agg(jsonb_build_object(
          'id', ch.id, 'name', ch.name, 'topic', ch.topic, 'position', ch.position, 'only_admins', ch.only_admins,
          'category_id', ch.category_id,
          'unread', (select count(*) from public.social_messages sm where sm.channel_id = ch.id and sm.deleted_at is null
                      and sm.sender_id <> p_user and sm.created_at > coalesce(r.last_read_at, m.joined_at)),
          'mentions', (select count(*) from public.social_messages sm where sm.channel_id = ch.id and sm.deleted_at is null
                      and sm.sender_id <> p_user and sm.created_at > coalesce(r.last_read_at, m.joined_at)
                      and (p_user = any(sm.mentions) or 'everyone' = any(sm.mentions)
                           or exists (select 1 from public.social_member_roles mr
                                      where mr.conversation_id = c.id and mr.user_key = p_user
                                        and ('role:' || mr.role_id::text) = any(sm.mentions)))),
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
          select p.user_key, p.username, p.display_name, p.avatar_path, p.banner_path, p.status, p.custom_status,
                 p.custom_emoji, p.last_seen, p.banner_color
          from public.social_members o join public.social_profiles p on p.user_key = o.user_key
          where o.conversation_id = c.id and o.user_key <> p_user limit 1) pp) end as peer,
      greatest(c.created_at, (select max(sm.created_at) from public.social_messages sm where sm.conversation_id = c.id)) as sort_at
    from public.social_members m
    join public.social_conversations c on c.id = m.conversation_id
    where m.user_key = p_user
  ) x;
$$;

-- Permissões: só a Edge Function (service_role) acessa. RLS sem políticas é proposital.
alter table public.social_categories enable row level security;
alter table public.social_roles enable row level security;
alter table public.social_member_roles enable row level security;
alter table public.social_events enable row level security;
revoke all on public.social_categories, public.social_roles, public.social_member_roles, public.social_events
  from public, anon, authenticated;
grant select, insert, update, delete on public.social_categories, public.social_roles, public.social_member_roles,
  public.social_events to service_role;
revoke all on function public.social_overview(text) from public, anon, authenticated;
grant execute on function public.social_overview(text) to service_role;
