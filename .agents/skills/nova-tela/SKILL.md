---
name: nova-tela
description: Padrões de interface do AVA Sync para criar ou mudar telas e componentes Flutter. Use ao mexer em lib/telas/.
---

# Telas e interface

## Padrões
- Material 3 com o tema da pessoa (`lib/tema.dart`, `temaAtual`): use
  `Theme.of(context).colorScheme` e `textTheme`; **nunca cores fixas** (o app tem
  modo escuro e temas personalizados).
- Cor por disciplina: `corDisciplina(nome, brightness)` em `lib/telas/aulas.dart`.
- Avisos rápidos: `aviso(context, msg)` em `lib/telas/comum.dart`.
- Dados vêm de `app` (`lib/estado_app.dart`); envolva com `ListenableBuilder`/
  `AnimatedBuilder` para atualizar quando `app.avisarMudanca()` for chamado.
- Textos em português, curtos, com estado de **carregando**, **vazio** e **erro**
  explicando o que fazer.
- Telas pequenas: teste em 360 px de largura. Nome longo: `maxLines` + `ellipsis`;
  nunca deixe `Text` sem limite dentro de `Row` sem `Expanded`/`Flexible`.
- `BuildContext` depois de `await`: confira `mounted` (o `flutter analyze` acusa).

## Onde encaixar
- Abas principais em `lib/telas/inicio.dart`.
- Configurações em `lib/telas/ajustes.dart` (veja skill `nova-configuracao`).
- Perfil e atalhos em `lib/telas/perfil.dart`.

## Testar
- Teste de widget em `test/telas_test.dart` ou num arquivo novo:
  `SharedPreferences.setMockInitialValues({}); await Cfg.init();`, preencha `app`
  com dados fictícios, `pumpWidget`, `pumpAndSettle`, `expect(t.takeException(), isNull)`.
