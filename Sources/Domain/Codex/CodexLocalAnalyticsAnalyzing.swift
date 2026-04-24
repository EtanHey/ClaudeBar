import Foundation
import Mockable

public enum CodexLocalAnalyticsRefreshPolicy: String, Sendable, Equatable, Codable {
    case ifNeeded
    case force
}

@Mockable
public protocol CodexLocalAnalyticsAnalyzing: Sendable {
    func cachedReport() async -> CodexLocalAnalyticsReport?
    func refresh(policy: CodexLocalAnalyticsRefreshPolicy) async throws -> CodexLocalAnalyticsReport?
}
