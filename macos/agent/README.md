# Machine-wide agent config (APM)

Shared MCP servers and rules for **Cursor**, **OpenCode**, and **Codex**.

Managed MCP servers: `context7`, `n8n-mcp`, `sentry`, `coolify`, `chrome-devtools`, `lighthouse`.

## Setup

1. Copy `secrets.env.example` to `~/.config/agent-secrets.env` and fill in values (`chmod 600`).
2. Bootstrap dotfiles: `make mac` from repo root (Stow links shell configs + `launchctl setenv` for GUI OpenCode).
3. Run `agent-sync` when editing `apm.yml` (also runs automatically at end of `make mac`).

## What gets deployed

| Asset | Location |
|-------|----------|
| MCP (Cursor) | `~/.cursor/mcp.json` |
| MCP (Codex) | `~/.codex/config.toml` |
| MCP (OpenCode) | `~/opencode.json` (via `OPENCODE_CONFIG` in linked `~/.zshenv`) |
| Rules (Cursor) | `~/.cursor/rules/global.mdc` |
| Rules (Codex/OpenCode) | `~/AGENTS.md` (via `apm compile`) |

OpenCode plugins and provider settings stay in `~/.config/opencode/opencode.json`.

## Add an MCP server

```bash
cd ~/Developer/GitHub/AlejandroAkbal/dotfiles/macos/agent
apm install --mcp <name> --transport http --url <url>
agent-sync
```
