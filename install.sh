#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNAME="$(uname)"

echo "==> Installing zsh-quickstart-kit"
if [ ! -d "$HOME/.zsh-quickstart-kit" ]; then
  git clone --depth=1 https://github.com/unixorn/zsh-quickstart-kit.git "$HOME/.zsh-quickstart-kit"
fi
ln -sf "$HOME/.zsh-quickstart-kit/zsh/.zshrc" "$HOME/.zshrc"

echo "==> Symlinking single dotfiles"
FILES=(
  "zshenv"
  "zshenv.local"
  "zsh-quickstart-local-plugins"
  "zpreztorc"
)
for name in "${FILES[@]}"; do
  src="$DOTFILES_DIR/zsh/$name"
  dest="$HOME/.$name"
  [ -f "$src" ] || continue
  if [ -L "$dest" ]; then
    rm -f "$dest"
  elif [ -e "$dest" ]; then
    backup="${dest}.bak.$(date +%s)"
    mv "$dest" "$backup"
    echo "  ! $dest already existed — backed up to $backup"
  fi
  ln -s "$src" "$dest"
done

echo "==> Symlinking fragment directories"
DIRS=(
  "zshrc.pre-plugins.d"
  "zshrc.d"
  "zshrc.pre-plugins.$UNAME.d"
  "zshrc.$UNAME.d"
  "zshrc.work.d"
  "zshrc.add-plugins.d"
)
for name in "${DIRS[@]}"; do
  src="$DOTFILES_DIR/zsh/$name"
  dest="$HOME/.$name"
  [ -d "$src" ] || continue
  if [ -L "$dest" ]; then
    # Already a symlink (possibly to somewhere else) — replace it
    rm -f "$dest"
  elif [ -d "$dest" ]; then
    # Real directory already exists (e.g. zqs created it on install) —
    # ln -s would nest inside it instead of replacing it, so back it up first.
    backup="${dest}.bak.$(date +%s)"
    mv "$dest" "$backup"
    echo "  ! $dest already existed as a real directory — backed up to $backup"
  elif [ -e "$dest" ]; then
    backup="${dest}.bak.$(date +%s)"
    mv "$dest" "$backup"
    echo "  ! $dest already existed — backed up to $backup"
  fi
  ln -s "$src" "$dest"
done

echo "==> Ensuring ~/.zshenv sources .zshenv.local (for untracked per-machine/secrets overrides)"
if [ -f "$HOME/.zshenv" ]; then
  grep -q "zshenv.local" "$HOME/.zshenv" 2>/dev/null || \
    echo '[ -f "$HOME/.zshenv.local" ] && source "$HOME/.zshenv.local"' >> "$HOME/.zshenv"
else
  echo '[ -f "$HOME/.zshenv.local" ] && source "$HOME/.zshenv.local"' > "$HOME/.zshenv"
fi

echo "==> Recreate any secrets files now (NOT tracked in this repo, create them fresh per machine):"
echo "      ~/.zshrc.secrets.local             (interactive secrets — loaded automatically by"
echo "                                          the tracked ~/.zshrc.d/000-secrets-loader.zsh)"
echo "      ~/.zshrc.pre-plugins.secrets.local (same, but needed before plugins load)"
echo "      ~/.zshenv.secrets.local            (secrets needed by scripts/cron, sourced from ~/.zshenv)"

echo "==> Triggering zgenom plugin build"
zsh -i -c 'echo "zqs setup complete"'

echo "==> Done. Restart your terminal or run: exec zsh"
echo "==> Note: zqs behavior toggles (zqs disable-omz-plugins, zqs enable-1password-agent, etc.)"
echo "    are not covered by this repo — re-run the relevant 'zqs ...' commands on this machine"
echo "    if you rely on any of them."
