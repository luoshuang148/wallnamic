import Foundation
import Combine

/// Resolves and stores the language used for interface strings.
///
/// The effective language can either follow the system preference or be pinned
/// to one of the shipped localizations. The selection is shared through the
/// app's preference suite so the background player follows the same choice.
public final class LanguageStore: ObservableObject {
    public static let shared = LanguageStore()

    /// Value stored when the interface should follow the system language.
    public static let systemSelection = "system"
    /// Language used when neither an explicit nor a system language matches.
    public static let fallbackCode = "zh-Hans"
    public static let preferenceSuiteName = "local.zongzihao.Wallnamic.shared"
    public static let preferenceKey = "interfaceLanguage"
    public static let languageDidChangeNotification =
        Notification.Name("local.zongzihao.Wallnamic.languageChanged")

    /// Localizations shipped in the app, in the order shown in Settings.
    public static let supportedCodes = [
        "en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es", "ru", "pt-BR"
    ]
    /// Every selectable value, including the follow-system option.
    public static let selectableCodes = [systemSelection] + supportedCodes

    @Published public private(set) var selection: String

    private let bundle: Bundle
    private let defaults: UserDefaults?
    private let preferredLocalizations: [String]
    private let cache = TableCache()

    public init(suiteName: String = LanguageStore.preferenceSuiteName, bundle: Bundle = .main) {
        self.bundle = bundle
        self.defaults = UserDefaults(suiteName: suiteName)
        self.preferredLocalizations = bundle.preferredLocalizations
        let stored = defaults?.string(forKey: Self.preferenceKey)
        self.selection = Self.validSelection(stored)
    }

    /// The concrete localization code currently in use.
    public var resolvedCode: String {
        Self.resolve(selection: selection, preferred: preferredLocalizations)
    }

    /// Changes the interface language and broadcasts the change to other processes.
    public func setLanguage(_ code: String) {
        guard code == Self.systemSelection || Self.supportedCodes.contains(code) else { return }
        let changed = selection != code
        selection = code
        defaults?.set(code, forKey: Self.preferenceKey)
        defaults?.synchronize()
        guard changed else { return }
        DistributedNotificationCenter.default().post(name: Self.languageDidChangeNotification, object: nil)
    }

    /// Re-reads the selection after another process changed it.
    public func reloadFromDefaults() {
        defaults?.synchronize()
        let stored = Self.validSelection(defaults?.string(forKey: Self.preferenceKey))
        guard stored != selection else { return }
        selection = stored
    }

    /// Returns the localized value for `key`, falling back to zh-Hans and then the key itself.
    public func string(_ key: String) -> String {
        let code = resolvedCode
        if let value = table(for: code)[key], !value.isEmpty { return value }
        if code != Self.fallbackCode,
           let value = table(for: Self.fallbackCode)[key], !value.isEmpty { return value }
        return key
    }

    /// The language name shown in its own language.
    public static func displayName(for code: String) -> String {
        switch code {
        case systemSelection: return L("settings.language.system")
        case "en": return "English"
        case "zh-Hans": return "简体中文"
        case "zh-Hant": return "繁體中文"
        case "ja": return "日本語"
        case "ko": return "한국어"
        case "de": return "Deutsch"
        case "fr": return "Français"
        case "es": return "Español"
        case "ru": return "Русский"
        case "pt-BR": return "Português (Brasil)"
        default: return code
        }
    }

    /// Resolves a stored selection and a list of preferred language identifiers.
    public static func resolve(selection: String, preferred: [String]) -> String {
        if supportedCodes.contains(selection) { return selection }
        for identifier in preferred {
            if let match = supportedMatch(identifier) { return match }
        }
        return fallbackCode
    }

    /// Maps a bundle language identifier (for example `de-AT`) to a shipped localization.
    public static func supportedMatch(_ identifier: String) -> String? {
        if supportedCodes.contains(identifier) { return identifier }
        let lower = identifier.lowercased()
        if lower.hasPrefix("zh") {
            if lower.contains("hant") || lower.contains("-tw") || lower.contains("-hk") || lower.contains("-mo") {
                return "zh-Hant"
            }
            return "zh-Hans"
        }
        if lower.hasPrefix("pt") { return "pt-BR" }
        for code in ["en", "ja", "ko", "de", "fr", "es", "ru"] {
            if lower == code || lower.hasPrefix(code + "-") { return code }
        }
        return nil
    }

    private static func validSelection(_ value: String?) -> String {
        guard let value,
              value == systemSelection || supportedCodes.contains(value) else {
            return systemSelection
        }
        return value
    }

    private func table(for code: String) -> [String: String] {
        cache.lock.lock()
        if let cached = cache.tables[code] {
            cache.lock.unlock()
            return cached
        }
        cache.lock.unlock()

        let loaded = loadTable(for: code)
        cache.lock.lock()
        cache.tables[code] = loaded
        cache.lock.unlock()
        return loaded
    }

    private func loadTable(for code: String) -> [String: String] {
        guard let url = bundle.resourceURL?
                .appendingPathComponent("\(code).lproj", isDirectory: true)
                .appendingPathComponent("Localizable.strings"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let table = plist as? [String: String] else {
            return [:]
        }
        return table
    }
}

private final class TableCache {
    let lock = NSLock()
    var tables: [String: [String: String]] = [:]
}
