//
//  ArisTagText.swift
//  Aris
//
//  The words of the open notch's one-line rows and folds, pure so they're tested: a status tag's label on one line
//  (ArisActivityTag cuts what doesn't fit with "…"), and when a card's words left up after the user answered it fold to
//  their first two lines (ArisSettledCardText).
//

import CoreGraphics
import Foundation

enum ArisTagText {
    /// A status as one line: line breaks, tabs and runs of spaces become single spaces, trimmed at both ends.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

enum ArisCardFold {
    /// Folded, a settled card shows this many lines, the last ending in "…".
    static let lines = 2

    /// Folds (and a tap unfolds) only when its words are taller than their first two lines.
    static func folds(full: CGFloat, folded: CGFloat) -> Bool {
        full > folded + 0.5
    }
}

// MARK: - Long work: a count and a clock on the tag (the owner, 2026-11-11: "오래 걸리는 작업은 '2/4 단계'나 경과 시간을 태그에")
//
// "2/4" when the work itself counted its steps: the count rides at the end of the status line, " · 2/4", written only
// by code that knows both numbers (the agent's ArisStepLine: a desktop batch's steps). A status without that ending
// shows no numbers: nothing here ever guesses one. And the time since the tag began running, once that is past ten
// seconds, so an ordinary step of a second or two looks exactly as it did.

/// Which step of how many: "2/4".
struct ArisTagCount: Equatable {
    let step: Int
    let of: Int

    var text: String { "\(step)/\(of)" }
}

enum ArisTagProgress {
    /// A tag shows its clock once it has run this long.
    static let clockAfter: TimeInterval = 10
    /// A count is shown for 2 to 99 steps.
    static let mostSteps = 99
    /// What sits between a status's words and its count.
    private static let mark = " · "

    private static func isCount(step: Int, of total: Int) -> Bool {
        (2...mostSteps).contains(total) && (1...total).contains(step)
    }

    /// A status with its count at the end ("메일 보는 중 · 2/4"); the words alone when the numbers aren't a real count.
    static func counted(_ words: String, step: Int, of total: Int) -> String {
        isCount(step: step, of: total) ? words + mark + "\(step)/\(total)" : words
    }

    /// A status's words and, when it ends in a count, the count.
    static func split(_ label: String) -> (words: String, count: ArisTagCount?) {
        guard let cut = label.range(of: mark, options: .backwards) else { return (label, nil) }
        let numbers = label[cut.upperBound...].split(separator: "/", omittingEmptySubsequences: false)
        let words = String(label[..<cut.lowerBound])
        guard numbers.count == 2, numbers.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy { ("0"..."9").contains($0) } }),
              let step = Int(numbers[0]), let total = Int(numbers[1]), isCount(step: step, of: total),
              !words.trimmingCharacters(in: .whitespaces).isEmpty else { return (label, nil) }
        return (words, ArisTagCount(step: step, of: total))
    }

    /// A long conversion's own note of its minutes ("… (3분째)", "… (3 min)") is dropped where the tag shows its clock.
    static func withoutMinutes(_ words: String) -> String {
        guard let note = words.range(of: #"\s*\(\d+(분째| min)\)$"#, options: .regularExpression) else { return words }
        return String(words[..<note.lowerBound])
    }

    /// The tag's clock ("0:10", "1:15", "1:02:05"): nil until the tag has run `clockAfter`, and for a tag with no start.
    static func clock(since: Date?, now: Date) -> String? {
        guard let since else { return nil }
        let ran = now.timeIntervalSince(since)
        return ran >= clockAfter ? elapsed(ran) : nil
    }

    /// "0:42", "10:05", "1:02:03": the jobs' pill's clock (ArisPillLayout.elapsed; the tests hold the two to the same form).
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let (h, m, s) = (total / 3_600, total % 3_600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// How long until a tag that began at `since` shows its clock; 0 when it already should.
    static func untilClock(since: Date, now: Date) -> TimeInterval {
        max(0, clockAfter - now.timeIntervalSince(since))
    }
}

// MARK: - A press on a running tag (third VM run, bug D)
//
// A press that ends anywhere inside the tag's frame as it is at that moment stops the work. The frame used to be a
// size kept from the tag's last layout; it is now read when the press ends, with a little room around it for a
// pointer that slipped a point while the tag's clock ticked. A press that was received and did nothing is never
// silent: one log line says why (it ended outside, the tag had stopped running, the press was taken away before it
// ended).
enum ArisTagPress {
    /// How far outside the tag's edge a press may end and still count.
    static let slack: CGFloat = 3

    enum Outcome: Equatable {
        case stop
        /// Nothing was done: why, for the log.
        case ignored(String)
    }

    /// `location`: where the press ended, in the tag's own space. `size`: the tag's frame at that moment.
    /// `pressable`: the tag still runs and has a stop.
    static func ended(at location: CGPoint, in size: CGSize, pressable: Bool) -> Outcome {
        guard pressable else { return .ignored("the tag was no longer running") }
        guard size.width > 0, size.height > 0 else { return .ignored("the tag had no frame yet") }
        guard CGRect(origin: .zero, size: size).insetBy(dx: -slack, dy: -slack).contains(location) else {
            return .ignored("it ended outside the tag (at \(Int(location.x)),\(Int(location.y)) of \(Int(size.width))×\(Int(size.height)))")
        }
        return .stop
    }

    /// The press went down on the tag and never ended there (SwiftUI took the gesture away): the line for the log.
    static let takenAway = "it was taken away before it ended"

    /// The one log line for a press that did nothing.
    static func logLine(_ reason: String) -> String { "a press on the running tag did nothing: \(reason)" }
}
