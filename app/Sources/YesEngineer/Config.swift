import Foundation
import SharedTypes

enum AppMode: String, Codable, CaseIterable {
    case whitelist, global, off

    var menuTitle: String {
        switch self {
        case .whitelist: return L10n.text("Whitelist (recommended)", "白名单（推荐）")
        case .global: return L10n.text("All apps", "所有应用")
        case .off: return L10n.text("Off (log only)", "关闭（仅记录）")
        }
    }

    var shortTitle: String {
        switch self {
        case .whitelist: return L10n.text("Whitelist", "白名单")
        case .global: return L10n.text("All apps", "所有应用")
        case .off: return L10n.text("Off", "关闭")
        }
    }
}

enum FeedbackMode: String, Codable, CaseIterable {
    case toast, alert, off

    var menuTitle: String {
        switch self {
        case .toast: return L10n.text("Toast", "Toast 提醒")
        case .alert: return L10n.text("Alert", "弹窗提醒")
        case .off: return L10n.text("Off", "关闭")
        }
    }
}

enum HotkeyModifier {
    static let command: UInt32 = 1 << 8
    static let shift: UInt32 = 1 << 9
    static let option: UInt32 = 1 << 11
    static let control: UInt32 = 1 << 12
}

struct HotkeySpec: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var displayName: String {
        var s = ""
        if modifiers & HotkeyModifier.control != 0 { s += "⌃" }
        if modifiers & HotkeyModifier.option != 0 { s += "⌥" }
        if modifiers & HotkeyModifier.shift != 0 { s += "⇧" }
        if modifiers & HotkeyModifier.command != 0 { s += "⌘" }
        s += HotkeySpec.keyName(keyCode)
        return s
    }

    static let confirm = HotkeySpec(keyCode: 0x24, modifiers: HotkeyModifier.option | HotkeyModifier.shift)
    static let yes = HotkeySpec(keyCode: 0x10, modifiers: HotkeyModifier.option | HotkeyModifier.shift)
    static let continuePrompt = HotkeySpec(keyCode: 0x08, modifiers: HotkeyModifier.option | HotkeyModifier.shift)

    static func keyName(_ keyCode: UInt32) -> String {
        switch keyCode {
        case 0x24: return "↩"
        case 0x30: return "Tab"
        case 0x31: return "Space"
        case 0x33: return "⌫"
        case 0x73: return "Home"
        case 0x74: return "Page Up"
        case 0x75: return "⌦"
        case 0x77: return "End"
        case 0x79: return "Page Down"
        case 0x7B: return "←"
        case 0x7C: return "→"
        case 0x7D: return "↓"
        case 0x7E: return "↑"
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        default:
            return keyCodeToLetter.first(where: { $0.value == keyCode })?.key.uppercased() ?? "#\(keyCode)"
        }
    }

    static func parse(_ raw: String) -> HotkeySpec? {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        let replacements = [
            "⌘": "+command+",
            "⌃": "+control+",
            "⌥": "+option+",
            "⇧": "+shift+",
            "↩": "+return+",
        ]
        for (from, to) in replacements {
            normalized = normalized.replacingOccurrences(of: from, with: to)
        }
        for sep in ["-", "_", ",", " "] {
            normalized = normalized.replacingOccurrences(of: sep, with: "+")
        }

        let parts = normalized
            .split(separator: "+")
            .map(String.init)
            .filter { !$0.isEmpty }

        var modifiers: UInt32 = 0
        var keyCode: UInt32?
        for part in parts {
            switch part {
            case "command", "cmd", "meta":
                modifiers |= HotkeyModifier.command
            case "control", "ctrl":
                modifiers |= HotkeyModifier.control
            case "option", "opt", "alt":
                modifiers |= HotkeyModifier.option
            case "shift":
                modifiers |= HotkeyModifier.shift
            case "return", "enter":
                keyCode = 0x24
            case "space", "spacebar":
                keyCode = 0x31
            default:
                if part.count == 1, let code = keyCodeToLetter[part] {
                    keyCode = code
                } else {
                    return nil
                }
            }
        }

        guard modifiers != 0, let keyCode = keyCode else { return nil }
        return HotkeySpec(keyCode: keyCode, modifiers: modifiers)
    }

    private static let keyCodeToLetter: [String: UInt32] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17,
        "=": 0x18, "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D,
        "]": 0x1E, "o": 0x1F, "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23,
        "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29, "\\": 0x2A,
        ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
    ]
}

struct TextAction: Codable, Equatable {
    var id: String
    var title: String
    var input: String
    var autoPressReturn: Bool = true
    var hotkey: HotkeySpec
    var enabled: Bool = true

    var menuTitle: String {
        if input.isEmpty {
            return L10n.format("%@ (Return only)", "%@（只按回车）", title)
        }
        return L10n.format("%@: %@", "%@：%@", title, input)
    }

    static let defaultSlapActionID = "yes"

    static let defaults: [TextAction] = [
        TextAction(id: "confirm",
                   title: L10n.text("Confirm / Continue", "确认 / 继续"),
                   input: "",
                   hotkey: .confirm),
        TextAction(id: "yes",
                   title: L10n.text("Type yes", "输入 yes"),
                   input: "yes",
                   hotkey: .yes),
        TextAction(id: "continue",
                   title: L10n.text("Type continue", "输入 continue"),
                   input: "continue",
                   hotkey: .continuePrompt),
    ]
}

struct AppConfig: Codable {
    var minAmplitude: Double = 0.144
    var cooldownMs: Int = 600
    /// New default is `.global` (fires in every foreground app). Users who
    /// want stricter behavior can flip to `.whitelist` and curate the list.
    var mode: AppMode = .global
    /// User's enable/disable choices for the built-in catalog. Bundle IDs
    /// not present in this set are treated as disabled. Defaults to
    /// "all built-ins enabled".
    var enabledDefaultApps: Set<String> = Set(WhitelistCatalog.defaultBundleIDs)
    /// User-added apps. These are always enabled when present.
    var customApps: [CustomApp] = []
    /// Effective allowlist = (enabled built-ins) ∪ (custom apps). Kept
    /// synchronized whenever the user toggles or adds/removes items.
    var apps: [String] = AppConfig.computeApps(
        enabledDefaultApps: Set(WhitelistCatalog.defaultBundleIDs),
        customApps: []
    )
    var paused: Bool = false
    var pauseSlapActions: Bool = false
    var pauseHotkeys: Bool = false
    var slapActionID: String = TextAction.defaultSlapActionID
    var textActions: [TextAction] = TextAction.defaults
    var feedbackMode: FeedbackMode = .toast
    var autoRequestAccessibility: Bool = true

    /// Effective allowlist derived from the two underlying sources.
    var effectiveApps: [String] {
        AppConfig.computeApps(enabledDefaultApps: enabledDefaultApps,
                              customApps: customApps)
    }

    static func computeApps(enabledDefaultApps: Set<String>,
                            customApps: [CustomApp]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in WhitelistCatalog.defaultBundleIDs where enabledDefaultApps.contains(id) {
            if seen.insert(id).inserted { result.append(id) }
        }
        for app in customApps {
            let trimmed = app.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    func daemonConfig() -> DaemonConfig {
        DaemonConfig(minAmplitude: minAmplitude, cooldownMs: cooldownMs)
    }

    var isSlapPaused: Bool {
        paused || pauseSlapActions
    }

    var isHotkeyPaused: Bool {
        paused || pauseHotkeys
    }

    var activeHotkeyActions: [TextAction] {
        isHotkeyPaused ? [] : textActions
    }

    func action(id: String) -> TextAction {
        textActions.first(where: { $0.id == id })
            ?? textActions.first(where: { $0.id == TextAction.defaultSlapActionID })
            ?? textActions.first
            ?? TextAction.defaults[1]
    }

    enum CodingKeys: String, CodingKey {
        case minAmplitude, cooldownMs, mode, apps, paused, pauseSlapActions, pauseHotkeys, slapActionID, textActions, feedbackMode, autoRequestAccessibility
        case enabledDefaultApps, customApps
    }

    init() {
        self.apps = effectiveApps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minAmplitude = try c.decodeIfPresent(Double.self, forKey: .minAmplitude) ?? 0.144
        cooldownMs = try c.decodeIfPresent(Int.self, forKey: .cooldownMs) ?? 600
        // First-run / pre-existing users get the safer `.whitelist` default
        // so we don't silently start sending Enter to every app on upgrade.
        // Only fresh installs (no `mode` key at all) get `.global`.
        let rawMode = try c.decodeIfPresent(String.self, forKey: .mode)
        if let raw = rawMode, let parsed = AppMode(rawValue: raw) {
            mode = parsed
        } else if (try? c.decodeNil(forKey: .mode)) == true {
            // Key exists with null value: written by this version, use new default.
            mode = .global
        } else {
            // Legacy config (no mode key, or unknown value): keep whitelist
            // to preserve prior behavior.
            mode = .whitelist
        }
        enabledDefaultApps = try c.decodeIfPresent(Set<String>.self, forKey: .enabledDefaultApps)
            ?? Set(WhitelistCatalog.defaultBundleIDs)
        customApps = try c.decodeIfPresent([CustomApp].self, forKey: .customApps) ?? []

        // Migration: if a legacy config wrote an `apps` array, intersect it
        // with the built-in catalog to recover the user's enable/disable
        // choices. Anything in the legacy list that doesn't match a known
        // built-in is treated as a custom app so we don't drop it.
        if let legacyApps = try c.decodeIfPresent([String].self, forKey: .apps) {
            let builtInSet = Set(WhitelistCatalog.defaultBundleIDs)
            var rebuiltEnabled: Set<String> = []
            var migrated: [CustomApp] = []
            for id in legacyApps {
                if builtInSet.contains(id) {
                    rebuiltEnabled.insert(id)
                } else {
                    migrated.append(CustomApp(
                        id: "migrated-\(UUID().uuidString)",
                        bundleID: id,
                        displayName: WhitelistCatalog.entry(for: id)?.displayName ?? id,
                        note: L10n.text("Migrated from previous settings", "从旧配置迁移")))
                }
            }
            // Only override if the user had an explicit choice.
            if !rebuiltEnabled.isEmpty || !legacyApps.isEmpty {
                enabledDefaultApps = rebuiltEnabled
                if !migrated.isEmpty {
                    customApps = migrated + customApps
                }
            }
        }

        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        pauseSlapActions = try c.decodeIfPresent(Bool.self, forKey: .pauseSlapActions) ?? false
        pauseHotkeys = try c.decodeIfPresent(Bool.self, forKey: .pauseHotkeys) ?? false
        slapActionID = try c.decodeIfPresent(String.self, forKey: .slapActionID) ?? TextAction.defaultSlapActionID
        textActions = try c.decodeIfPresent([TextAction].self, forKey: .textActions) ?? TextAction.defaults
        feedbackMode = try c.decodeIfPresent(FeedbackMode.self, forKey: .feedbackMode) ?? .toast
        autoRequestAccessibility = try c.decodeIfPresent(Bool.self, forKey: .autoRequestAccessibility) ?? true
        if textActions.isEmpty {
            textActions = TextAction.defaults
        }
        if !textActions.contains(where: { $0.id == slapActionID }) {
            slapActionID = textActions.first(where: { $0.id == TextAction.defaultSlapActionID })?.id
                ?? textActions[0].id
        }
        apps = effectiveApps
    }
}

final class ConfigStore {
    let url: URL
    private(set) var config: AppConfig

    init() {
        let fm = FileManager.default
        let configOverride = ProcessInfo.processInfo.environment["YES_ENGINEER_CONFIG_DIR"]
        let base = configOverride.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("YesEngineer", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("config.json")

        let legacyURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SlapToYes", isDirectory: true)
            .appendingPathComponent("config.json")
        let sourceURL = fm.fileExists(atPath: url.path) || configOverride != nil ? url : legacyURL
        if let data = try? Data(contentsOf: sourceURL),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            self.config = cfg
            if sourceURL == legacyURL {
                save(cfg)
            }
        } else {
            self.config = AppConfig()
        }
    }

    func save(_ cfg: AppConfig) {
        self.config = cfg
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(cfg) {
            try? data.write(to: url)
        }
    }
}
