---
name: lancar-versao
description: Publica uma versão oficial do AVA Sync (release latest). Use só quando o dono do repositório pedir para lançar ou "subir para oficial".
---

# Lançar versão oficial

Só o dono do repositório pede isto. Se você não tem certeza de que foi pedido, pergunte.

## Antes
- As mudanças estão testadas na beta (de preferência no celular do dono).
- `flutter analyze` e `flutter test` limpos na branch que vai para a `main`.

## Passos
1. Escolha o número: `X.Y.Z` atual + 1 em Z (só correções) ou em Y (novidades, Z volta a 0).
2. `CHANGELOG.md`:
   - Renomeie `## [Não lançado]` para `## [X.Y.Z] - AAAA-MM-DD` (data de hoje).
   - Crie um `## [Não lançado]` vazio acima dela.
   - Confira: `bash scripts/notas_versao.sh X.Y.Z`
3. `pubspec.yaml`: `version: X.Y.Z+N` (o `+N` pode ser o próximo número; o CI usa o
   número do build do GitHub).
4. `docs/contexto/ESTADO_ATUAL.md`: atualize "Última atualização" com a versão.
5. Commit `chore: versão X.Y.Z` e leve para a `main` (merge do PR ou, se o dono pediu,
   fast-forward + push).
6. Acompanhe o workflow "Gerar APK oficial":
   ```bash
   gh run list --branch main --limit 1
   gh run watch <id> --exit-status
   gh release view latest
   ```
7. Confira que a release tem `Build: N`, `Versão: X.Y.Z`, as notas e o `AVA-Sync.apk`.
8. Opcional, recomendado: conferir a assinatura com o build anterior
   (`apksigner verify --print-certs AVA-Sync.apk`); o SHA-256 tem de ser o mesmo.

## Se falhar
- "CHANGELOG.md não tem notas para a versão": faltou o passo 2.
- Assinatura diferente ou erro de keystore: **pare** e avise o dono. Nunca troque
  `applicationId`, chave ou secrets, e nunca peça para desinstalar o app.
