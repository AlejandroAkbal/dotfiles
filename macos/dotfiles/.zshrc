# Dotfiles shell config — aliases live in ~/.aliases

[[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"

# FZF
source <(fzf --zsh)
eval "$(mise activate zsh)"

# pnpm
export PNPM_HOME="/Users/alejandro/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end

# add CloudyPad CLI PATH
export PATH=$PATH:/Users/alejandro/.cloudypad/bin

# Added by CodeRabbit CLI installer
export PATH="/Users/alejandro/.local/bin:$PATH"
