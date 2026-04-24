# Codex Local Analytics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add cached local Codex analytics powered by `@ccusage/codex`, shown in the Codex panel as Today / This Month / Latest Session metrics.

**Architecture:** Introduce a Codex-specific local analytics report in Domain, a cached `@ccusage/codex` analyzer in Infrastructure, and a Codex-only analytics block in the menu UI.

**Tech Stack:** Swift 6.2, Tuist, Swift Testing, existing Domain/Infrastructure/App layers

---

### Task 1: Add failing domain tests for the report model

**Files:**
- Create: `Tests/DomainTests/Codex/CodexLocalAnalyticsReportTests.swift`
- Create: `Sources/Domain/Codex/`

**Step 1: Write the failing tests**

Cover:
- formatting of cost and token values
- empty slice behavior
- report carries today / month / latest session slices

**Step 2: Run test to verify it fails**

Run: `tuist test DomainTests`

**Step 3: Write minimal implementation**

Create:
- `CodexLocalAnalyticsSlice`
- `CodexLocalAnalyticsReport`

**Step 4: Run test to verify it passes**

Run: `tuist test DomainTests`

### Task 2: Extend UsageSnapshot for Codex local analytics

**Files:**
- Modify: `Sources/Domain/Provider/UsageSnapshot.swift`
- Modify: related tests if needed

**Step 1: Write the failing test**

Cover:
- snapshot stores and preserves `codexLocalAnalyticsReport`

**Step 2: Run test to verify it fails**

Run: `tuist test DomainTests`

**Step 3: Write minimal implementation**

Add optional `codexLocalAnalyticsReport` to `UsageSnapshot`.

**Step 4: Run test to verify it passes**

Run: `tuist test DomainTests`

### Task 3: Add failing infrastructure tests for parser and cache behavior

**Files:**
- Create: `Tests/InfrastructureTests/Codex/CodexLocalAnalyticsAnalyzerTests.swift`
- Create: `Sources/Infrastructure/Codex/CodexLocalAnalyticsAnalyzer.swift`

**Step 1: Write the failing tests**

Cover:
- parses realistic `daily`, `monthly`, and `session` JSON
- chooses `bunx` before `npx`
- falls back from `bunx` to `npx`
- reads last good cache immediately
- marks cache stale when newest session mtime changes

**Step 2: Run test to verify it fails**

Run: `tuist test InfrastructureTests`

**Step 3: Write minimal implementation**

Add analyzer + cache file model.

**Step 4: Run test to verify it passes**

Run: `tuist test InfrastructureTests`

### Task 4: Wire CodexProvider to attach local analytics

**Files:**
- Modify: `Sources/Domain/Provider/Codex/CodexProvider.swift`
- Add tests in an appropriate Domain test file

**Step 1: Write the failing test**

Cover:
- provider refresh preserves live snapshot fields
- provider attaches cached analytics immediately when available
- provider can update analytics after background recompute

**Step 2: Run test to verify it fails**

Run: `tuist test DomainTests`

**Step 3: Write minimal implementation**

Inject analyzer into `CodexProvider` and enrich the snapshot.

**Step 4: Run test to verify it passes**

Run: `tuist test DomainTests`

### Task 5: Render the Codex-only analytics block

**Files:**
- Modify: `Sources/App/Views/MenuContentView.swift`
- Create view helpers only if needed

**Step 1: Write the failing or characterization tests where practical**

Cover:
- analytics block appears only for Codex
- sections render Today / This Month / Latest Session
- each section shows Cost / Total Tokens / Cached Tokens / Reasoning Tokens

**Step 2: Run test to verify it fails**

Run: `tuist test AcceptanceTests`

**Step 3: Write minimal implementation**

Render the new block below live Codex cards.

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
- Codex panel loads cached analytics immediately
- manual refresh updates the local analytics block
- stale cache remains visible on command failure
- no fake dashboard fields are shown
