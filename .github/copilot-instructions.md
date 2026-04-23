# GitHub Copilot Instructions

This repository is **ClaudeBar** — a Swift 6.2 macOS menu bar app that monitors AI coding-assistant quotas (Claude, Codex, Gemini, Copilot, Antigravity, Z.ai, Kimi, Kiro, Amp, Bedrock, MiniMax).

## Read first

See **[../CLAUDE.md](../CLAUDE.md)** for the canonical architecture, build commands, logging conventions, and provider-addition workflow. Also see **[../AGENTS.md](../AGENTS.md)** for agent routing and **[../standards/agents.md](../standards/agents.md)** for the routing matrix.

## Quick rules for Copilot completions

- **Build tool:** Tuist. Never invent `xcodebuild` invocations — use `tuist generate / build / test`.
- **Architecture:** Layered — `Sources/Domain/` (pure logic), `Sources/Infrastructure/` (probes, storage), `Sources/App/` (SwiftUI). Views consume `QuotaMonitor` directly; no `ViewModel` / `AppState` indirection.
- **ISP:** Provider settings extend `ProviderSettingsRepository` with provider-specific sub-protocols (see `Sources/Infrastructure/Storage/JSONSettingsRepository.swift`).
- **TDD:** Tests first (Chicago School — state over mocks). `@Mockable` generates protocol mocks via Swift macros.
- **Settings storage:** Single JSON file at `~/.claudebar/settings.json`. Credentials stay in `UserDefaults` pending Keychain migration — don't log them.
- **Logging:** Use `AppLog.<category>` (`monitor`, `probes`, `network`, `credentials`, etc.). Redact secrets manually — `AppLog` uses plain strings, not OSLog privacy interpolation.

## Don't

- Don't suggest overwriting `*.xcodeproj` / `*.xcworkspace` — they're Tuist-generated and gitignored.
- Don't add `ViewModel` classes — the project deliberately has none.
- Don't hardcode API keys or tokens — use `UserDefaults` (current) or Keychain (future). See `CLAUDE.md` → *Logging → Privacy Rules*.
