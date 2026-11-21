//
//  ArisNoticePill.swift
//  Aris
//
//  The notice pill's decisions as plain values (the owner's pick D, 2026-11-16, "노치 아래 알약"): it hangs 6 under the closed
//  notch where the jobs' pill hangs, in the dictation pill's body. Collapsed it is one line 38 high, as wide as its words
//  ask (284 / 364 / 440); under the pointer it grows into a 364-wide card of corner 24 with the whole text and the
//  buttons (the width is stepped up until what must be read fits: ArisNoticePillFit). It arrives from the 36 × 8 bar (the dictation pill's idle size) in 250 ms, its content fading in over
//  150 ms, and leaves fading and shrinking to 0.8 in 150 ms, on CSS `ease`. Between the line and the card it morphs on
//  a spring (grow 0.34 s, fold 0.22 s), one progress driving the size, the corner and the crossfade (ArisNoticePillMorph),
//  after the pointer rests 100 ms and 150 ms after it leaves (ArisNoticeHoverIntent). Where it stands against the jobs'
//  pill, and when a notice that goes by itself runs its clock. Pure, so it's tested (ArisNoticePillView draws it).
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
    /// Half the height: a capsule (ArisDictationPillShape gives the same).
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
    /// An update's progress bar where the time stands: 56 × 3, the time's white .38 for the part done on white .12.
    static let progressWidth: CGFloat = 56
    static let progressHeight: CGFloat = 3
    static let progressTrack = 0.12

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

    // MARK: Motion (seconds)

    /// It arrives from the dictation pill's idle bar, and leaves, on CSS ease (the dictation pill's; unchanged).
    static let barSize = CGSize(width: 36, height: 8)
    static let arrive: Double = 0.25
    static let contentFade: Double = 0.15
    /// The content fades in as the size lands.
    static var contentDelay: Double { arrive - contentFade }
    static let exit: Double = 0.15
    static let exitScale: CGFloat = 0.8
    static let ease = (0.25, 0.1, 0.25, 1.0)

    /// Line ↔ card: a spring in Apple's duration / bounce form, so a pointer that turns back half-way reverses it from
    /// where it is at the speed it has (Emil Kowalski: springs for anything the user can interrupt; CSS curves restart).
    /// Growing 0.34 s at bounce 0.08: settled without a visible overshoot (damping ratio .92, under 0.1 % past).
    static let expand: Double = 0.34
    static let expandBounce: Double = 0.08
    /// Folding back faster than it grew, no bounce (Emil: the exit is quicker than the entrance; the system responds).
    static let collapse: Double = 0.22
    static let collapseBounce: Double = 0
    /// The crossfade as parts of the morph's progress (0 the line, 1 the card), never two layouts at once: the line's
    /// rest and time are gone by .4 (~73 ms into the grow), the card's body and buttons come in from .45 to .95
    /// (~80 → 225 ms), rising 3 points and sharpening from a 2-point blur (Emil: blur ≤ 2 px masks a crossfade).
    static let lineFadeEnd: CGFloat = 0.4
    static let cardFadeStart: CGFloat = 0.45
    static let cardFadeEnd: CGFloat = 0.95
    static let cardBlur: CGFloat = 2
    static let cardRise: CGFloat = 3
    /// Hover intent: the card opens once the pointer has rested 100 ms (brushing past leaves it a line), and folds 150 ms
    /// after the pointer leaves; back within that grace, it stays (Emil: tooltips wait before opening, against accidents).
    static let hoverIntent: Double = 0.1
    static let hoverGrace: Double = 0.15
    /// A button pressed: 0.97 in 120 ms (Emil: press feedback 0.95-0.98, 100-160 ms). With Reduce Motion it dims to .8.
    static let pressScale: CGFloat = 0.97
    static let press: Double = 0.12
    static let pressDim = 0.8
    /// Reduce Motion: the size changes at once and only the content crossfades, in 150 ms (the content's own fade).
    static var reducedFade: Double { contentFade }

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
        case .progress: L.progressWidth
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

    /// The line is read whole: a deadline's (what is due and the time left), and a card whose words are what to press
    /// for (the reopen card's "Reopen Aris to use it": fourth VM run, cut to "R…" under the closed notch). Its bold part
    /// shortens first, past 440; the rest never.
    static func readWhole(_ notice: ArisNotice) -> Bool {
        if case .deadline = notice.source { return true }
        return notice.actions.contains { $0.role == .relaunchApp }
    }

    /// What must be read whole: a whole line that is read whole; any other notice's title and time (its preview may be cut).
    static func needed(_ notice: ArisNotice, now: Date, english: Bool) -> CGFloat {
        if readWhole(notice) { return whole(notice, now: now, english: english) }
        return chrome + boldWidth(notice) + trailingWidth(ArisNoticePillRules.trailing(notice, now: now, english: english)) + slack
    }

    /// The collapsed width: the length's step, stepped up until what must be read fits; 440 at most (past it the bold
    /// part shortens, never a deadline's time left or its chip).
    static func width(_ notice: ArisNotice, now: Date, english: Bool) -> CGFloat {
        let need = needed(notice, now: now, english: english)
        let fits = L.widths.first { $0 >= need } ?? L.widths[L.widths.count - 1]
        return max(L.width(notice), fits)
    }

    /// Never cut on the line, whatever the width: a deadline's time left and its chip; a line read whole's rest.
    static func kept(_ notice: ArisNotice, now: Date, english: Bool) -> CGFloat {
        let trailing = trailingWidth(ArisNoticePillRules.trailing(notice, now: now, english: english))
        if readWhole(notice) { return chrome + textGap + restWidth(notice) + trailing + slack }
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

    /// Its size: the card is as tall as its text measures (`card`), a number the height can move to.
    func size(width collapsed: CGFloat, card: CGFloat) -> CGSize {
        switch self {
        case .bar: ArisNoticePillLayout.barSize
        case .collapsed: CGSize(width: collapsed, height: ArisNoticePillLayout.height)
        case .expanded: CGSize(width: ArisNoticePillLayout.expandedWidth, height: card)
        }
    }

    /// The corner at `height`: half of it while that is under 24 (the bar, the 38-high line's 19), else 24.
    static func radius(height: CGFloat) -> CGFloat { min(ArisNoticePillLayout.expandedRadius, height / 2) }

    /// How long the move from `self` to `next` takes: arriving 250 ms; growing a 0.34 s spring, folding a 0.22 s one.
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

/// The line ↔ card morph at one instant, as plain values of its progress (0 the line, 1 the card; a spring may pass 1 by
/// a hair). Everything follows the one number, so a reversal half-way never jumps, and a render can draw any instant.
struct ArisNoticePillMorph: Equatable {
    typealias L = ArisNoticePillLayout
    let progress: CGFloat

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    /// 0 before `from`, 1 after `to`, straight between (the spring already eases the progress).
    static func ramp(_ x: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat { min(1, max(0, (x - from) / (to - from))) }

    /// The size between the line (`collapsed` wide, 38 high) and the card (364 wide, `card` high, as measured); from the
    /// bar while it arrives (`arrival` 0 → 1).
    func size(collapsed: CGFloat, card: CGFloat, arrival: CGFloat = 1) -> CGSize {
        let width = Self.lerp(collapsed, L.expandedWidth, progress), height = Self.lerp(L.height, card, progress)
        return CGSize(width: Self.lerp(L.barSize.width, width, arrival), height: Self.lerp(L.barSize.height, height, arrival))
    }

    /// The line's rest and its time or chip: gone by .4.
    var lineOpacity: CGFloat { 1 - Self.ramp(progress, from: 0, to: L.lineFadeEnd) }
    /// The card's text, ✕ and buttons: from .45 to .95.
    var cardOpacity: CGFloat { Self.ramp(progress, from: L.cardFadeStart, to: L.cardFadeEnd) }
    /// The card's blur while it comes in (none while it is not there at all, so nothing is blurred unseen).
    var cardBlur: CGFloat { cardOpacity > 0 ? L.cardBlur * (1 - cardOpacity) : 0 }
    /// How far below its place the card's text still is.
    var cardRise: CGFloat { L.cardRise * (1 - cardOpacity) }
    /// The mark's (and a shared title's) top: 9 on the line (centred in 38), 10 on the card (its top padding).
    var headerTop: CGFloat { Self.lerp((L.height - L.markSize) / 2, L.cardPadding.top, min(1, max(0, progress))) }
    /// The card takes clicks and is read out once it is more than half there; the line until then.
    var cardLive: Bool { cardOpacity > 0.5 }
}

extension ArisNoticePillLayout {
    /// Where a spring of Apple's duration / bounce form (SwiftUI's Spring(duration:bounce:): stiffness (2π / duration)²,
    /// damping ratio 1 − bounce) stands `t` seconds after leaving 0 at rest for 1. For the render's frames and the tests.
    static func spring(_ t: Double, duration: Double, bounce: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * Double.pi / duration, zeta = 1 - bounce
        guard zeta < 1 else { return 1 - exp(-omega * t) * (1 + omega * t) }
        let damped = omega * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
    }

    /// The card's title room: 364 less its paddings, the mark, the gaps, the spacer's 4 and the ✕.
    static var cardTitleRoom: CGFloat { expandedWidth - cardPadding.leading - markSize - gap - 4 - gap - closeSize - cardPadding.trailing }
}

extension ArisNoticePillFit {
    /// The line's bold part and the card's title are one text, drawn once and kept in place across the morph, when they
    /// are the same words and fit whole in both (any notice but a deadline, whose line leads with what is due). Else the
    /// two crossfade where they stand.
    static func sharesTitle(_ notice: ArisNotice, now: Date, english: Bool) -> Bool {
        if case .deadline = notice.source { return false }
        let line = ArisNoticePillRules.line(notice)
        guard line.bold == notice.title, !notice.title.isEmpty else { return false }
        return needed(notice, now: now, english: english) <= width(notice, now: now, english: english)
            && textWidth(notice.title, size: L.textSize, weight: semibold) + slack <= L.cardTitleRoom
    }
}

/// The notice pill's hover intent (ArisHoverIntent): 100 ms of rest before the card, 150 ms of grace before it folds;
/// `expanded` is the notice drawn as the card.
typealias ArisNoticeHoverIntent = ArisHoverIntent<UUID>

extension ArisHoverIntent where Target == UUID {
    init() { self.init(delay: ArisNoticePillLayout.hoverIntent, grace: ArisNoticePillLayout.hoverGrace) }
}

/// What stands at the pill's right.
enum ArisNoticeTrailing: Equatable {
    /// When it came ("방금").
    case time(String)
    /// A deadline's "24h" or "3h" chip.
    case chip(ArisDueAlert)
    /// An update's progress, 0 to 1.
    case progress(Double)
}

enum ArisNoticePillRules {
    static func trailing(_ notice: ArisNotice, now: Date, english: Bool) -> ArisNoticeTrailing {
        if case .deadline(let alert) = notice.source { return .chip(alert) }
        if let progress = notice.progress { return .progress(progress) }
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
