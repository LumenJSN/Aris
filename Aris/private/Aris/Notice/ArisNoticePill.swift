//
//  ArisNoticePill.swift
//  Aris
//
//  The notice pill's decisions as plain values (the owner's pick D, 2026-11-16, "노치 아래 알약"): it hangs 6 under the closed
//  notch where the jobs' pill hangs, in the dictation pill's body. Collapsed it is one line 38 high, as wide as its words
//  ask (284 / 364 / 440); under the pointer it grows into a 364-wide card of corner 24 with the whole text and the
//  buttons (the width is stepped up until what must be read fits: ArisNoticePillFit). It arrives from the 36 × 8 bar (the dictation pill's idle size) in 250 ms, its content fading in over
//  150 ms; it grows in 250 ms and folds back in 180 ms; it leaves fading and shrinking to 0.8 in 150 ms, all on CSS
//  `ease`. Where it stands against the jobs' pill, and when a notice that goes by itself runs its clock. Pure, so it's
//  tested (ArisNoticePillView draws it).
//

import CoreGraphics
import CoreText
import Foundation

enum ArisNoticePillLayout {
    // MARK: Place

    /// Under the closed notch, as the jobs' pill hangs.
    static let belowNotch: CGFloat = 6

    // MARK: Collapsed

    static let height: CGFloat = 38
    /// Half the height: a capsule (ArisDictationPillRules.cornerRadius gives the same).
    static let radius: CGFloat = 19
    /// The widths by length, and the lengths (the title's and the body's characters together) under which each is used.
    static let widths: [CGFloat] = [284, 364, 440]
    static let shortUnder = 40
    static let mediumUnder = 100
    static let leading: CGFloat = 10
    static let trailing: CGFloat = 13
    static let gap: CGFloat = 8
    static let markSize: CGFloat = 20
    static let textSize: CGFloat = 13
    static let titleOpacity = 0.94
    static let bodyOpacity = 0.56
    /// The time at the right: 11 pt medium at .38.
    static let timeSize: CGFloat = 11
    static let timeOpacity = 0.38
    /// A deadline's chip: 20 high, 7 in, 11 pt bold, its colour on a .16 fill of itself.
    static let chipHeight: CGFloat = 20
    static let chipPadding: CGFloat = 7
    static let chipSize: CGFloat = 11
    static let chipFill = 0.16

    // MARK: Expanded (the card)

    static let expandedWidth: CGFloat = 364
    static let expandedRadius: CGFloat = 24
    static let cardPadding = (top: CGFloat(10), leading: CGFloat(10), bottom: CGFloat(12), trailing: CGFloat(12))
    static let cardSpacing: CGFloat = 8
    /// The text under the title starts under the title (the mark and its gap in from the edge).
    static var textIndent: CGFloat { markSize + gap }
    static let subtitleSize: CGFloat = 12.5
    static let bodySize: CGFloat = 13
    static let bodyLine: CGFloat = 19.5
    static let bodyLines = 6
    static let cardTextOpacity = 0.78
    static let buttonHeight: CGFloat = 26
    static let buttonGap: CGFloat = 6
    static let buttonPadding: CGFloat = 13
    static let buttonTextSize: CGFloat = 12
    /// The ✕ at the top right: a 20 circle, white .08, an 8-point glyph at .6.
    static let closeSize: CGFloat = 20
    static let closeGlyph: CGFloat = 8
    static let closeFill = 0.08
    static let closeGlyphOpacity = 0.6

    // MARK: Motion (seconds, CSS ease)

    /// It arrives from the dictation pill's idle bar.
    static let barSize = CGSize(width: 36, height: 8)
    static let arrive: Double = 0.25
    static let contentFade: Double = 0.15
    /// The content fades in as the size lands.
    static var contentDelay: Double { arrive - contentFade }
    static let expand: Double = 0.25
    static let collapse: Double = 0.18
    static let exit: Double = 0.15
    static let exitScale: CGFloat = 0.8
    static let ease = (0.25, 0.1, 0.25, 1.0)

    /// The collapsed width the words' length asks for (the mockup's rule): under 40 characters 284, under 100 364, else
    /// 440. The pill is never narrower than what must be read whole needs (ArisNoticePillFit.width).
    static func width(title: String, body: String) -> CGFloat {
        let count = title.count + body.count
        return count < shortUnder ? widths[0] : count < mediumUnder ? widths[1] : widths[2]
    }

    static func width(_ notice: ArisNotice) -> CGFloat { width(title: notice.title, body: notice.body) }
}

/// How wide the collapsed line must be, measured with the system font as the line is drawn: the mark and its gaps,
/// the bold part and the rest, the time or the chip, and the paddings. What must never be cut: a deadline's time left
/// and its chip (its bold part, what is due, shortens first, only past 440); any other notice's title and its time
/// (only its body, a dimmed preview, is cut, and past 440 the title shortens). The width steps up 284 → 364 → 440
/// until that fits.
enum ArisNoticePillFit {
    typealias L = ArisNoticePillLayout

    /// Everything on the line but its words: 10 in, the 20 mark, the 8 gaps either side of the words and the trailing
    /// part, the spacer's 4, 13 at the right.
    static var chrome: CGFloat { L.leading + L.markSize + L.gap + L.gap + 4 + L.gap + L.trailing }
    /// A little room against rounding between this measure and the drawn text.
    static let slack: CGFloat = 2
    /// The CoreText weights of the line's parts (semibold, medium, regular, bold).
    static let semibold: CGFloat = 0.3, medium: CGFloat = 0.23, regular: CGFloat = 0, bold: CGFloat = 0.4

    /// `text` set in the system font at `size` and `weight`, as wide as it draws (other scripts falling back as drawn).
    static func textWidth(_ text: String, size: CGFloat, weight: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let traits = [kCTFontWeightTrait: weight] as CFDictionary
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base), [kCTFontTraitsAttribute: traits] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        let string = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(string), nil, nil, nil)).rounded(.up)
    }

    /// Between the bold part and the rest: two spaces of the bold.
    static var textGap: CGFloat { textWidth("  ", size: L.textSize, weight: semibold) }

    static func trailingWidth(_ trailing: ArisNoticeTrailing) -> CGFloat {
        switch trailing {
        case .time(let words): textWidth(words, size: L.timeSize, weight: medium)
        case .chip(let alert): textWidth(alert.rawValue, size: L.chipSize, weight: bold) + 2 * L.chipPadding
        }
    }

    static func boldWidth(_ notice: ArisNotice) -> CGFloat { textWidth(ArisNoticePillRules.line(notice).bold, size: L.textSize, weight: semibold) }

    static func restWidth(_ notice: ArisNotice) -> CGFloat {
        let line = ArisNoticePillRules.line(notice)
        return textWidth(line.rest, size: L.textSize, weight: line.restTinted ? medium : regular)
    }

    /// The whole line, nothing cut.
    static func whole(_ notice: ArisNotice, now: Date, english: Bool) -> CGFloat {
        let rest = restWidth(notice)
        return chrome + boldWidth(notice) + (rest > 0 ? textGap + rest : 0)
            + trailingWidth(ArisNoticePillRules.trailing(notice, now: now, english: english)) + slack
    }

    /// What must be read whole: a deadline's whole line; any other notice's title and time (its preview may be cut).
    static func needed(_ notice: ArisNotice, now: Date, english: Bool) -> CGFloat {
        if case .deadline = notice.source { return whole(notice, now: now, english: english) }
        return chrome + boldWidth(notice) + trailingWidth(ArisNoticePillRules.trailing(notice, now: now, english: english)) + slack
    }

    /// The collapsed width: the length's step, stepped up until what must be read fits; 440 at most (past it the bold
    /// part shortens, never a deadline's time left or its chip).
    static func width(_ notice: ArisNotice, now: Date, english: Bool) -> CGFloat {
        let need = needed(notice, now: now, english: english)
        let fits = L.widths.first { $0 >= need } ?? L.widths[L.widths.count - 1]
        return max(L.width(notice), fits)
    }

    /// Never cut on the line, whatever the width: a deadline's time left and its chip.
    static func kept(_ notice: ArisNotice, now: Date, english: Bool) -> CGFloat {
        let trailing = trailingWidth(ArisNoticePillRules.trailing(notice, now: now, english: english))
        if case .deadline = notice.source { return chrome + textGap + restWidth(notice) + trailing + slack }
        return chrome + trailing + slack
    }
}

/// What the pill is drawn as: the bar it arrives from, one line, or the card under the pointer.
enum ArisNoticePillPhase: Equatable {
    case bar, collapsed, expanded

    /// Not yet arrived: the bar; then the card while the pointer is on it, else the line.
    static func of(arrived: Bool, hovered: Bool) -> ArisNoticePillPhase {
        guard arrived else { return .bar }
        return hovered ? .expanded : .collapsed
    }

    /// Its width; its height (nil: the card's, from its text).
    func size(width collapsed: CGFloat) -> (width: CGFloat, height: CGFloat?) {
        switch self {
        case .bar: (ArisNoticePillLayout.barSize.width, ArisNoticePillLayout.barSize.height)
        case .collapsed: (collapsed, ArisNoticePillLayout.height)
        case .expanded: (ArisNoticePillLayout.expandedWidth, nil)
        }
    }

    /// The corner at `height`: half of it while that is under 24 (the bar, the 38-high line's 19), else 24.
    static func radius(height: CGFloat) -> CGFloat { min(ArisNoticePillLayout.expandedRadius, height / 2) }

    /// How long the move from `self` to `next` takes: arriving and growing 250 ms, folding back 180 ms.
    func duration(to next: ArisNoticePillPhase) -> Double {
        switch (self, next) {
        case (.expanded, .collapsed), (.expanded, .bar): ArisNoticePillLayout.collapse
        case (.bar, _): ArisNoticePillLayout.arrive
        default: ArisNoticePillLayout.expand
        }
    }

    /// The content shows once it has arrived.
    var contentShown: Bool { self != .bar }
}

/// What stands at the pill's right.
enum ArisNoticeTrailing: Equatable {
    /// When it came ("방금").
    case time(String)
    /// A deadline's "24h" or "3h" chip.
    case chip(ArisDueAlert)
}

enum ArisNoticePillRules {
    static func trailing(_ notice: ArisNotice, now: Date, english: Bool) -> ArisNoticeTrailing {
        if case .deadline(let alert) = notice.source { return .chip(alert) }
        return .time(ArisNoticeWords.ago(now.timeIntervalSince(notice.posted), english: english))
    }

    /// The collapsed line's two parts: the bold one first. A deadline leads with what is due ("PS3 · 내일") and ends with
    /// the time left in its colour; the rest lead with the title and end with the body, dimmed.
    static func line(_ notice: ArisNotice) -> (bold: String, rest: String, restTinted: Bool) {
        if case .deadline = notice.source { return (notice.body, notice.title, true) }
        return (notice.title, notice.body, false)
    }

    /// The front notice's own clock runs (it goes after its showsFor) only while it is seen: not while it steps aside,
    /// and not while the pointer is on it.
    static func clockRuns(_ notice: ArisNotice?, hovered: UUID?, aside: Bool) -> Bool {
        guard let notice, notice.showsFor != nil else { return false }
        return !aside && hovered != notice.id
    }

    /// Who has the room under the closed notch: the notice pill on the display it shows on, else the jobs' pill. The
    /// music peek and the Now Playing notice keep it for themselves while they show (a moment), as before.
    enum UnderNotch: Equatable { case notice, jobs, none }

    static func underNotch(closed: Bool, hidden: Bool, musicPeek: Bool, nowPlaying: Bool, noticeUp: Bool, noticeHere: Bool) -> UnderNotch {
        guard closed, !musicPeek, !nowPlaying else { return .none }
        if noticeUp && noticeHere { return .notice }
        return hidden ? .none : .jobs
    }
}
