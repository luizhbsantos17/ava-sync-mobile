#!/usr/bin/env bash
# Imprime a seção do CHANGELOG.md de uma versão. Uso: scripts/notas_versao.sh 0.7.0
# Sai com erro 1 se a seção não existir ou estiver vazia.
set -euo pipefail
versao="$1"
arq="${2:-CHANGELOG.md}"
notas=$(awk -v v="[$versao]" '
  /^## \[/ { dentro = (index($0, "## " v) == 1); next }
  dentro { print }
' "$arq" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')
if [ -z "$(printf '%s' "$notas" | tr -d '[:space:]')" ]; then
  echo "CHANGELOG.md não tem notas para a versão $versao." >&2
  exit 1
fi
# "@usuário" no texto vira menção a contas do GitHub na release (@usu, @men...).
# Um espaço invisível depois do @ evita a menção; no app o texto aparece igual.
printf '%s\n' "$notas" | sed 's/@/@\xE2\x80\x8B/g'
