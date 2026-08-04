# AGENTS.md

## Repo shape
- Dotfiles repo, not app code. Main maintained path is macOS bootstrap + machine-wide agent config.
- `make mac` runs `macos/scripts/bootstrap.sh`: Homebrew install/check, `brew bundle`, GNU Stow for `.zshrc`/`.zshenv`/`.aliases`, then OpenCode-only APM deploy if secrets exist.
- Linux and Windows folders are older/manual setup scripts; do not assume parity with macOS flow.

## Commands
- Full macOS setup: `make mac`
- Preview setup: `make mac-dry-run`
- Bootstrap with skips: `macos/scripts/bootstrap.sh --skip-brew --skip-agent`
- Stow shell dotfiles only: `macos/scripts/link_dotfiles.sh`
- Redeploy agent config after editing `macos/agent/apm.yml`: `agent-sync`

## Agent config gotchas
- Active APM target is only `opencode` in `macos/agent/apm.yml`; Cursor/Codex/Claude/Antigravity entries are intentionally commented for rollback.
- `agent-sync` writes OpenCode MCP/rules to `~/opencode.json` and `~/AGENTS.md`, then symlinks `~/.config/opencode/AGENTS.md` to `~/AGENTS.md`; repo-local `AGENTS.md` is separate and should stay focused on this repository.
- `macos/dotfiles/.zshenv` exports `OPENCODE_CONFIG="$HOME/opencode.json"` and sources `~/.config/agent-secrets.env` for MCP secrets.
- Never commit real secrets. Template lives at `macos/agent/secrets.env.example`; real file is `~/.config/agent-secrets.env` with `chmod 600`.
- `macos/agent/apm_modules/` is generated install cache and ignored; do not edit or commit it.

## Editing conventions
- Prefer declarative installs: add macOS tools to `macos/Brewfile`; avoid one-off install scripts when Brew/mise covers it.
- If changing APM deploy behavior, keep `macos/agent/README.md`, `macos/scripts/bootstrap.sh`, and `macos/dotfiles/.aliases` in sync.
- If changing stowed shell files, verify with `macos/scripts/link_dotfiles.sh` or `make mac-dry-run` before claiming done.
