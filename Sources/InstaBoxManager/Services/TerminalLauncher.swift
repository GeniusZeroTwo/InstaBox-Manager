import AppKit
import Foundation

public enum TerminalAppPreference: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case iterm = "iTerm"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .terminal: return "macOS 终端 (Terminal.app)"
        case .iterm: return "iTerm2 (iTerm.app)"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm: return "com.googlecode.iterm2"
        }
    }
}

public enum TerminalLauncher {
    /// Launches an interactive SSH command in Terminal.app or iTerm2 via a self-cleaning `.command` script,
    /// avoiding macOS AppleEvents / TCC automation permission prompts.
    public static func openSSHCommand(_ sshCommand: String, machineName: String, preferredApp: TerminalAppPreference = .terminal) throws {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sshCommand, forType: .string)

        let tempDir = FileManager.default.temporaryDirectory
        let safeName = machineName.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        let scriptURL = tempDir.appendingPathComponent("instabox-\(safeName)-\(UUID().uuidString.prefix(6)).command")

        let scriptContent = """
        #!/bin/zsh
        rm -f "$0"
        clear
        echo "===================================================="
        echo " InstaBox SSH -> \(safeName)"
        echo " Command: \(sshCommand)"
        echo "===================================================="
        exec \(sshCommand)
        """

        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        if preferredApp == .iterm,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalAppPreference.iterm.bundleIdentifier) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([scriptURL], withApplicationAt: appURL, configuration: config)
        } else if let termURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalAppPreference.terminal.bundleIdentifier) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([scriptURL], withApplicationAt: termURL, configuration: config)
        } else {
            NSWorkspace.shared.open(scriptURL)
        }
    }

    public static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
