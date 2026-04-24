import Foundation

/// Persists the selected primary Claude config root and wires shell startup integration.
public enum ClaudeShellIntegration {
    public static let hookMarker = "# ClaudeBar Claude multi-account integration"

    public static func setActiveConfigRoot(_ path: String, appDirectory: URL = defaultAppDirectory()) {
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        try? path.write(to: pointerFileURL(appDirectory: appDirectory), atomically: true, encoding: .utf8)
    }

    public static func activeConfigRoot(appDirectory: URL = defaultAppDirectory()) -> String? {
        guard let contents = try? String(contentsOf: pointerFileURL(appDirectory: appDirectory), encoding: .utf8) else {
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func installZshHookIfNeeded(
        zshrcURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc"),
        appDirectory: URL = defaultAppDirectory()
    ) {
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        let integrationScriptURL = appDirectory.appendingPathComponent("claude-shell-integration.zsh")
        try? integrationScriptContents(appDirectory: appDirectory)
            .write(to: integrationScriptURL, atomically: true, encoding: .utf8)

        let sourceLine = "source \"\(integrationScriptURL.path)\""
        var zshrcContents = (try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? ""
        guard !zshrcContents.contains(hookMarker) else {
            return
        }

        if !zshrcContents.isEmpty, !zshrcContents.hasSuffix("\n") {
            zshrcContents += "\n"
        }

        zshrcContents += "\(hookMarker)\n\(sourceLine)\n"
        try? zshrcContents.write(to: zshrcURL, atomically: true, encoding: .utf8)
    }

    public static func defaultConfigRootPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .path
    }

    public static func defaultAppDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claudebar", isDirectory: true)
    }

    private static func pointerFileURL(appDirectory: URL) -> URL {
        appDirectory.appendingPathComponent("active-claude-config-dir")
    }

    private static func integrationScriptContents(appDirectory: URL) -> String {
        let pointerPath = pointerFileURL(appDirectory: appDirectory).path
        let defaultConfigRoot = defaultConfigRootPath()
        return """
        #!/usr/bin/env zsh
        # Managed by ClaudeBar. Reads the active Claude config root selected in the app.
        _claudebar_sync_claude_config_dir() {
          local pointer_file="\(pointerPath)"
          local default_root="\(defaultConfigRoot)"
          if [[ -f "$pointer_file" ]]; then
            local selected_root
            selected_root="$(<"$pointer_file")"
            if [[ -n "$selected_root" && "$selected_root" != "$default_root" ]]; then
              export CLAUDE_CONFIG_DIR="$selected_root"
            else
              unset CLAUDE_CONFIG_DIR
            fi
          else
            unset CLAUDE_CONFIG_DIR
          fi
        }

        autoload -Uz add-zsh-hook 2>/dev/null
        if typeset -f add-zsh-hook >/dev/null 2>&1; then
          add-zsh-hook precmd _claudebar_sync_claude_config_dir
        fi
        _claudebar_sync_claude_config_dir
        """
    }
}
