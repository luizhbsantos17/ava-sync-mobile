---
name: corrigir-bug
description: Como investigar e corrigir um bug no AVA Sync com teste de regressão. Use quando alguém relatar algo que não funciona.
---

# Corrigir bug

1. **Reproduza no papel antes de mexer.** Ache o caminho do código (veja
   `docs/contexto/ARQUITETURA.md`) e explique a causa provável em uma frase.
   Se depender de dado real (HTML do Q-Acadêmico, resposta do Moodle), peça um exemplo
   e **sanitize** antes de usar em teste.
2. **Escreva o teste que falha** em `test/` (fixtures em `test/fixtures/`, só dados
   fictícios). Rode e veja falhar.
3. **Corrija o mínimo necessário.** Não aproveite para refatorar coisas sem relação.
4. `flutter analyze` e `flutter test`.
5. CHANGELOG em `### Corrigido` (skill `changelog`).
6. Em `docs/contexto/ESTADO_ATUAL.md`, tire o problema de "Problemas conhecidos", se estava lá.
7. Branch `fix/...` ou `feature/...` (para ter APK beta), commit `fix: ...`, PR.
   Se veio de uma Issue, escreva `Fecha #N` no PR.

## Dicas por área
- Sync/Moodle: `test/app_test.dart` tem `MockClient` para simular o Moodle.
- Q-Acadêmico: skill `leitor-qacademico`.
- Telas: testes de widget em `test/telas_test.dart`; use `t.binding.setSurfaceSize`
  para telas pequenas (360 px).
