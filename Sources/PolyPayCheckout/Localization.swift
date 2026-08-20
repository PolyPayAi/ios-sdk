import Foundation

/// Returns SDK-localized copy from Swift Package resources.
func localized(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: key, table: "Localizable")
}
