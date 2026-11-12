//
//  ArisShotChip.swift
//  Aris
//
//  The `[img N]` markers in the user's words, as the owner's mockup B draws them (`mockups/gesture-ink.html`
//  `.chip`/`.pv`): a small pill with the circled window's thumbnail and its number, and on hover a larger preview.
//  The thumbnails are the PNG thumbs (no number on them) held in memory for this turn only. Markers sit at sentence
//  ends (ArisGestureMarkers.movedToSentenceEnds); the words wrap around the chips.
//

import AppKit
import SwiftUI

/// The prompt's words with chips in place of the markers, wrapping like text.
struct ArisMarkedPrompt: View {
    let text: String
    let thumbs: [Int: NSImage]
    @Binding var hovered: Int?

    var body: some View {
        ArisWordFlow(spacing: Self.wordGap, lineSpacing: ArisPromptCollapse.lineSpacing) {
            ForEach(Array(ArisGestureTurn.tokens(text).enumerated()), id: \.offset) { _, token in
                switch token {
                case .word(let word):
                    Text(word)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.9))
                case .chip(let badge):
                    ArisShotChip(badge: badge, thumb: thumbs[badge], hovered: hovered == badge)
                        .onHover { inside in
                            if inside { hovered = badge } else if hovered == badge { hovered = nil }
                        }
                        .anchorPreference(key: ArisShotAnchors.self, value: .bounds) { [badge: $0] }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ArisGestureTurn.spoken(text))
    }

    /// A space at 15 pt.
    static let wordGap: CGFloat = 4
}

/// `.chip`: 18 pt pill, padding 0 8 0 4, `rgba(255,255,255,.06)` (.10 hovered), 11 pt / 560 at .56, a 16×12 thumbnail
/// with a 0.5 pt ring, or an image glyph while there is none.
struct ArisShotChip: View {
    let badge: Int
    let thumb: NSImage?
    let hovered: Bool

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if let thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 16, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 0.5))
                } else {
                    Image(systemName: "photo").font(.system(size: 10, weight: .semibold))
                }
            }
            Text("\(badge)").font(.system(size: 11, weight: .medium)).monospacedDigit() // CSS 560
        }
        .foregroundStyle(.white.opacity(0.56))
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: 18)
        .background(Capsule().fill(.white.opacity(hovered ? 0.10 : 0.06)))
        // emil-design-eng: a hover is a colour change → ease, quick (the mockup's 140 ms).
        .animation(.easeOut(duration: 0.14), value: hovered)
    }
}

/// Where each chip is, by badge, for the preview drawn above the pill's clip.
struct ArisShotAnchors: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// `.pv`: the hovered chip's thumbnail, up to 360×300, radius 11, `#101014`, soft shadows and a faint ink-blue
/// glow, 7 pt from the chip. It opens below the chip (the prompt sits at the top of the notch, so there's no room
/// above) and is fitted into the room left below the chip inside the turn (`ArisShotPreviewFit`), so the notch's clip
/// never cuts it; with too little room there is none. Fades in over 340 ms and out over 260 ms, sliding 5 pt down
/// from above (it opens downwards).
struct ArisShotPreviewLayer: View {
    let anchors: [Int: Anchor<CGRect>]
    let hovered: Int?
    let thumbs: [Int: NSImage]

    /// The turn's coordinate space (ArisTurnView), where the room below a chip is measured.
    static let space = "arisTurn"
    private static let gap: CGFloat = 7
    private static let margin: CGFloat = 6

    @Environment(\.arisTurnHeight) private var turnHeight

    var body: some View {
        GeometryReader { proxy in
            let pillTop = proxy.frame(in: .named(Self.space)).minY
            ZStack(alignment: .topLeading) {
                ForEach(Array(anchors.keys.sorted()), id: \.self) { badge in
                    let chip = anchors[badge].map { proxy[$0] } ?? .zero
                    let room = turnHeight - (pillTop + chip.maxY) - Self.gap - Self.margin
                    if let thumb = thumbs[badge], anchors[badge] != nil,
                       let size = ArisShotPreviewFit.size(image: thumb.size, room: room) {
                        let x = min(max(chip.midX - size.width / 2, 0), max(0, proxy.size.width - size.width))
                        let shown = hovered == badge
                        ArisShotPreview(image: thumb, size: size)
                            .offset(x: x, y: chip.maxY + Self.gap + (shown ? 0 : -5))
                            .opacity(shown ? 1 : 0)
                            // emil-design-eng: enter slower than exit; the mockup's 340 ms in, 260 ms out (ease).
                            .animation(.easeInOut(duration: shown ? 0.34 : 0.26), value: shown)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ArisTurnHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// The turn view's height (ArisTurnView), for the chip preview's room.
    var arisTurnHeight: CGFloat {
        get { self[ArisTurnHeightKey.self] }
        set { self[ArisTurnHeightKey.self] = newValue }
    }
}

private struct ArisShotPreview: View {
    let image: NSImage
    let size: CGSize

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .background(Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x14 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 18, y: 12)
            // hsla(214,100%,60%,.18)
            .shadow(color: Color(red: 0.2, green: 0.5467, blue: 1).opacity(0.18), radius: 9)
    }
}

/// Words and chips left to right, wrapping between them; each line's items sit on its centre line.
struct ArisWordFlow: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in line.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = line.items.isEmpty ? size.width : line.width + spacing + size.width
            if !line.items.isEmpty, needed > width {
                lines.append(line)
                line = Line()
            }
            line.width = line.items.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.items.append(index)
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}
