import XCTest
@testable import YesEngineer

final class AppConfigTests: XCTestCase {
    func testDefaultSlapActionInputsYesAndPressesReturn() {
        let config = AppConfig()
        let action = config.action(id: config.slapActionID)

        XCTAssertEqual(config.slapActionID, TextAction.defaultSlapActionID)
        XCTAssertEqual(action.input, "yes")
        XCTAssertTrue(action.autoPressReturn)
    }

    func testAccessibilityPromptingDefaultsToEnabled() throws {
        XCTAssertTrue(AppConfig().autoRequestAccessibility)

        let decoded = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.autoRequestAccessibility)
    }

    func testAccessibilityPromptingCanBeDisabled() throws {
        let data = Data(#"{"autoRequestAccessibility":false}"#.utf8)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertFalse(decoded.autoRequestAccessibility)
    }

    func testFreshInstallDefaultsToGlobalMode() throws {
        let config = AppConfig()
        XCTAssertEqual(config.mode, .global)
    }

    func testFreshDecodedConfigWithoutModeKeyKeepsWhitelistForBackcompat() throws {
        // A pre-existing config written by an older version has no `mode`
        // key at all — we should NOT flip it to global silently.
        let decoded = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.mode, .whitelist)
    }

    func testDefaultEnabledAppsContainsFullCatalog() {
        let config = AppConfig()
        XCTAssertEqual(config.enabledDefaultApps, Set(WhitelistCatalog.defaultBundleIDs))
    }

    func testEffectiveAppsIsUnionOfEnabledDefaultsAndCustom() {
        var config = AppConfig()
        config.enabledDefaultApps = ["com.apple.Terminal"]
        config.customApps = [CustomApp(id: "x", bundleID: "com.example.Foo", displayName: "Foo", note: nil)]
        XCTAssertEqual(config.effectiveApps.sorted(),
                       ["com.apple.Terminal", "com.example.Foo"])
    }

    func testTogglingDefaultEntryUpdatesEffectiveApps() {
        var config = AppConfig()
        config.enabledDefaultApps.remove("com.apple.Terminal")
        XCTAssertFalse(config.effectiveApps.contains("com.apple.Terminal"))
    }

    func testLegacyAppsArrayMigratesToEnabledSetAndCustom() throws {
        let legacy = #"{"mode":"whitelist","apps":["com.apple.Terminal","com.example.Legacy"]}"#
        let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(legacy.utf8))
        XCTAssertTrue(decoded.enabledDefaultApps.contains("com.apple.Terminal"))
        XCTAssertFalse(decoded.enabledDefaultApps.contains("com.googlecode.iterm2"))
        XCTAssertTrue(decoded.customApps.contains { $0.bundleID == "com.example.Legacy" })
    }

    func testCustomAppsRoundTrip() throws {
        var config = AppConfig()
        config.customApps = [CustomApp(id: "a", bundleID: "com.trae.app", displayName: "Trae", note: nil)]
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.customApps.count, 1)
        XCTAssertEqual(decoded.customApps.first?.bundleID, "com.trae.app")
    }

    func testDuplicateCustomAppBundleIDsAreDeduplicated() {
        var config = AppConfig()
        config.customApps = [
            CustomApp(id: "1", bundleID: "com.example.X", displayName: "X", note: nil),
            CustomApp(id: "2", bundleID: "com.example.X", displayName: "X2", note: nil),
        ]
        let eff = config.effectiveApps
        XCTAssertEqual(eff.filter { $0 == "com.example.X" }.count, 1)
    }
}
