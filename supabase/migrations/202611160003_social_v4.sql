-- Social v4: notificações por grupo, turma de ingresso e "última mensagem lida".
-- Aditiva: o app antigo continua usando `muted`, que fica igual a notify <> 'all'.

-- Notificações por grupo -------------------------------------------------------------
-- all      = toda mensagem
-- mentions = só quando me marcam (@você; @cargo e @todos podem ser desligados)
-- none     = nada
alter table public.social_members
  add column if not exists notify text not null default 'all' check (notify in ('all', 'mentions', 'none')),
  add column if not exists suppress_everyone boolean not null default false,
  add column if not exists suppress_roles boolean not null default false;

update public.social_members set notify = 'mentions' where muted and notify = 'all';

-- Turma de ingresso (ex.: 2024/2), tirada do usuário do AVA; só o servidor escreve.
alter table public.social_profiles
  add column if not exists cohort text check (cohort is null or cohort ~ '^20[0-9]{2}/[12]$');

-- Resumo das conversas: preferências de notificação, última leitura por canal e
-- contagem de menções respeitando "ignorar @todos" e "ignorar @cargos".
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
          'category_id', ch.category_id,
          'last_read_at', coalesce(r.last_read_at, m.joined_at),
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
