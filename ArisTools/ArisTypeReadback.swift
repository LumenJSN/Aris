//
//  ArisTypeReadback.swift
//  aris-tools
//
//  Whether `aris-tools type` really typed (QA BUG-10: Aris said "입력했어요" while both TextEdit documents stayed
//  empty; the keys went out and nothing checked where they landed). The focused field is read through Accessibility
//  before and after, and only text that shows up there counts. Anything else is a failure line that leads with
//  notTypedLead, never "typed N characters", so the brain can't take it for a success. Pure, so the tests run it.
//

import Foundation

enum ArisTypeReadback {
    static let notTypedLead = "NOT TYPED (not confirmed): don't tell the user it was typed."
    /// The keys went out without an error, but the field can't be read back, or shows the text changed (an app's own
    /// capitals, a key the Mac dropped): typed, not checked to be exact (QA follow-up to BUG-10; second upgrade run,
    /// bug 3: the text WAS typed, and Aris said "nothing was added").
    static let notConfirmedLead = "NOT CONFIRMED: the keys were sent without an error, but the text box can't be checked to hold exactly the text; don't say it went in exactly, and never say nothing was added."
    /// `keys` stopped: the app left the front, so the rest wasn't sent there (QA follow-up).
    static let notSentLead = "NOT SENT: "

    /// What `aris-tools keys` says. A key's effect can't be read back in general, so the line says only what was sent,
    /// never that it worked; and it stops (failing) when the app is no longer in front, so nothing lands elsewhere.
    static func keysLine(_ written: String, times: Int, app: String, stayedInFront: Bool) -> (ok: Bool, line: String) {
        let count = times > 1 ? " ×\(times)" : ""
        guard stayedInFront else {
            return (false, "\(notSentLead)\(app) left the front, so \(written)\(count) wasn't (all) sent there. Don't tell the user it was done.")
        }
        return (true, "sent \(written)\(count) to \(app) (keys only: what they did is not checked; look with `desktop see` before telling the user it worked)")
    }

    /// The text is in the focused field now, one more time than before (compared composed, line endings alike).
    static func landed(_ text: String, before: String?, after: String?) -> Bool {
        let wanted = plain(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, let after else { return false }
        return count(wanted, in: plain(after)) > count(wanted, in: plain(before ?? ""))
    }

    /// The text is there as the app keeps typed text: its own capitals (TextEdit's "Seven"), curly quotes and dashes,
    /// and spaces it trims or doubles are what typing into it does, not a failure.
    static func landedAsTheAppTypes(_ text: String, before: String?, after: String?) -> Bool {
        let wanted = loose(text)
        guard !wanted.isEmpty, let after else { return false }
        return count(wanted, in: loose(after)) > count(wanted, in: loose(before ?? ""))
    }

    /// What aris-tools prints (ok) or fails with. "Nothing was typed" only when the field shows no change at all.
    static func result(_ text: String, app: String, before: String?, after: String?) -> (ok: Bool, line: String) {
        if landed(text, before: before, after: after) { return (true, "typed \(text.count) characters into \(app) (confirmed: the field shows it)") }
        if landedAsTheAppTypes(text, before: before, after: after) {
            return (true, "typed \(text.count) characters into \(app) (confirmed: the field shows it, with the app's own capitals, quotes or spaces)")
        }
        guard let after else {
            return (false, "\(notConfirmedLead) \(app): the text box with the cursor can't be read back. \(tell(notConfirmedKorean, notConfirmedEnglish)) To check, look with `desktop see`.")
        }
        guard mostlyArrived(text, before: before, after: after) else {
            return (false, "\(notTypedLead) \(app): the text box with the cursor doesn't show the text. \(tell(notTypedKorean, notTypedEnglish)) To work in its window, look first with `desktop see`.")
        }
        return (false, "\(notConfirmedLead) \(app): the text box changed, but it doesn't hold exactly the text (some characters may differ or be missing). \(tell(notConfirmedKorean, notConfirmedEnglish)) To check, look with `desktop see`.")
    }

    /// No field has the keyboard focus: nothing is typed (the keys would land nowhere, or somewhere else).
    static func noFieldLine(app: String) -> String {
        "\(notTypedLead) No text box has the cursor in \(app), so nothing was typed. \(tell(noFieldKorean, noFieldEnglish))"
    }

    /// The window isn't on any display (QA BUG-33): nothing is typed.
    static func offScreenLine(app: String) -> String {
        "\(notTypedLead) \(app)'s window isn't on any screen, so nothing was typed. \(tell(noFieldKorean, noFieldEnglish))"
    }

    // What the user hears, never the tool's own words (QA BUG-33: "focused field에서 …" reached the reply).
    static let notTypedKorean = "입력칸에 글자가 들어가지 않았어요."
    static let notTypedEnglish = "The text didn't go into the text box."
    static let notConfirmedKorean = "입력했어요. 다만 그대로 들어갔는지는 확인하지 못했어요."
    static let notConfirmedEnglish = "I typed it, but I couldn't check that it went in exactly as written."
    static let noFieldKorean = "입력칸이 선택돼 있지 않아서 입력하지 않았어요."
    static let noFieldEnglish = "No text box was selected, so nothing was typed."

    private static func tell(_ korean: String, _ english: String) -> String {
        "Tell the user exactly this, in their language: “\(korean)” (English: “\(english)”)."
    }

    private static func plain(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// The field grew by most of the text, and what is in it now is most of the text's letter pairs: typed, with
    /// characters changed or lost on the way (a key the Mac dropped). A field showing other words is not this.
    static func mostlyArrived(_ text: String, before: String?, after: String) -> Bool {
        let wanted = loose(text), now = loose(after), was = loose(before ?? "")
        guard wanted.count >= 2, now.count - was.count >= wanted.count / 2 else { return false }
        let pairs = { (words: String) -> Set<String> in
            let characters = Array(words)
            return Set(zip(characters, characters.dropFirst()).map { String([$0, $1]) })
        }
        let mine = pairs(wanted), there = pairs(now).subtracting(pairs(was))
        return Double(mine.intersection(there).count) >= 0.6 * Double(mine.count)
    }

    /// Compared the way an app may change typed text: letters in one case, curly quotes and dashes straight, every run
    /// of spaces one space, no spaces at the ends of lines.
    private static func loose(_ text: String) -> String {
        let straight = plain(text).lowercased()
            .replacingOccurrences(of: "[\u{2018}\u{2019}\u{201A}\u{2032}]", with: "'", options: .regularExpression)
            .replacingOccurrences(of: "[\u{201C}\u{201D}\u{201E}\u{2033}]", with: "\"", options: .regularExpression)
            .replacingOccurrences(of: "[\u{2013}\u{2014}]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "\u{2026}", with: "...")
            .replacingOccurrences(of: "[ \t\u{00A0}]+", with: " ", options: .regularExpression)
        return straight.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func count(_ needle: String, in haystack: String) -> Int { haystack.components(separatedBy: needle).count - 1 }
}
