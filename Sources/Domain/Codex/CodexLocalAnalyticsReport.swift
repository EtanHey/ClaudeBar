import Foundation

/// Aggregated Codex local analytics for the current day, current month, and latest session.
public struct CodexLocalAnalyticsReport: Sendable, Equatable, Codable {
    public let today: CodexLocalAnalyticsSlice
    public let thisMonth: CodexLocalAnalyticsSlice
    public let latestSession: CodexLocalAnalyticsSlice
    public let capturedAt: Date

    public init(
        today: CodexLocalAnalyticsSlice,
        thisMonth: CodexLocalAnalyticsSlice,
        latestSession: CodexLocalAnalyticsSlice,
        capturedAt: Date = Date()
    ) {
        self.today = today
        self.thisMonth = thisMonth
        self.latestSession = latestSession
        self.capturedAt = capturedAt
    }

    public var hasContent: Bool {
        !today.isEmpty || !thisMonth.isEmpty || !latestSession.isEmpty
    }
}
