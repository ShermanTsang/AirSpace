import Testing
@testable import AppBundle

struct LocalizationTest {
    @Test func systemLanguageSelection() {
        #expect(resolveSystemLanguage(["fr-FR", "zh-Hans-CN"]) == .zhHans)
        #expect(resolveSystemLanguage(["zh-Hant-TW", "en-US"]) == .en)
        #expect(resolveSystemLanguage(["fr-FR"]) == .en)
    }

    @Test func unknownKeyFallsBack() {
        #expect(L("Untranslated test key") == "Untranslated test key")
    }
}
