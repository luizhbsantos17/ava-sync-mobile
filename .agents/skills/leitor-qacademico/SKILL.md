---
name: leitor-qacademico
description: Como mexer no leitor do Q-Acadêmico (boletim, diários, horário, faltas) do AVA Sync com segurança e testes. Use para qualquer mudança em lib/qacademico.dart ou na coleta pelo WebView.
---

# Leitor do Q-Acadêmico

## Limites (não negociáveis)
- Só pelo WebView com o login da própria pessoa (`ColetorQA` em
  `lib/telas/qacademico_tela.dart`). Sem HTTP direto, sem burlar a proteção
  anti-robô (Radware/perfdrive), sem automatizar captcha.
- Senha só fica salva se a pessoa marcar "lembrar" e depois de importar com sucesso
  (`guardarCredenciaisQA`).
- **Nunca** commitar HTML real: tem nome, matrícula, notas e faltas.

## Como o leitor funciona
- `lerBoletim` (t=2032), `lerDiarios` (t=2071), `lerHorario` (t=2010) em `lib/qacademico.dart`.
- Só tabelas "folha" (`_folha`: sem `<table>` dentro); as de fora são layout e contêm
  o rodapé com o nome do aluno.
- Boletim ↔ diário ligados pelo COD_PAUTA (fallback: nome da disciplina).
- `resultadoImportacao` marca a importação como parcial se diário ou horário não foram lidos.
- O app pode exportar as páginas lidas (Perfil → Q-Acadêmico → Exportar páginas):
  é assim que se consegue HTML para investigar.

## Mudando o leitor
1. Peça à pessoa o HTML exportado. Copie só a **estrutura** para uma fixture em
   `test/fixtures/` trocando todos os dados: aluno "Aluno Exemplo da Silva",
   matrícula `20990XXX0001`, COD_PAUTA `9001xx`, professores "Professor Exemplo ...",
   notas e faltas inventadas. Remova comentários com dados reais.
2. Escreva o teste em `test/qacademico_ifes_test.dart` (ou novo arquivo) e veja falhar.
3. Ajuste o leitor. Prefira tolerância (aceitar variações) a regex rígida.
4. Rode a suíte inteira: os outros formatos não podem quebrar.
5. Antes do commit: `git diff --cached` procurando nomes, matrículas ou códigos reais.
