//
//  ArisNativeTextLadder.swift
//  aris-agent
//
//  How Aris's own engine puts text into the field that has the focus in a window, one way after another until the field
//  reads it back, every app by the same ladder (the owner: no short list of supported apps):
//  1. Accessibility: the field's selected text replaced by the text (the caret's place; nothing else of the field is
//     touched). Never in a mail, chat or call app (a web composer can show text its page never took), never with keys
//     in the text (Return, Tab), only into a field that reads back.
//  2. Key events to the app's process, in the background (Unicode strings, any layout). Not while an input method is the
//     selected source (it composes from the key codes: ArisNativeKeyLayout), not for an app measured or learned to drop
//     them.
//  3. The pasteboard: the text as a lazy item, ⌘V to the app's process, the user's clipboard back right after (the app
//     reading the item is the proof it pasted).
//  4. Last: the app brought forward in a gap in the user's input (ArisNativeFocusGap), the keys (or, with an input method on,
//     the paste) for real, and his front app and window given back.
//  A rung runs only after the one before left the field exactly as it was (nothing typed, so nothing can go in twice);
//  a field that changed some other way stops the ladder (the controller reads the window back). A rung an app was seen
//  to ignore (the field unchanged after it, the focus in the right window) is remembered for that app's bundle id, on
//  disk, and skipped next time (ArisNativeInputMemory): an Electron app that drops background keys goes straight to the
//  rung that worked. The plan and the run are pure over a seam (ArisNativeTextIO) and tested with fakes.
//

import Foundation

enum ArisNativeRung: String, Codable, CaseIterable, Equatable {
    case axInsert = "ax-insert"
    case background
    case paste
    case front
}

/// What the focused field of the target window reads now.
enum ArisNativeFieldRead: Equatable {
    /// No focused element in that window (the app's focus is in another one, or nowhere).
    case notFocused
    /// A password field: nothing is ever typed.
    case secure
    /// Focused, but it gives no value.
    case unreadable
    case value(String)

    var text: String? { if case .value(let text) = self { return text } else { return nil } }
}

/// What the brief turn in front came to.
enum ArisNativeFrontResult: Equatable {
    case sent
    /// No gap in the user's input within the limit (nothing sent).
    case busy(waited: Double)
    /// The window didn't come forward, or its keyboard focus was in another window then (nothing sent).
    case failed
}

/// The system calls the ladder makes (ArisNativeTextLive), so the decisions are tested with fakes.
protocol ArisNativeTextIO {
    func read() -> ArisNativeFieldRead
    /// The focused field takes its selected text set (AXSelectedText is settable).
    var insertable: Bool { get }
    /// Replaces the selection with `text` by Accessibility; false when the app refused it.
    func insertSelected(_ text: String) -> Bool
    /// The pieces as key events to the app's process.
    func postBackground(_ pieces: [ArisNativeInput.Piece])
    /// The text through the pasteboard with ⌘V to the process; true when the app read it.
    func paste(_ text: String) -> Bool
    /// The app in front for a moment (in a gap in the user's input), the pieces typed (or `text` pasted) for real, the front
    /// given back.
    func front(_ pieces: [ArisNativeInput.Piece], paste: String?) -> ArisNativeFrontResult
    /// A pause for the app to take what it was sent (the tests count them).
    func settle()
}

/// Per app (bundle id), the rungs it was seen to ignore, kept on disk for a month (an app's update may change it).
final class ArisNativeInputMemory: @unchecked Sendable {
    struct Entry: Codable, Equatable {
        var failed: [ArisNativeRung: Date] = [:]
        var worked: ArisNativeRung?
    }

    static let keep: TimeInterval = 30 * 24 * 3600
    /// `~/Library/Application Support/Aris/engine/input-ladder.json`.
    static let shared = ArisNativeInputMemory(file: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Aris/engine/input-ladder.json"))

    private let lock = NSLock()
    private let file: URL?
    private var entries: [String: Entry] = [:]
    private var loaded = false

    /// `file` nil: in memory only (the tests).
    init(file: URL?) { self.file = file }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let file, let data = try? Data(contentsOf: file), let read = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = read
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: file, options: .atomic)
    }

    /// The rungs `bundle` ignored within the last month.
    func failed(_ bundle: String?, now: Date = Date()) -> Set<ArisNativeRung> {
        guard let bundle else { return [] }
        return lock.withLock {
            load()
            return Set((entries[bundle]?.failed ?? [:]).filter { now.timeIntervalSince($0.value) < Self.keep }.keys)
        }
    }

    func worked(_ bundle: String?) -> ArisNativeRung? {
        guard let bundle else { return nil }
        return lock.withLock { load(); return entries[bundle]?.worked }
    }

    func noteFailed(_ bundle: String?, _ rung: ArisNativeRung, now: Date = Date()) {
        guard let bundle, rung != .front else { return }
        lock.withLock {
            load()
            entries[bundle, default: Entry()].failed[rung] = now
            save()
        }
    }

    func noteWorked(_ bundle: String?, _ rung: ArisNativeRung) {
        guard let bundle else { return }
        lock.withLock {
            load()
            var entry = entries[bundle, default: Entry()]
            guard entry.worked != rung || entry.failed[rung] != nil else { return }
            entry.worked = rung
            entry.failed[rung] = nil
            entries[bundle] = entry
            save()
        }
    }
}

enum ArisNativeLadder {
    /// What the ladder knows of the app and the call.
    struct Profile: Equatable {
        var bundle: String?
        /// Measured to drop background keys (Warp; an Electron or Chromium shell).
        var dropsBackgroundKeys = false
        /// An input method is the selected source.
        var inputMethod = false
        /// A mail, chat or call app (no Accessibility insert there).
        var sending = false
        /// The keyboard focus of the app is in another window than the target (background rungs can't reach it).
        var focusElsewhere = false
        /// The front may be taken (false: refuse instead of the last rung).
        var frontAllowed = true
    }

    /// The rungs to try, in order. Pure.
    static func plan(_ pieces: [ArisNativeInput.Piece], profile: Profile, learned: Set<ArisNativeRung>) -> [ArisNativeRung] {
        let textOnly = !pieces.isEmpty && pieces.allSatisfy { if case .text = $0 { return true } else { return false } }
        var rungs: [ArisNativeRung] = []
        if !profile.focusElsewhere {
            if textOnly, !profile.sending, !learned.contains(.axInsert) { rungs.append(.axInsert) }
            if !profile.inputMethod, !profile.dropsBackgroundKeys, !learned.contains(.background) { rungs.append(.background) }
            if textOnly, !profile.dropsBackgroundKeys, !learned.contains(.paste) { rungs.append(.paste) }
        }
        if profile.frontAllowed { rungs.append(.front) }
        return rungs
    }

    /// The text the field must show once it is in (the pieces' text, composed, its outer spaces off); nil for keys only.
    static func wanted(_ pieces: [ArisNativeInput.Piece]) -> String? {
        let text = pieces.compactMap { if case .text(let text) = $0 { return text } else { return nil } }.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        return trimmed.isEmpty ? nil : trimmed
    }

    enum Landing: Equatable {
        /// The field holds the text once more than it did.
        case landed
        /// Exactly as it was.
        case unchanged
        /// Changed, but not by the text (or it can't be told).
        case other
    }

    /// The field before and after, against the text. Pure.
    static func landing(_ wanted: String?, before: String, after: String) -> Landing {
        let was = before.precomposedStringWithCanonicalMapping, now = after.precomposedStringWithCanonicalMapping
        if was == now { return .unchanged }
        guard let wanted else { return .other }
        let count = { (text: String) in text.components(separatedBy: wanted).count - 1 }
        return count(now) > count(was) ? .landed : .other
    }

    struct Outcome: Equatable {
        enum State: Equatable {
            /// The field reads the text back.
            case verified
            /// Sent, and the field can't tell (no value, keys only): the controller reads the window back.
            case unverified
            /// Something changed that isn't the text: stopped there.
            case changedOther
            /// Nothing was sent anywhere (safe to try again): why.
            case nothing(code: String, message: String)
        }
        var state: State
        var delivery: ArisNativeRung?
        var tried: [ArisNativeRung] = []
        var learned: [ArisNativeRung] = []
    }

    /// How many times (each a `settle`) a sent rung's field is read again before it counts as unchanged.
    static let reads = 6

    /// Runs `rungs` against `io`; a rung the field ignored is remembered for `bundle` in `memory`.
    static func run(_ pieces: [ArisNativeInput.Piece], rungs: [ArisNativeRung], io: ArisNativeTextIO, memory: ArisNativeInputMemory, bundle: String?,
                    profile: Profile) -> Outcome {
        let wanted = wanted(pieces)
        let text = pieces.compactMap { if case .text(let text) = $0 { return text } else { return nil } }.joined()
        var outcome = Outcome(state: .nothing(code: "NOT_TYPED", message: "no way into that field was left to try"))
        let start = io.read()
        if start == .secure { return Outcome(state: .nothing(code: "SECURE_FIELD", message: "a password field has the focus")) }
        for rung in rungs {
            let before = io.read()
            if before == .secure { outcome.state = .nothing(code: "SECURE_FIELD", message: "a password field has the focus"); return outcome }
            // The background rungs need the field itself, focused in that window, read back to tell they landed.
            let known = before.text
            switch rung {
            case .axInsert:
                guard let known, io.insertable else { continue }
                outcome.tried.append(rung)
                guard io.insertSelected(text) else {
                    memory.noteFailed(bundle, rung)
                    outcome.learned.append(rung)
                    continue
                }
                switch settled(io, wanted: wanted, before: known) {
                case .landed: return finished(outcome, rung, memory: memory, bundle: bundle)
                case .unchanged:
                    memory.noteFailed(bundle, rung)
                    outcome.learned.append(rung)
                case .other: return stopped(outcome, rung)
                }
            case .background:
                guard before != .notFocused else { continue }
                outcome.tried.append(rung)
                io.postBackground(pieces)
                guard let known else { return unverified(outcome, rung) }
                switch settled(io, wanted: wanted, before: known) {
                case .landed: return finished(outcome, rung, memory: memory, bundle: bundle)
                case .unchanged:
                    // Keys only (no text to see) can't be told from ignored: sent, unverified.
                    guard wanted != nil else { return unverified(outcome, rung) }
                    memory.noteFailed(bundle, rung)
                    ArisNativeInput.learnForeground(bundle)
                    outcome.learned.append(rung)
                case .other: return stopped(outcome, rung)
                }
            case .paste:
                guard before != .notFocused else { continue }
                outcome.tried.append(rung)
                let read = io.paste(text)
                guard let known else { return read ? unverified(outcome, rung) : stopped(outcome, rung) }
                switch settled(io, wanted: wanted, before: known) {
                case .landed: return finished(outcome, rung, memory: memory, bundle: bundle)
                case .unchanged:
                    // The app read the item but the field shows nothing: it may still be on its way. Never typed again.
                    if read { return unverified(outcome, rung) }
                    memory.noteFailed(bundle, rung)
                    outcome.learned.append(rung)
                case .other: return stopped(outcome, rung)
                }
            case .front:
                outcome.tried.append(rung)
                switch io.front(pieces, paste: profile.inputMethod && wanted != nil && isTextOnly(pieces) ? text : nil) {
                case .busy(let waited):
                    outcome.state = .nothing(code: ArisNativeFocusGap.busyCode, message: ArisNativeFocusGap.busyLine(waited: waited))
                    return outcome
                case .failed:
                    outcome.state = .nothing(code: "FOCUS_ELSEWHERE", message: "the window couldn't be brought forward with its keyboard focus (the keyboard focus belongs to a different window)")
                    return outcome
                case .sent:
                    guard let known else { return unverified(outcome, rung) }
                    switch settled(io, wanted: wanted, before: known) {
                    case .landed: return finished(outcome, rung, memory: memory, bundle: bundle)
                    case .unchanged, .other: return unverified(outcome, rung)
                    }
                }
            }
        }
        if profile.focusElsewhere, !profile.frontAllowed {
            outcome.state = .nothing(code: "FOCUS_ELSEWHERE", message: "the keyboard focus belongs to a different window, and the front can't be taken for this call")
        }
        return outcome
    }

    static func isTextOnly(_ pieces: [ArisNativeInput.Piece]) -> Bool {
        !pieces.isEmpty && pieces.allSatisfy { if case .text = $0 { return true } else { return false } }
    }

    /// The field read again until it changes, at most `reads` times.
    private static func settled(_ io: ArisNativeTextIO, wanted: String?, before: String) -> Landing {
        var last = Landing.unchanged
        for _ in 0..<reads {
            io.settle()
            guard let now = io.read().text else { return .other }
            last = landing(wanted, before: before, after: now)
            if last != .unchanged { return last }
        }
        return last
    }

    private static func finished(_ outcome: Outcome, _ rung: ArisNativeRung, memory: ArisNativeInputMemory, bundle: String?) -> Outcome {
        memory.noteWorked(bundle, rung)
        var done = outcome
        done.state = .verified
        done.delivery = rung
        return done
    }

    private static func unverified(_ outcome: Outcome, _ rung: ArisNativeRung) -> Outcome {
        var done = outcome
        done.state = .unverified
        done.delivery = rung
        return done
    }

    private static func stopped(_ outcome: Outcome, _ rung: ArisNativeRung) -> Outcome {
        var done = outcome
        done.state = .changedOther
        done.delivery = rung
        return done
    }

    /// The engine's reply for an outcome.
    static func reply(_ outcome: Outcome, window: Int, pid: Int32) -> ArisNativeReply {
        let extra: [String: Any] = ["delivery": outcome.delivery.map(deliveryWord) ?? "none", "tried": outcome.tried.map(\.rawValue),
                                    "learned": outcome.learned.map(\.rawValue)]
        switch outcome.state {
        case .verified:
            var done = ArisNativeReply.done(window: window, pid: pid, extra: extra.merging(["verified": true]) { $1 })
            done.state = "confirmed_change"
            return done
        case .unverified, .changedOther:
            return .done(window: window, pid: pid, extra: extra.merging(["verified": false]) { $1 })
        case .nothing(let code, let message):
            var refused = ArisNativeReply.failure(code, message, retrySafe: true)
            refused.window = window
            refused.pid = pid
            return refused
        }
    }

    /// The words the controller has read as the delivery since before the ladder ("background", "foreground").
    static func deliveryWord(_ rung: ArisNativeRung) -> String {
        switch rung {
        case .axInsert: return "ax-insert"
        case .background: return "background"
        case .paste: return "paste"
        case .front: return "foreground"
        }
    }
}
