import XCTest
@testable import YesEngineer

final class LocalizationTests: XCTestCase {
    func testLanguageMatchesChineseSystemLocales() {
        XCTAssertEqual(AppLanguage.preferred(from: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.preferred(from: ["zh-Hant-TW"]), .simplifiedChinese)
    }

    func testLanguageFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.preferred(from: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.preferred(from: ["fr-FR"]), .english)
        XCTAssertEqual(AppLanguage.preferred(from: []), .english)
    }
}
