import Foundation

enum AppLanguage: String, Codable, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static func preferred(from languageCodes: [String]) -> AppLanguage {
        guard let first = languageCodes.first?.lowercased() else { return .english }
        return first.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

enum L10n {
    static var language: AppLanguage {
        if let override = ProcessInfo.processInfo.environment["YES_ENGINEER_LANGUAGE"],
           let language = AppLanguage(rawValue: override) {
            return language
        }
        return AppLanguage.preferred(from: Locale.preferredLanguages)
    }

    static func text(_ english: String, _ simplifiedChinese: String) -> String {
        language == .simplifiedChinese ? simplifiedChinese : english
    }

    static func format(_ english: String, _ simplifiedChinese: String, _ arguments: CVarArg...) -> String {
        String(format: text(english, simplifiedChinese), arguments: arguments)
    }
}

enum AppEnvironment {
    static let values = ProcessInfo.processInfo.environment

    static var isUITesting: Bool {
        values["YES_ENGINEER_UI_TEST"] == "1"
    }

    static var requestedSettingsPage: Int {
        switch values["YES_ENGINEER_SETTINGS_PAGE"] {
        case "actions": return 2
        case "appscope", "app_scope", "app-scope": return 1
        default: return 0
        }
    }
}
