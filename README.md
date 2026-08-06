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

### Chrome remote-debugging profile (agent-controlled Chrome)

Chrome 136+ refuses `--remote-debugging-port` on the default profile, so the agent-driven Chrome runs from a separate non-default data dir. This is what makes autonomous (cron) browser control work with no manual consent clicks.

Setup on a new Mac:

```bash
# 1. Create the debug profile as a one-time copy of the real profile
#    (brings cookies/logins across; afterwards Chrome Sync keeps it fresh)
mkdir -p "$HOME/Library/Application Support/ChromeDebug"
cp -R "$HOME/Library/Application Support/Google/Chrome/Default" \
      "$HOME/Library/Application Support/ChromeDebug/"

# 2. Suppress the "controlled by automation" infobar in the debug profile
python3 - <<'EOF'
import json, os
p = os.path.expanduser('~/Library/Application Support/ChromeDebug/Default/Preferences')
d = json.load(open(p))
d.setdefault('browser', {})['suppress_automation_infobar'] = True
d.setdefault('profile', {})['exit_type'] = 'Normal'
d['session'] = {'restore_on_startup': 5, 'restore_on_startup_migrated': True}  # default NTP
tmp = p + '.tmp'
with open(tmp, 'w') as f: json.dump(d, f); f.write('\n')
os.replace(tmp, p)
EOF

# 3. Wrapper app (open -a "Chrome Debug" == launch the agent Chrome)
mkdir -p "$HOME/Applications/Chrome Debug.app/Contents/MacOS"
cat > "$HOME/Applications/Chrome Debug.app/Contents/MacOS/Chrome Debug" <<'EOF'
#!/bin/bash
exec /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --user-data-dir="$HOME/Library/Application Support/ChromeDebug" \
  --remote-debugging-port=9222
EOF
chmod +x "$HOME/Applications/Chrome Debug.app/Contents/MacOS/Chrome Debug"

# 4. Hermes MCP config: ~/.hermes/config.yaml -> mcp_servers.chrome
#    args: ["-y", "chrome-devtools-mcp@latest", "--browserUrl=http://127.0.0.1:9222"]
#    (NOT --autoConnect: it looks for DevToolsActivePort, which Chrome 151+
#     never writes for non-default data dirs)
```

Verify: `lsof -nP -iTCP:9222 -sTCP:LISTEN` shows Chrome listening, `curl http://127.0.0.1:9222/json/version` returns browser metadata, and Hermes `mcp__chrome__list_pages` lists the live tabs.

Notes:
- Sign the debug profile into Google Sync once (manual) so passwords/extensions/bookmarks stay current; cookies do NOT sync, so re-login sites when needed.
- If the gateway was started before the MCP config change, restart it (`hermes gateway restart`) — a stale `hermes serve` process holds old MCP args in memory.
- Keep the debug profile lean: heavy tabs (Discord, Telegram Web) + remote debugging = high CPU. Close tabs you don't need.

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
