# Agent Routing Matrix

How to pick the right CLI agent for work in **ClaudeBar**. Defaults are opinionated — override when the task clearly fits a different tool.

## Matrix

| Task type | Default agent | Why |
|---|---|---|
| Architecture / design decision | **Claude Code** | Best at holding multi-file context, weighing tradeoffs, writing plans. |
| Multi-file refactor or cross-cutting change | **Claude Code** | Needs the overview + ability to orchestrate sub-agents. |
| Code review / PR review | **Claude Code** | Runs review skills (CodeRabbit, Greptile) and synthesizes findings. |
| Swift implementation (single module / focused diff) | **Codex CLI** | Fast targeted edits, good at Swift syntax and test scaffolding. |
| Unit / integration test authoring | **Codex CLI** | Chicago-School TDD flow fits Codex's rigor with small surface area. |
| Bug fix with known root cause | **Codex CLI** | Minimal diff, clear acceptance criteria. |
| Read-only audit (code search, "where is X used") | **Cursor CLI** | Fast grep/semantic search, no edit side-effects. |
| Dependency or framework research | **Claude Code + context7 MCP** | context7 returns current Swift 6.2 / Tuist / Sparkle / Mockable docs. |
| Web research outside docs | **Claude Code + exa MCP** | exa handles general-web queries; context7 handles library docs. |

## Rules of thumb

1. **Design before implementation.** Claude drafts a plan → Codex implements it. Don't let Codex invent architecture.
2. **Audits never edit.** If the request is "tell me how X works," route to Cursor (read-only) to avoid accidental diffs.
3. **TDD is mandatory.** Any code change needs a failing test first. See `CLAUDE.md` → *Adding a New AI Provider* and `.claude/skills/add-provider/SKILL.md`.
4. **Check BrainLayer before reading files.** `brain_search(<topic>)` beats cold file reads for prior decisions and context.
5. **One agent owns the PR.** Don't have two agents editing the same branch concurrently — use `git worktree` for parallel work.

## Launchers

Agents launch from the ecosystem repoGolem layer. Expected launcher names for this repo:

- `claudebarClaude` — Claude Code in this repo.
- `claudebarCodex` — Codex CLI in this repo.
- `claudebarCursor` — Cursor CLI in this repo.

Common flags:
- `-s` — skip intro / dive straight into task
- `-c` — continue previous session

If a launcher is missing from your shell, flag it to orc rather than hand-rolling `cd && claude`.

## Escalation

If an agent gets stuck for more than two iterations on the same failure, stop and escalate to **Claude Code** for re-planning. Don't loop.
