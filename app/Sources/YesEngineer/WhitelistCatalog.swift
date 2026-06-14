import Foundation

/// Metadata for a built-in whitelist entry: human-readable display name and
/// the category shown in the App Scope tab.
struct WhitelistEntry: Codable, Equatable {
    enum Category: String, Codable, CaseIterable {
        case terminal
        case aiEditor
        case editor

        var displayName: String {
            switch self {
            case .terminal: return L10n.text("Terminals", "终端")
            case .aiEditor: return L10n.text("AI Coding Editors", "AI 编程编辑器")
            case .editor: return L10n.text("Code Editors", "代码编辑器")
            }
        }
    }

    let bundleID: String
    let displayName: String
    let category: Category
    let note: String?
}

/// User-defined whitelist entry (added from the App Scope tab).
struct CustomApp: Codable, Equatable {
    var id: String
    var bundleID: String
    var displayName: String
    var note: String?
}

/// Single source of truth for the built-in allowlist. Both sides of the
/// config (default + initial enabled set) are derived from this table.
enum WhitelistCatalog {
    /// Order matters — this is the order the App Scope tab renders them in.
    static let entries: [WhitelistEntry] = [
        // Terminals
        .init(bundleID: "com.apple.Terminal", displayName: "Terminal",
              category: .terminal,
              note: L10n.text("Built-in macOS terminal", "macOS 自带终端")),
        .init(bundleID: "com.googlecode.iterm2", displayName: "iTerm2",
              category: .terminal, note: nil),
        .init(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty",
              category: .terminal, note: nil),
        .init(bundleID: "dev.warp.Warp-Stable", displayName: "Warp (legacy bundle)",
              category: .terminal,
              note: L10n.text("Older Warp installations only", "仅旧版 Warp 使用")),
        .init(bundleID: "dev.warp.Warp", displayName: "Warp",
              category: .terminal, note: nil),
        .init(bundleID: "net.kovidgoyal.kitty", displayName: "Kitty",
              category: .terminal, note: nil),
        .init(bundleID: "io.alacritty", displayName: "Alacritty",
              category: .terminal, note: nil),
        .init(bundleID: "co.zeit.hyper", displayName: "Hyper",
              category: .terminal, note: nil),
        .init(bundleID: "org.tabby", displayName: "Tabby",
              category: .terminal, note: nil),
        .init(bundleID: "com.github.wez.wezterm", displayName: "WezTerm",
              category: .terminal, note: nil),

        // AI coding editors
        .init(bundleID: "com.todesktop.230313mzl4w4u92", displayName: "Cursor",
              category: .aiEditor, note: nil),
        .init(bundleID: "com.exafunction.windsurf", displayName: "Windsurf",
              category: .aiEditor, note: nil),
        .init(bundleID: "dev.zed.Zed", displayName: "Zed",
              category: .aiEditor,
              note: L10n.text("Built-in AI assistant", "自带 AI 助手")),

        // Generic code editors
        .init(bundleID: "com.microsoft.VSCode", displayName: "Visual Studio Code",
              category: .editor, note: nil),
        .init(bundleID: "com.apple.dt.Xcode", displayName: "Xcode",
              category: .editor, note: nil),
    ]

    static var defaultBundleIDs: [String] { entries.map(\.bundleID) }

    static func entry(for bundleID: String) -> WhitelistEntry? {
        entries.first(where: { $0.bundleID == bundleID })
    }
}
