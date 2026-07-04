#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing zsh-quickstart-kit"
if [ ! -d "$HOME/.zsh-quickstart-kit" ]; then
  git clone --depth=1 https://github.com/unixorn/zsh-quickstart-kit.git "$HOME/.zsh-quickstart-kit"
fi
ln -sf "$HOME/.zsh-quickstart-kit/zsh/.zshrc" "$HOME/.zshrc"

echo "==> Symlinking customizations"
ln -sf "$DOTFILES_DIR/zsh/zshrc.local"             "$HOME/.zshrc.local"
ln -sf "$DOTFILES_DIR/zsh/zshrc.pre-plugins.local" "$HOME/.zshrc.pre-plugins.local"
[ -f "$DOTFILES_DIR/zsh/zpreztorc" ] && ln -sf "$DOTFILES_DIR/zsh/zpreztorc" "$HOME/.zpreztorc"
[ -f "$DOTFILES_DIR/zsh/zshenv.local" ] && ln -sf "$DOTFILES_DIR/zsh/zshenv.local" "$HOME/.zshenv.local"
ln -sf "$DOTFILES_DIR/zsh/zshrc.d"                 "$HOME/.zshrc.d"

echo "==> Ensuring ~/.zshenv sources .zshenv.local"
if [ -f "$HOME/.zshenv" ]; then
  grep -q "zshenv.local" "$HOME/.zshenv" 2>/dev/null || \
    echo '[ -f "$HOME/.zshenv.local" ] && source "$HOME/.zshenv.local"' >> "$HOME/.zshenv"
else
  echo '[ -f "$HOME/.zshenv.local" ] && source "$HOME/.zshenv.local"' > "$HOME/.zshenv"
fi

echo "==> If you keep secrets separately, create these now (both are gitignored, NOT tracked in this repo):"
echo "      ~/.zshrc.secrets.local   (interactive-only secrets, sourced from .zshrc)"
echo "      ~/.zshenv.secrets.local  (secrets needed by scripts/cron, sourced from .zshenv)"

echo "==> Triggering zgenom plugin build"
zsh -i -c 'echo "zqs setup complete"'

echo "==> Done. Restart your terminal or run: exec zsh"
