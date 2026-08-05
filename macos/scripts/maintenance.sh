#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if [[ "${1:-}" == "--check" ]]; then
  brew outdated --formula
  command -v hermes &>/dev/null && hermes update --check
  exit
fi

mkdir -p "$HOME/Library/Logs"
exec >>"$HOME/Library/Logs/mac-mini-maintenance.log" 2>&1
printf '\n[%s] daily maintenance\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"

brew update
brew upgrade --formula --yes

if command -v hermes &>/dev/null; then
  update_status="$(hermes update --check)"
  printf '%s\n' "$update_status"
fi
if [[ "${update_status:-}" == *'Update available'* ]]; then
  hermes_app="$HOME/Applications/Hermes.app"
  trap 'open "$hermes_app"' EXIT
  osascript -e 'tell application id "com.nousresearch.hermes" to quit' || true
  for _ in {1..30}; do
    pgrep -f '/Hermes.app/Contents/MacOS/Hermes|hermes_cli.main serve|/hermes desktop' >/dev/null || break
    sleep 1
  done
  if pgrep -f '/Hermes.app/Contents/MacOS/Hermes|hermes_cli.main serve|/hermes desktop' >/dev/null; then
    printf 'Hermes did not stop; update aborted.\n'
    exit 1
  fi
  hermes update --yes
  hermes desktop --build-only
fi