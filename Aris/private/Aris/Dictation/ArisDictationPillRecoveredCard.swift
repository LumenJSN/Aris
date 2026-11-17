//
//  ArisDictationPillRecoveredCard.swift
//  Aris
//
//  The recovered words' card (nowhere took them; they are on the clipboard), drawn to ArisDictationPillRecoveredLayout:
//  it stands where the pill stands, grows out of an 80 × 30 pill to the size that fits its words, and leaves with a
//  fade and a small shrink (ArisDictationPillView's transition). The header says the words are copied and how to paste
//  them; the words are the copy target. Its colours follow the system's appearance (the pill itself is always dark).
//

import AppKit
import SwiftUI

/// Offscreen renders: a part drawn hovered.
enum ArisDictationPillRecoveredHover { case body, close }

private typealias L = ArisDictationPillRecoveredLayout

/// The card's colours, dark and light.
struct ArisDictationPillRecoveredTokens {
    let fill: Color
    let line: Color
    let text: Color
    let secondary: Color
    let tertiary: Color
    let hover: Color
    let hoverStrong: Color
    let shadow: Color

    static let dark = ArisDictationPillRecoveredTokens(
        fill: Color(.sRGB, red: 20 / 255, green: 20 / 255, blue: 24 / 255, opacity: 0.86), line: .white.opacity(0.12),
        text: .white.opacity(0.94), secondary: .white.opacity(0.56), tertiary: .white.opacity(0.38),
        hover: .white.opacity(0.08), hoverStrong: .white.opacity(0.14), shadow: .black.opacity(0.38))
    static let light = ArisDictationPillRecoveredTokens(
        fill: Color(.sRGB, red: 250 / 255, green: 250 / 255, blue: 252 / 255, opacity: 0.84), line: .black.opacity(0.08),
        text: .black.opacity(0.88), secondary: .black.opacity(0.52), tertiary: .black.opacity(0.36),
        hover: .black.opacity(0.05), hoverStrong: .black.opacity(0.09), shadow: .black.opacity(0.16))
}

struct ArisDictationPillRecoveredCard: View {
    let text: String
    let english: Bool
    /// The words were just copied again: the label says so.
    let again: Bool
    let light: Bool
    var blending: NSVisualEffectView.BlendingMode? = .behindWindow
    let copy: () -> Void
    let close: () -> Void
    var hover: ArisDictationPillRecoveredHover?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown: Bool
    @State private var contentShown: Bool

    /// `still`: drawn already open (offscreen renders).
    init(text: String, english: Bool, again: Bool, light: Bool, blending: NSVisualEffectView.BlendingMode? = .behindWindow,
         copy: @escaping () -> Void, close: @escaping () -> Void, hover: ArisDictationPillRecoveredHover? = nil, still: Bool = false) {
        self.text = text
        self.english = english
        self.again = again
        self.light = light
        self.blending = blending
        self.copy = copy
        self.close = close
        self.hover = hover
        _grown = State(initialValue: still)
        _contentShown = State(initialValue: still)
    }

    private var tokens: ArisDictationPillRecoveredTokens { light ? .light : .dark }
    private var fit: L.Fit { L.fit(text, english: english, again: again) }
    private var growCurve: Animation {
        let c = L.growCurve
        return .timingCurve(c.0, c.1, c.2, c.3, duration: L.growDuration)
    }

    var body: some View {
        let fit = fit
        let size = grown ? fit.size : L.startSize
        let shape = RoundedRectangle(cornerRadius: grown ? L.radius : L.startRadius, style: .continuous)
        content(fit)
            .frame(width: fit.size.width, height: fit.size.height, alignment: .topLeading)
            .opacity(contentShown ? 1 : 0)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(shape)
            // 0 12 32 shadow under the glass (after the clip, so the clip doesn't cut it).
            .background {
                ZStack {
                    if let blending { ArisDictationPillRecoveredBlur(light: light, blending: blending) }
                    tokens.fill
                }
                .clipShape(shape)
                .shadow(color: tokens.shadow, radius: 16, y: 12)
            }
            .overlay { shape.strokeBorder(tokens.line, lineWidth: 0.5).allowsHitTesting(false) }
            .contentShape(shape)
            .animation(reduceMotion ? nil : growCurve, value: fit.size)
            .onAppear(perform: open)
    }

    private func open() {
        guard !grown else { return }
        if reduceMotion {
            grown = true
            withAnimation(.easeOut(duration: L.contentFade)) { contentShown = true }
            return
        }
        withAnimation(growCurve) { grown = true }
        withAnimation(.easeOut(duration: L.contentFade).delay(L.contentDelay)) { contentShown = true }
    }

    private func content(_ fit: L.Fit) -> some View {
        VStack(alignment: .leading, spacing: L.gap) {
            header
                .frame(width: fit.contentWidth, height: L.headerHeight)
            ArisDictationPillRecoveredWords(text: text, fit: fit, tokens: tokens, copy: copy, hoverPreset: hover.map { $0 == .body },
                                            label: english ? "Copy again" : "다시 복사")
                .padding(.horizontal, -L.bodyOutset)
        }
        .padding(EdgeInsets(top: L.paddingTop, leading: L.paddingLeading, bottom: L.paddingBottom, trailing: L.paddingTrailing))
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: L.gap) {
                ArisDictationPillRecoveredGlyphs.check.frame(width: L.checkSize, height: L.checkSize)
                Text(L.label(english: english, again: again))
                Text(L.dot)
                ArisDictationPillKeycap(tokens: tokens)
                Text(L.tail(english: english))
            }
            .fixedSize()
            Spacer(minLength: L.gap)
            ArisDictationPillRecoveredClose(tokens: tokens, label: ArisDictationPillWords.close(english), action: close,
                                            hoverPreset: hover.map { $0 == .close })
        }
        .font(Font(L.headerFont))
        .foregroundStyle(tokens.secondary)
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - The words

/// The words: a click copies them again; hover lights them (radius 8, 6 past them either side). Past 4 lines they
/// scroll, the bottom fading 16 while there is more.
private struct ArisDictationPillRecoveredWords: View {
    let text: String
    let fit: L.Fit
    let tokens: ArisDictationPillRecoveredTokens
    let copy: () -> Void
    var hoverPreset: Bool?
    let label: String

    @State private var hoveredLive = false
    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    private var hovered: Bool { hoverPreset ?? hoveredLive }
    private static let space = "ArisDictationPillRecoveredWords"

    var body: some View {
        let half = L.leading / 2
        let shape = RoundedRectangle(cornerRadius: L.bodyRadius, style: .continuous)
        ScrollView(.vertical) {
            Text(text)
                .font(Font(L.bodyFont))
                .kerning(L.kerning)
                .lineSpacing(L.leading)
                .foregroundStyle(tokens.text)
                .frame(width: fit.contentWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, L.bodyPadding + half)
                .padding(.horizontal, L.bodyOutset)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
                    contentHeight = frame.height
                    // macOS 14 has no scroll geometry: the content's place in the scroller is the offset.
                    if #unavailable(macOS 15.0) { offset = -frame.minY }
                }
        }
        .coordinateSpace(.named(Self.space))
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(!fit.scrolls)
        .modifier(OffsetReader { offset = $0 })
        .frame(width: fit.contentWidth + 2 * L.bodyOutset, height: fit.bodyHeight)
        .mask { fadeMask }
        .background { shape.fill(hovered ? tokens.hover : .clear) }
        .contentShape(shape)
        .onTapGesture(perform: copy)
        .onHover { hoveredLive = $0 }
        .animation(.easeOut(duration: L.hoverDuration), value: hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(label)
    }

    /// Opaque down to `fade` from the bottom, then clear; none once the end shows. Swapped at once.
    private var fadeMask: some View {
        let fade = L.fade(offset: offset, visible: fit.bodyHeight, content: contentHeight)
        return LinearGradient(stops: [.init(color: .black, location: 0),
                                      .init(color: .black, location: 1 - fade / max(fit.bodyHeight, 1)),
                                      .init(color: fade > 0 ? .clear : .black, location: 1)],
                              startPoint: .top, endPoint: .bottom)
            .transaction { $0.animation = nil }
    }
}

/// The scroller's offset on every scroll, where the system reports it (macOS 15 and later).
private struct OffsetReader: ViewModifier {
    let action: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                action(offset)
            }
        } else {
            content
        }
    }
}

// MARK: - Pieces

/// ⌘V as a key: at least 22 × 18, 0 4, radius 5, 11 / 600, a faint fill in a hairline with a 1 px line under it.
struct ArisDictationPillKeycap: View {
    let tokens: ArisDictationPillRecoveredTokens

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: L.keyRadius, style: .continuous)
        Text(L.key)
            .font(Font(L.keyFont))
            .foregroundStyle(tokens.secondary)
            .padding(.horizontal, L.keyPadding)
            .frame(minWidth: L.keyMinWidth, minHeight: L.keyHeight, maxHeight: L.keyHeight)
            .background {
                ZStack {
                    ArisDictationPillKeyUnderline(radius: L.keyRadius).fill(tokens.line)
                    shape.fill(tokens.hover)
                }
            }
            .overlay { shape.strokeBorder(tokens.line, lineWidth: 0.5) }
            .fixedSize()
    }
}

/// CSS `0 1px 0`: the key's outline moved down 1, less the key, so the line shows only below it.
private struct ArisDictationPillKeyUnderline: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let key = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        return key.offsetBy(dx: 0, dy: 1).subtracting(key)
    }
}

/// The thin ✕: a 22 circle, nothing behind it; on hover the stronger tint and the full text colour.
struct ArisDictationPillRecoveredClose: View {
    let tokens: ArisDictationPillRecoveredTokens
    let label: String
    let action: () -> Void
    var hoverPreset: Bool?

    @State private var hoveredLive = false
    private var hovered: Bool { hoverPreset ?? hoveredLive }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(hovered ? tokens.hoverStrong : .clear)
                ArisDictationPillRecoveredGlyphs.cross
                    .frame(width: L.closeGlyph, height: L.closeGlyph)
                    .foregroundStyle(hovered ? tokens.text : tokens.tertiary)
            }
            .frame(width: L.closeSize, height: L.closeSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .onHover { hoveredLive = $0 }
        .animation(.easeOut(duration: L.hoverDuration), value: hovered)
    }
}

/// The card's icons, in the label's colour.
enum ArisDictationPillRecoveredGlyphs {
    /// M1.5 1.5 L8.5 8.5 M8.5 1.5 L1.5 8.5 in 10, stroke 1.4 round.
    static var cross: some View {
        Canvas { canvas, size in
            let s = size.width / 10
            var path = Path()
            path.move(to: CGPoint(x: 1.5 * s, y: 1.5 * s)); path.addLine(to: CGPoint(x: 8.5 * s, y: 8.5 * s))
            path.move(to: CGPoint(x: 8.5 * s, y: 1.5 * s)); path.addLine(to: CGPoint(x: 1.5 * s, y: 8.5 * s))
            canvas.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round))
        }
    }

    /// M2.2 6.3 l2.4 2.4 5.2 −5.4 in 12, stroke 1.5 round.
    static var check: some View {
        Canvas { canvas, size in
            let s = size.width / 12
            var path = Path()
            path.move(to: CGPoint(x: 2.2 * s, y: 6.3 * s)); path.addLine(to: CGPoint(x: 4.6 * s, y: 8.7 * s))
            path.addLine(to: CGPoint(x: 9.8 * s, y: 3.3 * s))
            canvas.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round, lineJoin: .round))
        }
    }
}

/// The blur behind the card, in the card's appearance (the pill's window is dark-only).
private struct ArisDictationPillRecoveredBlur: NSViewRepresentable {
    let light: Bool
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        update(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { update(view) }

    private func update(_ view: NSVisualEffectView) {
        ArisBlur.configure(view, material: .hudWindow, blending: blending)
        view.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
    }
}
