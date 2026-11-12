//
//  ArisAgentInstall.swift
//  Aris
//
//  Where Aris's helper lives and how its LaunchAgent is written, so macOS shows one row, "Aris", for every privacy
//  permission (qa/design-1111/one-row-experiment.md, arrangement K). aris-agent and aris-tools sit inside the app, in
//  Aris.app/Contents/MacOS: a program launchd starts from there is charged to the app, so the app's own switches and
//  the helper's are the same rows, and they are kept across updates signed with the same certificate.
//
//  The app installs the LaunchAgent itself, through its unsandboxed XPC helper (ArisHelperService.installAgent). Nothing
//  here takes a path or a label from a caller: the job is built from these constants, the user's home and the place of
//  the app the XPC helper is in. Foundation only, in the app, the XPC helper and the tests.
//

import Foundation

enum ArisAgentInstall {
    static let label = ArisAgentKickstart.label
    /// The helper's launchd label before the rename; its job and file are removed.
    static let retiredLabel = "com.lumenjsn.aris.aris-agent"
    static let appId = "com.lumenjsn.aris"
    static let agentName = "aris-agent"
    static let toolsName = "aris-tools"
    /// The two programs' signing identifiers (ArisOrigin has the same two for the programs themselves; a test holds
    /// them equal).
    static let agentSigningId = "com.lumenjsn.aris.aris-agent"
    static let toolsSigningId = "com.lumenjsn.aris.aris-tools"
    /// The helper listens here on 127.0.0.1.
    static let port: UInt16 = 23351
    /// macOS mounts an app opened straight from a download at a path holding this folder (App Translocation).
    static let translocationMark = "/AppTranslocation/"

    // MARK: Places

    static func agentPath(app: String) -> String { "\(app)/Contents/MacOS/\(agentName)" }
    static func toolsPath(app: String) -> String { "\(app)/Contents/MacOS/\(toolsName)" }

    /// Aris's own folder, and its data folder inside it.
    static func folder(home: String) -> String { "\(home)/.config/aris" }
    static func dataFolder(home: String) -> String { "\(folder(home: home))/aris" }
    static func logPath(home: String) -> String { "\(dataFolder(home: home))/agent.log" }

    /// The path the AIs, hooks and Antigravity's rules call aris-tools by. It stays where it always was and is now a
    /// link to the program inside the app, rewritten when the app has moved.
    static func toolsLink(home: String) -> String { "\(folder(home: home))/\(toolsName)" }

    static func plistPath(home: String) -> String { ArisAgentKickstart.plistPath(home: home) }
    static func retiredPlistPath(home: String) -> String { "\(home)/Library/LaunchAgents/\(retiredLabel).plist" }

    /// What an install made by install-aris-agent.sh left in Aris's folder: the helper's own copy and half-swapped
    /// files. They are removed at the switch (a leftover copy started by launchd would be a second row again).
    /// aris-tools itself is not in the list: it is replaced by the link.
    static func retiredPrograms(home: String) -> [String] {
        ["\(agentName)", "\(agentName).new", "\(toolsName).new"].map { "\(folder(home: home))/\($0)" }
    }

    /// The app an XPC service sits in: ".../Aris.app/Contents/XPCServices/ArisXPCHelper.xpc" gives ".../Aris.app".
    /// Nil for any other shape, so a service run from an odd place installs nothing.
    static func app(ofService service: String) -> String? {
        let parts = (service as NSString).pathComponents
        guard parts.count >= 5, parts.first == "/", parts[parts.count - 1].hasSuffix(".xpc"), parts[parts.count - 2] == "XPCServices",
              parts[parts.count - 3] == "Contents", parts[parts.count - 4].hasSuffix(".app") else { return nil }
        return NSString.path(withComponents: Array(parts.dropLast(3)))
    }

    // MARK: Where the app may be

    /// Why the helper can't be installed from where the app is now.
    enum Refusal: String, Equatable, CaseIterable {
        /// Opened from a download without being moved: macOS runs it from a temporary, read-only copy.
        case translocated
        /// On a disk image or another read-only volume.
        case readOnly
        /// In the Trash.
        case trash
        /// The XPC helper is not inside an app at all.
        case shape
        /// The app has no aris-agent or aris-tools inside it (a build made in Xcode, not by deploy.sh or stage.sh).
        case noHelper
        /// The app, or one of the two programs inside it, no longer verifies as what was signed (security review 4,
        /// M7): nothing is written or loaded for a changed copy.
        case changed
        /// The app is in a place other users of this Mac can write (/Users/Shared, a world-writable folder): what
        /// runs with Aris's permissions would be theirs to swap (security review 4, L2).
        case sharedPlace
        /// Another copy of Aris has the helper's place and is still there, and this copy is not in an Applications
        /// folder: opening a second copy somewhere does not take the helper over.
        case notInApplications
        /// The copy that has the helper's place is a newer build than this one: an older build never replaces it
        /// silently.
        case older
        /// Aris's own folder (~/.config/aris, or its data folder) is a link to somewhere else: nothing is written
        /// through it (security review 4, L5).
        case linkedFolder
    }

    /// The first reason the app at `app` can't run its helper from there; nil when it can.
    static func refusal(app: String?, home: String, translocated: Bool, readOnly: Bool, hasAgent: Bool, hasTools: Bool) -> Refusal? {
        guard let app, app.hasPrefix("/"), app.hasSuffix(".app"), !app.contains("/../") else { return .shape }
        if translocated || app.contains(translocationMark) { return .translocated }
        if readOnly { return .readOnly }
        if app.hasPrefix("\(home)/.Trash/") || app.contains("/.Trashes/") { return .trash }
        if !hasAgent || !hasTools { return .noHelper }
        return nil
    }

    // MARK: Taking the helper's place over from another copy (security review 4, L2)

    /// Whether the app is in an Applications folder: the Mac's, or the user's own.
    static func isInApplications(app: String, home: String) -> Bool {
        app.hasPrefix("/Applications/") || app.hasPrefix("\(home)/Applications/")
    }

    /// When the app was built (the Info.plist's `ArisBuiltAt`, seconds since 1970, which the build scripts fill);
    /// nil for a build that does not say.
    static let builtAtKey = "ArisBuiltAt"
    static func builtAt(_ value: Any?) -> Double? {
        let number = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard let number, number > 1_000_000_000, number < 100_000_000_000 else { return nil }
        return number
    }

    /// Why this app does not take the helper's place from the copy of Aris that has it; nil when it may.
    ///  · From an Applications folder it may, unless the copy that has the place is a newer build.
    ///  · From anywhere else only when that copy's helper is no longer there.
    /// `current`: the aris-agent launchd runs now for another copy (or the old install's). The builds are compared only
    /// when both say when they were built.
    static func takeoverRefusal(app: String, home: String, current: String, currentExists: Bool, appBuiltAt: Double?, currentBuiltAt: Double?) -> Refusal? {
        guard currentExists else { return nil }
        guard isInApplications(app: app, home: home) else { return .notInApplications }
        if let appBuiltAt, let currentBuiltAt, appBuiltAt < currentBuiltAt { return .older }
        return nil
    }

    // MARK: The job

    /// The LaunchAgent, whole. Same label as before, so launchd and Login Items see one job.
    ///  · AssociatedBundleIdentifiers puts the Login Items entry under Aris's name (it does nothing for permissions).
    ///  · KeepAlive is a path condition on the program itself: launchd keeps the helper running while the app is there,
    ///    and with the app trashed or deleted it stops trying instead of failing every ten seconds for good.
    static func job(app: String, home: String) -> [String: Any] {
        let program = agentPath(app: app)
        return [
            "Label": label,
            "ProgramArguments": [program],
            "AssociatedBundleIdentifiers": [appId],
            "RunAtLoad": true,
            "KeepAlive": ["PathState": [program: true]],
            "ProcessType": "Interactive",
            "StandardErrorPath": logPath(home: home),
        ]
    }

    static func jobData(app: String, home: String) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: job(app: app, home: home), format: .xml, options: 0)
    }

    /// Whether the file on disk already is this job (compared as values, so its layout and key order don't matter).
    static func isSameJob(_ existing: Data?, app: String, home: String) -> Bool {
        guard let existing, let found = try? PropertyListSerialization.propertyList(from: existing, options: [], format: nil) as? NSDictionary else { return false }
        return found.isEqual(to: job(app: app, home: home))
    }

    // MARK: launchctl

    static func domain(uid: uid_t) -> String { "gui/\(uid)" }
    static func target(uid: uid_t, label: String = label) -> String { "\(domain(uid: uid))/\(label)" }
    static func printArguments(uid: uid_t, label: String = label) -> [String] { ["print", target(uid: uid, label: label)] }
    static func bootoutArguments(uid: uid_t, label: String = label) -> [String] { ["bootout", target(uid: uid, label: label)] }
    static func bootstrapArguments(uid: uid_t, home: String) -> [String] { ["bootstrap", domain(uid: uid), plistPath(home: home)] }

    // MARK: What to do

    /// What the installer found before it changed anything.
    struct Found: Equatable {
        /// The LaunchAgent file is this app's job already.
        var sameJob: Bool
        /// launchd has the job loaded.
        var loaded: Bool
        /// Something answers on the helper's port.
        var answering: Bool
        /// The helper's own copy from an earlier install is still in Aris's folder.
        var retiredCopy: Bool
        /// The app's build and the build the running helper wrote down; nil when not known.
        var appBuild: String?
        var agentBuild: String?
        /// What launchd itself has loaded under the label (nil: nothing, or it was not asked). Decided from launchd's
        /// own record, never from the file on disk (security review 4, M7).
        var loadedKind: ArisLoadedJob.Kind?
    }

    enum Step: Equatable {
        /// Nothing to do: this app's helper is running.
        case none
        /// Stop the job, write its file, remove the old copies, load it.
        case reinstall
        /// Load the job (its file is right, launchd doesn't have it).
        case load
        /// Restart the job once (the app was replaced under it, or it doesn't answer).
        case restart
    }

    /// The build the app carries is compared only when it has one ("dev" is a build made by hand).
    static func step(_ found: Found, unstamped: String = "dev") -> Step {
        // A job under Aris's label that is not this app's helper is replaced, whatever the file on disk says.
        if found.loaded, let kind = found.loadedKind, kind != .own { return .reinstall }
        if !found.sameJob || found.retiredCopy { return .reinstall }
        if !found.loaded { return .load }
        if !found.answering { return .restart }
        if let app = found.appBuild, app != unstamped, found.agentBuild != app { return .restart }
        return .none
    }
}

/// The installer's answer to the app, as one word over XPC and back.
enum ArisAgentInstallOutcome: Equatable {
    /// This app's helper was already running.
    case running
    /// It was loaded or restarted.
    case started
    /// An install made the old way (the helper's own copy in ~/.config/aris) was replaced by the one inside the app.
    case switched
    /// Another program was loaded under Aris's label (not a helper of Aris's at all); it was unloaded and this app's
    /// helper loaded in its place. The app says so once.
    case replaced
    case refused(ArisAgentInstall.Refusal)
    /// A step failed; the word says which ("folder", "plist", "link", "load", "port", "build").
    case failed(String)

    var word: String {
        switch self {
        case .running: "running"
        case .started: "started"
        case .switched: "switched"
        case .replaced: "replaced"
        case .refused(let why): "refused:\(why.rawValue)"
        case .failed(let step): "failed:\(step)"
        }
    }

    init(word: String) {
        let parts = word.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count > 1 ? parts[1] : nil) {
        case ("running", nil): self = .running
        case ("started", nil): self = .started
        case ("switched", nil): self = .switched
        case ("replaced", nil): self = .replaced
        case ("refused", let why?): self = ArisAgentInstall.Refusal(rawValue: why).map { .refused($0) } ?? .failed("answer")
        case ("failed", let step?): self = .failed(String(step.prefix(40)))
        default: self = .failed("answer")
        }
    }

    /// The helper is this app's and it answers.
    var isUp: Bool { self == .running || self == .started || self == .switched || self == .replaced }
}
