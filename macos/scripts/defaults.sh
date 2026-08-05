#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"

mise_activation='eval "$(/opt/homebrew/bin/mise activate zsh)"'
touch "$HOME/.zshrc"
grep -qxF "$mise_activation" "$HOME/.zshrc" || printf '%s\n' "$mise_activation" >> "$HOME/.zshrc"
mkdir -p "$HOME/.local/bin"
install -m 755 "$script_dir/maintenance.sh" "$HOME/.local/bin/mac-mini-maintenance"

install_hermes() {
  command -v hermes &>/dev/null || return 0

  command -v rtk &>/dev/null && rtk init --agent hermes
  hermes desktop --build-only
  shopt -s nullglob
  hermes_apps=("$HOME"/.hermes/hermes-agent/apps/desktop/release/*/Hermes.app)
  shopt -u nullglob
  (( ${#hermes_apps[@]} == 1 )) || { printf 'Expected one Hermes.app, found %s.\n' "${#hermes_apps[@]}" >&2; exit 1; }
  mkdir -p "$HOME/Applications"
  ln -sfn "${hermes_apps[0]}" "$HOME/Applications/Hermes.app"
}

install_user_agent() {
  local label="$1"
  local source_agent="$repo_dir/launchagents/$label.plist"
  local launch_agent="$HOME/Library/LaunchAgents/$label.plist"

  mkdir -p "$HOME/Library/LaunchAgents"
  if ! cmp -s "$source_agent" "$launch_agent"; then
    launchctl bootout "gui/$(id -u)/$label" &>/dev/null || true
    install -m 644 "$source_agent" "$launch_agent"
  fi
  launchctl print "gui/$(id -u)/$label" &>/dev/null || launchctl bootstrap "gui/$(id -u)" "$launch_agent"
}

install_system_daemon() {
  local source_daemon="$repo_dir/launchdaemons/com.alejandro.daily-softwareupdate.plist"
  local daemon="/Library/LaunchDaemons/com.alejandro.daily-softwareupdate.plist"

  if ! cmp -s "$source_daemon" "$daemon"; then
    sudo install -m 644 "$source_daemon" "$daemon"
  fi
  sudo chown root:wheel "$daemon"
  sudo launchctl bootout system/com.alejandro.daily-softwareupdate &>/dev/null || true
  sudo launchctl bootstrap system "$daemon"
}

install_ssh_policy() {
  local source_policy="$repo_dir/ssh/99-key-only.conf"
  local policy="/etc/ssh/sshd_config.d/99-key-only.conf"

  [[ -s "$HOME/.ssh/authorized_keys" ]] || { printf 'No SSH authorized_keys found; refusing key-only setup.\n' >&2; exit 1; }
  sudo install -d -m 755 /etc/ssh/sshd_config.d
  sudo install -m 644 "$source_policy" "$policy"
  sudo chown root:wheel "$policy"
  sudo /usr/sbin/sshd -t
  sudo systemsetup -setremotelogin off
  sudo systemsetup -setremotelogin on
}

install_hermes
install_user_agent com.alejandro.weekly-maintenance
if command -v hermes &>/dev/null; then
  install_user_agent com.alejandro.hermes-desktop
fi
install_system_daemon
install_ssh_policy

sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

pmset -g custom | grep -q 'autorestart *1' || sudo systemsetup -setrestartpowerfailure on
pmset -g custom | grep -Eq '^[[:space:]]*sleep[[:space:]]+0$' || sudo pmset -a sleep 0
sudo pmset repeat restart MTWRFSU 03:00:00
networksetup -listallnetworkservices | sed '1d;/^\*/d' | while IFS= read -r service; do
  networksetup -getinfo "$service" | grep -q '^IPv6: Off$' || sudo networksetup -setv6off "$service"
done
/usr/sbin/softwareupdate --schedule on
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
