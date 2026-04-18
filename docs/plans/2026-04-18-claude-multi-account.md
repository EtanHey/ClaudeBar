# Claude Multi-Account Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add auto-discovered Claude CLI multi-account support with account paging and a primary account selector that changes bare `claude` for future shells.

**Architecture:** Introduce a Claude account discovery layer plus shell-integration helper, then make `ClaudeProvider` implement `MultiAccountProvider` with one CLI probe per discovered config root. Keep Claude-owned config roots as the auth source of truth and let ClaudeBar store only active/primary account metadata.

**Tech Stack:** Swift 6.2, Tuist, Swift Testing, SwiftUI, existing Domain/Infrastructure/App layers

---

### Task 1: Add failing tests for Claude account discovery

**Files:**
- Create: `Tests/InfrastructureTests/Claude/ClaudeAccountDiscoveryTests.swift`
- Modify: `Sources/Infrastructure/Claude/`

**Step 1: Write the failing test**

Cover:
- discovery returns `~/.claude` and `~/.claude-*`
- identity is read from `.claude.json`
- primary root is ordered first

**Step 2: Run test to verify it fails**

Run: `tuist test InfrastructureTests`

**Step 3: Write minimal implementation**

Add a Claude account discovery type in infrastructure.

**Step 4: Run test to verify it passes**

Run: `tuist test InfrastructureTests`

### Task 2: Add failing tests for shell integration primary switching

**Files:**
- Create: `Tests/InfrastructureTests/Claude/ClaudeShellIntegrationTests.swift`
- Modify: `Sources/Infrastructure/Claude/`

**Step 1: Write the failing test**

Cover:
- active config-root pointer file write/remove
- zsh integration installation is idempotent
- snippet exports `CLAUDE_CONFIG_DIR` from the active pointer file

**Step 2: Run test to verify it fails**

Run: `tuist test InfrastructureTests`

**Step 3: Write minimal implementation**

Add Claude shell integration helper.

**Step 4: Run test to verify it passes**

Run: `tuist test InfrastructureTests`

### Task 3: Add failing tests for Claude multi-account provider behavior

**Files:**
- Modify: `Tests/DomainTests/Provider/Claude/ClaudeProviderTests.swift`
- Modify: `Sources/Domain/Provider/Claude/ClaudeProvider.swift`

**Step 1: Write the failing test**

Cover:
- provider conforms to `MultiAccountProvider`
- switching accounts updates `activeAccount`
- refresh for active account updates `snapshot`
- `Make Primary` persists the primary account and calls shell integration

**Step 2: Run test to verify it fails**

Run: `tuist test DomainTests`

**Step 3: Write minimal implementation**

Add multi-account state and switching logic to `ClaudeProvider`.

**Step 4: Run test to verify it passes**

Run: `tuist test DomainTests`

### Task 4: Wire settings persistence for active/primary Claude accounts

**Files:**
- Modify: `Sources/Domain/Provider/MultiAccountSettingsRepository.swift`
- Modify: `Sources/Infrastructure/Storage/JSONSettingsRepository.swift`
- Modify: `Tests/InfrastructureTests/Settings/JSONSettingsRepositoryAppTests.swift`

**Step 1: Write the failing test**

Cover:
- active Claude account id persistence
- primary Claude config-root persistence if needed

**Step 2: Run test to verify it fails**

Run: `tuist test InfrastructureTests`

**Step 3: Write minimal implementation**

Implement the persistence API in `JSONSettingsRepository`.

**Step 4: Run test to verify it passes**

Run: `tuist test InfrastructureTests`

### Task 5: Wire menu and settings UI

**Files:**
- Modify: `Sources/App/Views/MenuContentView.swift`
- Modify: `Sources/App/Views/ProviderSectionView.swift`
- Modify: `Sources/App/Views/AccountPickerView.swift`
- Modify: `Sources/App/Views/Settings/ClaudeConfigCard.swift`
- Modify: `Sources/App/Views/Settings/AccountManagementCard.swift`

**Step 1: Write the failing or characterization tests where practical**

Prefer acceptance coverage for:
- discovered Claude accounts appear
- switching viewed account changes displayed usage
- `Make Primary` is visible for non-primary accounts

**Step 2: Run test to verify it fails**

Run: `tuist test AcceptanceTests`

**Step 3: Write minimal implementation**

Show account paging and account-management controls only for Claude multi-account.

**Step 4: Run test to verify it passes**

Run: `tuist test AcceptanceTests`

### Task 6: Verify end to end

**Files:**
- Modify only if verification reveals issues

**Step 1: Run focused suites**

Run:
- `tuist test DomainTests`
- `tuist test InfrastructureTests`
- `tuist test AcceptanceTests`

**Step 2: Run full suite**

Run: `tuist test`

**Step 3: Manual verification**

Check:
- multiple Claude accounts are auto-discovered
- switching pages updates Claude usage
- `Make Primary` writes the active default and affects new shell sessions

