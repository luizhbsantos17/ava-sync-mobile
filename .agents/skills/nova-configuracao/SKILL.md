---
name: nova-configuracao
description: Como adicionar uma preferência ou segredo novo no AVA Sync (Cfg) e expor em Ajustes. Use ao criar opção configurável.
---

# Nova configuração

## Preferência comum (SharedPreferences)
Em `lib/config.dart`, dentro de `Cfg`, na seção certa:
```dart
static bool get minhaOpcao => _p.getBool('minha_opcao') ?? false;
static Future<void> setMinhaOpcao(bool v) => _p.setBool('minha_opcao', v);
```
- Chave em `snake_case`, curta e **nova** (procure com grep para não colidir).
- Sempre um valor padrão que mantenha o comportamento atual para quem atualiza.
- Nunca reaproveite uma chave antiga com outro significado: crie outra.

## Segredo (token, senha)
Use o `FlutterSecureStorage` como `Cfg.token()`/`Cfg.qaSenha()`. Nunca em
SharedPreferences, nunca em log, nunca no snapshot.

## Em Ajustes
`lib/telas/ajustes.dart`: `SwitchListTile`/`ListTile` na seção certa, com subtítulo
explicando o efeito. Use `_mudar(() => Cfg.setX(v), reagendar: true)` se a opção
afeta o segundo plano (intervalo de sync, notificações).

## Testar
`SharedPreferences.setMockInitialValues({}); await Cfg.init();` e confira o padrão e
a mudança. Registre no CHANGELOG ("em Ajustes, ...").
