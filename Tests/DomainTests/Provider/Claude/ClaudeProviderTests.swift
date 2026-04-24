import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("ClaudeProvider Tests")
struct ClaudeProviderTests {

    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - Identity

    @Test
    func `claude provider has correct id`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.id == "claude")
    }

    @Test
    func `claude provider has correct name`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.name == "Claude")
    }

    @Test
    func `claude provider has correct cliCommand`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.cliCommand == "claude")
    }

    @Test
    func `claude provider has dashboard URL pointing to anthropic`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.dashboardURL != nil)
        #expect(claude.dashboardURL?.host?.contains("anthropic") == true)
    }

    @Test
    func `claude provider is enabled by default`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.isEnabled == true)
    }

    // MARK: - State

    @Test
    func `claude provider starts with no snapshot`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.snapshot == nil)
    }

    @Test
    func `claude provider starts not syncing`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.isSyncing == false)
    }

    @Test
    func `claude provider starts with no error`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.lastError == nil)
    }

    // MARK: - Delegation

    @Test
    func `claude provider delegates isAvailable to probe`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        let isAvailable = await claude.isAvailable()
        #expect(isAvailable == true)
    }

    @Test
    func `isAvailable returns false in API mode when API unavailable and CLI fallback disabled`() async {
        let settings = FakeClaudeSettings(probeMode: .api, cliFallbackEnabled: false)
        let cliProbe = MockUsageProbe()
        given(cliProbe).isAvailable().willReturn(true)
        let apiProbe = MockUsageProbe()
        given(apiProbe).isAvailable().willReturn(false)
        let claude = ClaudeProvider(cliProbe: cliProbe, apiProbe: apiProbe, settingsRepository: settings)

        #expect(await claude.isAvailable() == false)
    }

    @Test
    func `isAvailable returns true in API mode when API unavailable but CLI fallback enabled`() async {
        let settings = FakeClaudeSettings(probeMode: .api, cliFallbackEnabled: true)
        let cliProbe = MockUsageProbe()
        given(cliProbe).isAvailable().willReturn(true)
        let apiProbe = MockUsageProbe()
        given(apiProbe).isAvailable().willReturn(false)
        let claude = ClaudeProvider(cliProbe: cliProbe, apiProbe: apiProbe, settingsRepository: settings)

        #expect(await claude.isAvailable() == true)
    }

    @Test
    func `claude provider delegates refresh to probe`() async throws {
        let settings = makeSettingsRepository()
        let expectedSnapshot = UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date())
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        let snapshot = try await claude.refresh()
        #expect(snapshot.quotas.isEmpty)
    }

    // MARK: - Snapshot Storage

    @Test
    func `claude provider stores snapshot after refresh`() async throws {
        let settings = makeSettingsRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.snapshot == nil)
        _ = try await claude.refresh()
        #expect(claude.snapshot != nil)
        #expect(claude.snapshot?.quotas.first?.percentRemaining == 50)
    }

    // MARK: - Error Handling

    @Test
    func `claude provider stores error on refresh failure`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.timeout)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.lastError == nil)
        do {
            _ = try await claude.refresh()
        } catch {
            // Expected
        }
        #expect(claude.lastError != nil)
    }

    // MARK: - Syncing State

    @Test
    func `claude provider resets isSyncing after refresh completes`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date()))
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.isSyncing == false)
        _ = try await claude.refresh()
        #expect(claude.isSyncing == false)
    }

    // MARK: - Equality via ID

    @Test
    func `two claude providers have same id`() {
        let settings = makeSettingsRepository()
        let provider1 = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let provider2 = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(provider1.id == provider2.id)
    }

    // MARK: - Multi-Account

    @Test
    func `multi account provider exposes discovered accounts and persists active selection`() {
        let settings = FakeMultiAccountClaudeSettings(activeAccountId: "secondary")
        let primaryProbe = MockUsageProbe()
        let secondaryProbe = MockUsageProbe()

        let claude = ClaudeProvider(
            accounts: [
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: ProviderAccount.defaultAccountId,
                        providerId: "claude",
                        label: "Default",
                        email: "primary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude",
                    cliProbe: primaryProbe
                ),
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: "secondary",
                        providerId: "claude",
                        label: "Secondary",
                        email: "secondary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude-secondary",
                    cliProbe: secondaryProbe
                ),
            ],
            settingsRepository: settings
        )

        #expect(claude.accounts.count == 2)
        #expect(claude.activeAccount.accountId == "secondary")

        #expect(claude.switchAccount(to: ProviderAccount.defaultAccountId) == true)
        #expect(claude.activeAccount.accountId == ProviderAccount.defaultAccountId)
        #expect(settings.storedActiveAccountId == ProviderAccount.defaultAccountId)
    }

    @Test
    func `refreshing active multi account updates active snapshot and accountSnapshots`() async throws {
        let settings = FakeMultiAccountClaudeSettings(activeAccountId: "secondary")

        let primaryProbe = MockUsageProbe()
        given(primaryProbe).probe().willReturn(
            UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude")],
                capturedAt: Date(),
                accountEmail: "primary@example.com"
            )
        )

        let secondaryProbe = MockUsageProbe()
        given(secondaryProbe).probe().willReturn(
            UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 35, quotaType: .session, providerId: "claude")],
                capturedAt: Date(),
                accountEmail: "secondary@example.com"
            )
        )

        let claude = ClaudeProvider(
            accounts: [
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: ProviderAccount.defaultAccountId,
                        providerId: "claude",
                        label: "Default",
                        email: "primary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude",
                    cliProbe: primaryProbe
                ),
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: "secondary",
                        providerId: "claude",
                        label: "Secondary",
                        email: "secondary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude-secondary",
                    cliProbe: secondaryProbe
                ),
            ],
            settingsRepository: settings
        )

        let snapshot = try await claude.refresh()

        #expect(snapshot.accountEmail == "secondary@example.com")
        #expect(claude.snapshot?.accountEmail == "secondary@example.com")
        #expect(claude.accountSnapshots["secondary"]?.accountEmail == "secondary@example.com")
    }

    @Test
    func `refresh returns active account first and warms inactive accounts afterward`() async throws {
        let settings = FakeMultiAccountClaudeSettings(activeAccountId: "secondary")

        let primaryProbe = DelayedUsageProbe(
            snapshot: UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 82, quotaType: .session, providerId: "claude")],
                capturedAt: Date(),
                accountEmail: "primary@example.com"
            ),
            delayNanoseconds: 350_000_000
        )

        let secondaryProbe = DelayedUsageProbe(
            snapshot: UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 41, quotaType: .session, providerId: "claude")],
                capturedAt: Date(),
                accountEmail: "secondary@example.com"
            ),
            delayNanoseconds: 15_000_000
        )

        let claude = ClaudeProvider(
            accounts: [
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: ProviderAccount.defaultAccountId,
                        providerId: "claude",
                        label: "Default",
                        email: "primary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude",
                    cliProbe: primaryProbe
                ),
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: "secondary",
                        providerId: "claude",
                        label: "Secondary",
                        email: "secondary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude-secondary",
                    cliProbe: secondaryProbe
                ),
            ],
            settingsRepository: settings
        )

        let startedAt = Date()
        let snapshot = try await claude.refresh()
        let refreshDuration = Date().timeIntervalSince(startedAt)

        #expect(snapshot.accountEmail == "secondary@example.com")
        #expect(claude.accountSnapshots["secondary"]?.accountEmail == "secondary@example.com")
        #expect(claude.accountSnapshots[ProviderAccount.defaultAccountId] == nil)
        #expect(refreshDuration < 0.2)

        for _ in 0..<10 where claude.accountSnapshots[ProviderAccount.defaultAccountId] == nil {
            try? await Task.sleep(nanoseconds: 60_000_000)
        }

        #expect(claude.accountSnapshots[ProviderAccount.defaultAccountId]?.accountEmail == "primary@example.com")
    }

    @Test
    func `refreshing non active account stores account specific error`() async {
        let settings = FakeMultiAccountClaudeSettings(activeAccountId: ProviderAccount.defaultAccountId)
        let primaryProbe = MockUsageProbe()
        given(primaryProbe).probe().willReturn(
            UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude")],
                capturedAt: Date(),
                accountEmail: "primary@example.com"
            )
        )

        let expectedError = ProbeError.timeout
        let secondaryProbe = ScriptedUsageProbe(results: [.failure(expectedError)])

        let claude = ClaudeProvider(
            accounts: [
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: ProviderAccount.defaultAccountId,
                        providerId: "claude",
                        label: "Default",
                        email: "primary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude",
                    cliProbe: primaryProbe
                ),
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: "secondary",
                        providerId: "claude",
                        label: "Secondary",
                        email: "secondary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude-secondary",
                    cliProbe: secondaryProbe
                ),
            ],
            settingsRepository: settings
        )

        do {
            _ = try await claude.refreshAccount("secondary")
        } catch {
            // Expected
        }

        #expect(claude.accountErrors["secondary"]?.localizedDescription == expectedError.localizedDescription)
        #expect(claude.accountError(for: "secondary")?.localizedDescription == expectedError.localizedDescription)
        #expect(claude.lastError == nil)
    }

    @Test
    func `refreshing non active account successfully clears prior account error`() async throws {
        let settings = FakeMultiAccountClaudeSettings(activeAccountId: ProviderAccount.defaultAccountId)
        let primaryProbe = MockUsageProbe()
        given(primaryProbe).probe().willReturn(
            UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude")],
                capturedAt: Date(),
                accountEmail: "primary@example.com"
            )
        )

        let expectedSnapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 55, quotaType: .session, providerId: "claude")],
            capturedAt: Date(),
            accountEmail: "secondary@example.com"
        )
        let secondaryProbe = ScriptedUsageProbe(results: [
            .failure(ProbeError.timeout),
            .success(expectedSnapshot),
        ])

        let claude = ClaudeProvider(
            accounts: [
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: ProviderAccount.defaultAccountId,
                        providerId: "claude",
                        label: "Default",
                        email: "primary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude",
                    cliProbe: primaryProbe
                ),
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: "secondary",
                        providerId: "claude",
                        label: "Secondary",
                        email: "secondary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude-secondary",
                    cliProbe: secondaryProbe
                ),
            ],
            settingsRepository: settings
        )

        do {
            _ = try await claude.refreshAccount("secondary")
        } catch {
            // Expected on first attempt
        }

        #expect(claude.accountErrors["secondary"] != nil)

        let snapshot = try await claude.refreshAccount("secondary")

        #expect(snapshot.accountEmail == "secondary@example.com")
        #expect(claude.accountErrors["secondary"] == nil)
        #expect(claude.accountError(for: "secondary") == nil)
    }

    @Test
    func `refreshing active account still stores lastError for back compat`() async {
        let settings = FakeMultiAccountClaudeSettings(activeAccountId: "secondary")
        let primaryProbe = MockUsageProbe()
        given(primaryProbe).probe().willReturn(
            UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude")],
                capturedAt: Date(),
                accountEmail: "primary@example.com"
            )
        )

        let expectedError = ProbeError.executionFailed("secondary probe failed")
        let secondaryProbe = ScriptedUsageProbe(results: [.failure(expectedError)])

        let claude = ClaudeProvider(
            accounts: [
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: ProviderAccount.defaultAccountId,
                        providerId: "claude",
                        label: "Default",
                        email: "primary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude",
                    cliProbe: primaryProbe
                ),
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: "secondary",
                        providerId: "claude",
                        label: "Secondary",
                        email: "secondary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude-secondary",
                    cliProbe: secondaryProbe
                ),
            ],
            settingsRepository: settings
        )

        do {
            _ = try await claude.refreshAccount("secondary")
        } catch {
            // Expected
        }

        #expect(claude.lastError?.localizedDescription == expectedError.localizedDescription)
        #expect(claude.accountErrors["secondary"]?.localizedDescription == expectedError.localizedDescription)
    }

    @Test
    func `refreshAllAccounts records inactive account errors while keeping active account healthy`() async {
        let settings = FakeMultiAccountClaudeSettings(activeAccountId: ProviderAccount.defaultAccountId)
        let primaryProbe = MockUsageProbe()
        given(primaryProbe).probe().willReturn(
            UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude")],
                capturedAt: Date(),
                accountEmail: "primary@example.com"
            )
        )

        let expectedError = ProbeError.timeout
        let secondaryProbe = ScriptedUsageProbe(results: [.failure(expectedError)])

        let claude = ClaudeProvider(
            accounts: [
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: ProviderAccount.defaultAccountId,
                        providerId: "claude",
                        label: "Default",
                        email: "primary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude",
                    cliProbe: primaryProbe
                ),
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: "secondary",
                        providerId: "claude",
                        label: "Secondary",
                        email: "secondary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude-secondary",
                    cliProbe: secondaryProbe
                ),
            ],
            settingsRepository: settings
        )

        await claude.refreshAllAccounts()

        #expect(claude.snapshot?.accountEmail == "primary@example.com")
        #expect(claude.accountErrors["secondary"]?.localizedDescription == expectedError.localizedDescription)
        #expect(claude.lastError == nil)
    }

    @Test
    func `setting primary account updates primary account and invokes callback`() {
        let settings = FakeMultiAccountClaudeSettings()
        let primaryProbe = MockUsageProbe()
        let secondaryProbe = MockUsageProbe()
        var selectedPrimary: String?

        let claude = ClaudeProvider(
            accounts: [
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: ProviderAccount.defaultAccountId,
                        providerId: "claude",
                        label: "Default",
                        email: "primary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude",
                    cliProbe: primaryProbe
                ),
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: "secondary",
                        providerId: "claude",
                        label: "Secondary",
                        email: "secondary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude-secondary",
                    cliProbe: secondaryProbe
                ),
            ],
            settingsRepository: settings,
            primaryAccountId: ProviderAccount.defaultAccountId,
            onPrimaryAccountChange: { selectedPrimary = $0.account.accountId }
        )

        #expect(claude.primaryAccount?.accountId == ProviderAccount.defaultAccountId)
        #expect(claude.setPrimaryAccount(to: "secondary") == true)
        #expect(claude.primaryAccount?.accountId == "secondary")
        #expect(selectedPrimary == "secondary")
    }

    @Test
    func `setting alias updates account label and persists account config`() {
        let settings = FakeMultiAccountClaudeSettings()
        let primaryProbe = MockUsageProbe()
        let secondaryProbe = MockUsageProbe()

        let claude = ClaudeProvider(
            accounts: [
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: ProviderAccount.defaultAccountId,
                        providerId: "claude",
                        label: "Default",
                        email: "primary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude",
                    cliProbe: primaryProbe
                ),
                ClaudeAccountDefinition(
                    account: ProviderAccount(
                        accountId: "secondary",
                        providerId: "claude",
                        label: "Secondary",
                        email: "secondary@example.com"
                    ),
                    configRootPath: "/Users/test/.claude-secondary",
                    cliProbe: secondaryProbe
                ),
            ],
            settingsRepository: settings
        )

        #expect(claude.setAlias("Work", for: "secondary") == true)
        #expect(claude.accounts.first(where: { $0.accountId == "secondary" })?.label == "Work")
        #expect(settings.savedAccounts["secondary"]?.label == "Work")
        #expect(settings.savedAccounts["secondary"]?.probeConfig["configRootPath"] == "/Users/test/.claude-secondary")
    }
}

// MARK: - Test Helpers

private final class FakeClaudeSettings: ClaudeSettingsRepository, @unchecked Sendable {
    var probeMode: ClaudeProbeMode
    var cliFallbackEnabled: Bool

    init(probeMode: ClaudeProbeMode = .cli, cliFallbackEnabled: Bool = true) {
        self.probeMode = probeMode
        self.cliFallbackEnabled = cliFallbackEnabled
    }

    func isEnabled(forProvider id: String) -> Bool { true }
    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { true }
    func setEnabled(_ enabled: Bool, forProvider id: String) {}
    func customCardURL(forProvider id: String) -> String? { nil }
    func setCustomCardURL(_ url: String?, forProvider id: String) {}
    func claudeProbeMode() -> ClaudeProbeMode { probeMode }
    func setClaudeProbeMode(_ mode: ClaudeProbeMode) { probeMode = mode }
    func claudeCliFallbackEnabled() -> Bool { cliFallbackEnabled }
    func setClaudeCliFallbackEnabled(_ enabled: Bool) { cliFallbackEnabled = enabled }
}

private final class FakeMultiAccountClaudeSettings: ClaudeSettingsRepository, MultiAccountSettingsRepository, @unchecked Sendable {
    var probeMode: ClaudeProbeMode = .cli
    var cliFallbackEnabled: Bool = true
    var storedActiveAccountId: String?
    var savedAccounts: [String: ProviderAccountConfig] = [:]

    init(activeAccountId: String? = nil) {
        self.storedActiveAccountId = activeAccountId
    }

    func isEnabled(forProvider id: String) -> Bool { true }
    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { true }
    func setEnabled(_ enabled: Bool, forProvider id: String) {}
    func customCardURL(forProvider id: String) -> String? { nil }
    func setCustomCardURL(_ url: String?, forProvider id: String) {}
    func claudeProbeMode() -> ClaudeProbeMode { probeMode }
    func setClaudeProbeMode(_ mode: ClaudeProbeMode) { probeMode = mode }
    func claudeCliFallbackEnabled() -> Bool { cliFallbackEnabled }
    func setClaudeCliFallbackEnabled(_ enabled: Bool) { cliFallbackEnabled = enabled }
    func accounts(forProvider id: String) -> [ProviderAccountConfig] { Array(savedAccounts.values) }
    func addAccount(_ config: ProviderAccountConfig, forProvider id: String) { savedAccounts[config.accountId] = config }
    func removeAccount(accountId: String, forProvider id: String) { savedAccounts.removeValue(forKey: accountId) }
    func updateAccount(_ config: ProviderAccountConfig, forProvider id: String) { savedAccounts[config.accountId] = config }
    func activeAccountId(forProvider id: String) -> String? { storedActiveAccountId }
    func setActiveAccountId(_ accountId: String?, forProvider id: String) { storedActiveAccountId = accountId }
}

private struct DelayedUsageProbe: UsageProbe, @unchecked Sendable {
    let snapshot: UsageSnapshot
    let delayNanoseconds: UInt64

    func probe() async throws -> UsageSnapshot {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return snapshot
    }

    func isAvailable() async -> Bool {
        true
    }
}

private actor ScriptedUsageProbe: UsageProbe {
    private var results: [Result<UsageSnapshot, Error>]

    init(results: [Result<UsageSnapshot, Error>]) {
        self.results = results
    }

    func probe() async throws -> UsageSnapshot {
        guard !results.isEmpty else {
            throw ProbeError.executionFailed("No scripted probe result available")
        }

        let next = results.removeFirst()
        return try next.get()
    }

    func isAvailable() async -> Bool {
        true
    }
}
