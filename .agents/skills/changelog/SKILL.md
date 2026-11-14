---
name: changelog
description: Como escrever as notas de versão no CHANGELOG.md do AVA Sync. Use em toda mudança que a pessoa usuária vai perceber.
---

# Escrever no CHANGELOG

O texto do `CHANGELOG.md` aparece **dentro do app**, na janela "Nova versão disponível",
e na página da release. Escreva para quem usa o app, não para programador.

## Onde
Sempre em `## [Não lançado]`, no topo. Nunca edite a seção de uma versão já lançada
(a não ser para corrigir erro de digitação). Quem lança a versão renomeia a seção
(skill `lancar-versao`).

## Categorias (use só as que tiver)
```
## [Não lançado]
### Adicionado
- coisas novas
### Alterado
- coisas que mudaram de comportamento ou de lugar
### Corrigido
- bugs resolvidos
### Removido
- coisas que saíram
```

## Como escrever cada item
- Uma linha por mudança, começando pelo que a pessoa vê. Negrito no nome da função.
- Diga onde fica, quando ajudar: "em Ajustes", "na aba Acadêmico".
- Sem nomes de arquivo, classe ou função. Sem dados pessoais.
- Bom: `- **Horário** agora mostra aulas de sábado.`
- Ruim: `- Corrige regex _diaHorario em qacademico.dart.`

## Conflitos
Se duas branches adicionarem itens, ao resolver conflito **mantenha os dois**.

## Conferir
```bash
bash scripts/notas_versao.sh "Não lançado"
```
Mostra exatamente o que vai para a beta.
