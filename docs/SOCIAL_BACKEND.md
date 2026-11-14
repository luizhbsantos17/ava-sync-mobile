# Área Social do AVA Sync

O Social usa a conta AVA que já está conectada no app. Não há cadastro ou senha
separada. O app envia o token Moodle somente em uma chamada HTTPS à Edge Function,
que valida a conta com `core_webservice_get_site_info` antes de atender cada ação.
O token não é guardado no Supabase. A função aceita os domínios oficiais do AVA
Ifes configurados no código.

## Supabase

O projeto fica no Supabase na região de São Paulo. A Edge Function `social` é o
único caminho de acesso às tabelas; as tabelas têm RLS ligado e não dão acesso
direto às chaves `anon` ou `authenticated`. A função usa a chave administrativa
apenas no servidor. Essa chave não deve entrar no app nem no repositório.

As migrations estão em `supabase/migrations/`. O fonte que foi enviado ao projeto
está em `supabase/functions/social/index.ts`.

Para executar localmente com a configuração já preparada:

```powershell
flutter pub get
flutter run --dart-define-from-file=social-supabase-config.json
```

`social-supabase-config.json` está ignorado pelo Git. O URL e a chave publishable
não são segredos; a chave `service_role`/secret nunca pode ser copiada para ele.

## Identidade e privacidade

- O servidor valida a identidade Moodle em cada chamada e associa as contas por
  host e ID de usuário do AVA. Não cria uma conta de login independente no app.
- Só a Edge Function lê e escreve os registros. Ela confere participação antes de
  listar ou enviar mensagens; professor não recebe acesso aos grupos privados de
  amigos só por ser professor.
- O app cifra mensagens com AES-GCM antes de enviá-las. O Supabase guarda texto
  cifrado, nonce, tag, IDs e horários. O token AVA não é persistido pelo backend.
- Convite contém a chave de leitura do grupo. Qualquer pessoa que receba o convite
  pode tentar entrar; em grupos de matéria a função só aceita quem já foi incluído
  no diário de participantes da disciplina pelo AVA.
- A consulta ao AVA para verificar professores usa os papéis devolvidos por
  `core_enrol_get_enrolled_users`. Se o serviço Moodle não permitir consultar os
  participantes ou não devolver um papel reconhecido, o app não libera a criação.
- No grupo de matéria, o AVA confirma o professor e a função inclui os inscritos
  atuais como membros. O convite precisa ser compartilhado com a turma para que
  cada aparelho receba a chave E2E; sem essa etapa o conteúdo continua cifrado.
- As mensagens atualizam por polling a cada quatro segundos. Recuperar o histórico
  em um celular novo exige receber novamente o convite/chave do grupo.

## Backends alternativos

A interface Flutter depende de `SocialRepository`, não de chamadas diretas às
telas. O adaptador atual usa Supabase Edge Functions. `HttpSocialRepository` é a
implementação local antiga para o servidor Node em `server/`; ela ainda usa sua
autenticação própria e não implementa a identidade Moodle nem grupos de matéria.
Para trocar o backend, será necessário implementar no servidor alternativo as
mesmas validações de token e permissões antes de apontar o app para ele.

## Backend local no PC

Para executar o servidor Node local, rode `node server/index.js`. Ele escuta em
`127.0.0.1:8787` e persiste dados em `server/data/` (ignorada pelo Git). Para
testar com outro dispositivo na rede, gere TLS com `server/enable-local-tls.ps1`
e autorize a porta privada pelo script `server/open-lan-firewall.ps1`. Este modo
é destinado a desenvolvimento; não exponha a porta publicamente.
