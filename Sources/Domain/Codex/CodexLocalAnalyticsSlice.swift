import Foundation

/// A single Codex local analytics period derived from `@ccusage/codex`.
public struct CodexLocalAnalyticsSlice: Sendable, Equatable, Codable {
    public let costUSD: Decimal
    public let totalTokens: Int
    public let cachedInputTokens: Int
    public let reasoningOutputTokens: Int
    public let referenceLabel: String?

    public init(
        costUSD: Decimal,
        totalTokens: Int,
        cachedInputTokens: Int,
        reasoningOutputTokens: Int,
        referenceLabel: String? = nil
    ) {
        self.costUSD = costUSD
        self.totalTokens = totalTokens
        self.cachedInputTokens = cachedInputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.referenceLabel = referenceLabel
    }

    public var isEmpty: Bool {
        costUSD == 0 &&
            totalTokens == 0 &&
            cachedInputTokens == 0 &&
            reasoningOutputTokens == 0
    }

    public var formattedCost: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: costUSD as NSDecimalNumber) ?? "$\(costUSD)"
    }

    public var formattedTotalTokens: String {
        Self.formatTokenCount(totalTokens)
    }

    public var formattedCachedInputTokens: String {
        Self.formatTokenCount(cachedInputTokens)
    }

    public var formattedReasoningOutputTokens: String {
        Self.formatTokenCount(reasoningOutputTokens)
    }

    public static func empty(referenceLabel: String? = nil) -> Self {
        CodexLocalAnalyticsSlice(
            costUSD: 0,
            totalTokens: 0,
            cachedInputTokens: 0,
            reasoningOutputTokens: 0,
            referenceLabel: referenceLabel
        )
    }

    private static func formatTokenCount(_ value: Int) -> String {
        switch value {
        case 1_000_000_000...:
            return String(format: "%.1fB", Double(value) / 1_000_000_000.0)
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        case 1_000...:
            return String(format: "%.1fK", Double(value) / 1_000.0)
        default:
            return "\(value)"
        }
    }
}
