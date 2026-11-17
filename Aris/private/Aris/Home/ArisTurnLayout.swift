//
//  ArisTurnLayout.swift
//  Aris
//
//  The open notch's turn as numbers: the composer's one to three lines, when your words collapse in their card, and
//  when the answer offers "Open answer". Pure, so the tests check them.
//

import CoreGraphics

/// The composer: 22-point lines, 8 above and below, at most three lines tall.
enum ArisComposerLines {
    static let lineHeight: CGFloat = 22
    static let padding: CGFloat = 16
    static let maxLines = 3

    static func height(lines: Int) -> CGFloat {
        CGFloat(min(max(lines, 1), maxLines)) * lineHeight + padding
    }

    /// How many lines the field's text takes, from its height at the field's own line height.
    static func lines(measured: CGFloat, lineHeight: CGFloat) -> Int {
        guard measured > 0, lineHeight > 0 else { return 1 }
        return min(max(Int((measured / lineHeight).rounded()), 1), maxLines)
    }
}

/// The composer's field after Return (the film's "…one pdfmake these…"): macOS's field editor behind a vertical
/// TextField can keep the sent words when the bound text is cleared inside onSubmit, and write them back with the next
/// keystroke, so the next request is typed onto the last one.
enum ArisComposerClear {
    /// The most new characters typed onto the sent words in the one change that brings them back (a keystroke, or a
    /// few from an input method).
    static let keystrokes = 3

    /// Right after a send: the field still holds the sent words, so they are cleared.
    static func stillSent(_ current: String, sent: String) -> Bool { !sent.isEmpty && current == sent }

    /// The first change after a send, from an empty field to `new`: the sent words written back with what was just
    /// typed, then only the typed part is kept; nil when it is ordinary typing (leave it).
    static func restored(old: String, new: String, sent: String) -> String? {
        guard !sent.isEmpty, old.isEmpty, new.hasPrefix(sent) else { return nil }
        let typed = new.count - sent.count
        return (0...keystrokes).contains(typed) ? String(new.dropFirst(sent.count)) : nil
    }
}

/// The sent-prompt card: 22-point lines inside 16 of padding. Over two
/// lines it collapses to two lines and an 18-point peek of the third under a 34-point fade; tapped, it shows all of it.
enum ArisPromptCollapse {
    static let lineHeight: CGFloat = 22
    static let padding: CGFloat = 16
    static let collapsedLines = 2
    static let peek: CGFloat = 18
    static let fade: CGFloat = 34
    /// The collapsed text: 2·22 + 18.
    static let collapsedContent = CGFloat(collapsedLines) * lineHeight + peek
    /// Where the collapsed text's fade starts, as a share of its height.
    static let fadeStart = 1 - fade / collapsedContent
    /// The text's spacing between lines (22 less SF's 18-point line at 15 points); the last line has none.
    static let lineSpacing: CGFloat = 4

    /// Lines in text `measured` tall, laid out on the 22-point pitch.
    static func lines(measured: CGFloat) -> Int {
        max(1, Int(((measured + lineSpacing) / lineHeight).rounded()))
    }

    static func collapses(lines: Int, expanded: Bool) -> Bool {
        lines > collapsedLines && !expanded
    }

    static func content(lines: Int, collapsed: Bool) -> CGFloat {
        collapsed ? collapsedContent : CGFloat(max(lines, 1)) * lineHeight
    }

    /// The whole card, its padding included.
    static func box(lines: Int, collapsed: Bool) -> CGFloat {
        content(lines: lines, collapsed: collapsed) + 2 * padding
    }

    /// The words' height on screen from their full height, decided in the same layout pass (ArisPromptClamp): cut to
    /// the collapsed height past two lines unless expanded.
    static func clamped(full: CGFloat, expanded: Bool) -> CGFloat {
        collapses(lines: lines(measured: full), expanded: expanded) ? collapsedContent : full
    }

    /// Whether words `height` tall on screen are the cut ones, which fade at the bottom. Only a cut card is the
    /// collapsed height: two lines are 40, three or more are cut.
    static func fades(height: CGFloat, expanded: Bool) -> Bool {
        !expanded && height >= collapsedContent - 0.5
    }
}

/// "Open answer": offered once the answer is taller than the reader limit, the answer budget but never over 360, by
/// more than a point.
enum ArisAnswerReader {
    static func limit(budget: CGFloat) -> CGFloat {
        min(ArisAnswerBudget.widgetMax, budget)
    }

    static func offers(content: CGFloat, budget: CGFloat) -> Bool {
        content > limit(budget: budget) + 1
    }
}
