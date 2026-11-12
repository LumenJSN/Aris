//
//  ArisAppIdentity.swift
//  aris-agent
//
//  Which app a computer-use step is for. The runtime names the app it resolved (a bundle id, `tool_params.app`) and
//  shows its name (`tool_params_display`); Aris takes the bundle id the way Launch Services resolves it, only for an
//  app installed in the usual places, registered once, with a valid signature, and checks the shown name is one of
//  that app's own names (Korean and English). Anything else is unknown: it always asks and is never remembered.
//

import AppKit
import Foundation
import Security

/// Launch Services' lookup of an app by name; deprecated without a replacement for names, so it's called through this
/// protocol (no warning) and stays the same lookup the computer-use runtime resolves a name with.
private protocol ArisAppNameLookup {
    func fullPath(forApplication appName: String) -> String?
}

extension NSWorkspace: ArisAppNameLookup {}

enum ArisAppIdentity {
    /// Where an app may live for its bundle id to count (the system's sealed folder for Safari included).
    static var installRoots: [String] {
        ["/Applications", "/System/Applications", "/System/Library/CoreServices",
         "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
    }

    /// An app's bundle id from a bundle id (any case) or a name (with or without .app). Nil for a path (anything with a
    /// "/"), or when no app matches as `url(ofBundle:)` requires.
    static func bundle(for identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { return nil }
        if let url = url(ofBundle: trimmed) { return Bundle(url: url)?.bundleIdentifier }
        guard let path = (NSWorkspace.shared as ArisAppNameLookup).fullPath(forApplication: trimmed),
              let id = Bundle(path: path)?.bundleIdentifier, url(ofBundle: id) != nil else { return nil }
        return id
    }

    /// The one place the app with this bundle id is registered: under `installRoots`, with a valid signature. Nil when
    /// it's registered nowhere, in more than one place, elsewhere, or unsigned.
    static func url(ofBundle id: String) -> URL? {
        let urls = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
        guard urls.count == 1, let url = urls.first?.resolvingSymlinksInPath(),
              installRoots.contains(where: { url.path.hasPrefix($0 + "/") }), isSigned(url) else { return nil }
        return url
    }

    /// The app's name as the Mac shows it: what the card says and what is remembered.
    static func name(ofBundle id: String) -> String? {
        url(ofBundle: id).map { strippingApp(FileManager.default.displayName(atPath: $0.path)) }
    }

    /// Every name the app gives itself (bundle and display names, in Korean and English, and its file's), lowercased.
    static func names(ofBundle id: String) -> Set<String> {
        guard let url = url(ofBundle: id), let bundle = Bundle(url: url) else { return [] }
        let keys = ["CFBundleDisplayName", "CFBundleName"]
        let tables = [bundle.infoDictionary, bundle.localizedInfoDictionary] + ["ko", "en"].map { localized(bundle, $0) }
        let fromTables = tables.flatMap { table in keys.compactMap { table?[$0] as? String } }
        let files = [FileManager.default.displayName(atPath: url.path), url.lastPathComponent].map(strippingApp)
        return Set((fromTables + files).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
    }

    /// A name as said is one of these names, spacing and case aside ("텍스트편집기" is "텍스트 편집기"; desk-imp-4).
    static func isNamed(_ said: String, among names: Set<String>) -> Bool {
        let fold = { (name: String) in name.precomposedStringWithCanonicalMapping.lowercased().filter { !$0.isWhitespace } }
        let wanted = fold(said)
        return !wanted.isEmpty && names.contains { fold($0) == wanted }
    }

    /// Whether the shown name is one of the named app's own names (never resolved by itself).
    static func matches(shown: String, bundle id: String) -> Bool {
        names(ofBundle: id).contains(shown.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// The app both of the runtime's names stand for: the named one's bundle id, when the shown name is one of its
    /// names. Nil (always asked, never remembered) when either is missing, it can't be resolved, or they differ.
    static func identity(shown: String?, named: String?) -> String? {
        guard let shown, let named, let id = bundle(for: named), matches(shown: shown, bundle: id) else { return nil }
        return id
    }

    /// Apps that open web links (Launch Services), by bundle id: browsers, which never get computer use.
    static let webHandlers: Set<String> = {
        guard let link = URL(string: "https://example.com") else { return [] }
        return Set(NSWorkspace.shared.urlsForApplications(toOpen: link).compactMap { Bundle(url: $0)?.bundleIdentifier })
    }()

    /// A basic check of the app's code signature (milliseconds; the full check reads every file).
    /// Signed by Apple as exactly this bundle (QA follow-up to BUG-15): a system app (anchor apple) or Apple's own Mac App
    /// Store app (Pages, Keynote, Numbers: Apple's App Store signing, and only Apple may ship com.apple ids there). Nil
    /// for a bundle id that isn't one (it goes into the requirement's text).
    static func appleRequirement(bundle: String) -> String? {
        guard bundle.range(of: #"^[A-Za-z0-9][A-Za-z0-9.-]{0,254}$"#, options: .regularExpression) != nil else { return nil }
        return "identifier \"\(bundle)\" and (anchor apple or (anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9] exists))"
    }

    private static func requirement(bundle: String) -> SecRequirement? {
        guard let text = appleRequirement(bundle: bundle) else { return nil }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    /// The app on disk at `url` is Apple's own `bundle`.
    static func isAppleSigned(url: URL, bundle: String) -> Bool {
        var code: SecStaticCode?
        guard let requirement = requirement(bundle: bundle), SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        // Full validation (every file, strictly), never the basic check (security review).
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }

    /// The running process `pid` (what the keys reach) is Apple's own `bundle`.
    static func isAppleSigned(pid: pid_t, bundle: String) -> Bool {
        var code: SecCode?
        guard pid > 0, let requirement = requirement(bundle: bundle),
              SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code) == errSecSuccess, let code else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private static func isSigned(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSBasicValidateOnly), nil) == errSecSuccess
    }

    /// The Info.plist names in one language: from InfoPlist.loctable (newer apps) or <language>.lproj/InfoPlist.strings.
    private static func localized(_ bundle: Bundle, _ language: String) -> [String: Any]? {
        if let table = bundle.url(forResource: "InfoPlist", withExtension: "loctable"),
           let all = NSDictionary(contentsOf: table) as? [String: Any], let names = all[language] as? [String: Any] {
            return names
        }
        return bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: Any] }
    }

    private static func strippingApp(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
