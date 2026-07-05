#!/usr/bin/env bash
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNAME="$(uname)"
ZGENOM_DIR="${ZGENOM_DIR:-$HOME/.zgenom}"
ZQS_DIR="${ZQS_DIR:-$HOME/.zsh-quickstart-kit}"
BACKUP_ROOT="$HOME/.dotfiles-install-backups/$(date +%Y%m%d-%H%M%S)"

has() { command -v "$@" >/dev/null 2>&1; }

# Parses GNU Stow's dry-run output for the exact conflicting paths (Stow
# reports these as "existing target is neither a link nor a directory: X"
# or "existing target is not owned by stow: X") and backs up precisely those
# files, preserving their relative path — including ones nested inside a
# directory that otherwise already exists on both sides. This is more
# reliable than only checking top-level entries, since a file we already
# copied into the repo (with the same name as what's still sitting in
# $HOME) is a leaf-level conflict, not a directory-level one.
backup_stow_conflicts_from_output() {
  local output="$1"
  local relpath target backup_path found=0
  while IFS= read -r relpath; do
    [ -n "$relpath" ] || continue
    target="$HOME/$relpath"
    if [ -e "$target" ] || [ -L "$target" ]; then
      backup_path="$BACKUP_ROOT/$relpath"
      mkdir -p "$(dirname "$backup_path")"
      mv "$target" "$backup_path"
      echo "  Backing up conflicting $target to $backup_path"
      found=1
    fi
  done < <(echo "$output" | sed -n 's/^.*existing target [^:]*: //p')
  [ "$found" -eq 1 ]
}

stow_package() {
  local package_dir="$1" label="$2"
  if ! has stow; then
    echo "  ⚠️  GNU Stow is not installed (brew install stow / apt-get install stow)."
    echo "     Cannot symlink $label without it."
    return 1
  fi
  local pkg_parent pkg_name dryrun_output
  pkg_parent="$(dirname "$package_dir")"
  pkg_name="$(basename "$package_dir")"
  dryrun_output="$(cd "$pkg_parent" && stow -n --target="$HOME" "$pkg_name" 2>&1)"
  if [ $? -eq 0 ]; then
    (cd "$pkg_parent" && stow --target="$HOME" "$pkg_name")
    echo "  ✓ $label stowed into \$HOME."
    return 0
  fi
  echo "  Stow dry-run reported conflicts for $label — backing up conflicting files and retrying."
  if backup_stow_conflicts_from_output "$dryrun_output"; then
    dryrun_output="$(cd "$pkg_parent" && stow -n --target="$HOME" "$pkg_name" 2>&1)"
    if [ $? -eq 0 ]; then
      (cd "$pkg_parent" && stow --target="$HOME" "$pkg_name")
      echo "  ✓ $label stowed into \$HOME after resolving conflicts."
      return 0
    fi
    # A second pass catches conflicts only revealed after the first backup
    # (e.g. a directory that becomes empty and now folds differently).
    if backup_stow_conflicts_from_output "$dryrun_output"; then
      if (cd "$pkg_parent" && stow --target="$HOME" "$pkg_name"); then
        echo "  ✓ $label stowed into \$HOME after resolving conflicts."
        return 0
      fi
    fi
  fi
  echo "  ⚠️  Stow still failed for $label. Remaining output:"
  echo "$dryrun_output" | sed 's/^/     /'
  echo "     Inspect manually — anything already backed up is under: $BACKUP_ROOT"
}

echo "==> Installing zgenom"
if [ ! -d "$ZGENOM_DIR" ]; then
  git clone https://github.com/jandamm/zgenom.git "$ZGENOM_DIR"
else
  echo "  zgenom already present at $ZGENOM_DIR"
fi

echo "==> Installing zsh-quickstart-kit"
if [ ! -d "$ZQS_DIR" ]; then
  git clone --depth=1 https://github.com/unixorn/zsh-quickstart-kit.git "$ZQS_DIR"
else
  echo "  zsh-quickstart-kit already present at $ZQS_DIR"
fi

echo "==> Stowing zsh-quickstart-kit's own dotfiles (.zshrc, .zsh_aliases, etc.)"
stow_package "$ZQS_DIR/zsh" "zsh-quickstart-kit"

echo "==> Stowing this dotfiles repo's zsh customizations"
stow_package "$DOTFILES_DIR/zsh" "your dotfiles zsh/ package"

echo "==> Ensuring ~/.zshenv sources .zshenv.local (for untracked per-machine/secrets overrides)"
if [ -f "$HOME/.zshenv" ]; then
  grep -q "zshenv.local" "$HOME/.zshenv" 2>/dev/null || \
    echo '[ -f "$HOME/.zshenv.local" ] && source "$HOME/.zshenv.local"' >> "$HOME/.zshenv"
else
  echo '[ -f "$HOME/.zshenv.local" ] && source "$HOME/.zshenv.local"' > "$HOME/.zshenv"
fi

echo "==> Recreate any secrets files now (NOT tracked in this repo, create them fresh per machine):"
echo "      ~/.zshrc.secrets.local             (interactive secrets — loaded automatically by"
echo "                                          the tracked .zshrc.d/000-secrets-loader.zsh)"
echo "      ~/.zshrc.pre-plugins.secrets.local (same, but needed before plugins load)"
echo "      ~/.zshenv.secrets.local            (secrets needed by scripts/cron, sourced from ~/.zshenv)"

if has zsh; then
  echo "==> Triggering zgenom plugin build"
  zsh -i -c 'echo "zqs setup complete"'
else
  echo "==> zsh not found on PATH — install it, then open a new zsh session to finish setup."
fi

echo "==> Done. Restart your terminal or run: exec zsh"
echo "==> Note: zqs behavior toggles (zqs disable-omz-plugins, zqs enable-1password-agent, etc.)"
echo "    are not covered by this repo — re-run the relevant 'zqs ...' commands on this machine"
echo "    if you rely on any of them."
if [ -d "$BACKUP_ROOT" ]; then
  echo "==> Any conflicting pre-existing files were backed up to: $BACKUP_ROOT"
fi
