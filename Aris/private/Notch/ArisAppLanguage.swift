//
//  ArisAppLanguage.swift
//  Aris
//
//  The app's display language: the system's, or one of the bundle's translations that actually has strings.
//  Choosing one writes `AppleLanguages` for this app (and needs a restart).
//

import Foundation

struct AppLanguage: RawRepresentable, Hashable, Identifiable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    var id: String { rawValue }

    static let system = AppLanguage(rawValue: "system")

    /// "System default", then every bundle localization with at least one non-empty string, by name.
    static var allCases: [AppLanguage] { [.system] + available(in: .main) }

    static func available(in bundle: Bundle) -> [AppLanguage] {
        let codes = bundle.localizations.filter { $0 != "Base" && hasStrings(bundle, $0) }
        return choices(codes)
    }

    /// The codes as languages, sorted by their names in their own language.
    static func choices(_ codes: [String]) -> [AppLanguage] {
        codes.map(AppLanguage.init(rawValue:))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func hasStrings(_ bundle: Bundle, _ code: String) -> Bool {
        guard let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: code),
              let table = NSDictionary(contentsOfFile: path) as? [String: Any] else { return false }
        return hasValue(table)
    }

    static func hasValue(_ table: [String: Any]) -> Bool {
        table.values.contains { ($0 as? String).map { !$0.isEmpty } ?? true }
    }

    var displayName: String {
        guard self != .system else { return String(localized: "System default", comment: "App language: follow the system") }
        let own = Locale(identifier: rawValue)
        return own.localizedString(forIdentifier: rawValue)?.capitalized(with: own) ?? rawValue
    }

    /// The system language removes this app's override; anything else sets it.
    func applyAppleLanguagesOverride(_ defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
        defaults.synchronize()
    }
}
