//
//  ArisNoticeCardView.swift
//  Aris
//
//  The cards as drawn, with the measured values (ArisNoticeLayout): a row of a 30-point tile and the text, padding 13,
//  gap 10; the buttons come up at the bottom right on hover (22-point capsules, the blue one last), the close circle
//  on the top-left corner. Collapsed, the front card alone is drawn in full and up to two layers peek under it; a
//  click opens the stack into a list of up to five with "+N" under it, and 접기 on the front card's buttons closes it.
//  Everything moves in 220 ms on (0.22, 1, 0.36, 1); with Reduce Motion it only fades. The glass card's colours follow
//  the system's appearance (ArisNoticePalette). Plain values in, callbacks
//  out: ArisNoticeCenter feeds it, the render harness draws it.
//

import AppKit
import SwiftUI

/// What the cards ask their owner to do.
struct ArisNoticeHandlers {
    var close: @MainActor (UUID) -> Void = { _ in }
    var act: @MainActor (UUID, ArisNoticeAction) -> Void = { _, _ in }
    var expand: @MainActor () -> Void = {}
    var collapse: @MainActor () -> Void = {}
    var hover: @MainActor (UUID?) -> Void = { _ in }
}

/// The whole stack, in the window's coordinates (the cards' space starts 14 in and 14 down).
struct ArisNoticeStackView: View {
    let queue: ArisNoticeQueue
    let hovered: UUID?
    let material: ArisNoticeMaterial
    let english: Bool
    /// The cards step aside (the notch is open, the setup shows): faded out, kept as they are.
    var aside = false
    var handlers = ArisNoticeHandlers()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var heights: [CGFloat] { queue.shown.map(ArisNoticeLayout.height) }
    private var stack: ArisNoticeStack { ArisNoticeLayout.stack(heights, expanded: queue.expanded) }

    static func motion(reduce: Bool) -> Animation {
        let c = ArisNoticeLayout.motionCurve
        return reduce ? .linear(duration: ArisNoticeLayout.motion) : .timingCurve(c.0, c.1, c.2, c.3, duration: ArisNoticeLayout.motion)
    }

    var body: some View {
        let layout = stack
        let palette = ArisNoticePalette.of(material, scheme)
        ZStack(alignment: .topLeading) {
            ForEach(Array(queue.shown.enumerated()), id: \.element.id) { index, notice in
                placed(notice, index: index, stack: layout)
            }
            if let more = layout.moreRow {
                Text(verbatim: ArisNoticeWords.more(layout.hidden, english: english))
                    .font(.system(size: 11, weight: .semibold)).tracking(-0.11)
                    .foregroundStyle(palette.moreText)
                    .padding(.horizontal, 12).frame(height: 22)
                    .background(Capsule().fill(palette.moreFill))
                    .overlay(Capsule().strokeBorder(palette.moreRim, lineWidth: 0.5))
                    .frame(width: more.width, height: more.height)
                    .offset(x: more.minX, y: more.minY)
                    .transition(.opacity)
            }
        }
        .frame(width: ArisNoticeLayout.width, height: max(layout.height, 1), alignment: .topLeading)
        .padding(.leading, ArisNoticeLayout.closeOverhang).padding(.top, ArisNoticeLayout.closeOverhang)
        .frame(width: ArisNoticeLayout.windowSize.width, height: ArisNoticeLayout.windowSize.height, alignment: .topLeading)
        .opacity(aside ? 0 : 1)
        .animation(Self.motion(reduce: reduceMotion), value: queue)
        .animation(.easeOut(duration: ArisNoticeLayout.fadeIn), value: aside)
    }

    /// One card where its index puts it: the front card (or every card of the open list) in full, the next two as
    /// layers (their bottom band only), the rest hidden behind the last layer.
    @ViewBuilder
    private func placed(_ notice: ArisNotice, index: Int, stack: ArisNoticeStack) -> some View {
        let full = index < stack.cards.count
        let depth = min(index, ArisNoticeLayout.stackMaxLayers)
        let front = stack.cards.first?.height ?? ArisNoticeLayout.compactHeight
        let frame: CGRect = full ? stack.cards[index]
            : CGRect(x: CGFloat(depth) * ArisNoticeLayout.stackInset, y: CGFloat(depth) * ArisNoticeLayout.stackOffset,
                     width: ArisNoticeLayout.width - 2 * CGFloat(depth) * ArisNoticeLayout.stackInset, height: front)
        let showsCard = full
        let visible = full || index <= ArisNoticeLayout.stackMaxLayers
        ArisNoticeCard(notice: notice, material: material, english: english,
                       hovered: hovered == notice.id && showsCard,
                       stacked: index == 0 && !queue.expanded && queue.shown.count > 1,
                       showLess: index == 0 && queue.expanded,
                       contentShown: showsCard, handlers: handlers,
                       tap: { if !queue.expanded && queue.shown.count > 1 { handlers.expand() } })
            .frame(width: frame.width, height: frame.height)
            // A layer shows only its last 9 points, under the card above it.
            .mask(ArisNoticeBandMask(hiddenTop: showsCard ? -ArisNoticeLayout.closeSize : frame.height - ArisNoticeLayout.stackOffset))
            .offset(x: frame.minX, y: frame.minY)
            // Reduce Motion: the cards take their places at once and only fade.
            .animation(reduceMotion ? nil : Self.motion(reduce: false), value: frame)
            .opacity(visible ? 1 : 0)
            .zIndex(Double(100 - index))
            .allowsHitTesting(showsCard || index <= ArisNoticeLayout.stackMaxLayers)
            .transition(reduceMotion ? .opacity
                        : .asymmetric(insertion: .opacity.combined(with: .offset(y: -10)).combined(with: .scale(scale: 0.97, anchor: .top)),
                                      removal: .opacity.combined(with: .offset(y: -8)).combined(with: .scale(scale: 0.97, anchor: .top))))
    }
}

/// What is left visible of a card: everything below `hiddenTop` (the close circle's room above the card included).
struct ArisNoticeBandMask: Shape {
    var hiddenTop: CGFloat

    var animatableData: CGFloat {
        get { hiddenTop }
        set { hiddenTop = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let out = ArisNoticeLayout.closeSize
        return Path(CGRect(x: rect.minX - out, y: rect.minY + hiddenTop, width: rect.width + 2 * out, height: rect.height - hiddenTop + out))
    }
}

/// One card.
struct ArisNoticeCard: View {
    let notice: ArisNotice
    let material: ArisNoticeMaterial
    let english: Bool
    let hovered: Bool
    /// Layers peek under it.
    let stacked: Bool
    /// It is the front card of the open list: 접기 joins its buttons.
    let showLess: Bool
    /// False for a peeking layer: the surface only.
    let contentShown: Bool
    let handlers: ArisNoticeHandlers
    let tap: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private typealias L = ArisNoticeLayout

    /// The glass card follows the system's appearance; the opaque one is always dark (ArisNoticePalette).
    private var palette: ArisNoticePalette { ArisNoticePalette.of(material, scheme) }
    private var buttonsShown: Bool { hovered && contentShown && (!notice.actions.isEmpty || showLess) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ArisNoticeSurface(material: material, stacked: stacked, layer: !contentShown)
            if contentShown {
                content
                highlight
                buttons
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: L.cornerRadius, style: .continuous))
        .onTapGesture { tap() }
        .overlay(alignment: .topLeading) {
            if contentShown {
                ArisNoticeCloseButton(shown: hovered, label: ArisNoticeWords.close(english: english), palette: palette) { handlers.close(notice.id) }
                    .offset(x: -L.closeOut, y: -L.closeOut)
            }
        }
        .onHover { inside in
            guard contentShown else { return }
            handlers.hover(inside ? notice.id : nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: notice.title + ". " + notice.body))
    }

    private var content: some View {
        HStack(alignment: .center, spacing: L.gap) {
            ArisNoticeTileView(kind: notice.kind)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: notice.title)
                    .font(.system(size: L.titleSize, weight: .semibold)).tracking(L.titleTracking)
                    .foregroundStyle(palette.title)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(height: L.titleLine)
                if notice.kind == .incoming {
                    if let subtitle = notice.subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle)
                            .font(.system(size: L.subtitleSize, weight: .medium))
                            .foregroundStyle(palette.subtitle)
                            .lineLimit(1).truncationMode(.tail)
                            .frame(height: L.subtitleLine)
                            .padding(.top, L.subtitleTop)
                    }
                    if !notice.body.isEmpty {
                        lines(notice.body, size: L.snippetSize, lineHeight: L.snippetLine, color: palette.snippet, limit: 2)
                    }
                } else if !notice.body.isEmpty {
                    lines(notice.body, size: L.bodySize, lineHeight: L.bodyLine, color: palette.body, limit: L.bodyLines(notice.body))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(L.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Wrapped text at a set line height (the system font's own, plus the difference as line spacing).
    private func lines(_ text: String, size: CGFloat, lineHeight: CGFloat, color: Color, limit: Int) -> some View {
        let font = NSFont.systemFont(ofSize: size)
        let natural = font.ascender - font.descender + font.leading
        let spacing = max(0, lineHeight - natural)
        return Text(verbatim: text)
            .font(.system(size: size))
            .lineSpacing(spacing)
            .foregroundStyle(color)
            .lineLimit(limit).truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, L.bodyTop + spacing / 2)
    }

    /// A light line along the top, 15 % in from each side.
    private var highlight: some View {
        LinearGradient(colors: [.clear, ArisNoticeLook.highlight, .clear], startPoint: .leading, endPoint: .trailing)
            .frame(height: 1)
            .padding(.horizontal, L.width * 0.15)
            .frame(maxWidth: .infinity, alignment: .top)
            .allowsHitTesting(false)
    }

    private var buttons: some View {
        HStack(spacing: L.buttonGap) {
            if showLess {
                ArisNoticeButton(title: ArisNoticeWords.showLess(english: english), primary: false, palette: palette) { handlers.collapse() }
            }
            ForEach(Array(notice.orderedActions.enumerated()), id: \.offset) { _, action in
                ArisNoticeButton(title: action.title, primary: action.primary, palette: palette) { handlers.act(notice.id, action) }
            }
        }
        .background {
            // Over the opaque card, a dark blur behind the buttons keeps the text under them from showing through.
            if material == .opaque {
                Capsule().fill(Color(.sRGB, red: 20.0 / 255, green: 20.0 / 255, blue: 24.0 / 255, opacity: 0.9))
                    .padding(.horizontal, -12).padding(.vertical, -9).blur(radius: 10)
            }
        }
        .padding(.bottom, L.buttonsBottom).padding(.trailing, L.buttonsRight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .opacity(buttonsShown ? 1 : 0)
        .offset(y: buttonsShown || reduceMotion ? 0 : L.revealRise)
        .allowsHitTesting(buttonsShown)
        .animation(.easeOut(duration: L.reveal), value: buttonsShown)
    }
}

/// The kind's tile: a 30-point squircle in its gradient, a sheen from the top, a faint rim, the white glyph.
struct ArisNoticeTileView: View {
    let kind: ArisNoticeKind
    var size: CGFloat = ArisNoticeLayout.tileSize

    private func color(_ hex: UInt32) -> Color {
        let c = ArisNoticeTile.components(hex)
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }

    var body: some View {
        let tile = kind.tile
        let shape = ArisNoticeSquircle()
        ZStack {
            shape.fill(LinearGradient(stops: [.init(color: color(tile.top), location: 0), .init(color: color(tile.mid), location: 0.55),
                                              .init(color: color(tile.deep), location: 1)], startPoint: .top, endPoint: .bottom))
            shape.fill(RadialGradient(stops: [.init(color: .white.opacity(0.26), location: 0), .init(color: .white.opacity(0), location: 0.6)],
                                      center: .top, startRadius: 0, endRadius: size))
            Image(systemName: kind.glyph)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            shape.stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
        .accessibilityHidden(true)
    }
}

/// A superellipse (|x|⁵ + |y|⁵ = 1) in the rect: rounder than a rounded rectangle, with no flat-to-curve kink.
struct ArisNoticeSquircle: Shape {
    var exponent: Double = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 96
        for step in 0...steps {
            let t = Double(step) / Double(steps) * 2 * .pi
            let c = cos(t), s = sin(t)
            let x = (c < 0 ? -1 : 1) * pow(abs(c), 2 / exponent)
            let y = (s < 0 ? -1 : 1) * pow(abs(s), 2 / exponent)
            let point = CGPoint(x: rect.midX + CGFloat(x) * rect.width / 2, y: rect.midY + CGFloat(y) * rect.height / 2)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// A 22-point capsule, 11-point semibold: the blue one or a grey one; brighter on hover, 0.97 when pressed.
struct ArisNoticeButton: View {
    let title: String
    let primary: Bool
    let palette: ArisNoticePalette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) { Text(verbatim: title) }
            .buttonStyle(ArisNoticeButtonStyle(primary: primary, hovering: hovering, palette: palette))
            .onHover { hovering = $0 }
    }
}

struct ArisNoticeButtonStyle: ButtonStyle {
    let primary: Bool
    let hovering: Bool
    /// The grey one's colours (the blue one is the same in every appearance).
    let palette: ArisNoticePalette
    private typealias L = ArisNoticeLayout

    func makeBody(configuration: Configuration) -> some View {
        let blue = ArisNoticeTile.components(L.primaryColor)
        return configuration.label
            .font(.system(size: L.buttonTextSize, weight: .semibold)).tracking(-0.11)
            .foregroundStyle(primary ? Color.white : palette.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, L.buttonPadding)
            .frame(minWidth: L.buttonMinWidth, minHeight: L.buttonHeight, maxHeight: L.buttonHeight)
            .background(Capsule().fill(primary ? Color(.sRGB, red: blue.red, green: blue.green, blue: blue.blue, opacity: 1) : palette.secondaryFill))
            .overlay {
                if primary {
                    Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2)), lineWidth: 1)
                } else {
                    Capsule().strokeBorder(palette.secondaryRing, lineWidth: 0.5)
                }
            }
            .brightness(configuration.isPressed ? L.pressBrightness : hovering ? L.hoverBrightness : 0)
            .scaleEffect(configuration.isPressed ? L.pressScale : 1)
            .animation(.easeOut(duration: L.press), value: configuration.isPressed)
            .animation(.easeOut(duration: L.press), value: hovering)
            .contentShape(Capsule())
    }
}

/// The 24-point close circle on the card's top-left corner: shown on hover, a hairline ring, an ✕.
struct ArisNoticeCloseButton: View {
    let shown: Bool
    let label: String
    let palette: ArisNoticePalette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(hovering ? palette.closeHover : palette.closeFill)
                Circle().strokeBorder(palette.closeRing, lineWidth: 0.5)
                ArisNoticeCross()
                    .stroke(palette.closeGlyph, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 6, height: 6)
            }
            .frame(width: ArisNoticeLayout.closeSize, height: ArisNoticeLayout.closeSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : ArisNoticeLayout.closeHiddenScale)
        .allowsHitTesting(shown)
        .animation(.easeOut(duration: ArisNoticeLayout.reveal), value: shown)
        .accessibilityLabel(Text(verbatim: label))
    }
}

/// An ✕ from corner to corner of its rect.
struct ArisNoticeCross: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
