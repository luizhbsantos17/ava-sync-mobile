# Pacote do AUR (`ava-sync-bin`)

Deixa o app de computador instalável no Arch Linux (e Manjaro, EndeavourOS...) com:

```bash
yay -S ava-sync-bin
```

O pacote baixa o `AVA-Sync-Linux.tar.gz` da release `latest` e instala em `/opt/ava-sync`,
com o comando `ava-sync`, o atalho "AVA Sync" no menu e o ícone.

## Como funciona

- `PKGBUILD` e `ava-sync.desktop` ficam aqui no repositório.
- A cada push na `main`, o job `aur` do `.github/workflows/desktop.yml`:
  1. roda `preparar.sh` (põe `pkgver` = versão do pubspec + build do CI e o sha256 do `.tar.gz`);
  2. monta o pacote num container `archlinux:base-devel` e gera o `.SRCINFO`;
  3. se o secret `AUR_SSH_PRIVATE_KEY` existir, publica no AUR.
- Não edite o pacote direto no AUR: mude aqui e faça merge.

## Configuração (uma vez, pelo dono do repositório)

1. Crie uma conta em <https://aur.archlinux.org/register>.
2. Gere uma chave SSH só para isso (no seu computador):
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/aur -C "ava-sync aur" -N ""
   ```
3. No AUR, em **My Account → SSH Public Key**, cole o conteúdo de `~/.ssh/aur.pub`.
4. No GitHub, em **Settings → Secrets and variables → Actions → New repository secret**,
   crie `AUR_SSH_PRIVATE_KEY` com o conteúdo de `~/.ssh/aur` (a chave **privada**).
5. Rode o workflow "Gerar APK oficial e apps de computador" (ou faça um merge na `main`).
   O primeiro push cria o pacote `ava-sync-bin` no AUR.

## Testar localmente (num Arch)

```bash
cd packaging/aur
makepkg -si           # baixa a release latest, monta e instala
```
