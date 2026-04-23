# AGENTS.md

Agent guidance for **ClaudeBar** (Swift 6.2 macOS menu bar AI-quota tracker).

## Primary source of truth

Read **[CLAUDE.md](./CLAUDE.md)** first. It covers architecture, Tuist build/test commands, logging, adding providers, theme system, and release workflow. Everything here is a pointer into it.

## Routing (which agent does what)

See **[standards/agents.md](./standards/agents.md)** for the full routing matrix. Short version:

- **Claude Code** — design decisions, architecture review, multi-file refactors, PR orchestration.
- **Codex CLI** — Swift implementation, unit/integration tests, targeted diffs. Default for focused code changes.
- **Cursor CLI** — read-only audits, code search, "what does X do" exploration.

## Codex-specific notes

- Run Swift commands via `tuist` (not raw `xcodebuild`) — `tuist generate`, `tuist build`, `tuist test`. See CLAUDE.md → *Build & Test Commands*.
- Tests follow Chicago School TDD (state over mocks). Use the `Mockable` macro for protocol mocks — see CLAUDE.md → *Architecture → Key Patterns*.
- Adding a provider? Use the `add-provider` skill in `.claude/skills/add-provider/SKILL.md` — it encodes the repository-protocol ISP pattern.
- Settings live in `~/.claudebar/settings.json` via `JSONSettingsRepository`. Credentials (tokens) stay in UserDefaults pending Keychain migration.

## MCP servers configured here

`.mcp.json` wires four servers for this workspace (gitignored — copy from `.mcp.json.example` and fill in your `EXA_API_KEY`):

- **brainlayer** — cross-session memory (`brain_search`, `brain_store`, etc.).
- **context7** — Swift 6.2 / Tuist / macOS 15 / Sparkle / Mockable documentation lookups. Use this before guessing API shapes.
- **exa** — web search fallback for things outside docs.
- **cmux** — pane/agent control for cmux-native workflows (sibling surfaces, agent-to-agent messages, splits).

## Repo orchestrator

Parent orchestrator lives at `~/Gits/orchestrator`. Cross-repo dispatches land in `~/Gits/orchestrator/docs.local/dispatches/`.
