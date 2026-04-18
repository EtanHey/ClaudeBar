import Testing
import Foundation
import Domain
@testable import Infrastructure

@Suite("ClaudeAccountDiscovery Tests")
struct ClaudeAccountDiscoveryTests {

    @Test
    func `discovers default root and sibling claude roots`() throws {
        let home = makeTempHome()
        defer { cleanup(home) }

        try createClaudeAccount(home: home, rootName: ".claude", email: "primary@example.com", displayName: "Primary User")
        try createClaudeAccount(home: home, rootName: ".claude-secondary", email: "secondary@example.com", displayName: "Secondary User")
        try createClaudeAccount(home: home, rootName: ".claude-work", email: "work@example.com", displayName: "Work User")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".cursor"), withIntermediateDirectories: true)

        let discovery = ClaudeAccountDiscovery(homeDirectory: home)

        let accounts = try discovery.discoverAccounts()

        #expect(accounts.count == 3)
        #expect(accounts.first?.account.accountId == ProviderAccount.defaultAccountId)
        #expect(accounts.first?.account.email == "primary@example.com")
        #expect(accounts.map(\.account.accountId).contains("secondary"))
        #expect(accounts.map(\.account.accountId).contains("work"))
    }

    @Test
    func `ignores sibling roots without readable oauth account metadata`() throws {
        let home = makeTempHome()
        defer { cleanup(home) }

        try createClaudeAccount(home: home, rootName: ".claude", email: "primary@example.com", displayName: "Primary User")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude-broken"),
            withIntermediateDirectories: true
        )
        try "{}".write(
            to: home.appendingPathComponent(".claude-broken/.claude.json"),
            atomically: true,
            encoding: .utf8
        )

        let discovery = ClaudeAccountDiscovery(homeDirectory: home)

        let accounts = try discovery.discoverAccounts()

        #expect(accounts.count == 1)
        #expect(accounts.first?.account.email == "primary@example.com")
    }

    private func makeTempHome() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-home-\(UUID().uuidString)", isDirectory: true)
    }

    private func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private func createClaudeAccount(
        home: URL,
        rootName: String,
        email: String,
        displayName: String
    ) throws {
        let fm = FileManager.default
        let root = home.appendingPathComponent(rootName, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let payload = """
        {
          "oauthAccount": {
            "emailAddress": "\(email)",
            "displayName": "\(displayName)",
            "organizationName": "\(displayName) Org"
          }
        }
        """

        let metadataURL: URL
        if rootName == ".claude" {
            metadataURL = home.appendingPathComponent(".claude.json")
        } else {
            metadataURL = root.appendingPathComponent(".claude.json")
        }

        try payload.write(to: metadataURL, atomically: true, encoding: .utf8)
    }
}
