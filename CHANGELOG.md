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
