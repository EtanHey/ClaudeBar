import Testing
import Foundation
@testable import Infrastructure

@Suite("ClaudeShellIntegration Tests")
struct ClaudeShellIntegrationTests {

    @Test
    func `stores active config root in app support file`() throws {
        let appSupport = makeTempDirectory()
        defer { cleanup(appSupport) }

        ClaudeShellIntegration.setActiveConfigRoot(
            "/Users/test/.claude-secondary",
            appDirectory: appSupport
        )

        #expect(
            ClaudeShellIntegration.activeConfigRoot(appDirectory: appSupport)
                == "/Users/test/.claude-secondary"
        )
    }

    @Test
    func `installing zsh hook is idempotent and creates integration script`() throws {
        let directory = makeTempDirectory()
        defer { cleanup(directory) }

        let zshrc = directory.appendingPathComponent(".zshrc")
        try "".write(to: zshrc, atomically: true, encoding: .utf8)

        ClaudeShellIntegration.installZshHookIfNeeded(
            zshrcURL: zshrc,
            appDirectory: directory
        )
        ClaudeShellIntegration.installZshHookIfNeeded(
            zshrcURL: zshrc,
            appDirectory: directory
        )

        let zshrcContents = try String(contentsOf: zshrc, encoding: .utf8)
        #expect(zshrcContents.components(separatedBy: ClaudeShellIntegration.hookMarker).count == 2)

        let integrationScript = directory.appendingPathComponent("claude-shell-integration.zsh")
        let scriptContents = try String(contentsOf: integrationScript, encoding: .utf8)
        #expect(scriptContents.contains("CLAUDE_CONFIG_DIR"))
        #expect(scriptContents.contains("active-claude-config-dir"))
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-shell-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
