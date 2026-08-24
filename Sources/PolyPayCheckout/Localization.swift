import Foundation

/// Returns SDK-localized copy from Swift Package resources.
func localized(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: key, table: "Localizable")
}

/// Formats SDK-localized copy with locale-aware positional values.
func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: localized(key), locale: Locale.current, arguments: arguments)
}
