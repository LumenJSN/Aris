//
//  ArisAppsBundle.swift
//  Shared/Core/Apps
//
//  What an app's Info.plist says it offers: its names (and the localized ones from InfoPlist.loctable or
//  <lang>.lproj/InfoPlist.strings), version, URL schemes, document types, Services, and whether it is scriptable.
//  Pure: the caller hands in the files' bytes.
//

import Foundation

extension ArisApps {
    struct BundleInfo: Codable, Equatable, Sendable {
        struct DocumentType: Codable, Equatable, Sendable {
            var name: String
            var role: String
            var types: [String]
            var extensions: [String]
        }

        struct Service: Codable, Equatable, Sendable {
            var title: String
            var message: String
            var sendTypes: [String]
        }

        var bundle: String = ""
        var name: String = ""
        var displayName: String?
        var version: String = ""
        var build: String = ""
        var schemes: [String] = []
        var documents: [DocumentType] = []
        var services: [Service] = []
        /// NSAppleScriptEnabled or an OSAScriptingDefinition: it has a scripting dictionary.
        var scriptable = false
        /// Localized shown names by language ("ko": "텍스트 편집기").
        var localizedNames: [String: String] = [:]

        /// The cache key: the bundle at this version and build.
        var versionKey: String { "\(bundle)@\(version)(\(build))" }

        /// Every name to match against, shown names first.
        var names: [String] {
            var all: [String] = []
            for name in [displayName, name.isEmpty ? nil : name].compactMap({ $0 }) + localizedNames.keys.sorted().compactMap({ localizedNames[$0] })
            where !all.contains(name) { all.append(name) }
            return all
        }

        /// From Info.plist's bytes (XML or binary), with an InfoPlist.loctable's bytes, or .strings per language.
        static func parse(infoPlist: Data, loctable: Data? = nil, strings: [String: Data] = [:]) -> BundleInfo? {
            guard let plist = (try? PropertyListSerialization.propertyList(from: infoPlist, format: nil)) as? [String: Any] else { return nil }
            var info = BundleInfo()
            info.bundle = plist["CFBundleIdentifier"] as? String ?? ""
            info.name = plist["CFBundleName"] as? String ?? ""
            info.displayName = plist["CFBundleDisplayName"] as? String
            info.version = plist["CFBundleShortVersionString"] as? String ?? ""
            info.build = plist["CFBundleVersion"] as? String ?? ""
            info.scriptable = plist["NSAppleScriptEnabled"] as? Bool == true || (plist["NSAppleScriptEnabled"] as? String)?.lowercased() == "yes"
                || plist["OSAScriptingDefinition"] != nil
            for type in plist["CFBundleURLTypes"] as? [[String: Any]] ?? [] {
                for scheme in type["CFBundleURLSchemes"] as? [String] ?? [] where !info.schemes.contains(scheme.lowercased()) {
                    info.schemes.append(scheme.lowercased())
                }
            }
            for document in plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? [] {
                info.documents.append(DocumentType(name: document["CFBundleTypeName"] as? String ?? "", role: document["CFBundleTypeRole"] as? String ?? "",
                                                   types: document["LSItemContentTypes"] as? [String] ?? [],
                                                   extensions: document["CFBundleTypeExtensions"] as? [String] ?? []))
            }
            for service in plist["NSServices"] as? [[String: Any]] ?? [] {
                let title = ((service["NSMenuItem"] as? [String: Any])?["default"] as? String) ?? ""
                guard !title.isEmpty else { continue }
                info.services.append(Service(title: title, message: service["NSMessage"] as? String ?? "", sendTypes: service["NSSendTypes"] as? [String] ?? []))
            }
            if let loctable, let table = (try? PropertyListSerialization.propertyList(from: loctable, format: nil)) as? [String: Any] {
                for (language, value) in table {
                    guard let entries = value as? [String: Any] else { continue }
                    if let shown = (entries["CFBundleDisplayName"] as? String) ?? (entries["CFBundleName"] as? String) { info.localizedNames[language] = shown }
                }
            }
            for (language, data) in strings {
                if let shown = Self.stringsValue(data, "CFBundleDisplayName") ?? Self.stringsValue(data, "CFBundleName") { info.localizedNames[language] = shown }
            }
            return info
        }

        /// A key's value in a .strings file (old-style plist or binary plist).
        static func stringsValue(_ data: Data, _ key: String) -> String? {
            if let table = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] { return table[key] as? String }
            return nil
        }
    }
}
