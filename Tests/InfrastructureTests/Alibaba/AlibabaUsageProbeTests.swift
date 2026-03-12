import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct AlibabaUsageProbeTests {

    private func makeSettingsRepository() -> UserDefaultsProviderSettingsRepository {
        let suiteName = "com.claudebar.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let repo = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
        repo.setEnabled(true, forProvider: "alibaba")
        return repo
    }

    // MARK: - isAvailable

    @Test
    func `isAvailable returns false when no cookie and no API key`() async {
        let repo = makeSettingsRepository()
        repo.setAlibabaCookieSource(.manual)
        // No manual cookie and no API key set

        let probe = AlibabaUsageProbe(settingsRepository: repo)

        let available = await probe.isAvailable()
        #expect(available == false)
    }

    @Test
    func `isAvailable returns true when API key is set`() async {
        let repo = makeSettingsRepository()
        repo.saveAlibabaApiKey("sk-test-key-123")

        let probe = AlibabaUsageProbe(settingsRepository: repo)

        let available = await probe.isAvailable()
        #expect(available == true)
    }

    @Test
    func `isAvailable returns true when manual cookie is set`() async {
        let repo = makeSettingsRepository()
        repo.setAlibabaCookieSource(.manual)
        repo.saveAlibabaManualCookie("login_aliyunid_ticket=abc123")

        let probe = AlibabaUsageProbe(settingsRepository: repo)

        let available = await probe.isAvailable()
        #expect(available == true)
    }
}
