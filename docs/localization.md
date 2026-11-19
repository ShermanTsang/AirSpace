# Interface translations

AirSpace follows the first supported language in the macOS preferred-language list by default. The General settings page can override this choice with English or Simplified Chinese; the choice is stored in user defaults.

Interface strings use `L("English text")`. English is the fallback for missing keys. Translations are stored in `Sources/AppBundle/i18n/zh-Hans.json`. Configuration keys, commands, and diagnostic details must remain unchanged.

To add a language, add an `AppLanguage` case and its native display name, add a JSON dictionary named after its language identifier, include that file in the AppBundle resources in `Package.swift`, and update `resolveSystemLanguage` to match its supported system locale identifiers. Translate format placeholders without changing their types, and test language selection and fallback.
