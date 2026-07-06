# Machine-wide agent config (APM)

Shared MCP servers and rules for **Cursor**, **OpenCode**, and **Codex**.

Managed MCP servers: `context7`, `sentry`, `chrome-devtools`, `lighthouse`, `gsc`, `brave-search`, `maestro` (plus optional `n8n-mcp`, `coolify`, `matomo` when uncommented in `apm.yml`).

## Setup

1. Copy `secrets.env.example` to `~/.config/agent-secrets.env` and fill in values (`chmod 600`).
2. Bootstrap dotfiles: `make mac` from repo root (Stow links `~/.zshenv`, which exports `OPENCODE_CONFIG` and sources MCP secrets).
3. Run `agent-sync` when editing `apm.yml` (also runs automatically at end of `make mac`).

`agent-sync` sources `~/.config/agent-secrets.env` before `apm install`, so HTTP MCP auth (`n8n-mcp`, `coolify`, `matomo`) is written into each editor config at install time. `brave-search` loads `BRAVE_API_KEY` from that same secrets file at server start via `dotenv-cli` (Cursor does not resolve `${env:VAR}` in stdio `env` blocks).

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

Uses [mcp-gsc](https://github.com/AminForou/mcp-gsc) via `uvx mcp-search-console` (requires `uv` from Brewfile).

1. In [Google Cloud Console](https://console.cloud.google.com/): enable **Search Console API**, create an **OAuth client ID** (Desktop app), download the JSON.
2. Save it as `~/.config/gsc/client_secrets.json`.
3. Run `agent-sync`, then reload MCP in Cursor (`Cmd+Q` and reopen).
5. On first use, a browser window opens for Google sign-in; the token is cached after that.

## Brave Search MCP (`brave-search`)

Uses Brave's official [`@brave/brave-search-mcp-server`](https://github.com/brave/brave-search-mcp-server) package.

1. Get an API key from [Brave Search API](https://brave.com/search/api/).
2. Add `BRAVE_API_KEY` to `~/.config/agent-secrets.env`.
3. Run `agent-sync`, then reload MCP in Cursor.

## Maestro MCP (`maestro`)

Mobile UI testing via [Maestro](https://maestro.mobile.dev/) — same config as Verso's former project-level `.cursor/mcp.json`, deployed globally.

Requires `maestro` and `openjdk` from Brewfile. No secrets. Run `agent-sync` after install.

Works in Cursor and OpenCode via APM. Codex uses the same `apm.yml` entry; if a new MCP does not appear in `codex mcp list`, re-run `agent-sync` or add it with `codex mcp add` using the same command/env from `apm.yml`.

## Add an MCP server

```bash
cd ~/Developer/GitHub/AlejandroAkbal/dotfiles/macos/agent
apm install --mcp <name> --transport http --url <url>
agent-sync
```
