# Sources an untracked, per-machine secrets file if present.
# ~/.zshrc.pre-plugins.secrets.local is NOT part of this repo — recreate it manually on each machine.
[[ -f ~/.zshrc.pre-plugins.secrets.local ]] && source ~/.zshrc.pre-plugins.secrets.local
