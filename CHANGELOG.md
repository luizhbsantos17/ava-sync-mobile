# Notas de versão

Cada versão nova do app precisa de uma seção aqui **antes** de ir para a `main`.
O GitHub Actions copia a seção da versão do `pubspec.yaml` para a release, e o app
mostra esse texto na janela "Nova versão disponível". Sem a seção, o build oficial falha.

Formato (escreva para quem usa o app, em português, sem dados pessoais):

```
## [X.Y.Z] - AAAA-MM-DD
### Adicionado
- ...
### Alterado
- ...
### Corrigido
- ...
```

Mudanças que ainda não têm versão ficam em `## [Não lançado]`; o APK beta usa
essa seção quando a versão atual ainda não tem uma.

## [Não lançado]
### Corrigido
- O app **fechava sozinho ao entrar num canal de voz** no Android.

## [1.2.0] - 2026-11-16
### Adicionado
- **Canais de voz**, como no Discord: várias pessoas na mesma chamada, microfone,
  "ensurdecer", câmera e **compartilhar a tela** (no computador dá para escolher a tela ou a
  janela). Quem está falando aparece com um anel verde; a lista de canais mostra quem está
  em cada chamada antes de entrar.
- Barra "Voz conectada" no Social, com mudo, ensurdecer e sair, enquanto você usa o resto do app.
- Na chamada: destacar o vídeo de alguém, volume de cada pessoa (só no seu aparelho),
  escolher microfone e saída de som (computador) e, para quem modera, desconectar alguém.
- Canal de voz com **limite de pessoas**. Ao criar canal, escolha "Texto" ou "Voz".
- Áudio e vídeo **cifrados de ponta a ponta** com a chave do grupo: nem o servidor da
  chamada consegue ouvir.
### Alterado
- **Presença calculada sobre o total do semestre** (a carga horária), que é o que decide
  reprovar por falta. O % sobre as aulas já dadas continua aparecendo como detalhe.
- **Aulas do dia** mostram quantos dias você ainda pode faltar daquela matéria (ou se não
  pode mais), no lugar de "2 faltas".
- **App mais leve**: o Social só se atualiza sozinho com a tela dele aberta; fotos e
  imagens são carregadas no tamanho em que aparecem; listas longas (novidades) montam só o
  que está na tela; os dados salvos grandes são lidos e gravados sem travar a tela.
### Corrigido
- Sair de uma conversa podia deixar a última mensagem como não lida.
- Quem marcou "ignorar @todos" ou "ignorar @cargos" ainda recebia o aviso como menção.
- Duas gravações dos dados ao mesmo tempo podiam falhar; agora esperam uma a outra.
- A sincronização deixava conexões abertas, e cada imagem de conteúdo do AVA abria uma nova.
- O simulador de faltas ignorava a frequência mínima informada pelo Q-Acadêmico.
- A **turma de ingresso** (ex.: 2024/2) não aparecia para quase ninguém: agora vem do login
  do AVA, do número de identificação do AVA ou da matrícula do Q-Acadêmico, ao abrir o Social.

## [1.1.0] - 2026-11-16
### Adicionado
- **Social mais fluido**: telas, listas, menus e botões com animação; resposta ao toque
  e ao passar o mouse; a lista atualiza sem piscar e digitar não trava mais a conversa.
- **Menu ao segurar ou com o botão direito** em grupos, canais, categorias, conversas,
  membros, mensagens e anexos (marcar como lido, notificações, editar, excluir...).
- **Arrastar para organizar**: a ordem dos grupos na barra lateral, os canais (inclusive
  de uma categoria para outra) e as categorias. No celular, segure e arraste.
- **Excluir canal** direto pelo menu do canal.
- **Notificações por grupo**: todas as mensagens, só menções ou nada; e ignorar @todos
  ou menções de cargos.
- **@todos aparece nas sugestões** ao digitar @ (quem pode marcar todos) e **@all** também funciona.
- **Pular para as não lidas**: ao abrir um canal, aviso "N mensagens novas desde..." com
  botão para voltar até onde você parou de ler.
- **Ir para a menção**: botão com @ e o número de vezes que te marcaram; leva direto à
  mensagem, que pisca. Tocar numa resposta também leva à mensagem original.
- **Turma de ingresso** (ex.: 2024/2) no perfil e na lista de membros, tirada do seu
  usuário do AVA.
- **Computador**: Enter envia (Shift+Enter pula linha), Esc cancela, seta para cima edita
  a última mensagem; barra de ações ao passar o mouse na mensagem (reagir, responder);
  lista lateral que recolhe (Ctrl+B); membros ao lado da conversa; barra de rolagem
  mais fina e bonita.
- **Computador: escolher onde salvar**: pasta dos arquivos baixados em Ajustes (com
  opção de levar os que já estão lá) e "Salvar como…" em fotos e anexos do Social.
- **Instalador do Windows**: escolher a pasta de instalação, instalar só para você ou
  para todos e criar atalhos na área de trabalho e no Menu Iniciar.
### Corrigido
- Abrir um canal tirava ele da categoria até a próxima atualização.
- **Menções mostram o nome**: na notificação, na busca e na prévia da conversa aparece
  "@Mikame" (o nome do chat), e não mais o código "@ifes_...". A busca acha a mensagem
  pelo nome de quem foi marcado.
### Alterado
- **Ser marcado chama mais atenção**: a notificação vem com 📣 e, no Android, num canal
  próprio "Menções" com prioridade máxima (dá para escolher outro som). No chat, a
  mensagem que marca você fica mais destacada.
- **"Só menções" avisa quando marcam você** (@você, um @cargo seu ou @todos, conforme
  as opções do grupo). Grupos silenciados antes viram "Só menções".

## [1.0.0] - 2026-11-16
### Adicionado
- **AVA Sync para computador** (Windows, Linux e macOS): prazos, matérias, notas e o
  Social, com a mesma conta do AVA. Baixe na página de versões do GitHub.
- No computador, o app **fica na bandeja** (perto do relógio) ao fechar a janela e continua
  sincronizando, avisando de prazos e de mensagens novas. Para fechar de vez, use "Sair"
  no ícone da bandeja.
- **Abre junto com o sistema**, escondido na bandeja (dá para desligar em Ajustes > Computador).
- **Notificações do Social em tempo real**: a mensagem nova aparece na hora no computador
  (mesmo com a janela fechada) e no celular, **inclusive com o app fechado**.
- **Tela grande**: menu lateral, conteúdo centralizado e o Social com a lista e a conversa
  lado a lado, como no Discord.
- **Atalhos**: F5 ou Ctrl+R sincronizam; clique com o botão direito abre os mesmos menus
  de segurar o dedo no celular.
- No Windows, a **atualização é automática**: o app baixa, instala e abre de novo sozinho.
- **Cargos personalizados nos grupos**: nome, cor, hierarquia e permissões (editar o grupo,
  gerenciar canais e cargos, remover, banir, apagar mensagens, fixar, marcar @todos,
  escrever em avisos). Uma pessoa pode ter vários cargos, e o nome aparece na cor do cargo.
- **@cargo**: marque todo mundo de um cargo (ex.: @monitor) quando ele for marcável.
- **Categorias de canais** (ex.: "Canais gerais", "Estudo"), que dá para recolher.
- **Fundo com foto** no perfil e no grupo, e **cor do grupo**.
- **Mais notificações do Social**: pedido de amizade, amizade aceita, entrar, ser removido
  ou banido de um grupo e ganhar cargo.
### Alterado
- **Notificações do Social mostram cada mensagem**: uma notificação por grupo/canal ou
  conversa, com quem mandou e o texto. Várias mensagens seguidas se juntam na mesma
  notificação (como no WhatsApp) e ela some quando você abre a conversa.
### Corrigido
- **Trocar a cor do fundo do perfil** dava erro.
- **Faltas no Acadêmico**: limites corrigidos de 7, 15 e 22 para 9, 18 e 27 nas disciplinas de 30, 60 e 90 horas, com ajuste das faltas e dias restantes.

## [0.8.0] - 2026-11-15
### Adicionado
- **Social novo, no estilo Discord**: barra lateral com seus grupos, mensagens
  diretas, aba de amigos e aba "Você".
- **Canais dentro dos grupos** (#geral, #avisos…), com tópico e canal de avisos em
  que só administradores escrevem. O grupo da matéria já vem com #avisos, #geral e #dúvidas.
- **Perfis**: foto, cor, "sobre mim", nome de exibição, @usuário e status
  (disponível, ocupado, ausente, invisível) com status personalizado e emoji.
- **Amigos**: pedidos de amizade, aceitar/recusar, bloquear, busca por nome ou @usuário.
- **Mensagens diretas** entre amigos ou pessoas do mesmo grupo.
- **Mensagens melhores**: foto e nome de quem mandou, mensagens agrupadas, separador
  de dia e de "Novas mensagens", responder (também arrastando para o lado), reações
  com emoji, editar, apagar, fixar, @menções, formatação (**negrito**, *itálico*,
  `código`, ||spoiler||), links clicáveis e busca.
- **Anexos**: fotos e arquivos (até 8 MB), cifrados como as mensagens.
- **Quem está digitando**, quem está online e lista de membros do grupo.
- **Administração**: tornar admin, transferir posse, remover, banir e desbanir,
  convites com validade, revogar convites, editar nome, descrição e foto do grupo,
  apelido por grupo, silenciar grupo, sair e apagar.
- **Notificações** de mensagens novas, inclusive com o app fechado (a cada ~15 min).
### Alterado
- As mensagens aparecem na hora ao enviar e chegam em menos de um segundo, sem
  esperar a atualização a cada 4 s.
- Amigo adicionado direto no grupo, conversa direta e troca de celular recebem a
  chave sozinhos quando outro membro abre o app, sem precisar de um convite novo.
### Corrigido
- Erro ao voltar para o app com um chat aberto depois de deixá-lo em segundo plano.
- Mensagens de grupo que viravam "protegidas": o aparelho guarda todas as chaves que
  já teve para cada grupo e não apaga mais a chave quando um convite dá erro.

## [0.7.0] - 2026-11-14
### Adicionado
- **Grupos e conversas** (ícone de balão no topo ou Perfil → Grupos e conversas):
  entra com a mesma conta do AVA, sem outro cadastro. Crie grupos privados e chame
  amigos por convite. As mensagens são cifradas no celular antes de sair.
- **Grupo da matéria** para professores: o AVA confirma quem é professor da
  disciplina e a turma entra no grupo automaticamente.
- **Versão de testes** (“AVA Sync Teste”), que instala ao lado do app oficial.
- Botão **Sincronizar todas as matérias agora**, em Ajustes.
- Formulários para relatar problemas e sugerir melhorias no GitHub.

### Alterado
- O sync comum busca só as matérias do semestre atual (mais rápido). A primeira
  sincronização e o botão manual continuam buscando todas.
- “Ignorar matérias” e “Somente estas matérias” agora são uma lista com busca e
  caixas de marcar, em vez de digitar os nomes.
- A janela de atualização mostra o que mudou na versão nova.

## [0.6.1] - 2026-11-14
### Corrigido
- Boletim do Q-Acadêmico: o rodapé com o nome do aluno não aparece mais como disciplina;
  colunas CH, T. Faltas, NS, EF e MF reconhecidas.
- Diários: frequência, faltas, aulas previstas e avaliações ligadas à disciplina certa;
  “Nota Máxima” não é mais lida como a nota.
- Horário: dias “2ª-FEIRA”, intervalos com “~” e nomes das disciplinas.
- A importação avisa quando diário ou horário não foram lidos.
- A senha do Q-Acadêmico só é salva com “lembrar” marcado e depois de importar.
- Nomes longos de disciplina não quebram mais letra por letra.

## [0.6.0] - 2026-11-14
### Adicionado
- Aba **Acadêmico**: disciplinas, boletim e horário (aulas de hoje e da semana).
- Quantos dias de aula ainda pode faltar e o simulador “E se eu faltar?”.
- Cor por disciplina, cartões expansíveis e animações.
### Alterado
- Sem média ou frequência geral; do AVA aparecem só as notas de prova.

## [0.5.0] - 2026-11-14
### Adicionado
- Aba **Perfil**: foto, nome, curso, bio e resumo.
- **Aparência**: temas prontos, cor, modo, cantos, fonte e tema em JSON.
- Notas do AVA e dados do Q-Acadêmico (média, etapas, faltas, % de presença).

## [0.4.1] - 2026-11-14
### Alterado
- Mostra versão e build em Ajustes → Sobre.

## [0.4.0] - 2026-11-14
### Adicionado
- Atualização dentro do app, com aviso automático de versão nova.
- Lembretes 3 dias, 1 dia e 3 horas antes de entregas, questionários e provas.
- Avisos de entrega registrada, nota publicada, prazo alterado e prazo vencido.
- Integração opcional com a agenda do celular (Google Agenda).
### Corrigido
- Download da atualização que travava em 100%.
- O app passa a ter assinatura fixa: atualiza por cima, sem desinstalar.

## [0.3.1] - 2026-11-14
### Corrigido
- Classificação de matérias, sync e tela inicial.
