# Machine-wide agent config (APM)

Shared MCP servers and rules for **Cursor**, **OpenCode**, and **Codex**.

Managed MCP servers: `context7`, `n8n-mcp`, `sentry`, `coolify`, `chrome-devtools`, `lighthouse`, `matomo`, `gsc`.

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

## Matomo MCP

1. Ensure the [MCP Server plugin](https://plugins.matomo.org/McpServer) is enabled on `matomo.akbal.dev`.
2. Create an auth token: **Administration → Personal → Security → Auth Tokens**.
3. Add `MATOMO_API_TOKEN` to `~/.config/agent-secrets.env`.
4. Run `agent-sync`.

See [Matomo's Claude Code integration guide](https://matomo.org/faq/integrate-the-mcp-server-with-claude-code/).

## Google Search Console MCP (`gsc`)

Uses [mcp-gsc](https://github.com/AminForou/mcp-gsc) via `uv tool install mcp-search-console` (requires `uv` from Brewfile). Installed to `~/.local/bin/mcp-search-console` for fast Cursor startup (avoids `uvx` cold-download timeouts).

1. In [Google Cloud Console](https://console.cloud.google.com/): enable **Search Console API**, create an **OAuth client ID** (Desktop app), download the JSON.
2. Save it as `~/.config/gsc/client_secrets.json`.
3. Run `agent-sync`, then reload MCP in Cursor (`Cmd+Q` and reopen).
5. On first use, a browser window opens for Google sign-in; the token is cached after that.

## Add an MCP server

```bash
cd ~/Developer/GitHub/AlejandroAkbal/dotfiles/macos/agent
apm install --mcp <name> --transport http --url <url>
agent-sync
```
