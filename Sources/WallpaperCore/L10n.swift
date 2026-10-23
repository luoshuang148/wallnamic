import Foundation

/// Both hand-built app bundles carry the same Localizable.strings tables.
/// Keep lookups in the executable's bundle, including the login-item player.
/// The concrete language is chosen by `LanguageStore`, which can follow the
/// system preference or an in-app selection.
public func L(_ key: String) -> String {
    LanguageStore.shared.string(key)
}
