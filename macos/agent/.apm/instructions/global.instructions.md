---
description: Global agent workflow guidance shared across Cursor, OpenCode, and Codex
---

## Self-Improving Agent Notes

- When a session reveals durable workflow or tooling knowledge, add it to the most specific applicable `AGENTS.md`
  file before handing off. Prefer repo-local guidance for project behavior and global guidance only for reusable agent
  workflow.
- For Chrome DevTools MCP with Chrome's `chrome://inspect/#remote-debugging` toggle, configure
  `chrome-devtools-mcp` with `--autoConnect`. The old `--browser-url=http://127.0.0.1:9222` mode expects
  `/json/version` and can fail with 404 on the newer Chrome remote-debugging flow.
