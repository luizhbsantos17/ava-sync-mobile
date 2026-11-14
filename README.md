# AVA Sync (Android)

Seu **Moodle no celular**: prazos, atividades, avisos, materiais e livros, até offline,
com notificações e envio de atividades. Funciona sozinho no celular, sem PC, e com
**qualquer Moodle** que tenha o serviço do app oficial habilitado.

É a versão Android do [ava-sync](https://github.com/SEU-USUARIO/ava-sync) (Python).

> Use só com a **sua própria conta** e respeite as regras da sua instituição.

## O que faz

- **Prazos**: tarefas, questionários e eventos em ordem, com cor por urgência e situação da entrega.
- **Matérias**: abas Estudar (IA), Atividades, Provas, Avisos, Conteúdo (igual ao AVA) e Arquivos.
- **Semestre atual**: por padrão só aparecem as matérias do semestre atual (detectado pelo nome,
  pela data de início e pela atividade). "Todas" mostra as antigas. Toque e segure numa matéria
  para corrigir.
- **Atividade x prova**: questionários com tempo ou nome de prova e provas marcadas no calendário
  vão para Provas. Toque e segure num item para mover.
- **Links dentro dos textos**: arquivos do Moodle linkados em rótulos e páginas são baixados;
  links para atividades do Moodle abrem dentro do app. HTML (notas de aula) abre num leitor interno.
- **Offline**: PDFs, slides, anexos, páginas, **livros do Moodle** e as **imagens** dos textos
  ficam salvos no celular.
- **Links**: PDFs e slides em links públicos são baixados. Vídeos, Google Drive, reuniões e
  bibliotecas virtuais (leitores protegidos) ficam só como link.
- **Segundo plano**: sincroniza a cada 6, 12 ou 24 h e avisa quando aparece tarefa, aviso ou
  material novo, quando a entrega é registrada, quando sai nota, quando um prazo muda e quando
  um prazo vence sem entrega (dizendo se ainda aceita até a data de corte).
- **Lembretes de prazo**: 3 dias, 1 dia e 3 horas antes de cada entrega pendente, questionário
  e prova. Ficam agendados no Android e disparam mesmo com o app fechado.
- **Agenda (Google Agenda)**: opcional, em Ajustes. Coloca prazos e provas numa agenda do celular
  e mantém atualizado (muda a data, marca ✓ quando entrega, apaga o que sumiu do AVA). Escolhendo
  uma agenda da conta Google, aparece no Google Agenda em todos os dispositivos.
- **Atualização dentro do app**: ao abrir (e em segundo plano) procura versão nova, baixa o APK
  com barra de progresso e abre o instalador do Android. Não precisa desinstalar.
- **Enviar atividade**: escolha os arquivos (e/ou texto online), digite **ENVIAR** e confirme.
  Mostra antes o que já foi enviado. "Finalizar" e a declaração de autoria são marcados por você.
- **Busca** em tudo.
- **Guias por IA (opcional)**: Gemini, ChatGPT, Claude ou compatíveis (OpenRouter, Groq, Ollama).
  Guia geral da matéria, guia de cada atividade (ensina o caminho, sem entregar a resposta) e
  preparação para cada prova (o que deve cair, revisão, exercícios, plano de estudo). A IA lê os
  textos, avisos, DOCX/PPTX e, nos provedores que aceitam, os PDFs da matéria.
  Cada IA tem a sua pasta (`IA/<provedor>/`): trocar de IA não apaga nada, uma não altera o
  conteúdo da outra, mas cada uma pode ler o que as outras geraram como referência.

## Instalar

1. No celular, abra a página **Releases** deste repositório e baixe `AVA-Sync.apk`.
2. Abra o arquivo. O Android vai pedir para permitir "instalar apps desta fonte": permita.
3. Entre com o endereço do seu Moodle, usuário e senha.

### Meu Moodle é compatível?

Na tela de login, toque no ícone ao lado do endereço para **verificar o site**. Ele confere se
a API do app oficial está ligada. Se o Moodle usa login pelo navegador (SSO, por exemplo
"Entrar com Google/Microsoft" obrigatório), o login por senha pode não funcionar.

## Privacidade e segurança

- A **senha não é salva**: é usada uma vez para gerar um token (o mesmo mecanismo do app
  oficial do Moodle). O token fica criptografado no Keystore do Android.
- O token **só é enviado ao seu Moodle**. Imagens e links externos são baixados sem ele.
- Nada sai do celular, exceto: as chamadas ao seu Moodle e, se você ativar, o enunciado
  enviado ao provedor de IA quando você pede um guia.
- O segundo plano **só lê**. Envio de atividade só acontece na tela de envio, com ENVIAR digitado.
- Para revogar o acesso: Ajustes > Sair, e no AVA: Preferências > Chaves de segurança.

## Limitações

- Questionários, H5P, SCORM e ferramentas externas (LTI) abrem no navegador.
- Livros de bibliotecas virtuais (Pearson, Minha Biblioteca etc.) não são baixáveis.
- O Android pode atrasar a sincronização em segundo plano para economizar bateria. Se ela
  não estiver rodando, tire o app da otimização de bateria.

## Compilar

Requer Flutter (canal stable) e Android SDK.

```bash
flutter pub get
flutter test
flutter build apk --release --split-per-abi
```

O GitHub Actions (`.github/workflows/build.yml`) roda os testes e publica o APK no Release
`latest` a cada push na `main`.

No app, abra **Ajustes > Verificar atualizações**. Se houver um build mais novo, o app abre o
download do APK; o Android pede confirmação antes de instalar. Para atualizar por cima da versão
instalada, configure a mesma keystore de release em todos os builds (veja abaixo).

### Assinatura (recomendado)

Sem keystore próprio o APK sai assinado com uma chave de debug diferente a cada build do
GitHub, e o Android recusa a atualização ("conflito de pacote"). Com o keystore, todas as
versões saem com a mesma assinatura e atualizam por cima, sem perder dados.
**Guarde uma cópia do keystore e da senha**: sem eles, nenhuma versão nova instala por cima. Para assinar sempre com a mesma chave:

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias avasync
base64 -w0 release.jks > release.jks.b64
```

No GitHub: Settings > Secrets and variables > Actions, crie `ANDROID_KEYSTORE_BASE64`
(conteúdo do .b64), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`avasync`) e
`ANDROID_KEY_PASSWORD`. Nunca coloque o keystore no repositório.

## Estrutura

```
lib/
  moodle.dart      cliente da API REST do Moodle (token, chamadas, download, upload)
  sync.dart        sincronização -> snapshot.json + arquivos
  midia.dart       imagens dos textos, livros do Moodle, links
  envio.dart       entrega de tarefas (com as travas de confirmação)
  fundo.dart       notificações e sincronização em segundo plano
  ia.dart          guias de estudo (opcional)
  telas/           interface
test/              testes com respostas simuladas da API
```

## Licença

MIT.
