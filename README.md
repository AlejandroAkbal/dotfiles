# dotfiles

Scripts and configuration for setting up a fresh OS installation.

## macOS

Quick start on a new Mac:

```bash
git clone https://github.com/AlejandroAkbal/dotfiles.git ~/Developer/GitHub/AlejandroAkbal/dotfiles
cd ~/Developer/GitHub/AlejandroAkbal/dotfiles
make mac
```

`make mac` runs [`macos/scripts/bootstrap.sh`](macos/scripts/bootstrap.sh), which:

1. Ensures Homebrew is installed
2. Applies [`macos/Brewfile`](macos/Brewfile) (stow, apm, rtk, fzf, mise, opencode, uv, gh, jq, ripgrep, Cursor, OpenCode, Codex, Claude Code, iTerm2)
3. Links shell configs via GNU Stow (`~/.zshrc`, `~/.zshenv`, `~/.aliases`)
4. Runs APM `agent-sync` if secrets are configured

Shell env (`OPENCODE_CONFIG`, MCP secrets) is set in stowed `~/.zshenv`, which sources `~/.config/agent-secrets.env`.

### Agent secrets (required for authenticated MCP)

```bash
mkdir -p ~/.config
cp macos/agent/secrets.env.example ~/.config/agent-secrets.env
chmod 600 ~/.config/agent-secrets.env
# Edit and fill in token values, then:
make mac
```

See [`macos/agent/README.md`](macos/agent/README.md) for MCP and rules management.

### Mac mini

Minimal unattended-machine setup:

```bash
make mac-mini
```

This installs Homebrew when missing, applies `macos/Brewfile.mac-mini`, prevents system sleep while retaining the existing display-sleep timer, disables IPv6 on enabled network services, enables restart after power failure, schedules a daily 03:00 restart, and runs daily Homebrew formula updates plus macOS software updates at 00:00. It enables the native macOS Application Firewall with stealth mode and installs an SSH policy that permits public-key authentication only. If Hermes is already installed, it also enables RTK terminal-output filtering and builds the Desktop app, but Desktop launch is manual rather than automatic; otherwise install Hermes and rerun `make mac-mini-defaults`. Signed GUI apps use their own updaters. It also auto-hides the Dock, empties both persistent Dock sections, disables recent apps, and shows Finder filename extensions and the path bar. FileVault is deliberately not enabled because it prevents automatic login after an unattended restart.

Run `make mac-mini-clean` once after setup to remove GarageBand with Mole. Mole defaults to Trash and the target deliberately leaves caches, project artifacts, shared Apple Loops, Trash, and other applications alone. Run `mo clean --dry-run` manually only when deeper cleanup is needed; its cache scan can take several minutes.

Browser policy:

- Use 9router search/fetch for public research.
- Use the persistent native Google Chrome profile for logged-in sites, driven through background computer use. Sign in again or use Chrome Sync on a replacement Mac; never copy raw browser profiles or session files.
- Use Camofox only for isolated or anti-bot browsing.

Open or focus Hermes anytime from Spotlight/Raycast, or run `open -a Hermes`.

After installing or migrating Hermes, restore background computer control:

```bash
hermes computer-use install
hermes tools enable computer_use
cua-driver permissions grant
```

Accessibility and Screen Recording consent must be granted again on each Mac.

### Useful commands

| Command | Purpose |
|---------|---------|
| `make mac` | Full workstation bootstrap (idempotent) |
| `make mac-dry-run` | Preview the workstation bootstrap |
| `make mac-mini` | Install Mac mini packages and apply its defaults |
| `make mac-mini-clean` | Remove GarageBand with Mole |
| `make mac-mini-defaults` | Reapply only Mac mini defaults |
| `make mac-mini-check` | Verify packages and Mac mini defaults |
| `agent-sync` | Re-deploy APM MCP + rules after editing `macos/agent/apm.yml` |
| `macos/scripts/link_dotfiles.sh` | Stow shell configs only |

## Linux

Check the [Linux directory](linux).

## Windows 10

Check the [Windows directory](windows).
