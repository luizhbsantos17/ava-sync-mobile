-- Push do Social (Firebase Cloud Messaging) ----------------------------------
-- Cada aparelho Android registra o seu token do FCM. Quando chega mensagem, a Edge
-- Function manda um aviso SEM conteúdo ("tem mensagem nova na conversa X") para os
-- aparelhos dos outros membros; o app acorda, baixa a mensagem cifrada, decifra e
-- mostra a notificação com nome e texto. O Google nunca vê o texto.

create table if not exists public.social_push_tokens (
  token text primary key check (char_length(token) between 20 and 4096),
  user_key text not null references public.social_profiles(user_key) on delete cascade,
  platform text not null default 'android' check (platform in ('android')),
  updated_at timestamptz not null default now()
);

create index if not exists social_push_tokens_user on public.social_push_tokens(user_key);

-- Só a Edge Function (service_role) acessa. RLS sem políticas é proposital.
alter table public.social_push_tokens enable row level security;
revoke all on public.social_push_tokens from public, anon, authenticated;
grant select, insert, update, delete on public.social_push_tokens to service_role;
