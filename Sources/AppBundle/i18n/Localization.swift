import Foundation

/// Add a language here and provide a matching JSON dictionary in this resource directory.
public enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, zhHans = "zh-Hans"

    public var id: String { rawValue }
    var displayName: String {
        switch self {
            case .system: L("System")
            case .en: "English"
            case .zhHans: "简体中文"
        }
    }
}

private let languagePreferenceKey = "airspace.language"
private let translations: [String: [String: String]] = Dictionary(uniqueKeysWithValues: AppLanguage.allCases.compactMap { language in
    guard language != .system, let url = Bundle.module.url(forResource: language.rawValue, withExtension: "json"),
          let data = try? Data(contentsOf: url), let dictionary = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
    return (language.rawValue, dictionary)
})

func resolveSystemLanguage(_ preferredLanguages: [String]) -> AppLanguage {
    for identifier in preferredLanguages {
        let parts = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
        if parts == "en" || parts.hasPrefix("en-") { return .en }
        if parts == "zh" || parts.hasPrefix("zh-hans") || parts.hasPrefix("zh-cn") || parts.hasPrefix("zh-sg") { return .zhHans }
    }
    return .en
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    let selected = AppLanguage(rawValue: UserDefaults.standard.string(forKey: languagePreferenceKey) ?? "system") ?? .system
    let language: AppLanguage
    if selected == .system {
        language = resolveSystemLanguage(Locale.preferredLanguages)
    } else {
        language = selected
    }
    let translated = translations[language.rawValue]?[key] ?? key
    return arguments.isEmpty ? translated : unsafe String(format: translated, locale: Locale.current, arguments: arguments)
}
