import Foundation

/// Claude-specific account definition backing both single-account and multi-account modes.
///
/// Each definition owns the probes and config root needed to query one Claude account.
public struct ClaudeAccountDefinition: Sendable {
    public var account: ProviderAccount
    public let defaultLabel: String
    public let configRootPath: String
    public let cliProbe: any UsageProbe
    public let apiProbe: (any UsageProbe)?
    public let passProbe: (any ClaudePassProbing)?
    public let dailyUsageAnalyzer: (any DailyUsageAnalyzing)?

    public init(
        account: ProviderAccount,
        defaultLabel: String? = nil,
        configRootPath: String,
        cliProbe: any UsageProbe,
        apiProbe: (any UsageProbe)? = nil,
        passProbe: (any ClaudePassProbing)? = nil,
        dailyUsageAnalyzer: (any DailyUsageAnalyzing)? = nil
    ) {
        self.account = account
        self.defaultLabel = defaultLabel ?? account.label
        self.configRootPath = configRootPath
        self.cliProbe = cliProbe
        self.apiProbe = apiProbe
        self.passProbe = passProbe
        self.dailyUsageAnalyzer = dailyUsageAnalyzer
    }
}
