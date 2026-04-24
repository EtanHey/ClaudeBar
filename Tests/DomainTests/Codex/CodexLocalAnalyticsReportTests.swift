import Foundation
import Testing
@testable import Domain

@Suite("CodexLocalAnalyticsReport Tests")
struct CodexLocalAnalyticsReportTests {
    @Test
    func `slice formats cost and token values`() {
        let slice = CodexLocalAnalyticsSlice(
            costUSD: 47.798651,
            totalTokens: 125_389_222,
            cachedInputTokens: 120_791_424,
            reasoningOutputTokens: 238_763,
            referenceLabel: "Apr 18, 2026"
        )

        #expect(slice.formattedCost == "$47.80")
        #expect(slice.formattedTotalTokens == "125.4M")
        #expect(slice.formattedCachedInputTokens == "120.8M")
        #expect(slice.formattedReasoningOutputTokens == "238.8K")
    }

    @Test
    func `empty slice reports empty`() {
        let slice = CodexLocalAnalyticsSlice.empty(referenceLabel: "Latest Session")

        #expect(slice.isEmpty == true)
        #expect(slice.referenceLabel == "Latest Session")
    }

    @Test
    func `report tracks slices and content state`() {
        let today = CodexLocalAnalyticsSlice(
            costUSD: 12.4,
            totalTokens: 1000,
            cachedInputTokens: 400,
            reasoningOutputTokens: 100,
            referenceLabel: "Today"
        )
        let month = CodexLocalAnalyticsSlice.empty(referenceLabel: "Apr 2026")
        let latestSession = CodexLocalAnalyticsSlice.empty(referenceLabel: "rollout-123")

        let report = CodexLocalAnalyticsReport(
            today: today,
            thisMonth: month,
            latestSession: latestSession
        )

        #expect(report.today.referenceLabel == "Today")
        #expect(report.thisMonth.referenceLabel == "Apr 2026")
        #expect(report.latestSession.referenceLabel == "rollout-123")
        #expect(report.hasContent == true)
    }

    @Test
    func `snapshot preserves codex local analytics report`() {
        let report = CodexLocalAnalyticsReport(
            today: CodexLocalAnalyticsSlice(
                costUSD: 1.2,
                totalTokens: 2000,
                cachedInputTokens: 1500,
                reasoningOutputTokens: 200
            ),
            thisMonth: .empty(),
            latestSession: .empty()
        )

        let snapshot = UsageSnapshot(
            providerId: "codex",
            quotas: [],
            capturedAt: Date(),
            codexLocalAnalyticsReport: report
        )

        #expect(snapshot.codexLocalAnalyticsReport == report)
    }
}
