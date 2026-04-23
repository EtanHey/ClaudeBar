import Foundation
import Observation

/// Claude AI provider - rich domain model with optional multi-account support.
@Observable
public final class ClaudeProvider: AIProvider, MultiAccountProvider, @unchecked Sendable {
    // MARK: - Identity

    public let id: String = "claude"
    public let name: String = "Claude"
    public let cliCommand: String = "claude"

    public var dashboardURL: URL? {
        URL(string: "https://console.anthropic.com/settings/billing")
    }

    public var statusPageURL: URL? {
        URL(string: "https://status.anthropic.com")
    }

    public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    // MARK: - State

    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?
    public private(set) var accountErrors: [String: Error] = [:]
    public private(set) var guestPass: ClaudePass?
    public private(set) var isFetchingPasses: Bool = false

    // MARK: - Multi Account

    public private(set) var accounts: [ProviderAccount]
    public private(set) var accountSnapshots: [String: UsageSnapshot] = [:]
    public private(set) var primaryAccount: ProviderAccount?

    public var activeAccount: ProviderAccount {
        definition(for: activeAccountId)?.account ?? accounts[0]
    }

    // MARK: - Probe Mode

    public var probeMode: ClaudeProbeMode {
        get {
            if let claudeSettings = settingsRepository as? ClaudeSettingsRepository {
                return claudeSettings.claudeProbeMode()
            }
            return .cli
        }
        set {
            if let claudeSettings = settingsRepository as? ClaudeSettingsRepository {
                claudeSettings.setClaudeProbeMode(newValue)
            }
        }
    }

    // MARK: - Internal

    private var accountDefinitions: [ClaudeAccountDefinition]
    private var activeAccountId: String
    private var primaryAccountId: String
    private let settingsRepository: any ProviderSettingsRepository
    private let onPrimaryAccountChange: ((ClaudeAccountDefinition) -> Void)?
    private var accountWarmTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(
        probe: any UsageProbe,
        passProbe: (any ClaudePassProbing)? = nil,
        settingsRepository: any ProviderSettingsRepository,
        dailyUsageAnalyzer: (any DailyUsageAnalyzing)? = nil
    ) {
        let configRootPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .path
        let definition = ClaudeAccountDefinition(
            account: ProviderAccount(providerId: "claude", label: "Primary"),
            configRootPath: configRootPath,
            cliProbe: probe,
            passProbe: passProbe,
            dailyUsageAnalyzer: dailyUsageAnalyzer
        )
        self.accountDefinitions = [definition]
        self.accounts = [definition.account]
        self.activeAccountId = definition.account.accountId
        self.primaryAccountId = definition.account.accountId
        self.primaryAccount = definition.account
        self.settingsRepository = settingsRepository
        self.onPrimaryAccountChange = nil
        self.isEnabled = settingsRepository.isEnabled(forProvider: "claude")
    }

    public init(
        cliProbe: any UsageProbe,
        apiProbe: any UsageProbe,
        passProbe: (any ClaudePassProbing)? = nil,
        settingsRepository: any ClaudeSettingsRepository,
        dailyUsageAnalyzer: (any DailyUsageAnalyzing)? = nil
    ) {
        let configRootPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .path
        let definition = ClaudeAccountDefinition(
            account: ProviderAccount(providerId: "claude", label: "Primary"),
            configRootPath: configRootPath,
            cliProbe: cliProbe,
            apiProbe: apiProbe,
            passProbe: passProbe,
            dailyUsageAnalyzer: dailyUsageAnalyzer
        )
        self.accountDefinitions = [definition]
        self.accounts = [definition.account]
        self.activeAccountId = definition.account.accountId
        self.primaryAccountId = definition.account.accountId
        self.primaryAccount = definition.account
        self.settingsRepository = settingsRepository
        self.onPrimaryAccountChange = nil
        self.isEnabled = settingsRepository.isEnabled(forProvider: "claude")
    }

    public init(
        accounts: [ClaudeAccountDefinition],
        settingsRepository: any ProviderSettingsRepository,
        primaryAccountId: String? = nil,
        onPrimaryAccountChange: ((ClaudeAccountDefinition) -> Void)? = nil
    ) {
        precondition(!accounts.isEmpty, "ClaudeProvider requires at least one account definition")

        self.accountDefinitions = accounts
        self.accounts = accounts.map(\.account)
        self.settingsRepository = settingsRepository
        self.onPrimaryAccountChange = onPrimaryAccountChange
        self.isEnabled = settingsRepository.isEnabled(forProvider: "claude")

        let persistedActiveAccountId = (settingsRepository as? MultiAccountSettingsRepository)?
            .activeAccountId(forProvider: "claude")
        self.activeAccountId = Self.validAccountId(
            persistedActiveAccountId,
            definitions: accounts
        ) ?? accounts[0].account.accountId

        let resolvedPrimaryAccountId = Self.validAccountId(primaryAccountId, definitions: accounts)
            ?? Self.validAccountId(ProviderAccount.defaultAccountId, definitions: accounts)
            ?? accounts[0].account.accountId
        self.primaryAccountId = resolvedPrimaryAccountId
        self.primaryAccount = accounts.first { $0.account.accountId == resolvedPrimaryAccountId }?.account
        self.snapshot = nil
    }

    // MARK: - AIProvider

    public func isAvailable() async -> Bool {
        let definition = activeDefinition
        switch probeMode {
        case .cli:
            if await definition.cliProbe.isAvailable() {
                return true
            }
            if let apiProbe = definition.apiProbe, await apiProbe.isAvailable() {
                return true
            }
            return false
        case .api:
            if let apiProbe = definition.apiProbe, await apiProbe.isAvailable() {
                return true
            }
            guard cliFallbackEnabled else { return false }
            return await definition.cliProbe.isAvailable()
        }
    }

    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        if accountDefinitions.count > 1 {
            return try await refreshActiveAccountDefinition()
        }

        isSyncing = true
        defer { isSyncing = false }

        let definition = activeDefinition
        do {
            let refreshed = try await refresh(definition: definition)
            accountSnapshots[definition.account.accountId] = refreshed
            snapshot = refreshed
            clearAccountError(for: definition.account.accountId)
            return refreshed
        } catch {
            storeAccountError(error, for: definition.account.accountId)
            throw error
        }
    }

    // MARK: - MultiAccountProvider

    @discardableResult
    public func switchAccount(to accountId: String) -> Bool {
        guard definition(for: accountId) != nil else {
            return false
        }

        activeAccountId = accountId
        snapshot = accountSnapshots[accountId]
        guestPass = nil
        lastError = accountErrors[accountId]
        (settingsRepository as? MultiAccountSettingsRepository)?
            .setActiveAccountId(accountId, forProvider: id)
        return true
    }

    @discardableResult
    public func refreshAccount(_ accountId: String) async throws -> UsageSnapshot {
        guard let definition = definition(for: accountId) else {
            throw ProbeError.executionFailed("Unknown Claude account: \(accountId)")
        }

        do {
            let refreshed = try await refresh(definition: definition)
            accountSnapshots[accountId] = refreshed
            clearAccountError(for: accountId)
            if accountId == activeAccountId {
                snapshot = refreshed
            }
            return refreshed
        } catch {
            storeAccountError(error, for: accountId)
            if accountId == activeAccountId {
                if let existingSnapshot = accountSnapshots[accountId] {
                    snapshot = existingSnapshot
                }
            }
            throw error
        }
    }

    public func refreshAllAccounts() async {
        _ = try? await refreshAllAccountDefinitions()
    }

    public func accountError(for accountId: String) -> Error? {
        accountErrors[accountId]
    }

    // MARK: - Account Management

    @discardableResult
    public func setPrimaryAccount(to accountId: String) -> Bool {
        guard let definition = definition(for: accountId) else {
            return false
        }

        primaryAccountId = accountId
        primaryAccount = definition.account
        onPrimaryAccountChange?(definition)
        return true
    }

    @discardableResult
    public func setAlias(_ alias: String, for accountId: String) -> Bool {
        guard let index = accountDefinitions.firstIndex(where: { $0.account.accountId == accountId }) else {
            return false
        }

        let resolvedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedLabel = resolvedAlias.isEmpty ? accountDefinitions[index].defaultLabel : resolvedAlias
        let current = accountDefinitions[index]
        accountDefinitions[index].account = ProviderAccount(
            accountId: current.account.accountId,
            providerId: current.account.providerId,
            label: updatedLabel,
            email: current.account.email,
            organization: current.account.organization
        )
        syncAccounts()

        if let settings = settingsRepository as? MultiAccountSettingsRepository {
            settings.updateAccount(
                ProviderAccountConfig(
                    accountId: current.account.accountId,
                    label: updatedLabel,
                    email: current.account.email,
                    organization: current.account.organization,
                    probeConfig: ["configRootPath": current.configRootPath]
                ),
                forProvider: id
            )
        }

        return true
    }

    // MARK: - Guest Pass

    @discardableResult
    public func fetchPasses() async throws -> ClaudePass {
        guard let passProbe = activeDefinition.passProbe else {
            throw PassError.probeNotConfigured
        }

        isFetchingPasses = true
        defer { isFetchingPasses = false }

        do {
            let pass = try await passProbe.probe()
            guestPass = pass
            lastError = nil
            return pass
        } catch {
            lastError = error
            throw error
        }
    }

    public var supportsGuestPasses: Bool {
        activeDefinition.passProbe != nil
    }

    public var supportsApiMode: Bool {
        activeDefinition.apiProbe != nil
    }

    // MARK: - Private

    private var activeDefinition: ClaudeAccountDefinition {
        definition(for: activeAccountId) ?? accountDefinitions[0]
    }

    private var cliFallbackEnabled: Bool {
        (settingsRepository as? ClaudeSettingsRepository)?
            .claudeCliFallbackEnabled() ?? true
    }

    private func definition(for accountId: String) -> ClaudeAccountDefinition? {
        accountDefinitions.first { $0.account.accountId == accountId }
    }

    private func clearAccountError(for accountId: String) {
        accountErrors.removeValue(forKey: accountId)
        if accountId == activeAccountId {
            lastError = nil
        }
    }

    private func storeAccountError(_ error: Error, for accountId: String) {
        accountErrors[accountId] = error
        if accountId == activeAccountId {
            lastError = error
        }
    }

    private func refresh(definition: ClaudeAccountDefinition) async throws -> UsageSnapshot {
        do {
            let newSnapshot = try await primaryProbe(for: definition).probe()
            return await attachDailyReport(to: newSnapshot, using: definition.dailyUsageAnalyzer)
        } catch {
            if let fallback = await fallbackProbe(for: definition) {
                let newSnapshot = try await fallback.probe()
                return await attachDailyReport(to: newSnapshot, using: definition.dailyUsageAnalyzer)
            }
            throw error
        }
    }

    @discardableResult
    private func refreshActiveAccountDefinition() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        let definition = activeDefinition
        let accountId = definition.account.accountId

        do {
            let refreshed = try await refresh(definition: definition)
            accountSnapshots[accountId] = refreshed
            snapshot = refreshed
            clearAccountError(for: accountId)
            warmInactiveAccountsIfNeeded(excluding: accountId)
            return refreshed
        } catch {
            if let existingSnapshot = accountSnapshots[accountId] {
                snapshot = existingSnapshot
            }
            storeAccountError(error, for: accountId)
            throw error
        }
    }

    @discardableResult
    private func refreshAllAccountDefinitions() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        let definitions = accountDefinitions
        let currentActiveId = activeAccountId
        var refreshedSnapshots: [String: UsageSnapshot] = [:]
        var refreshErrors: [String: Error] = [:]
        var activeError: Error?

        await withTaskGroup(of: (String, Result<UsageSnapshot, Error>).self) { group in
            for definition in definitions {
                let accountId = definition.account.accountId
                group.addTask { [self] in
                    do {
                        let snapshot = try await self.refresh(definition: definition)
                        return (accountId, .success(snapshot))
                    } catch {
                        return (accountId, .failure(error))
                    }
                }
            }

            for await (accountId, result) in group {
                switch result {
                case let .success(snapshot):
                    refreshedSnapshots[accountId] = snapshot
                case let .failure(error):
                    refreshErrors[accountId] = error
                    if accountId == currentActiveId {
                        activeError = error
                    }
                }
            }
        }

        accountSnapshots.merge(refreshedSnapshots) { _, new in new }
        for definition in definitions {
            let accountId = definition.account.accountId
            if let error = refreshErrors[accountId] {
                accountErrors[accountId] = error
            } else if refreshedSnapshots[accountId] != nil {
                accountErrors.removeValue(forKey: accountId)
            }
        }

        if let refreshedActiveSnapshot = refreshedSnapshots[currentActiveId] {
            snapshot = refreshedActiveSnapshot
            lastError = nil
            return refreshedActiveSnapshot
        }

        if let activeError {
            if let existingActiveSnapshot = accountSnapshots[currentActiveId] {
                snapshot = existingActiveSnapshot
            }
            lastError = activeError
            throw activeError
        }

        if let activeSnapshot = accountSnapshots[currentActiveId] {
            snapshot = activeSnapshot
            lastError = nil
            return activeSnapshot
        }

        let fallbackError = ProbeError.executionFailed("No Claude account snapshots available")
        storeAccountError(fallbackError, for: currentActiveId)
        throw fallbackError
    }

    private func warmInactiveAccountsIfNeeded(excluding activeAccountId: String) {
        let definitionsToWarm = accountDefinitions.filter { definition in
            guard definition.account.accountId != activeAccountId else {
                return false
            }

            guard let snapshot = accountSnapshots[definition.account.accountId] else {
                return true
            }

            return snapshot.isStale
        }

        guard !definitionsToWarm.isEmpty else {
            return
        }

        accountWarmTask?.cancel()
        accountWarmTask = Task { [self, definitionsToWarm] in
            var refreshedSnapshots: [String: UsageSnapshot] = [:]
            var refreshErrors: [String: Error] = [:]

            await withTaskGroup(of: (String, Result<UsageSnapshot, Error>).self) { group in
                for definition in definitionsToWarm {
                    let accountId = definition.account.accountId
                    group.addTask { [self] in
                        do {
                            let snapshot = try await refresh(definition: definition)
                            return (accountId, .success(snapshot))
                        } catch {
                            return (accountId, .failure(error))
                        }
                    }
                }

                for await (accountId, result) in group {
                    switch result {
                    case let .success(snapshot):
                        refreshedSnapshots[accountId] = snapshot
                    case let .failure(error):
                        refreshErrors[accountId] = error
                    }
                }
            }

            guard !Task.isCancelled else {
                return
            }

            accountSnapshots.merge(refreshedSnapshots) { _, new in new }
            for definition in definitionsToWarm {
                let accountId = definition.account.accountId
                if let error = refreshErrors[accountId] {
                    accountErrors[accountId] = error
                } else if refreshedSnapshots[accountId] != nil {
                    accountErrors.removeValue(forKey: accountId)
                }
            }
            if let activeSnapshot = accountSnapshots[self.activeAccountId] {
                snapshot = activeSnapshot
            }
        }
    }

    private func primaryProbe(for definition: ClaudeAccountDefinition) -> any UsageProbe {
        switch probeMode {
        case .cli:
            return definition.cliProbe
        case .api:
            return definition.apiProbe ?? definition.cliProbe
        }
    }

    private func fallbackProbe(for definition: ClaudeAccountDefinition) async -> (any UsageProbe)? {
        switch probeMode {
        case .cli:
            guard let apiProbe = definition.apiProbe, await apiProbe.isAvailable() else {
                return nil
            }
            return apiProbe
        case .api:
            guard cliFallbackEnabled else {
                return nil
            }
            return await definition.cliProbe.isAvailable() ? definition.cliProbe : nil
        }
    }

    private func attachDailyReport(
        to snapshot: UsageSnapshot,
        using analyzer: (any DailyUsageAnalyzing)?
    ) async -> UsageSnapshot {
        guard let analyzer,
              let report = try? await analyzer.analyzeToday(),
              !report.today.isEmpty || !report.previous.isEmpty else {
            return snapshot
        }

        return UsageSnapshot(
            providerId: snapshot.providerId,
            quotas: snapshot.quotas,
            capturedAt: snapshot.capturedAt,
            accountEmail: snapshot.accountEmail,
            accountOrganization: snapshot.accountOrganization,
            loginMethod: snapshot.loginMethod,
            accountTier: snapshot.accountTier,
            costUsage: snapshot.costUsage,
            bedrockUsage: snapshot.bedrockUsage,
            dailyUsageReport: report
        )
    }

    private func syncAccounts() {
        accounts = accountDefinitions.map(\.account)
        primaryAccount = definition(for: primaryAccountId)?.account
        if let activeSnapshot = accountSnapshots[activeAccountId] {
            snapshot = activeSnapshot
        }
    }

    private static func validAccountId(
        _ candidate: String?,
        definitions: [ClaudeAccountDefinition]
    ) -> String? {
        guard let candidate else { return nil }
        return definitions.contains(where: { $0.account.accountId == candidate }) ? candidate : nil
    }
}

// MARK: - Pass Error

public enum PassError: Error, LocalizedError {
    case probeNotConfigured

    public var errorDescription: String? {
        switch self {
        case .probeNotConfigured:
            return "Guest pass probe is not configured"
        }
    }
}
