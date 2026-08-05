.PHONY: mac mac-dry-run mac-mini mac-mini-clean mac-mini-defaults mac-mini-check

mac:
	@bash macos/scripts/bootstrap.sh

mac-dry-run:
	@bash macos/scripts/bootstrap.sh --dry-run

mac-mini:
	@command -v brew >/dev/null || /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	@"$$(command -v brew || printf /opt/homebrew/bin/brew)" bundle install --file macos/Brewfile.mac-mini
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
	@networksetup -listallnetworkservices | sed '1d;/^\*/d' | while IFS= read -r service; do networksetup -getinfo "$$service" | grep -q '^IPv6: Off$$' || exit 1; done
	@test "$$(defaults read com.apple.finder AppleShowAllExtensions)" = 1
	@test "$$(defaults read com.apple.finder ShowPathbar)" = 1
	@grep -q 'mise activate zsh' "$$HOME/.zshrc"
	@plutil -lint "$$HOME/Library/LaunchAgents/com.alejandro.weekly-maintenance.plist" >/dev/null
	@launchctl print "gui/$$(id -u)/com.alejandro.weekly-maintenance" >/dev/null
	@"$$HOME/.local/bin/mac-mini-maintenance" --check >/dev/null
	@if command -v hermes >/dev/null && command -v rtk >/dev/null; then hermes plugins list --plain --no-bundled | grep -q 'enabled.*rtk-rewrite'; fi
	@if command -v hermes >/dev/null; then test -L "$$HOME/Applications/Hermes.app"; plutil -lint "$$HOME/Library/LaunchAgents/com.alejandro.hermes-desktop.plist" >/dev/null; launchctl print "gui/$$(id -u)/com.alejandro.hermes-desktop" >/dev/null; codesign --verify --deep --strict "$$HOME/Applications/Hermes.app"; ! xattr -p com.apple.quarantine "$$HOME/Applications/Hermes.app" >/dev/null 2>&1; fi
