---
description: Global agent workflow guidance shared across Cursor, OpenCode, Codex, Claude Code, and Antigravity
---

## Package management

- Prefer **declarative package managers** over one-off install scripts (`curl | bash`, `irm`, vendor installers).
- On macOS, use **Homebrew** (`brew install`, `brew bundle`, Brewfile) for CLI tools and casks when a formula or cask exists.
- Use **mise** (`mise use`, `mise install`) for language runtimes and per-project tool versions (Node, Python, Go, etc.).
- Reach for install scripts only when there is no Brew/mise equivalent, the upstream docs require it, or the user explicitly asks for that method.
- When adding tooling to this machine, update `macos/Brewfile` or project mise config rather than documenting ad-hoc script installs.

## Self-Improving Agent Notes

- When a session reveals durable workflow or tooling knowledge, add it to the most specific applicable `AGENTS.md`
  file before handing off. Prefer repo-local guidance for project behavior and global guidance only for reusable agent
  workflow.
## Browser tools

- Use `browser-testing-with-devtools` for browser-facing debugging and performance work: console errors, network waterfalls, payloads, computed styles, accessibility tree, screenshots, Core Web Vitals, and performance traces.
- For Chrome DevTools MCP with Chrome's `chrome://inspect/#remote-debugging` toggle, configure
  `chrome-devtools-mcp` with `--autoConnect`. The old `--browser-url=http://127.0.0.1:9222` mode expects
  `/json/version` and can fail with 404 on the newer Chrome remote-debugging flow.
- Use `agent-browser` for fast browser automation and UI smoke tests: open pages, inspect interactive elements, click/fill by stable refs, verify flows, capture screenshots, and reproduce user-facing behavior.
