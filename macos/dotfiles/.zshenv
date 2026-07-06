# Sourced for every zsh session (interactive and non-interactive).
# MCP secrets + OpenCode config path for Cursor, OpenCode, and Codex.

[ -f "$HOME/.config/agent-secrets.env" ] && source "$HOME/.config/agent-secrets.env"
export OPENCODE_CONFIG="$HOME/opencode.json"
