#!/usr/bin/env bash
# Idempotent macOS bootstrap: Homebrew, dotfiles (Stow), APM agent config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$MACOS_DIR/.." && pwd)"
BREWFILE="$MACOS_DIR/Brewfile"
SECRETS_FILE="$HOME/.config/agent-secrets.env"
SECRETS_EXAMPLE="$MACOS_DIR/agent/secrets.env.example"
AGENT_DIR="$MACOS_DIR/agent"

DRY_RUN=false
SKIP_BREW=false
SKIP_AGENT=false

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [OPTIONS]

Bootstrap macOS dotfiles and agent MCP config.

Options:
  --dry-run      Show what would run without making changes
  --skip-brew    Skip Homebrew and Brewfile steps
  --skip-agent   Skip agent-secrets check and agent-sync
  -h, --help     Show this help
EOF
}

log() { printf '[macos-bootstrap] %s\n' "$*"; }
run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --skip-brew) SKIP_BREW=true ;;
    --skip-agent) SKIP_AGENT=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

ensure_xcode_clt() {
  if xcode-select -p &>/dev/null; then
    log "Xcode Command Line Tools: installed"
    return 0
  fi
  log "Xcode Command Line Tools not found — install manually if brew fails:"
  log "  xcode-select --install"
}

ensure_homebrew() {
  if command -v brew &>/dev/null; then
    log "Homebrew: already installed"
    return 0
  fi
  log "Installing Homebrew..."
  run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ "$DRY_RUN" == false ]]; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi
}

ensure_brew_on_path() {
  if command -v brew &>/dev/null; then
    return 0
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  command -v brew &>/dev/null
}

run_brewfile() {
  if [[ "$SKIP_BREW" == true ]]; then
    log "Skipping Brewfile (--skip-brew)"
    return 0
  fi
  ensure_brew_on_path || { log "Homebrew not available; skipping Brewfile"; return 0; }
  log "Applying Brewfile: $BREWFILE"
  run brew bundle install --file "$BREWFILE"
}

prepare_stow_targets() {
  local pkg_dir="$MACOS_DIR/dotfiles"
  local files=(.zshrc .zshenv .aliases)

  for file in "${files[@]}"; do
    local dest="$HOME/$file"
    [[ -e "$dest" || -L "$dest" ]] || continue

    if [[ -L "$dest" ]]; then
      local target
      target="$(readlink "$dest")"
      if [[ "$target" == "$pkg_dir/$file" ]]; then
        log "Removing prior symlink (pre-stow): $dest"
        run rm "$dest"
      elif [[ "$DRY_RUN" == false ]]; then
        log "WARNING: $dest is a symlink to $target — stow may conflict; fix manually if bootstrap fails"
      fi
    elif [[ -f "$dest" && "$DRY_RUN" == false ]]; then
      log "WARNING: $dest is a regular file — stow will refuse to overwrite; move aside or use stow --adopt manually"
    fi
  done
}

stow_dotfiles() {
  if ! command -v stow &>/dev/null; then
    log "GNU Stow not found — install with: brew install stow"
    return 1
  fi
  prepare_stow_targets
  log "Stowing macOS dotfiles into $HOME"
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] stow --dotfiles -v -t %s -d %s dotfiles\n' "$HOME" "$MACOS_DIR"
    return 0
  fi
  if ! stow --dotfiles -v -t "$HOME" -d "$MACOS_DIR" dotfiles 2>/dev/null; then
    log "Restowing dotfiles (stow -R)"
    stow --dotfiles -R -v -t "$HOME" -d "$MACOS_DIR" dotfiles
  fi
}

check_secrets() {
  if [[ "$SKIP_AGENT" == true ]]; then
    log "Skipping secrets check (--skip-agent)"
    return 0
  fi
  if [[ -f "$SECRETS_FILE" ]]; then
    log "Agent secrets: $SECRETS_FILE found"
    return 0
  fi
  log "WARNING: Missing $SECRETS_FILE"
  log "Copy the template and fill in values:"
  log "  mkdir -p ~/.config"
  log "  cp $SECRETS_EXAMPLE $SECRETS_FILE"
  log "  chmod 600 $SECRETS_FILE"
}

run_agent_sync() {
  if [[ "$SKIP_AGENT" == true ]]; then
    log "Skipping agent-sync (--skip-agent)"
    return 0
  fi
  if ! command -v apm &>/dev/null; then
    log "apm not found — skipping agent-sync (install via Brewfile)"
    return 0
  fi
  if [[ ! -f "$SECRETS_FILE" ]]; then
    log "Skipping agent-sync until secrets file exists"
    return 0
  fi
  log "Running agent-sync..."
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] cd %s && source %s && apm install --root ~ --target cursor,opencode,codex && apm compile -t codex,opencode --root ~\n' \
      "$AGENT_DIR" "$SECRETS_FILE"
    return 0
  fi
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
  (
    cd "$AGENT_DIR"
    apm install --root ~ --target cursor,opencode,codex
    apm compile -t codex,opencode --root ~
  )
  log "agent-sync complete"
}

main() {
  log "Repo: $REPO_ROOT"
  ensure_xcode_clt
  ensure_homebrew
  run_brewfile
  stow_dotfiles
  check_secrets
  run_agent_sync
  log "Done."
}

main "$@"
