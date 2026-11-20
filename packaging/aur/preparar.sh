#!/usr/bin/env bash
# Prepara os arquivos do pacote ava-sync-bin para o AUR.
# Uso: packaging/aur/preparar.sh <versao X.Y.Z> <build> <AVA-Sync-Linux.tar.gz> <pasta de saída>
# Copia PKGBUILD e ava-sync.desktop para a pasta, com pkgver = X.Y.Z.<build> e o sha256
# do .tar.gz que acabou de ir para a release (no lugar do SKIP).
set -euo pipefail
versao="$1"; build="$2"; tarball="$3"; saida="$4"
aqui="$(cd "$(dirname "$0")" && pwd)"

[[ "$versao" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "versão inválida: $versao" >&2; exit 1; }
[[ "$build" =~ ^[0-9]+$ ]] || { echo "build inválido: $build" >&2; exit 1; }

sha="$(sha256sum "$tarball" | cut -d' ' -f1)"
mkdir -p "$saida"
cp "$aqui/ava-sync.desktop" "$saida/"
sed -e "s/^pkgver=.*/pkgver=${versao}.${build}/" \
    -e "s/^pkgrel=.*/pkgrel=1/" \
    -e "0,/'SKIP'/s//'${sha}'/" \
    "$aqui/PKGBUILD" > "$saida/PKGBUILD"
grep -q "'${sha}'" "$saida/PKGBUILD" || { echo "não consegui pôr o sha256 no PKGBUILD" >&2; exit 1; }
