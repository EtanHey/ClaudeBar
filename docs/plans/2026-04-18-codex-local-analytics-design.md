# Codex Local Analytics Design

Status: approved

## Goal

Add Codex local analytics to ClaudeBar using `@ccusage/codex`, with a Codex-only analytics block that shows:

- Today
- This Month
- Latest Session

Each slice shows:

- cost
- total tokens
- cached input tokens
- reasoning output tokens

## Scope

- Use `@ccusage/codex` as the local analytics backend
- Add a Codex-specific local analytics report to `UsageSnapshot`
- Render a Codex-only analytics block under the existing live Codex cards
- Cache the last good analytics report on disk and load it immediately on menu open
- Refresh analytics in the background when stale

## Non-Goals

- No `threads` / `turns` / per-client product activity in v1
- No browser-cookie dashboard scraping in v1
- No forced fit into the Claude `DailyUsageReport` shape
- No Codex multi-account work in v1

## Why This Shape

`@ccusage/codex` is strongest at daily, monthly, and session analytics. Forcing it into the Claude daily card model would throw away the month/session strength and distort the data model.

The live Codex usage API already covers quota-style limits and credits. Local analytics should complement that instead of replacing it.

## Data Source

`@ccusage/codex` commands:

- `daily --json --offline`
- `monthly --json --offline`
- `session --json --offline`

Observed fields available from the tool include:

- `costUSD`
- `inputTokens`
- `cachedInputTokens`
- `outputTokens`
- `reasoningOutputTokens`
- `totalTokens`
- per-model breakdown

V1 will use the top-level aggregate fields and ignore per-model breakdown.

## Architecture

### Domain

Add a Codex-specific report model:

- `CodexLocalAnalyticsSlice`
- `CodexLocalAnalyticsReport`

Attach it to `UsageSnapshot` as an optional field, parallel to `dailyUsageReport`.

### Infrastructure

Add a Codex analyzer that:

- chooses a runner in this order:
  - `bunx`
  - `npx -y`
- runs the three `@ccusage/codex` JSON commands
- parses the JSON payloads into a domain report
- reads and writes a persistent cache file

Recommended cache file:

- `~/.claudebar/cache/codex-local-analytics.json`

### App

Render a Codex-only analytics block in `MenuContentView` when `snapshot.codexLocalAnalyticsReport` exists.

The block should contain three sections:

- Today
- This Month
- Latest Session

Each section should render four compact metric cards:

- Cost
- Total Tokens
- Cached Tokens
- Reasoning Tokens

## Caching Model

`@ccusage/codex` is too slow to run synchronously on every menu open, so v1 must be cache-first.

Cache invalidation inputs:

- newest mtime under `~/.codex/sessions`
- timezone used for grouping
- runner identity

Stale conditions:

- newest session-file mtime changed since last successful analysis, or
- cache age exceeds 5 minutes

Behavior:

- menu open loads cache immediately if present
- stale cache triggers background refresh
- refresh failures keep the last good cached report visible
- manual refresh forces recomputation

## UI Behavior

Placement:

- keep existing live Codex quota/credits cards first
- render local analytics underneath

V1 labeling:

- clearly mark this section as local analytics
- avoid implying these metrics come from the OpenAI dashboard

## Risks

- `npx` / `bunx` cold starts are slow, so cache-first is mandatory
- `@ccusage/codex` may change JSON shape across versions, so parser tests should use realistic fixtures
- local analytics may lag behind live limits slightly because of background refresh

## Recommendation

Implement this as a Codex-specific report path, not as generic `extensionMetrics` and not as a reuse of `DailyUsageReport`.
