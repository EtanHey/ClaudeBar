import Testing
import Foundation
@testable import Infrastructure

@Suite("ClaudeCLIEnvironment Tests")
struct ClaudeCLIEnvironmentTests {

    @Test
    func `default config root does not inject CLAUDE_CONFIG_DIR`() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

        let overrides = ClaudeCLIEnvironment.overrides(
            forConfigRootPath: "/Users/test/.claude",
            homeDirectory: home
        )

        #expect(overrides.isEmpty)
    }

    @Test
    func `secondary config root injects CLAUDE_CONFIG_DIR`() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

        let overrides = ClaudeCLIEnvironment.overrides(
            forConfigRootPath: "/Users/test/.claude-secondary",
            homeDirectory: home
        )

        #expect(overrides == ["CLAUDE_CONFIG_DIR": "/Users/test/.claude-secondary"])
    }
}
