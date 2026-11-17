//
//  ArisDictationPillRecoveredLayout.swift
//  Aris
//
//  The recovered words' card (the owner's pick B, "글에 맞춘 카드", mockups reccard-mock): a card that hugs its words.
//  A header line (a 12 check, "복사해 뒀어요 · [⌘V] 로 붙여 넣기" in 12 / 500 at the secondary white, the thin ✕ at the
//  far right) over the words (14 / 500, ×1.45, word-wrapped: Hangul breaks at spaces). The content is as wide as its
//  longest line between 220 and 340, plus 16 / 10 padding; as tall as header + 6 + words (at most 4 lines, then it
//  scrolls with a 16 bottom fade while there is more), plus 11 / 13. The words are the copy target: a click copies them
//  again and the label says "다시 복사했어요" for 1.2 s. It grows out of the pill (80 × 30, r15) to its size in 300 ms
//  (0.2, 0.8, 0.2, 1), its contents fading in 160 ms after 110 ms; it leaves in 160 ms (opacity, scale .96).
//  Sizes are measured with the text system here, so the window's pointer area and the drawn card agree. Pure.
//

import AppKit

enum ArisDictationPillRecoveredLayout {
    // MARK: - Tokens

    static let minContentWidth: CGFloat = 220
    static let maxContentWidth: CGFloat = 340
    static let paddingTop: CGFloat = 11
    static let paddingTrailing: CGFloat = 10
    static let paddingBottom: CGFloat = 13
    static let paddingLeading: CGFloat = 16
    /// Between the header and the words, and between the header's pieces.
    static let gap: CGFloat = 6
    static let radius: CGFloat = 18

    static let closeSize: CGFloat = 22
    static let closeGlyph: CGFloat = 10
    static let checkSize: CGFloat = 12
    static let headerHeight: CGFloat = closeSize

    static let headerFontSize: CGFloat = 12
    static let keyFontSize: CGFloat = 11
    static let keyMinWidth: CGFloat = 22
    static let keyHeight: CGFloat = 18
    static let keyPadding: CGFloat = 4
    static let keyRadius: CGFloat = 5

    static let bodyFontSize: CGFloat = 14
    static let lineHeight: CGFloat = 14 * 1.45
    static let kerning: CGFloat = -0.005 * 14
    /// The words' box: 2 above and below, and 6 either side of the words (its hover fill reaches past them).
    static let bodyPadding: CGFloat = 2
    static let bodyOutset: CGFloat = 6
    static let bodyRadius: CGFloat = 8
    static let maxLines = 4
    static let fadeMax: CGFloat = 16

    static let growDuration = 0.3
    static let growCurve = (0.2, 0.8, 0.2, 1.0)
    static let startSize = CGSize(width: 80, height: 30)
    static let startRadius: CGFloat = 15
    static let contentFade = 0.16
    static let contentDelay = 0.11
    static let leaveDuration = 0.16
    static let leaveScale: CGFloat = 0.96
    static let hoverDuration = 0.15
    /// How long the label says "다시 복사했어요" after a click.
    static let againLinger: Duration = .milliseconds(1200)

    // MARK: - Words

    static let key = "⌘V"
    static let dot = "·"

    static func label(english: Bool, again: Bool) -> String {
        switch (english, again) {
        case (false, false): "복사해 뒀어요"
        case (false, true): "다시 복사했어요"
        case (true, false): "Copied"
        case (true, true): "Copied again"
        }
    }

    static func tail(english: Bool) -> String { english ? "to paste" : "로 붙여 넣기" }

    // MARK: - Fonts

    static let headerFont = NSFont.systemFont(ofSize: headerFontSize, weight: .medium)
    static let keyFont = NSFont.systemFont(ofSize: keyFontSize, weight: .semibold)
    static let bodyFont = NSFont.systemFont(ofSize: bodyFontSize, weight: .medium)

    /// What the 1.45 line leaves over the text system's own line (17 at 14): between lines, half above and below.
    static let leading: CGFloat = max(0, lineHeight - NSLayoutManager().defaultLineHeight(for: bodyFont))

    // MARK: - Measuring

    private static func width(_ text: String, _ font: NSFont, kern: CGFloat = 0) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font, .kern: kern]).size().width.rounded(.up)
    }

    static func keyWidth() -> CGFloat { max(keyMinWidth, (width(key, keyFont) + 2 * keyPadding).rounded(.up)) }

    /// The header's own width: check, label, dot, key, tail (6 apart), then 6 and the ✕.
    static func headerWidth(english: Bool, again: Bool) -> CGFloat {
        let pieces = [checkSize, width(label(english: english, again: again), headerFont), width(dot, headerFont), keyWidth(),
                      width(tail(english: english), headerFont)]
        return (pieces.reduce(0, +) + gap * CGFloat(pieces.count - 1) + gap + closeSize).rounded(.up)
    }

    /// The words on one line.
    static func textWidth(_ text: String) -> CGFloat { width(text, bodyFont, kern: kerning).rounded(.up) + 1 }

    /// The content's width: its longest line (the header's or the words'), 220 to 340.
    static func contentWidth(_ text: String, english: Bool, again: Bool) -> CGFloat {
        min(maxContentWidth, max(minContentWidth, headerWidth(english: english, again: again), textWidth(text)))
    }

    /// Where the words break at `width`: at spaces (Hangul too, word by word), inside a word only when it is longer
    /// than the line.
    static func lines(_ text: String, width: CGFloat) -> [String] {
        guard !text.isEmpty else { return [] }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineBreakStrategy = .standard
        let storage = NSTextStorage(string: text, attributes: [.font: bodyFont, .kern: kerning, .paragraphStyle: style])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        var result: [String] = []
        var glyph = 0
        while glyph < layout.numberOfGlyphs {
            var range = NSRange()
            layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
            let characters = layout.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            result.append((text as NSString).substring(with: characters))
            glyph = NSMaxRange(range)
        }
        return result
    }

    /// The words' whole height, and what shows of it (at most 4 lines).
    static func textHeight(lines count: Int) -> CGFloat { CGFloat(max(1, count)) * lineHeight }
    static func visibleTextHeight(lines count: Int) -> CGFloat { textHeight(lines: min(count, maxLines)) }

    struct Fit: Equatable {
        var size: CGSize
        var contentWidth: CGFloat
        var lines: Int
        var scrolls: Bool { lines > ArisDictationPillRecoveredLayout.maxLines }
        var bodyHeight: CGFloat { ArisDictationPillRecoveredLayout.visibleTextHeight(lines: lines) + 2 * ArisDictationPillRecoveredLayout.bodyPadding }
    }

    static func fit(_ text: String, english: Bool, again: Bool) -> Fit {
        let content = contentWidth(text, english: english, again: again)
        let count = lines(text, width: content).count
        let body = visibleTextHeight(lines: count) + 2 * bodyPadding
        let size = CGSize(width: content + paddingLeading + paddingTrailing,
                          height: paddingTop + headerHeight + gap + body + paddingBottom)
        return Fit(size: size, contentWidth: content, lines: count)
    }

    static func size(_ text: String, english: Bool, again: Bool) -> CGSize { fit(text, english: english, again: again).size }

    /// The bottom fade: 16, or what is left to scroll when that is less; none at the end or when it all shows.
    static func fade(offset: CGFloat, visible: CGFloat, content: CGFloat) -> CGFloat {
        min(fadeMax, max(0, content - visible - offset))
    }
}
