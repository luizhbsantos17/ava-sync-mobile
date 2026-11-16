# Push do Social (Firebase) — como configurar

Com isto, o celular Android recebe a notificação do Social **na hora, com o app fechado**.
O servidor manda só um aviso sem conteúdo ("tem mensagem nova na conversa X"); o app
acorda, busca a mensagem cifrada, decifra no próprio celular e mostra quem mandou e o
texto. O Google nunca vê o texto, o nome de quem mandou nem o nome do grupo.

Sem esta configuração tudo continua funcionando: as notificações só demoram (~15 min com
o app fechado). Quem configura é o dono do repositório. **Nunca cole chaves no chat, em
Issue ou no Git.**

## 1. Criar o projeto no Firebase (grátis)
1. Entre em <https://console.firebase.google.com> com uma conta Google e clique em
   **Criar projeto** (ex.: `ava-sync`). O Google Analytics pode ficar desligado.
2. No projeto, clique no ícone do Android para **adicionar um app Android**:
   - Nome do pacote: `io.github.avasync.mobile` → Registrar. Pode pular o resto do assistente.
3. Adicione **outro app Android** para a beta: `io.github.avasync.mobile.beta`.
4. Em **Configurações do projeto** (engrenagem) > **Geral** > "Seus apps", clique no app
   `io.github.avasync.mobile` e baixe o **google-services.json**. Abra no Bloco de Notas:
   - `project_id` → `FCM_PROJECT_ID`
   - `project_number` → `FCM_SENDER_ID`
   - `current_key` (dentro de `api_key`, começa com `AIza`) → `FCM_API_KEY`.
     A "Chave de API da Web" da tela Geral **não aparece** em projeto só com Android;
     use esta (é a mesma da "Android key (auto created by Firebase)" no Google Cloud).
   - `mobilesdk_app_id` de `io.github.avasync.mobile` → `FCM_APP_ID`; o da `.beta` →
     `FCM_APP_ID_BETA` (se o arquivo não tiver a beta, baixe o da beta também).
   Depois **apague o google-services.json**: o projeto não usa esse arquivo.

## 2. Guardar os valores no GitHub (para o APK sair com push)
Repositório > **Settings** > **Secrets and variables** > **Actions** > **New repository
secret**, um para cada: `FCM_API_KEY`, `FCM_PROJECT_ID`, `FCM_SENDER_ID`, `FCM_APP_ID`,
`FCM_APP_ID_BETA`.

Para compilar no seu computador, coloque em `android/key.properties` (que já não vai para
o Git): `fcm.api_key=...`, `fcm.project_id=...`, `fcm.sender_id=...`, `fcm.app_id=...`,
`fcm.app_id_beta=...`.

## 3. Dar ao servidor a chave para enviar push
1. No Firebase: **Configurações do projeto** > **Contas de serviço** > **Gerar nova chave
   privada**. Baixa um arquivo `.json`. Ele é secreto: não mande para ninguém.
2. No Supabase: projeto do Social > **Edge Functions** > **Secrets** (ou **Project
   Settings > Edge Functions**) > adicionar segredo:
   - Nome: `FCM_SERVICE_ACCOUNT`
   - Valor: o conteúdo inteiro do arquivo `.json`.
3. Apague o `.json` baixado do seu computador depois de colar.

## 4. Publicar banco e função (uma vez)
```bash
supabase db push
supabase functions deploy social --no-verify-jwt
```
(Isso cria a tabela `social_push_tokens` e a função com `push_register` e o envio.)

## Como conferir
1. Gere um APK novo (push numa branch `feature/**` gera a beta) e instale.
2. Abra o app e o Social uma vez (o celular registra o token).
3. Feche o app. Peça para alguém mandar mensagem num grupo seu: a notificação deve
   aparecer em segundos, com o nome de quem mandou e o texto.
