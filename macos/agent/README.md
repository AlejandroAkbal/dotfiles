# Machine-wide agent config (APM)

Shared MCP servers and rules for **Cursor**, **OpenCode**, **Codex**, **Claude Code**, and **Antigravity**.

Managed MCP servers: `context7`, `9router-search`, `sentry`, `chrome-devtools`, `lighthouse`, `gsc`, `maestro` (plus optional `exa`, `brave-search`, `n8n-mcp`, `coolify`, `matomo` when uncommented in `apm.yml`).

## Setup

1. Copy `secrets.env.example` to `~/.config/agent-secrets.env` and fill in values (`chmod 600`).
2. Bootstrap dotfiles: `make mac` from repo root (Stow links `~/.zshenv`, which exports `OPENCODE_CONFIG` and sources MCP secrets).
3. Run `agent-sync` when editing `apm.yml` (also runs automatically at end of `make mac`).

`agent-sync` sources `~/.config/agent-secrets.env` before `apm install`, so HTTP MCP auth (`n8n-mcp`, `coolify`, `matomo`) is written into each editor config at install time. Some stdio MCPs may also need runtime env workarounds when clients do not resolve `${env:VAR}` consistently.

## What gets deployed

| Asset | Location |
|-------|----------|
| MCP (Cursor) | `~/.cursor/mcp.json` |
| MCP (Codex) | `~/.codex/config.toml` |
| MCP (OpenCode) | `~/opencode.json` (via `OPENCODE_CONFIG` in linked `~/.zshenv`) |
| MCP (Claude Code) | `~/.mcp.json` |
| MCP (Antigravity) | `~/.gemini/config/mcp_config.json` |
| Rules (Cursor) | `~/.cursor/rules/*.mdc` |
| Rules (Claude Code) | `~/.claude/rules/*.md` |
| Rules (Codex/OpenCode) | `~/AGENTS.md` (via `apm compile`) |
| Rules (Antigravity) | `~/.agents/rules/*.md` + `~/AGENTS.md` (via `apm compile`) |
| Skills (cross-tool) | `~/.agents/skills/*` (Cursor, Codex, OpenCode, Antigravity) |
| Skills (Claude Code) | `~/.claude/skills/*` |

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

## 9router MCP (`9router-search`)

Search via [9router MCP](https://github.com/dipandhali2021/9router-mcp).

1. Add `ROUTER_BASE_URL` and `ROUTER_API_KEY` to `~/.config/agent-secrets.env`.
2. Run `agent-sync`, then reload MCP in each editor.

The MCP loads credentials at runtime via `dotenv-cli` (same pattern as the old `brave-search` setup).

**Current limitation:** upstream `9router-mcp` hardcodes the search tool model to `openclaw-search` and fetch to `openclaw-fetch`.

## Exa MCP (`exa`)

Replaced by `9router-search` for now. The old config is still preserved as commented lines in `apm.yml` in case you want to roll back.

## Brave Search MCP (`brave-search`)

Replaced by `9router-search` for now. The old config is still preserved as commented lines in `apm.yml` in case you want to roll back.

## Maestro MCP (`maestro`)

Mobile UI testing via [Maestro](https://maestro.mobile.dev/) — same config as Verso's former project-level `.cursor/mcp.json`, deployed globally.

Requires `maestro` and `openjdk` from Brewfile. No secrets. Run `agent-sync` after install.

Works in Cursor and OpenCode via APM. Codex uses the same `apm.yml` entry; if a new MCP does not appear in `codex mcp list`, re-run `agent-sync` or add it with `codex mcp add` using the same command/env from `apm.yml`.

## Skills

APM deploys [Agent Skills](https://agentskills.io) to every target in `apm.yml`. Add a GitHub package under `dependencies.apm`:

```yaml
dependencies:
  apm:
    - shadcn/improve
    - git: Leonxlnx/taste-skill
      path: skills/taste-skill
    - git: uditgoenka/autoresearch
      path: .agents/skills/autoresearch
    - addyosmani/agent-skills
```

Then run `agent-sync`. Skills land in `~/.agents/skills/` (shared by Cursor, Codex, OpenCode, Antigravity) and `~/.claude/skills/` (Claude Code).

### improve (`shadcn/improve`)

Codebase audit skill — writes implementation plans in `plans/` for cheaper models to execute. Invoke with `/improve` (or `/improve quick`, `/improve security`, etc.). See [shadcn/improve](https://github.com/shadcn/improve).

### taste-skill (`Leonxlnx/taste-skill`)

Anti-slop frontend design skill for landing pages, portfolios, and redesigns. Only `skills/taste-skill` is installed (not the full 13-skill pack). See [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill).

### autoresearch (`uditgoenka/autoresearch`)

Autonomous iteration loop — modify, verify, keep/discard against a metric. Invoke with `/autoresearch` (plus subcommands like `plan`, `debug`, `security`, `ship`). Installed via path dependency (the repo root is a hybrid plugin; the skill lives under `.agents/skills/autoresearch`). See [uditgoenka/autoresearch](https://github.com/uditgoenka/autoresearch).

### agent-skills (`addyosmani/agent-skills`)

Production-grade engineering skills — spec, plan, build, test, review, ship workflows (`/spec`, `/plan`, `/build`, `/test`, `/review`, `/ship`, and more). 24 skills including TDD, code review, security hardening, frontend UI, API design, and debugging. Installed from the repo root (hybrid plugin with `plugin.json`). See [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills).

## Antigravity

APM's **`antigravity`** target deploys rules to `~/.agents/rules/` and MCP to `~/.gemini/config/mcp_config.json`. Requires:

- **APM 0.24.0+** (Homebrew may lag; upgrade manually until the formula catches up)
- **Antigravity CLI** (`agy`) — `brew install --cask antigravity-cli` (in `macos/Brewfile`)

`agent-sync` runs two installs: project-scope for Cursor/Codex/etc., then `apm install -g --target antigravity --runtime antigravity` for global Antigravity MCP (APM 0.24.0 does not auto-detect `antigravity` in its runtime probe).

Reload MCP in Antigravity after `agent-sync` (IDE: MCP Servers panel; CLI: `/mcp`).

**Note:** HTTP servers (e.g. `context7`) are written with `httpUrl` (Gemini schema). If Antigravity rejects them, rename to `serverUrl` in `mcp_config.json` until APM maps the field for Antigravity.

## Add an MCP server

```bash
cd ~/Developer/GitHub/AlejandroAkbal/dotfiles/macos/agent
apm install --mcp <name> --transport http --url <url>
agent-sync
```
