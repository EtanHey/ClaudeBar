import Foundation
import Observation

/// Codex AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Supports dual probe modes: RPC (default) and API.
@Observable
public final class CodexProvider: AIProvider, @unchecked Sendable {
    // MARK: - Identity

    public let id: String = "codex"
    public let name: String = "Codex"
    public let cliCommand: String = "codex"

    public var dashboardURL: URL? {
        URL(string: "https://platform.openai.com/usage")
    }

    public var statusPageURL: URL? {
        URL(string: "https://status.openai.com")
    }

    /// Whether the provider is enabled (persisted via settingsRepository)
    public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    // MARK: - State (Observable)

    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?
    private var analyticsRefreshTask: Task<Void, Never>?

    // MARK: - Probe Mode

    /// The current probe mode (RPC or API)
    public var probeMode: CodexProbeMode {
        get {
            if let codexSettings = settingsRepository as? CodexSettingsRepository {
                return codexSettings.codexProbeMode()
            }
            return .rpc
        }
        set {
            if let codexSettings = settingsRepository as? CodexSettingsRepository {
                codexSettings.setCodexProbeMode(newValue)
            }
        }
    }

    // MARK: - Internal

    /// The RPC probe for fetching usage data via `codex app-server`
    private let rpcProbe: any UsageProbe

    /// The API probe for fetching usage data via HTTP API (optional)
    private let apiProbe: (any UsageProbe)?

    /// The settings repository for persisting provider settings
    private let settingsRepository: any ProviderSettingsRepository
    private let localAnalyticsAnalyzer: (any CodexLocalAnalyticsAnalyzing)?

    /// Returns the active probe based on current mode
    private var activeProbe: any UsageProbe {
        switch probeMode {
        case .rpc:
            return rpcProbe
        case .api:
            // Fall back to RPC if API probe not available
            return apiProbe ?? rpcProbe
        }
    }

    // MARK: - Initialization

    /// Creates a Codex provider with RPC probe only (legacy initializer)
    /// - Parameters:
    ///   - probe: The RPC probe to use for fetching usage data
    ///   - settingsRepository: The repository for persisting settings
    public init(
        probe: any UsageProbe,
        settingsRepository: any ProviderSettingsRepository,
        localAnalyticsAnalyzer: (any CodexLocalAnalyticsAnalyzing)? = nil
    ) {
        self.rpcProbe = probe
        self.apiProbe = nil
        self.settingsRepository = settingsRepository
        self.localAnalyticsAnalyzer = localAnalyticsAnalyzer
        self.isEnabled = settingsRepository.isEnabled(forProvider: "codex")
    }

    /// Creates a Codex provider with both RPC and API probes
    /// - Parameters:
    ///   - rpcProbe: The RPC probe for fetching usage via `codex app-server`
    ///   - apiProbe: The API probe for fetching usage via HTTP API
    ///   - settingsRepository: The repository for persisting settings (must be CodexSettingsRepository for mode switching)
    public init(
        rpcProbe: any UsageProbe,
        apiProbe: any UsageProbe,
        settingsRepository: any CodexSettingsRepository,
        localAnalyticsAnalyzer: (any CodexLocalAnalyticsAnalyzing)? = nil
    ) {
        self.rpcProbe = rpcProbe
        self.apiProbe = apiProbe
        self.settingsRepository = settingsRepository
        self.localAnalyticsAnalyzer = localAnalyticsAnalyzer
        self.isEnabled = settingsRepository.isEnabled(forProvider: "codex")
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await activeProbe.isAvailable()
    }

    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let liveSnapshot = try await activeProbe.probe()
            let cachedReport = await localAnalyticsAnalyzer?.cachedReport()
            let newSnapshot = attachLocalAnalytics(to: liveSnapshot, report: cachedReport)
            snapshot = newSnapshot
            lastError = nil
            scheduleLocalAnalyticsRefresh()
            return newSnapshot
        } catch {
            lastError = error
            throw error
        }
    }

    /// Whether API mode is available (API probe was provided)
    public var supportsApiMode: Bool {
        apiProbe != nil
    }

    private func attachLocalAnalytics(
        to snapshot: UsageSnapshot,
        report: CodexLocalAnalyticsReport?
    ) -> UsageSnapshot {
        UsageSnapshot(
            providerId: snapshot.providerId,
            quotas: snapshot.quotas,
            capturedAt: snapshot.capturedAt,
            accountEmail: snapshot.accountEmail,
            accountOrganization: snapshot.accountOrganization,
            loginMethod: snapshot.loginMethod,
            accountTier: snapshot.accountTier,
            costUsage: snapshot.costUsage,
            bedrockUsage: snapshot.bedrockUsage,
            dailyUsageReport: snapshot.dailyUsageReport,
            codexLocalAnalyticsReport: report?.hasContent == true ? report : nil,
            extensionMetrics: snapshot.extensionMetrics
        )
    }

    private func scheduleLocalAnalyticsRefresh() {
        guard let localAnalyticsAnalyzer else { return }

        analyticsRefreshTask?.cancel()
        analyticsRefreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                let refreshedReport = try await localAnalyticsAnalyzer.refresh(policy: .ifNeeded)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let currentSnapshot = self.snapshot else { return }
                    self.snapshot = self.attachLocalAnalytics(to: currentSnapshot, report: refreshedReport)
                }
            } catch {
                // Keep the last cached analytics attached to the current snapshot.
            }
        }
    }
}
