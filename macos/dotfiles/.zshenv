# Sourced for every zsh session (interactive and non-interactive).
# Ensures OpenCode MCP config is available outside .zshrc-only setups.

[ -f "$HOME/.config/agent-secrets.env" ] && source "$HOME/.config/agent-secrets.env"
export OPENCODE_CONFIG="$HOME/opencode.json"
