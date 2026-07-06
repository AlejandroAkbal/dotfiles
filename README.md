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
2. Applies [`macos/Brewfile`](macos/Brewfile) (stow, apm, fzf, mise, opencode, uv, gh, jq, ripgrep, Cursor, OpenCode, Codex, iTerm2)
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

### Useful commands

| Command | Purpose |
|---------|---------|
| `make mac` | Full bootstrap (idempotent) |
| `make mac-dry-run` | Preview bootstrap steps |
| `agent-sync` | Re-deploy APM MCP + rules after editing `macos/agent/apm.yml` |
| `macos/scripts/link_dotfiles.sh` | Stow shell configs only |

## Linux

Check the [Linux directory](linux).

## Windows 10

Check the [Windows directory](windows).
