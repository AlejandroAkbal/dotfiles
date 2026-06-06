#!/usr/bin/env bash
# Thin wrapper — prefer: make mac  (or macos/scripts/bootstrap.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v stow &>/dev/null; then
  echo "GNU Stow is required. Install with: brew install stow" >&2
  exit 1
fi

stow --dotfiles -v -t "$HOME" -d "$MACOS_DIR" dotfiles
echo "Dotfiles stowed. For full setup run: make mac"
