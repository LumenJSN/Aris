//
//  ArisFieldWrite.swift
//  aris-agent
//
//  Where a rewrite ("이거 더 정중하게 바꿔 줘") or a draft ("여기에 답장 써 줘") goes: into the field the look read,
//  by that element's own Accessibility reference, never into whatever has the keyboard when the answer comes back.
//  Typing the request into the notch makes Aris the app with the keyboard, so a ⌘V "where the cursor is" went to Aris
//  itself and was refused (VM run 2, h1); a spoken request only worked while nothing else took the keyboard.
//  The look keeps the field (ArisFieldTargetDesk: app, window, element, the selection it read and its range), the app
//  hands its token back with the new text, and the write:
//  1. never goes into Aris itself (ArisInsertRefusal.refusedApps) nor into a password field;
//  2. puts the selection back where it was read when it moved, and stops when the text there is no longer what was read;
//  3. replaces the selection through Accessibility (AXSelectedText on that element: no keys, no front change);
//  4. else, while that element still has its app's keyboard focus, pastes into that app's process (⌘V to its pid);
//  5. else brings that app forward in a gap in the user's input, focuses the element, puts the selection back and pastes.
//  Each way is read back before the next; one that changed the field some other way stops there. Pure over a seam
//  (ArisFieldWriteIO); the live half is ArisFieldTargetLive. Ranges are ArisTextRange (UTF-16 offsets, as Accessibility).
//

import Foundation

/// The field a look read: the write lands here.
struct ArisFieldTarget {
    let pid: Int32
    let bundleId: String?
    let app: String
    /// The window-server id of the field's window, when known.
    let window: Int?
    /// The field's Accessibility element (an AXUIElement; opaque here).
    let element: AnyObject
    /// The selected text read (nil: a caret, nothing selected).
    let selection: String?
    /// The selection's (or caret's) range as read.
    let range: ArisTextRange?
    /// A password field (never written).
    let secure: Bool
}

/// What the write does to the element, as the system does it (ArisFieldTargetLive), so the plan is tested with fakes.
protocol ArisFieldWriteIO {
    /// The element still exists and answers (its app is running).
    var alive: Bool { get }
    /// The element's whole value now; nil when it gives none.
    func value() -> String?
    /// The selected range and text now.
    func selectedRange() -> ArisTextRange?
    func selectedText() -> String?
    /// Moves the selection to `range`; false when the app refused.
    func select(_ range: ArisTextRange) -> Bool
    /// AXSelectedText can be set on the element.
    var insertable: Bool { get }
    /// Replaces the selection with `text` through Accessibility; false when the app refused.
    func insertSelected(_ text: String) -> Bool
    /// The element is its app's focused element now (keys and ⌘V to the app's process reach it).
    var focusedInApp: Bool { get }
    /// `text` pasted into the app's process (⌘V to its pid); true when the app read the pasteboard item.
    func paste(_ text: String) -> Bool
    /// The app forward in a gap in the user's input, the element focused, `range` selected again and `text` pasted.
    func front(_ text: String, range: ArisTextRange?) -> ArisNativeFrontResult
    /// A pause for the app to take it (the tests count them).
    func settle()
}

enum ArisFieldWrite {
    enum Way: String, Equatable {
        case axInsert = "ax-insert"
        case paste
        case front
    }

    enum Outcome: Equatable {
        /// The field reads the new text back.
        case written(Way)
        /// Sent, and the field can't tell (it gives no value).
        case sent(Way)
        /// Nothing was written anywhere: why (said to the owner).
        case refused(String)
        /// Something changed that isn't the text: stopped there.
        case changedOther(Way)

        /// The failure the app shows, or nil when the text went in.
        var failure: String? {
            switch self {
            case .written, .sent: return nil
            case .refused(let why): return why
            case .changedOther: return "the field changed some other way, so nothing more was typed"
            }
        }
    }

    static let gone = "the field it read is gone (its window was closed or its app quit), so nothing was typed"
    static let moved = "the text there changed since it was read, so nothing was typed (select it again and ask again)"
    static let secureField = "a password field has the focus"
    static let stale = "what was read is too old or was already used; ask again with it selected"

    static let notAtCaret = "something is selected in that field (or its selection couldn't be read), so nothing was typed over it"

    /// A write the app's quick path asked for only at a caret (ArisTypeHere): refused when the look saw a selection or
    /// couldn't read where the caret was, or when the field now has a selection or can't say (twelfth VM run, S3: the
    /// selected "내용입니다" was typed over with no card).
    static func caretRefusal(_ target: ArisFieldTarget, io: ArisFieldWriteIO) -> String? {
        guard target.selection == nil, let range = target.range, range.length == 0 else { return notAtCaret }
        guard let now = io.selectedText(), now.isEmpty, let caret = io.selectedRange(), caret.length == 0 else { return notAtCaret }
        return nil
    }

    /// Why nothing may be written into the target at all, or nil when it may.
    static func refusal(_ target: ArisFieldTarget) -> String? {
        if let id = target.bundleId?.lowercased(), ArisInsertRefusal.refusedApps.contains(id) { return "won't type into \(target.app)" }
        return target.secure ? secureField : nil
    }

    /// The ways to try, in order: Accessibility on the element, a paste into its app while it has that app's focus,
    /// then a brief turn in front.
    static func plan(insertable: Bool, focusedInApp: Bool) -> [Way] {
        (insertable ? [.axInsert] : []) + (focusedInApp ? [.paste] : []) + [.front]
    }

    /// How many times a sent way's field is read again before it counts as unchanged.
    static let reads = 6

    /// Writes `text` over the target's selection (or at its caret).
    static func run(_ text: String, target: ArisFieldTarget, io: ArisFieldWriteIO) -> Outcome {
        if let refusal = refusal(target) { return .refused(refusal) }
        guard io.alive else { return .refused(gone) }
        if let failure = restoreSelection(target, io: io) { return .refused(failure) }
        let wanted = ArisNativeLadder.wanted([.text(text)])
        for way in plan(insertable: io.insertable, focusedInApp: io.focusedInApp) {
            let before = io.value()
            var read = false
            switch way {
            case .axInsert:
                guard io.insertSelected(text) else { continue }
            case .paste:
                read = io.paste(text)
            case .front:
                switch io.front(text, range: target.range) {
                case .busy(let waited): return .refused(ArisNativeFocusGap.busyLine(waited: waited))
                case .failed: return .refused("\(target.app) couldn't be brought forward with that field focused, so nothing was typed")
                case .sent: read = true
                }
            }
            guard let before else { return .sent(way) }
            switch settled(io, wanted: wanted, before: before) {
            case .landed: return .written(way)
            case .other: return .changedOther(way)
            case .unchanged:
                // A paste the app read may still be on its way: never typed a second time.
                if read || way == .front { return .sent(way) }
                // Nothing changed: the selection is where it was, the next way may go.
                if let failure = restoreSelection(target, io: io) { return .refused(failure) }
            }
        }
        return .refused("no way into that field was left to try")
    }

    /// Puts the selection back where the look read it, when it moved; a failure when the text there isn't what was read.
    static func restoreSelection(_ target: ArisFieldTarget, io: ArisFieldWriteIO) -> String? {
        if let range = target.range {
            if io.selectedRange() != range { _ = io.select(range) }
            guard io.selectedRange() == range else { return moved }
        }
        guard let selection = target.selection else { return nil }
        return same(io.selectedText() ?? "", selection) ? nil : moved
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.precomposedStringWithCanonicalMapping == b.precomposedStringWithCanonicalMapping
    }

    private static func settled(_ io: ArisFieldWriteIO, wanted: String?, before: String) -> ArisNativeLadder.Landing {
        var last = ArisNativeLadder.Landing.unchanged
        for _ in 0..<reads {
            io.settle()
            guard let now = io.value() else { return .other }
            last = ArisNativeLadder.landing(wanted, before: before, after: now)
            if last != .unchanged { return last }
        }
        return last
    }
}

/// The fields looks read, each by a token the app hands back with the text; a token is used once and goes stale after
/// two minutes (a turn's length).
final class ArisFieldTargetDesk: @unchecked Sendable {
    static let shared = ArisFieldTargetDesk()
    static let freshFor: TimeInterval = 120
    /// Looks are one at a time; a few kept is plenty.
    static let most = 4

    private let lock = NSLock()
    private var kept: [(token: String, target: ArisFieldTarget, at: Date)] = []

    /// Keeps `target`; the token to hand back.
    func keep(_ target: ArisFieldTarget, at: Date = Date()) -> String {
        let token = UUID().uuidString
        lock.withLock {
            kept = Array((kept.filter { at.timeIntervalSince($0.at) < Self.freshFor } + [(token, target, at)]).suffix(Self.most))
        }
        return token
    }

    /// The target for `token` (once), while fresh.
    func take(_ token: String, now: Date = Date()) -> ArisFieldTarget? {
        lock.withLock {
            guard let index = kept.firstIndex(where: { $0.token == token }) else { return nil }
            let found = kept.remove(at: index)
            return now.timeIntervalSince(found.at) < Self.freshFor ? found.target : nil
        }
    }
}
