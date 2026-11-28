import Foundation

/// These defaults apply before reading any editable text. Bundle families cover
/// helper processes and edition-specific identifiers of the listed applications.
package enum LiveHostPolicy {
    private static let excluded = [
        "com.apple.terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "dev.warp.warp-stable", "dev.warp.warp-preview",
        "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby",
        "com.apple.keychainaccess", "com.apple.passwords", "com.apple.securityagent",
        "com.apple.security.authorizationhost", "com.apple.loginwindow",
        "com.apple.localauthentication", "com.apple.coreauth", "com.apple.coreautha", "com.apple.authenticationservices",
        "com.1password", "com.agilebits", "com.bitwarden", "org.keepassxc",
        "com.dashlane", "in.sinew.enpass-desktop", "com.lastpass", "com.nordpass",
        "me.proton.pass", "protontechnology.pass", "com.apple.passwordmanager"
    ]
    private static let alternate = [
        "com.microsoft.vscode", "com.microsoft.vscodeinsiders", "com.visualstudio.code.oss",
        "com.todesktop.230313mzl4w4u92", "com.jetbrains", "com.sublimetext",
        "com.apple.dt.xcode", "dev.zed.zed", "com.microsoft.excel", "com.apple.iwork.numbers",
        "org.vim.macvim", "org.gnu.emacs"
    ]

    private static func matches(_ id: String, _ families: [String]) -> Bool {
        families.contains { id == $0 || id.hasPrefix($0 + ".") }
    }

    /// A role-less HTML contenteditable can appear as a group. Require an
    /// explicit editable flag for generic containers before probing text APIs.
    package static func textControl(role: String, editable: Bool?) -> Bool {
        switch role {
        case "AXTextArea", "AXTextField", "AXComboBox": return editable != false
        case "AXGroup", "AXLayoutArea": return editable == true
        default: return false
        }
    }

    package static func excludesControl(subrole: String?, classes: [String]) -> Bool {
        if ["AXSecureTextField", "AXSystemDialog", "AXSecureTextArea", "AXSourceEditor"].contains(subrole) { return true }
        // Electron IDEs may embed a terminal alongside an ordinary code editor.
        return classes.contains {
            $0 == "xterm" || $0.hasPrefix("xterm-") ||
                ["monaco-editor", "CodeMirror", "cm-editor", "ace_editor"].contains($0)
        }
    }

    package static func enabled(_ bundle: String?) -> Bool {
        guard let id = bundle?.lowercased(), !id.isEmpty else { return false }
        return !matches(id, excluded)
    }

    package static func reservesTab(role: String, classes: [String]) -> Bool {
        role == "AXCell" || role == "AXGrid" ||
            classes.contains { ["monaco-editor", "CodeMirror", "cm-editor", "ace_editor"].contains($0) }
    }

    package static func usesOptionSpace(_ bundle: String) -> Bool {
        matches(bundle.lowercased(), alternate)
    }

    package static func requiresWebDocument(_ bundle: String) -> Bool {
        matches(bundle.lowercased(), ["com.apple.safari", "com.apple.safaritechnologypreview",
            "com.google.chrome", "org.mozilla.firefox", "org.mozilla.nightly",
            "com.microsoft.edgemac", "com.brave.browser", "company.thebrowser.browser"])
    }
}
