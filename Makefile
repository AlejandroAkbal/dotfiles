.PHONY: mac mac-dry-run mac-mini mac-mini-clean mac-mini-defaults mac-mini-check

mac:
	@bash macos/scripts/bootstrap.sh

mac-dry-run:
	@bash macos/scripts/bootstrap.sh --dry-run

mac-mini:
	@command -v brew >/dev/null || /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	@brew_bin="$$(command -v brew || true)"; test -n "$$brew_bin" || for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do test -x "$$candidate" && brew_bin="$$candidate" && break; done; test -n "$$brew_bin"; "$$brew_bin" bundle install --file macos/Brewfile.mac-mini
	@bash macos/scripts/defaults.sh

mac-mini-defaults:
	@bash macos/scripts/defaults.sh

mac-mini-clean:
	@command -v mo >/dev/null || { echo "Mole is required; run make mac-mini first" >&2; exit 1; }
	@if [ -d /Applications/GarageBand.app ]; then mo uninstall GarageBand; else echo "GarageBand is already absent"; fi

mac-mini-check:
	@brew bundle check --file macos/Brewfile.mac-mini
	@test "$$(defaults read com.apple.dock autohide)" = 1
	@test "$$(defaults read com.apple.dock show-recents)" = 0
	@test "$$(defaults read com.apple.dock persistent-apps | tr -d '[:space:]')" = '()'
	@test "$$(defaults read com.apple.dock persistent-others | tr -d '[:space:]')" = '()'
	@pmset -g custom | grep -q 'autorestart *1'
	@pmset -g custom | grep -Eq '^[[:space:]]*sleep[[:space:]]+0$$'
	@test -z "$$(pmset -g sched | grep -E '^repeating (restart|wake)' || true)"
	@networksetup -listallnetworkservices | sed '1d;/^\*/d' | while IFS= read -r service; do networksetup -getinfo "$$service" | grep -q '^IPv6: Off$$' || exit 1; done
	@test "$$(defaults read com.apple.finder AppleShowAllExtensions)" = 1
	@test "$$(defaults read com.apple.finder ShowPathbar)" = 1
	@grep -q 'mise activate zsh' "$$HOME/.zshrc"
	@plutil -lint "$$HOME/Library/LaunchAgents/com.alejandro.weekly-maintenance.plist" >/dev/null
	@launchctl print "gui/$$(id -u)/com.alejandro.weekly-maintenance" >/dev/null
	@"$$HOME/.local/bin/mac-mini-maintenance" --check >/dev/null
	@cmp -s macos/scripts/mac-mini-backup "$$HOME/.local/bin/mac-mini-backup"
	@cmp -s macos/restic/macmini-excludes.txt "$$HOME/.config/restic/macmini-excludes.txt"
	@cmp -s macos/launchagents/com.alejandro.mac-mini-backup.plist "$$HOME/Library/LaunchAgents/com.alejandro.mac-mini-backup.plist"
	@test "$$(readlink "$$HOME/.hermes/scripts/mac-mini-backup-watchdog.py")" = "$$(pwd)/macos/scripts/mac-mini-backup-watchdog.py"
	@plutil -lint "$$HOME/Library/LaunchAgents/com.alejandro.mac-mini-backup.plist" >/dev/null
	@launchctl print "gui/$$(id -u)/com.alejandro.mac-mini-backup" >/dev/null
	@test "$$(defaults read com.apple.finder AppleShowAllExtensions)" = 1
	@/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -q 'enabled'
	@/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode | grep -q 'on'
	@plutil -lint macos/launchdaemons/com.alejandro.daily-softwareupdate.plist >/dev/null
	@test -f /Library/LaunchDaemons/com.alejandro.daily-softwareupdate.plist
	@launchctl print system/com.alejandro.daily-softwareupdate >/dev/null
	@test -f /etc/ssh/sshd_config.d/99-key-only.conf
	@grep -qx 'PasswordAuthentication no' /etc/ssh/sshd_config.d/99-key-only.conf
	@grep -qx 'AuthenticationMethods publickey' /etc/ssh/sshd_config.d/99-key-only.conf
