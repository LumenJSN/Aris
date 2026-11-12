//
//  ArisMarquee.swift
//  Aris
//
//  One line of text in a fixed width. Text that fits sits still at the leading edge; text that doesn't waits
//  `delayDuration`, then scrolls left at 30 pt/s forever, followed by a copy of itself 20 pt behind so the loop has
//  no seam. A new text starts over. The line is as tall as `nsFont`'s bounding box (rounded up), and the view takes the width
//  it is offered, drawing at its leading edge.
//

import AppKit
import SwiftUI

struct MarqueeText: View {
    static let speed: CGFloat = 30
    static let gap: CGFloat = 20

    let text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let color: Color
    let delayDuration: Double
    let frameWidth: CGFloat

    init(_ text: String, font: Font = .body, nsFont: NSFont.TextStyle = .body, color: Color = .primary,
         delayDuration: Double = 3.0, frameWidth: CGFloat) {
        self.text = text
        self.font = font
        self.nsFont = nsFont
        self.color = color
        self.delayDuration = delayDuration
        self.frameWidth = frameWidth
    }

    static func lineHeight(_ style: NSFont.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: style).boundingRectForFont.height.rounded(.up)
    }

    var body: some View {
        ArisMarqueeLine(text: text, font: font, color: color, delay: delayDuration, width: frameWidth)
            .id(text)
            .frame(height: Self.lineHeight(nsFont), alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ArisMarqueeLine: View {
    let text: String
    let font: Font
    let color: Color
    let delay: Double
    let width: CGFloat

    @State private var textWidth: CGFloat = 0
    @State private var shift: CGFloat = 0

    private var scrolls: Bool { textWidth > width }

    var body: some View {
        HStack(spacing: MarqueeText.gap) {
            label
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            if scrolls { label }
        }
        .offset(x: -shift)
        .frame(width: width, alignment: .leading)
        .clipped()
        .onChange(of: scrolls, initial: true) { _, scrolls in
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { shift = 0 }
            guard scrolls else { return }
            let distance = textWidth + MarqueeText.gap
            withAnimation(.linear(duration: distance / MarqueeText.speed).delay(delay).repeatForever(autoreverses: false)) {
                shift = distance
            }
        }
    }

    private var label: some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
    }
}
