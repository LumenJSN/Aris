//
//  ArisAnswerAttributed.swift
//  Aris
//
//  Aris's answer as one attributed string for a selectable NSTextView (the open notch now draws the user's pick A
//  instead, ArisAnswerDocumentView, and ArisFont below is shared), in the answer's markdown rhythm: 15-point
//  paragraphs on a 1.6 line at .95 with 11 points after (.75em) and
//  nothing outside the first and last block; list items on a 1.7 line at .85, 7.5 apart, hanging behind a marker
//  column of 1.4em (wider when a number needs it); strong at weight 650 and .95; headings 1.3 / 1.2 / 1.1em at
//  700 / 650 / 600; quotes behind a 2-point rule at .22 with text at .65. One string, so a selection runs across
//  paragraphs and list markers; `plainText` is what a copy gives. The blocks come from ArisAnswerMarkdown.
//

import AppKit

/// The system font at a CSS weight, set on SF's variation axis so 560 and 650 are real in-between weights (named
/// faces snap: 0.27 → Semibold 590, 0.35 → Bold 700). Hangul falls back to Apple SD Gothic Neo, whose discrete faces
/// still snap to the nearest of Medium, SemiBold and Bold.
enum ArisFont {
    private static let variation = NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
    /// 'wght'.
    private static let weightAxis = 0x7767_6874

    static func system(_ size: CGFloat, weight: CGFloat = 400, italic: Bool = false) -> NSFont {
        var descriptor = NSFont.systemFont(ofSize: size).fontDescriptor
        if weight != 400 { descriptor = descriptor.addingAttributes([variation: [weightAxis: weight]]) }
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    /// The weight a font was asked for on the variation axis (400 when none was set).
    static func weight(of font: NSFont?) -> CGFloat? {
        guard let font else { return nil }
        let axes = font.fontDescriptor.object(forKey: variation) as? [NSNumber: NSNumber]
        return CGFloat(axes?[NSNumber(value: weightAxis)]?.doubleValue ?? 400)
    }
}

enum ArisAnswerAttributed {
    static let size: CGFloat = 15
    /// After a paragraph: .75em.
    static let blockSpacing: CGFloat = 11
    /// Paragraphs and quotes: line height 1.6.
    static let paragraphLine: CGFloat = 24
    /// List items: line height 1.7, .5em apart.
    static let itemLine: CGFloat = 25.5
    static let itemSpacing: CGFloat = 7.5
    /// A list's indent, 1.4em: the marker column, unless a marker needs more.
    static let indent: CGFloat = 21
    /// Room between the widest marker and the item's text.
    static let markerGap: CGFloat = 6
    static let quoteRule: CGFloat = 2
    static let quoteGap: CGFloat = 10
    static var markerFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular) }
    /// Marks the tab after a list marker, which a copy turns into a space.
    static let markerTab = NSAttributedString.Key("ArisMarkerTab")

    static func string(from markdown: String) -> NSAttributedString {
        let paragraphs = ArisAnswerMarkdown.blocks(from: markdown).flatMap(paragraphs(for:))
        let out = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            let last = index == paragraphs.count - 1
            let text = NSMutableAttributedString(attributedString: paragraph.text)
            if !last {
                let attributes = text.length > 0 ? text.attributes(at: text.length - 1, effectiveRange: nil) : [:]
                text.append(NSAttributedString(string: "\n", attributes: attributes))
            }
            let style = paragraph.style.mutableCopy() as! NSMutableParagraphStyle
            if last { style.paragraphSpacing = 0 }
            text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
            out.append(text)
        }
        return out
    }

    /// What a copy gives: line breaks as newlines, a list marker and a space before each item.
    static func plainText(_ text: NSAttributedString) -> String {
        let plain = NSMutableString(string: text.string)
        text.enumerateAttribute(markerTab, in: NSRange(location: 0, length: text.length), options: .reverse) { value, range, _ in
            if value != nil { plain.replaceCharacters(in: range, with: " ") }
        }
        return (plain as String).replacingOccurrences(of: "\u{2028}", with: "\n")
    }

    /// 21 points, or the widest marker and a gap when a number is wider ("10." is about 22.6 at 15 points).
    static func markerColumn(for items: [ArisAnswerMarkdown.Item]) -> CGFloat {
        let widest = items.map { NSAttributedString(string: $0.marker, attributes: [.font: markerFont]).size().width }.max() ?? 0
        return max(indent, ceil(widest + markerGap))
    }

    private struct Paragraph {
        let text: NSAttributedString
        let style: NSParagraphStyle
    }

    private static func paragraphs(for block: ArisAnswerMarkdown.Block) -> [Paragraph] {
        switch block {
        case .paragraph(let words):
            let base = ArisFont.system(size)
            return [Paragraph(text: centred(inline(words, font: base, color: white(0.95)), line: paragraphLine, font: base),
                              style: style(line: paragraphLine, after: blockSpacing))]
        case .heading(let level, let words):
            let (scale, weight, opacity, height): (CGFloat, CGFloat, Double, CGFloat) =
                level == 1 ? (1.3, 700, 0.95, 1.35) : level == 2 ? (1.2, 650, 0.93, 1.35) : (1.1, 600, 0.9, 1.4)
            let font = ArisFont.system(size * scale, weight: weight)
            let line = (size * scale * height).rounded()
            return [Paragraph(text: centred(inline(words, font: font, color: white(opacity), weight: weight), line: line, font: font),
                              style: style(line: line, after: blockSpacing))]
        case .list(let items):
            let column = markerColumn(for: items)
            return items.enumerated().map { index, item in
                let base = ArisFont.system(size)
                let text = NSMutableAttributedString(string: item.marker, attributes: [.font: markerFont, .foregroundColor: white(0.85)])
                text.append(NSAttributedString(string: "\t", attributes: [.font: markerFont, .foregroundColor: white(0.85), markerTab: true]))
                text.append(inline(item.text, font: base, color: white(0.85)))
                return Paragraph(text: centred(text, line: itemLine, font: base),
                                 style: style(line: itemLine, after: index == items.count - 1 ? blockSpacing : itemSpacing, indent: column))
            }
        case .quote(let words):
            let base = ArisFont.system(size)
            let rule = NSTextBlock()
            rule.setWidth(quoteRule, type: .absoluteValueType, for: .border, edge: .minX)
            rule.setBorderColor(white(0.22), for: .minX)
            rule.setWidth(quoteGap, type: .absoluteValueType, for: .padding, edge: .minX)
            return [Paragraph(text: centred(inline(words, font: base, color: white(0.65)), line: paragraphLine, font: base),
                              style: style(line: paragraphLine, after: blockSpacing, block: rule))]
        case .code(let code):
            let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            let box = NSTextBlock()
            box.backgroundColor = white(0.06)
            for edge in [NSRectEdge.minX, .maxX, .minY, .maxY] { box.setWidth(10, type: .absoluteValueType, for: .padding, edge: edge) }
            let text = NSAttributedString(string: code.replacingOccurrences(of: "\n", with: "\u{2028}"),
                                          attributes: [.font: font, .foregroundColor: white(0.85)])
            return [Paragraph(text: text, style: style(line: 0, after: blockSpacing, block: box))]
        }
    }

    /// Bold, italics and code inline; strong at 650 (or the heading's own weight, if heavier) and .95. Links keep
    /// their words and lose their address: the words may come from web pages or mail.
    private static func inline(_ words: String, font: NSFont, color: NSColor, weight: CGFloat = 400) -> NSMutableAttributedString {
        let parsed = (try? AttributedString(markdown: words, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(words)
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var runFont = font
            var runColor = color
            if intent.contains(.code) {
                runFont = NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .regular)
            } else if intent.contains(.stronglyEmphasized) {
                runFont = ArisFont.system(font.pointSize, weight: max(650, weight), italic: intent.contains(.emphasized))
                runColor = white(0.95)
            } else if intent.contains(.emphasized) {
                runFont = ArisFont.system(font.pointSize, weight: weight, italic: true)
            }
            let piece = String(parsed[run.range].characters).replacingOccurrences(of: "\n", with: "\u{2028}")
            out.append(NSAttributedString(string: piece, attributes: [.font: runFont, .foregroundColor: runColor]))
        }
        return out
    }

    /// TextKit puts a tall line's extra height above the glyphs; lifting them by half of it splits it above and
    /// below, as CSS line-height does.
    private static func centred(_ text: NSAttributedString, line: CGFloat, font: NSFont) -> NSAttributedString {
        let natural = ceil(font.ascender - font.descender + font.leading)
        let out = NSMutableAttributedString(attributedString: text)
        out.addAttribute(.baselineOffset, value: max(0, (line - natural) / 2), range: NSRange(location: 0, length: out.length))
        return out
    }

    private static func style(line: CGFloat, after: CGFloat, indent: CGFloat = 0, block: NSTextBlock? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        if line > 0 {
            style.minimumLineHeight = line
            style.maximumLineHeight = line
        }
        style.paragraphSpacing = after
        if indent > 0 {
            style.headIndent = indent
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
            style.defaultTabInterval = indent
        }
        if let block { style.textBlocks = [block] }
        return style
    }

    private static func white(_ alpha: CGFloat) -> NSColor { NSColor(white: 1, alpha: alpha) }
}
