#!/usr/bin/env bash
set -euo pipefail

mise_activation='eval "$(/opt/homebrew/bin/mise activate zsh)"'
touch "$HOME/.zshrc"
grep -qxF "$mise_activation" "$HOME/.zshrc" || printf '%s\n' "$mise_activation" >> "$HOME/.zshrc"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents"
install -m 755 "$script_dir/maintenance.sh" "$HOME/.local/bin/mac-mini-maintenance"
labels=(com.alejandro.weekly-maintenance)
if command -v hermes &>/dev/null; then
  command -v rtk &>/dev/null && rtk init --agent hermes
  hermes desktop --build-only
  shopt -s nullglob
  hermes_apps=("$HOME"/.hermes/hermes-agent/apps/desktop/release/*/Hermes.app)
  shopt -u nullglob
  (( ${#hermes_apps[@]} == 1 )) || { printf 'Expected one Hermes.app, found %s.\n' "${#hermes_apps[@]}" >&2; exit 1; }
  mkdir -p "$HOME/Applications"
  ln -sfn "${hermes_apps[0]}" "$HOME/Applications/Hermes.app"
  labels+=(com.alejandro.hermes-desktop)
fi
for label in "${labels[@]}"; do
  source_agent="$script_dir/../launchagents/$label.plist"
  launch_agent="$HOME/Library/LaunchAgents/$label.plist"
  if ! cmp -s "$source_agent" "$launch_agent"; then
    launchctl bootout "gui/$(id -u)/$label" &>/dev/null || true
    install -m 644 "$source_agent" "$launch_agent"
  fi
  launchctl print "gui/$(id -u)/$label" &>/dev/null || launchctl bootstrap "gui/$(id -u)" "$launch_agent"
done

pmset -g custom | grep -q 'autorestart *1' || sudo systemsetup -setrestartpowerfailure on
pmset -g custom | grep -Eq '^[[:space:]]*sleep[[:space:]]+0$' || sudo pmset -a sleep 0
networksetup -listallnetworkservices | sed '1d;/^\*/d' | while IFS= read -r service; do
  networksetup -getinfo "$service" | grep -q '^IPv6: Off$' || sudo networksetup -setv6off "$service"
done
for domain in com.p5sys.jump.connect dev.kdrag0n.MacVirt; do
  defaults write "$domain" SUEnableAutomaticChecks -bool true
  defaults write "$domain" SUAutomaticallyUpdate -bool true
done
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock persistent-apps -array
defaults write com.apple.dock persistent-others -array
defaults write com.apple.finder AppleShowAllExtensions -bool true
defaults write com.apple.finder ShowPathbar -bool true
killall Dock
killall Finder
