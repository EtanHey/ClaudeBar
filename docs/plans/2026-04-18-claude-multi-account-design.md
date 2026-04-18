# Claude Multi-Account Design

Status: approved

## Goal

Add Claude multi-account support to ClaudeBar by auto-discovering standard Claude config roots, showing each account in the menu UI, and letting the user pick which account is the default bare `claude` account for new shell sessions.

## Scope

- Discover `~/.claude` and sibling config roots matching `~/.claude-*`
- Treat each root as a separate Claude account
- Use Claude CLI usage probing per account for v1
- Add account paging/switching in the Claude menu section
- Add `Make Primary` support that changes bare `claude` for future shells

## Non-Goals

- Manual account entry UI in v1
- Arbitrary custom config-dir paths in v1
- Full API-mode multi-account in v1
- Rewriting or swapping Claude's own config directories on each switch

## Source Of Truth

- Claude account state remains in Claude-owned config roots
- ClaudeBar stores only app metadata:
  - discovered account overrides such as label/order if needed later
  - active viewed account
  - primary default account root for shell integration

## Discovery Model

- Primary root: `~/.claude`
- Additional roots: direct home-directory siblings matching `.claude-*`
- Identity comes from the root's `.claude.json`
  - primary account identity is currently in `~/.claude.json`
  - discovered sibling root identity is in `<root>/.claude.json`

## Switching Model

- Viewing an account in ClaudeBar switches the active Claude account inside the app only
- `Make Primary` updates an app-owned pointer file used by shell integration
- Future bare `claude` shells read the pointer file and export `CLAUDE_CONFIG_DIR`
- Existing shells are not forcibly rewritten

## Why This Approach

- Matches the user's current real-world Claude setup
- Avoids risky mutation of Claude's own directories
- Keeps sign-in state stable per account root
- Reuses the repo's dormant multi-account provider abstractions cleanly

## V1 Tradeoff

CLI-mode multi-account is the first version because the current Claude API credential path is still effectively single-home oriented. CLI usage probing already works naturally with separate config roots.
