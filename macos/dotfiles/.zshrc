# Dotfiles shell config — aliases live in ~/.aliases

[[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"

# FZF
source <(fzf --zsh)
eval "$(mise activate zsh)"

# Added by Windsurf
export PATH="/Users/alejandro/.codeium/windsurf/bin:$PATH"

# pnpm
export PNPM_HOME="/Users/alejandro/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/alejandro/.lmstudio/bin"
# End of LM Studio CLI section

# add CloudyPad CLI PATH
export PATH=$PATH:/Users/alejandro/.cloudypad/bin

# Added by CodeRabbit CLI installer
export PATH="/Users/alejandro/.local/bin:$PATH"
