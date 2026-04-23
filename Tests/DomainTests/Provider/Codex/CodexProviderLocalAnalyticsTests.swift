import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("CodexProvider Local Analytics Tests")
struct CodexProviderLocalAnalyticsTests {
    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    private func makeSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            providerId: "codex",
            quotas: [UsageQuota(percentRemaining: 76, quotaType: .session, providerId: "codex")],
            capturedAt: Date()
        )
    }

    @Test
    func `refresh attaches cached local analytics immediately`() async throws {
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).probe().willReturn(makeSnapshot())

        let cachedReport = CodexLocalAnalyticsReport(
            today: CodexLocalAnalyticsSlice(costUSD: 10, totalTokens: 1000, cachedInputTokens: 600, reasoningOutputTokens: 200),
            thisMonth: .empty(),
            latestSession: .empty()
        )
        let analyzer = StubCodexLocalAnalyticsAnalyzer(cached: cachedReport, refreshed: cachedReport)

        let codex = CodexProvider(
            probe: probe,
            settingsRepository: settings,
            localAnalyticsAnalyzer: analyzer
        )

        let snapshot = try await codex.refresh()

        #expect(snapshot.codexLocalAnalyticsReport?.today.costUSD == 10)
        #expect(codex.snapshot?.codexLocalAnalyticsReport?.today.costUSD == 10)
    }

    @Test
    func `refresh updates snapshot when background analytics returns fresher report`() async throws {
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).probe().willReturn(makeSnapshot())

        let cachedReport = CodexLocalAnalyticsReport(
            today: CodexLocalAnalyticsSlice(costUSD: 10, totalTokens: 1000, cachedInputTokens: 600, reasoningOutputTokens: 200),
            thisMonth: .empty(),
            latestSession: .empty()
        )
        let refreshedReport = CodexLocalAnalyticsReport(
            today: CodexLocalAnalyticsSlice(costUSD: 20, totalTokens: 2000, cachedInputTokens: 1200, reasoningOutputTokens: 400),
            thisMonth: .empty(),
            latestSession: .empty()
        )
        let analyzer = StubCodexLocalAnalyticsAnalyzer(cached: cachedReport, refreshed: refreshedReport, refreshDelay: 50_000_000)

        let codex = CodexProvider(
            probe: probe,
            settingsRepository: settings,
            localAnalyticsAnalyzer: analyzer
        )

        let snapshot = try await codex.refresh()
        #expect(snapshot.codexLocalAnalyticsReport?.today.costUSD == 10)

        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(codex.snapshot?.codexLocalAnalyticsReport?.today.costUSD == 20)
    }
}

private struct StubCodexLocalAnalyticsAnalyzer: CodexLocalAnalyticsAnalyzing {
    let cached: CodexLocalAnalyticsReport?
    let refreshed: CodexLocalAnalyticsReport?
    let refreshDelay: UInt64

    init(
        cached: CodexLocalAnalyticsReport?,
        refreshed: CodexLocalAnalyticsReport?,
        refreshDelay: UInt64 = 0
    ) {
        self.cached = cached
        self.refreshed = refreshed
        self.refreshDelay = refreshDelay
    }

    func cachedReport() async -> CodexLocalAnalyticsReport? {
        cached
    }

    func refresh(policy _: CodexLocalAnalyticsRefreshPolicy) async throws -> CodexLocalAnalyticsReport? {
        if refreshDelay > 0 {
            try await Task.sleep(nanoseconds: refreshDelay)
        }
        return refreshed
    }
}
