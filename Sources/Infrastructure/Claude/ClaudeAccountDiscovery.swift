import Foundation
import Domain

/// Auto-discovers standard Claude config roots on disk.
///
/// Supported roots for v1:
/// - `~/.claude`
/// - `~/.claude-*`
public struct ClaudeAccountDiscovery: Sendable {
    public struct DiscoveredAccountMetadata: Sendable, Decodable {
        public let emailAddress: String?
        public let displayName: String?
        public let organizationName: String?
    }

    private struct ClaudeMetadataRoot: Sendable, Decodable {
        let oauthAccount: DiscoveredAccountMetadata?
    }

    private let homeDirectory: URL
    private let labelOverrides: [String: ProviderAccountConfig]

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        labelOverrides: [ProviderAccountConfig] = []
    ) {
        self.homeDirectory = homeDirectory
        self.labelOverrides = Dictionary(uniqueKeysWithValues: labelOverrides.map { ($0.accountId, $0) })
    }

    public func discoverAccounts() throws -> [ClaudeDiscoveredAccount] {
        let fileManager = FileManager.default
        var roots: [String] = []
        if fileManager.fileExists(atPath: homeDirectory.appendingPathComponent(".claude").path) {
            roots.append(".claude")
        }

        let children = try fileManager.contentsOfDirectory(
            at: homeDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )

        for child in children where child.lastPathComponent.hasPrefix(".claude-") {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                roots.append(child.lastPathComponent)
            }
        }

        let accounts = roots.compactMap { discoverAccount(rootName: $0) }
        return accounts.sorted { lhs, rhs in
            switch (lhs.account.isDefault, rhs.account.isDefault) {
            case (true, false):
                return true
            case (false, true):
                return false
            default:
                return lhs.account.accountId.localizedCaseInsensitiveCompare(rhs.account.accountId) == .orderedAscending
            }
        }
    }

    private func discoverAccount(rootName: String) -> ClaudeDiscoveredAccount? {
        let accountId = accountId(for: rootName)
        let configRoot = homeDirectory.appendingPathComponent(rootName, isDirectory: true)
        let configFileURL = metadataURL(for: rootName, configRoot: configRoot)

        guard let data = try? Data(contentsOf: configFileURL),
              let metadata = try? JSONDecoder().decode(ClaudeMetadataRoot.self, from: data).oauthAccount,
              metadata.emailAddress != nil || metadata.displayName != nil else {
            return nil
        }

        let override = labelOverrides[accountId]
        let label = override?.label ?? defaultLabel(for: accountId)
        let account = ProviderAccount(
            accountId: accountId,
            providerId: "claude",
            label: label,
            email: override?.email ?? metadata.emailAddress,
            organization: override?.organization ?? metadata.organizationName ?? metadata.displayName
        )

        return ClaudeDiscoveredAccount(
            account: account,
            defaultLabel: defaultLabel(for: accountId),
            configRootPath: configRoot.path,
            metadataFilePath: configFileURL.path
        )
    }

    private func accountId(for rootName: String) -> String {
        guard rootName != ".claude" else {
            return ProviderAccount.defaultAccountId
        }
        return String(rootName.dropFirst(".claude-".count))
    }

    private func defaultLabel(for accountId: String) -> String {
        guard accountId != ProviderAccount.defaultAccountId else {
            return "Primary"
        }

        return accountId
            .split(separator: "-")
            .map { segment in
                let lower = segment.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    private func metadataURL(for rootName: String, configRoot: URL) -> URL {
        if rootName == ".claude" {
            return homeDirectory.appendingPathComponent(".claude.json")
        }
        return configRoot.appendingPathComponent(".claude.json")
    }
}

public struct ClaudeDiscoveredAccount: Sendable, Equatable {
    public let account: ProviderAccount
    public let defaultLabel: String
    public let configRootPath: String
    public let metadataFilePath: String

    public init(
        account: ProviderAccount,
        defaultLabel: String,
        configRootPath: String,
        metadataFilePath: String
    ) {
        self.account = account
        self.defaultLabel = defaultLabel
        self.configRootPath = configRootPath
        self.metadataFilePath = metadataFilePath
    }
}
