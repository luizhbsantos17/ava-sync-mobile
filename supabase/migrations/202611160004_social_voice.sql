-- Canais de voz (issue #3): tipo do canal, limite de pessoas e quem está na chamada.
-- A mídia passa pelo LiveKit (com criptografia de ponta a ponta feita no aparelho);
-- aqui só fica quem está em cada canal, para a lista mostrar antes de entrar.

alter table public.social_channels
  add column if not exists kind text not null default 'text' check (kind in ('text', 'voice')),
  add column if not exists user_limit integer check (user_limit is null or user_limit between 2 and 99);

-- Quem está em cada canal de voz. O aparelho renova a cada ~20 s; sem renovar, some
-- em 45 s (app fechado, sem internet).
create table if not exists public.social_voice_presence (
  channel_id uuid not null references public.social_channels(id) on delete cascade,
  user_key text not null references public.social_profiles(user_key) on delete cascade,
  muted boolean not null default false,
  deafened boolean not null default false,
  video boolean not null default false,
  screen boolean not null default false,
  joined_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (channel_id, user_key)
);
create index if not exists social_voice_presence_user_idx on public.social_voice_presence (user_key);

alter table public.social_voice_presence enable row level security;
revoke all on public.social_voice_presence from public, anon, authenticated;
grant select, insert, update, delete on public.social_voice_presence to service_role;

-- Resumo das conversas: tipo e limite do canal e quem está na voz.
create or replace function public.social_overview(p_user text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_at desc), '[]'::jsonb) from (
    select c.id, c.title, c.description, c.icon_path, c.banner_path, c.accent_color, c.group_kind,
      c.moodle_course_id, c.moodle_course_name, c.created_at,
      m.role, m.muted, m.nickname, m.notify, m.suppress_everyone, m.suppress_roles,
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
          'category_id', ch.category_id, 'kind', ch.kind, 'user_limit', ch.user_limit,
          'last_read_at', coalesce(r.last_read_at, m.joined_at),
          'voice', case when ch.kind = 'voice' then (
              select coalesce(jsonb_agg(jsonb_build_object('user_key', vp.user_key, 'muted', vp.muted, 'deafened', vp.deafened,
                       'video', vp.video, 'screen', vp.screen, 'joined_at', vp.joined_at) order by vp.joined_at), '[]'::jsonb)
              from public.social_voice_presence vp where vp.channel_id = ch.id and vp.expires_at > now()) end,
          'unread', (select count(*) from public.social_messages sm where sm.channel_id = ch.id and sm.deleted_at is null
                      and sm.sender_id <> p_user and sm.created_at > coalesce(r.last_read_at, m.joined_at)),
          'mentions', (select count(*) from public.social_messages sm where sm.channel_id = ch.id and sm.deleted_at is null
                      and sm.sender_id <> p_user and sm.created_at > coalesce(r.last_read_at, m.joined_at)
                      and (p_user = any(sm.mentions)
                           or (not m.suppress_everyone and 'everyone' = any(sm.mentions))
                           or (not m.suppress_roles and exists (select 1 from public.social_member_roles mr
                                      where mr.conversation_id = c.id and mr.user_key = p_user
                                        and ('role:' || mr.role_id::text) = any(sm.mentions))))),
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
                 p.custom_emoji, p.last_seen, p.banner_color, p.cohort
          from public.social_members o join public.social_profiles p on p.user_key = o.user_key
          where o.conversation_id = c.id and o.user_key <> p_user limit 1) pp) end as peer,
      greatest(c.created_at, (select max(sm.created_at) from public.social_messages sm where sm.conversation_id = c.id)) as sort_at
    from public.social_members m
    join public.social_conversations c on c.id = m.conversation_id
    where m.user_key = p_user
  ) x;
$$;

revoke all on function public.social_overview(text) from public, anon, authenticated;
grant execute on function public.social_overview(text) to service_role;
