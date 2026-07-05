#!/usr/bin/env bash
#
# extract-zsh-dotfiles.sh
#
# Extracts your zsh-quickstart-kit (zqs) customizations into a dotfiles repo
# laid out as a GNU Stow package — the same tool zqs's own official bootstrap
# script (bootstrap-zsh-quickstart-kit) uses to install itself. The repo's
# zsh/ directory mirrors $HOME exactly (with leading dots), so `stow` can
# symlink it in directly, folding into any real directories that already
# exist instead of nesting a nested-name symlink inside them.
#
#   Directories (auto-sourced by zqs's own .zshrc, no wiring needed):
#     ~/.zshrc.pre-plugins.d/           - runs before plugins load
#     ~/.zshrc.d/                       - runs after plugins load
#     ~/.zshrc.pre-plugins.<uname>.d/   - OS-specific, before plugins
#     ~/.zshrc.<uname>.d/               - OS-specific, after plugins
#     ~/.zshrc.work.d/                  - work-specific fragments
#     ~/.zshrc.add-plugins.d/           - additive zgenom plugin lines
#
#   Single files:
#     ~/.zshenv                         - NOT managed by zqs; plain zsh startup file,
#                                         sourced by every shell invocation. Tracked
#                                         directly since it's yours, not a zqs override.
#     ~/.zshenv.local                   - untracked, per-machine layer sourced from
#                                         ~/.zshenv (secrets, machine-specific paths)
#     ~/.zsh-quickstart-local-plugins   - FULL plugin list replacement (not additive)
#     ~/.zpreztorc                      - only if you're also using Prezto modules
#
# NOTE: ~/.zshrc.local and ~/.zshrc.pre-plugins.local are NOT real zqs mechanisms
# (an older ".local" override convention was deprecated by zqs in 2022 in favor of
# just using ~/.zshrc.d and ~/.zshrc.pre-plugins.d directly). This script does not
# capture them.
#
# Secrets: interactive-only secrets go in ~/.zshrc.secrets.local, a file living
# directly in $HOME (NOT inside .zshrc.d, so it's never part of the stowed package).
# A tracked loader fragment (.zshrc.d/000-secrets-loader.zsh) sources it
# automatically - this script generates that loader for you. Same pattern for
# ~/.zshrc.pre-plugins.secrets.local if you need secrets before plugins load.
# As a backstop, this script also excludes any fragment file with "secret" in
# its name from the repo copy, in case one ends up directly inside .zshrc.d.
# Secrets needed by non-interactive shells/scripts go in ~/.zshenv.secrets.local
# instead (see the printed guidance below for how that gets wired up).
#
# Usage:
#   ./extract-zsh-dotfiles.sh [target-dir]
#
# Default target-dir is ~/dotfiles

set -euo pipefail

TARGET_DIR="${1:-$HOME/dotfiles}"
ZSH_DIR="$TARGET_DIR/zsh"
UNAME="$(uname)"

echo "==> Extracting zsh setup into: $TARGET_DIR (Stow package layout)"
echo "==> Detected OS: $UNAME"
mkdir -p "$ZSH_DIR"

copied=()
skipped=()

# --- Single files -----------------------------------------------------
# name is used for both source (~/.$name) and destination ($ZSH_DIR/.$name)
FILES=(
  "zshenv"
  "zshenv.local"
  "zsh-quickstart-local-plugins"
  "zpreztorc"
)

echo "==> Copying single dotfiles"
for name in "${FILES[@]}"; do
  src="$HOME/.$name"
  dest="$ZSH_DIR/.$name"
  if [ -e "$src" ] && [ ! -L "$src" ]; then
    cp "$src" "$dest"
    copied+=("$src")
  elif [ -L "$src" ]; then
    echo "  ! $src is already a symlink — skipping (assuming it's already managed)"
    skipped+=("$src (symlink)")
  else
    skipped+=("$src (not found)")
  fi
done

# --- Fragment directories -----------------------------------------------
DIRS=(
  "zshrc.pre-plugins.d"
  "zshrc.d"
  "zshrc.pre-plugins.$UNAME.d"
  "zshrc.$UNAME.d"
  "zshrc.work.d"
  "zshrc.add-plugins.d"
)

echo "==> Copying fragment directories"
excluded_secrets=()
for name in "${DIRS[@]}"; do
  src="$HOME/.$name"
  dest="$ZSH_DIR/.$name"
  if [ -d "$src" ] && [ ! -L "$src" ]; then
    mkdir -p "$dest"
    cp -R "$src/." "$dest/"
    copied+=("$src/*")

    # Exclude any fragment file that looks like a secrets file from the repo copy.
    while IFS= read -r -d '' f; do
      rel="${f#$dest/}"
      rm -f "$f"
      excluded_secrets+=(".$name/$rel")
    done < <(find "$dest" -maxdepth 1 -type f -iname '*secret*' ! -name '000-secrets-loader.zsh' -print0)

    if [ -z "$(ls -A "$dest" 2>/dev/null)" ]; then
      touch "$dest/.gitkeep"
      echo "  (added .gitkeep — $src was empty)"
    fi
  elif [ -L "$src" ]; then
    echo "  ! $src is already a symlink — skipping (assuming it's already managed)"
    skipped+=("$src (symlink)")
  else
    skipped+=("$src (not found)")
  fi
done

# --- Secrets loader fragments -------------------------------------------
# Since there's no ~/.zshrc.local for zqs to source, secrets get a tracked
# loader fragment inside ~/.zshrc.d (and ~/.zshrc.pre-plugins.d, if needed),
# pointing at an untracked file living directly in $HOME.
add_secrets_loader() {
  local dest_dir="$1" secrets_filename="$2"
  local loader="$dest_dir/000-secrets-loader.zsh"
  if [ ! -f "$loader" ]; then
    mkdir -p "$dest_dir"
    cat > "$loader" <<EOF
# Sources an untracked, per-machine secrets file if present.
# ~/.$secrets_filename is NOT part of this repo — recreate it manually on each machine.
[[ -f ~/.$secrets_filename ]] && source ~/.$secrets_filename
EOF
    echo "  Wrote loader: $loader (sources ~/.$secrets_filename)"
    rm -f "$dest_dir/.gitkeep" 2>/dev/null
  fi
}

echo "==> Ensuring secrets-loader fragments exist"
add_secrets_loader "$ZSH_DIR/.zshrc.d" "zshrc.secrets.local"
add_secrets_loader "$ZSH_DIR/.zshrc.pre-plugins.d" "zshrc.pre-plugins.secrets.local"

# --- Sanity check: full plugin replacement vs add-plugins.d --------------
if [ -e "$ZSH_DIR/.zsh-quickstart-local-plugins" ] && [ -d "$ZSH_DIR/.zshrc.add-plugins.d" ] \
   && [ -n "$(ls -A "$ZSH_DIR/.zshrc.add-plugins.d" 2>/dev/null)" ]; then
  echo ""
  echo "  ⚠️  You have BOTH ~/.zsh-quickstart-local-plugins AND ~/.zshrc.add-plugins.d/ content."
  echo "     zsh-quickstart-local-plugins completely REPLACES the plugin list, so files in"
  echo "     zshrc.add-plugins.d are likely being ignored. Confirm which one you actually want."
  echo ""
fi

# --- Secret scanning -------------------------------------------------------
echo "==> Scanning copied files for likely secrets"
SECRET_PATTERN='(API_KEY|SECRET|TOKEN|PASSWORD|AWS_ACCESS_KEY|AWS_SECRET|PRIVATE_KEY|CLIENT_SECRET)'
flagged=()

while IFS= read -r -d '' file; do
  if grep -EIq "$SECRET_PATTERN" "$file" 2>/dev/null; then
    flagged+=("$file")
  fi
done < <(find "$ZSH_DIR" -type f -print0)

if [ "${#excluded_secrets[@]}" -gt 0 ]; then
  echo ""
  echo "  Excluded these files entirely (filename contained \"secret\") — they were"
  echo "  NOT copied into the repo, since ~/.zshrc.d and ~/.zshrc.pre-plugins.d are"
  echo "  auto-sourced by zqs and don't need a repo copy for secrets to work:"
  for f in "${excluded_secrets[@]}"; do
    echo "     - $f"
  done
fi

if [ "${#flagged[@]}" -gt 0 ]; then
  echo ""
  echo "  ⚠️  Possible secrets found in these copied files — review before committing:"
  for f in "${flagged[@]}"; do
    echo "     - $f"
    grep -EIn "$SECRET_PATTERN" "$f" | sed 's/^/         /'
  done
  echo ""
  echo "  Split these based on where they're needed:"
  echo "    - Only used at your interactive prompt (aliases, manual CLI calls)"
  echo "      -> move to ~/.zshrc.secrets.local (lives in \$HOME, not in .zshrc.d,"
  echo "         so it's never part of the stowed package). The tracked loader"
  echo "         fragment .zshrc.d/000-secrets-loader.zsh sources it automatically —"
  echo "         this script has already generated that loader for you."
  echo "    - Needed by scripts, cron jobs, or non-interactive shells (e.g. TF_VAR_*,"
  echo "      AWS_PROFILE used by automation, CI tokens)"
  echo "      -> move to untracked ~/.zshenv.secrets.local, sourced from ~/.zshenv:"
  echo '         [ -f "$HOME/.zshenv.secrets.local" ] && source "$HOME/.zshenv.secrets.local"'
  echo ""
fi

# --- install.sh --------------------------------------------------------
INSTALL_SCRIPT="$TARGET_DIR/install.sh"
if [ ! -f "$INSTALL_SCRIPT" ]; then
  cat > "$INSTALL_SCRIPT" <<'EOF'
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
EOF
  chmod +x "$INSTALL_SCRIPT"
  echo "==> Wrote $INSTALL_SCRIPT"
else
  echo "==> $INSTALL_SCRIPT already exists — leaving it as-is"
fi

# --- .gitignore ----------------------------------------------------------
GITIGNORE="$TARGET_DIR/.gitignore"
if [ ! -f "$GITIGNORE" ]; then
  cat > "$GITIGNORE" <<'EOF'
.DS_Store
*.zwc
*secret*
zshenv.secrets.local
EOF
  echo "==> Wrote $GITIGNORE"
fi

# --- Summary ---------------------------------------------------------------
echo ""
echo "==> Done."
echo ""
echo "Copied:"
for c in "${copied[@]}"; do echo "  - $c"; done
echo ""
echo "Skipped:"
for s in "${skipped[@]}"; do echo "  - $s"; done
echo ""
if [ "${#excluded_secrets[@]}" -gt 0 ]; then
  echo "Excluded from repo (filename contained \"secret\" — recreate manually per machine):"
  for e in "${excluded_secrets[@]}"; do echo "  - $e"; done
  echo ""
fi
echo "Not covered by this script (zqs behavior toggles, e.g. zqs disable-omz-plugins,"
echo "zqs enable-1password-agent) — these are stored as marker files/settings and are"
echo "better reproduced on a new machine by re-running the relevant 'zqs ...' command."
echo ""
echo "Next steps:"
echo "  1. Review $ZSH_DIR for anything machine-specific or secret."
echo "  2. cd $TARGET_DIR && git init && git add . && git commit -m 'Extract zqs dotfiles'"
echo "  3. git remote add origin <your-repo-url> && git push -u origin main"
echo "  4. On a new machine: git clone <your-repo-url> ~/dotfiles && ~/dotfiles/install.sh"
echo "     (install.sh uses GNU Stow to symlink both the kit and your customizations,"
echo "     mirroring zqs's own official bootstrap script's approach.)"
