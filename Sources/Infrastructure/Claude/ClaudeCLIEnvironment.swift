import Foundation

/// Builds environment overrides for Claude CLI subprocesses.
///
/// The default Claude account must run without `CLAUDE_CONFIG_DIR` so the CLI keeps
/// resolving its primary metadata from `~/.claude.json`. Non-default roots still need
/// the override so Claude switches to that account's isolated config directory.
public enum ClaudeCLIEnvironment {
    public static func defaultConfigRootPath(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .path
    }

    public static func overrides(
        forConfigRootPath configRootPath: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        guard configRootPath != defaultConfigRootPath(homeDirectory: homeDirectory) else {
            return [:]
        }

        return ["CLAUDE_CONFIG_DIR": configRootPath]
    }
}
