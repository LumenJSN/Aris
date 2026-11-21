//
//  ArisUpdateRules.swift
//  Aris
//
//  Aris's updates as plain values (ArisUpdater runs them on Sparkle). Only the public build updates itself: its bundle
//  id is the public one and its Info.plist carries the feed and the update key, which only the public export adds
//  (export-public.sh). Any other build, the owner's own among them, has no updater at all: no feed, no checks. A check
//  runs at launch and every 24 hours. With 자동으로 업데이트 on (the default) a new version is downloaded in the
//  background and installed once Aris is idle (no turn, job or dictation), then Aris opens again; off, the notice pill
//  offers it. Everything Sparkle would show is a notice on the pill instead (ArisUpdatePill): what came out, a quiet
//  progress bar while it downloads, one line for an error. Foundation only (tested).
//

import Foundation

// MARK: - Versions

/// Dotted version numbers ("1.2.10"), compared number by number; a missing part counts as 0 ("1.3" == "1.3.0").
enum ArisUpdateVersion {
    /// The numbers of `version`: a leading "v" is dropped, each part is its leading digits, and the parts stop at the
    /// first that has none ("1.3.0-beta" gives 1, 3, 0).
    static func parts(_ version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        var numbers: [Int] = []
        for piece in text.split(separator: ".", omittingEmptySubsequences: false) {
            let digits = piece.prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty, let number = Int(digits) else { break }
            numbers.append(number)
            if digits.count != piece.count { break }
        }
        return numbers
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = parts(a), y = parts(b)
        for index in 0..<max(x.count, y.count) {
            let left = index < x.count ? x[index] : 0, right = index < y.count ? y[index] : 0
            if left != right { return left < right ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func isNewer(_ version: String, than other: String) -> Bool { compare(version, other) == .orderedDescending }
}

// MARK: - Whether this build updates itself

enum ArisUpdatePolicy {
    /// The public build's bundle id (export-public.sh --rename-bundle). Every other id is off.
    static let publicBundleId = "com.lumenjsn.aris"
    /// The Info.plist keys the public export adds.
    static let feedKey = "SUFeedURL"
    static let publicKeyKey = "SUPublicEDKey"
    /// A test-only feed in the app's own defaults, used only when it is on this Mac (127.0.0.1, localhost): the VM test
    /// serves its appcast from there. Any other address is ignored, so the default can't point users elsewhere.
    static let testFeedDefault = "ArisUpdateTestFeed"
    /// Checked at launch (a little after, once the notch is up) and every 24 hours.
    static let checkInterval: TimeInterval = 24 * 3_600
    static let firstCheckDelay: TimeInterval = 15

    /// Whether this build may update itself: the public bundle id, an https feed and a 32-byte EdDSA public key.
    static func isOn(bundleId: String?, info: [String: Any]) -> Bool {
        guard bundleId == publicBundleId else { return false }
        guard let feed = info[feedKey] as? String, let url = URL(string: feed), url.scheme == "https", url.host?.isEmpty == false else { return false }
        guard let key = info[publicKeyKey] as? String, Data(base64Encoded: key)?.count == 32 else { return false }
        return true
    }

    /// The certificate the releases are signed with (release/make-release.sh, signing-identity.sh): its common name.
    static let releaseSigner = "Aris Release (Lumen JS)"

    /// Whether this copy was signed for the release channel. A build made from the public source has the public id,
    /// feed and key too, but its own signature (ad hoc, or the builder's): an official release must never be put over
    /// it, so its updater stays off.
    static func signedForRelease(signer: String?) -> Bool { signer == releaseSigner }

    /// The feed to read: the test feed when it is set and on this Mac, else the Info.plist's.
    static func feed(info: [String: Any], testFeed: String?) -> String? {
        if let testFeed, isLoopback(testFeed) { return testFeed }
        return info[feedKey] as? String
    }

    static func isLoopback(_ address: String) -> Bool {
        guard let url = URL(string: address), let scheme = url.scheme, ["http", "https"].contains(scheme), let host = url.host else { return false }
        return ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host.lowercased())
    }
}

// MARK: - When it may install

/// A downloaded update is installed only while Aris is idle: no turn (or conversation), no job, no dictation, no setup
/// on screen, the notch closed and Settings not open, and that has held for `settle`.
enum ArisUpdateIdle {
    struct Activity: Equatable {
        var turn = false
        var job = false
        var dictation = false
        var onboarding = false
        /// A notch is open: the user may be reading or typing in it.
        var notchOpen = false
        /// The Settings window is on screen.
        var settingsOpen = false
    }

    static let settle: TimeInterval = 30
    static let recheck: TimeInterval = 10

    static func isIdle(_ activity: Activity) -> Bool {
        !activity.turn && !activity.job && !activity.dictation && !activity.onboarding && !activity.notchOpen && !activity.settingsOpen
    }

    /// A job still to finish: waiting, running or waiting for an approval.
    static func jobBusy(_ states: [ArisJobState]) -> Bool {
        states.contains {
            switch $0 {
            case .queued, .running, .awaitingApproval: true
            case .done, .failed, .cancelled: false
            }
        }
    }

    /// Whether the moment has come: idle now, and idle since `since` for at least `settle`.
    static func mayInstall(_ activity: Activity, idleSince since: Date?, now: Date) -> Bool {
        guard isIdle(activity), let since else { return false }
        return now.timeIntervalSince(since) >= settle
    }
}

// MARK: - After an update

/// The version that ran last time differs from this one: the app was replaced under its helper (an update), so the
/// helper is restarted from this app even when its build stamp says nothing changed.
enum ArisUpdateRelaunch {
    static let lastVersionKey = "arisLastLaunchedVersion"

    static func restartsHelper(last: String?, current: String) -> Bool {
        guard let last, !last.isEmpty else { return false }
        return last != current
    }
}

// MARK: - The pill

/// What the notice pill says about an update, moved on by what Sparkle tells the user driver.
struct ArisUpdatePill: Equatable {
    enum Phase: Equatable {
        /// Nothing up.
        case none
        /// A check the user asked for runs (the pill stays as it was).
        case checking
        /// A new version came out: 지금 업데이트 / 나중에.
        case available
        /// It downloads; the fraction once its length is known.
        case downloading(Double?)
        /// It is being put in place; Aris opens again.
        case installing
        /// A check the user asked for found nothing newer.
        case upToDate
        /// One line: what went wrong.
        case failed(ArisUpdateFailure)
    }

    enum Event: Equatable {
        case checkStarted(userInitiated: Bool)
        case found(version: String)
        case notFound(userInitiated: Bool)
        /// 나중에, the ✕, or Sparkle dismissing it.
        case dismissed
        case downloadStarted
        case expectedLength(UInt64)
        case received(UInt64)
        case extracting
        case installing
        case failed(ArisUpdateFailure)
    }

    var phase: Phase = .none
    /// The version on offer.
    var version: String?
    var expected: UInt64 = 0
    var received: UInt64 = 0

    func on(_ event: Event) -> ArisUpdatePill {
        var next = self
        switch event {
        case .checkStarted(let user):
            if user, phase == .none || phase == .upToDate || isFailed { next.phase = .checking }
        case .found(let version):
            next = ArisUpdatePill(phase: .available, version: version)
        case .notFound(let user):
            next = ArisUpdatePill(phase: user ? .upToDate : .none)
        case .dismissed:
            next = ArisUpdatePill()
        case .downloadStarted:
            next.phase = .downloading(nil)
            next.expected = 0
            next.received = 0
        case .expectedLength(let length):
            next.expected = length
            next.phase = .downloading(length > 0 ? fraction(received, of: length) : nil)
        case .received(let length):
            next.received = received &+ length
            next.phase = .downloading(expected > 0 ? fraction(next.received, of: expected) : nil)
        case .extracting, .installing:
            next.phase = .installing
        case .failed(let why):
            next.phase = .failed(why)
        }
        return next
    }

    private var isFailed: Bool { if case .failed = phase { true } else { false } }

    private func fraction(_ part: UInt64, of whole: UInt64) -> Double { min(1, Double(part) / Double(whole)) }

    /// The one notice the pill shows for this state; nil: none (the update's notice is withdrawn).
    /// `id`: the same for every state of one update, so the pill redraws instead of arriving again.
    func notice(id: UUID = UUID(), current: String, english: Bool, now: Date = Date()) -> ArisNotice? {
        let shown = version ?? current
        let key = ArisUpdateWords.key
        switch phase {
        case .none, .checking:
            return nil
        case .available:
            return ArisNotice(id: id, key: key, kind: .system, title: ArisUpdateWords.available(shown, english: english),
                              body: ArisUpdateWords.availableBody(english: english),
                              actions: [ArisNoticeAction(title: ArisUpdateWords.later(english: english), primary: false, role: .laterUpdate),
                                        ArisNoticeAction(title: ArisUpdateWords.installNow(english: english), primary: true, role: .installUpdate)],
                              posted: now)
        case .downloading(let fraction):
            return ArisNotice(id: id, key: key, kind: .system, title: ArisUpdateWords.downloading(shown, english: english), body: "",
                              posted: now, progress: fraction ?? 0)
        case .installing:
            return ArisNotice(id: id, key: key, kind: .system, title: ArisUpdateWords.installing(shown, english: english),
                              body: ArisUpdateWords.installingBody(english: english), posted: now, progress: 1)
        case .upToDate:
            return ArisNotice(id: id, key: key, kind: .system, title: ArisUpdateWords.upToDate(english: english),
                              body: ArisUpdateWords.currentVersion(current, english: english), posted: now,
                              showsWithin: ArisUpdateWords.shortWait, showsFor: ArisUpdateWords.shortStay)
        case .failed(let why):
            return ArisNotice(id: id, key: key, kind: .problem, title: ArisUpdateWords.failedTitle(english: english),
                              body: ArisUpdateWords.failure(why, english: english), posted: now,
                              showsWithin: ArisUpdateWords.shortWait, showsFor: ArisUpdateWords.errorStay)
        }
    }
}

/// Why an update did not go through, said in one line.
enum ArisUpdateFailure: Equatable {
    case network, signature, install, other

    /// From an error's domain and code (Sparkle's SUSparkleErrorDomain codes, SUErrors.h).
    static func of(domain: String, code: Int) -> ArisUpdateFailure {
        if domain == NSURLErrorDomain { return .network }
        if domain == "SUSparkleErrorDomain" {
            switch code {
            case 1002, 2001: return .network           // the appcast or the download could not be fetched
            case 3001, 3002: return .signature          // the update's EdDSA signature or its code signature
            case 3000, 4000...4999: return .install     // unpacking it, or putting it in place
            default: return .other
            }
        }
        return .other
    }
}

// MARK: - Words

enum ArisUpdateWords {
    /// One update notice at a time.
    static let key = "update"
    static let shortWait: TimeInterval = 60
    static let shortStay: TimeInterval = 5
    static let errorStay: TimeInterval = 8

    static func available(_ version: String, english: Bool) -> String {
        english ? "Aris \(version) is available" : "새 버전 \(ArisParticle.attach(version, .iGa)) 나왔어요"
    }
    static func availableBody(english: Bool) -> String {
        english ? "Updating restarts Aris; your settings and permissions stay." : "업데이트하면 Aris가 다시 열려요. 설정과 권한은 그대로예요."
    }
    static func installNow(english: Bool) -> String { english ? "Update now" : "지금 업데이트" }
    static func later(english: Bool) -> String { english ? "Later" : "나중에" }
    static func downloading(_ version: String, english: Bool) -> String { english ? "Downloading Aris \(version)" : "새 버전 \(version) 받는 중" }
    static func installing(_ version: String, english: Bool) -> String { english ? "Installing Aris \(version)" : "\(version) 설치하는 중" }
    static func installingBody(english: Bool) -> String { english ? "Aris reopens in a moment." : "곧 다시 열려요." }
    static func upToDate(english: Bool) -> String { english ? "Aris is up to date" : "최신 버전이에요" }
    static func currentVersion(_ version: String, english: Bool) -> String { english ? "Version \(version)" : "버전 \(version)" }
    static func failedTitle(english: Bool) -> String { english ? "Couldn't update" : "업데이트하지 못했어요" }

    static func failure(_ why: ArisUpdateFailure, english: Bool) -> String {
        switch why {
        case .network: english ? "Check the internet connection; Aris tries again later." : "인터넷 연결을 확인해 주세요. 나중에 다시 해 볼게요."
        case .signature: english ? "The download didn't check out, so nothing was installed." : "받은 파일이 확인되지 않아 설치하지 않았어요."
        case .install: english ? "It couldn't be put in place; Aris tries again later." : "설치하지 못했어요. 나중에 다시 해 볼게요."
        case .other: english ? "Aris tries again later." : "나중에 다시 해 볼게요."
        }
    }
}
