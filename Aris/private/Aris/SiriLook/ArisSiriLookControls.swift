//
//  ArisSiriLookControls.swift
//  Aris
//
//  The siri look's pieces, each drawn from ArisSiriLook's measured numbers: the control glass (the grey that is
//  lighter than black and darker than light, with a rim lit at its top and bottom), the round buttons, your words
//  as a small bubble with a tail, and the ring of six dots that turns and swells while Aris works. Aris's own
//  SwiftUI; SF Symbols and the system font only. Nothing here knows about the rest of Aris, so the off-screen
//  renders draw these same views.
//

import SwiftUI

/// The glass the round buttons and the field are made of.
struct ArisSiriLookGlass<S: InsettableShape>: View {
    let shape: S
    /// Under the pointer or pressed: a little more light.
    var lift: Double = 0

    private typealias Spec = ArisSiriLook.Control

    var body: some View {
        let tint = ArisSiriLook.Field.rimTint
        let lit = Color(.sRGB, red: tint.red, green: tint.green, blue: tint.blue, opacity: Spec.rimLit)
        ZStack {
            shape.fill(Color(.sRGB, white: Spec.grey, opacity: Spec.alpha))
            shape.fill(.white.opacity(lift))
            // Lit at the top and bottom edges, a darker line at the sides, as Siri's glass shows over black.
            shape.strokeBorder(LinearGradient(stops: [
                .init(color: lit, location: 0),
                .init(color: lit.opacity(0.15), location: 0.28),
                .init(color: .black.opacity(Spec.rimDark), location: 0.5),
                .init(color: lit.opacity(0.15), location: 0.72),
                .init(color: lit, location: 1),
            ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }
}

/// A round glass button: Siri's ✕, expand, + and microphone. 36 across in the content, 28 in Aris's top band.
struct ArisSiriLookRoundButton<Mark: View>: View {
    var size = CGFloat(ArisSiriLook.Control.size)
    var help = ""
    let action: () -> Void
    @ViewBuilder var mark: () -> Mark

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            mark()
                .foregroundStyle(.white.opacity(ArisSiriLook.Control.glyphInk))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(ArisSiriLookPress(hovering: hovering))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .help(help)
    }
}

extension ArisSiriLookRoundButton where Mark == AnyView {
    /// With an SF Symbol sized as Siri's glyphs are (11 of 36).
    init(symbol: String, size: CGFloat = CGFloat(ArisSiriLook.Control.size), help: String = "", action: @escaping () -> Void) {
        // An SF Symbol's ✕ is about .82 of its point size across: 13.5 points draws Siri's 11.
        let glyph = size * CGFloat(ArisSiriLook.Control.glyph / ArisSiriLook.Control.size) / 0.82
        self.init(size: size, help: help, action: action) {
            AnyView(Image(systemName: symbol).font(.system(size: glyph, weight: .medium)))
        }
    }
}

private struct ArisSiriLookPress: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(ArisSiriLookGlass(shape: Circle(), lift: configuration.isPressed ? 0.14 : hovering ? 0.07 : 0))
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Your words as Siri shows them: a small bubble at the right with a tail under its right end. `beside`: what
/// stands at the bubble's left (Aris's pencil while the pointer is on the row).
struct ArisSiriLookBubble<Beside: View>: View {
    let text: String
    /// A hint in the words' place ("듣고 있어요…"): quieter.
    var quiet = false
    @ViewBuilder var beside: () -> Beside

    private typealias Spec = ArisSiriLook.Bubble

    var body: some View {
        HStack(spacing: 6) {
            Spacer(minLength: CGFloat(Spec.leastGap) - 6)
            beside().padding(.bottom, Spec.tailHeight)
            Text(text)
                .font(.system(size: Spec.fontSize))
                .foregroundStyle(.white.opacity(quiet ? Spec.quietInk : Spec.ink))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .padding(.horizontal, Spec.padding)
                .padding(.vertical, 6)
                .frame(minHeight: Spec.height)
                .background(ArisSiriLookGlass(shape: ArisSiriLookBubbleShape()))
                .padding(.bottom, Spec.tailHeight)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

extension ArisSiriLookBubble where Beside == EmptyView {
    init(text: String, quiet: Bool = false) {
        self.init(text: text, quiet: quiet) { EmptyView() }
    }
}

/// The bubble: a rounded box (radius 15: a capsule at one line) with a small tail under its right end.
struct ArisSiriLookBubbleShape: InsettableShape {
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> ArisSiriLookBubbleShape { ArisSiriLookBubbleShape(inset: inset + amount) }

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: inset, dy: inset)
        let radius = min(CGFloat(ArisSiriLook.Bubble.radius) - inset, box.height / 2)
        let tailW = CGFloat(ArisSiriLook.Bubble.tailWidth), tailH = CGFloat(ArisSiriLook.Bubble.tailHeight) - inset
        let body = Path(roundedRect: box, cornerRadius: radius, style: .continuous)
        // The tail hangs under the right end, its tip a little in from the edge (shot 2: 4 in, 5 down), joined to
        // the body as one outline.
        let right = box.maxX, bottom = box.maxY
        var tail = Path()
        tail.move(to: CGPoint(x: right - tailW * 1.9, y: bottom - 0.5))
        tail.addQuadCurve(to: CGPoint(x: right - tailW * 0.55, y: bottom + tailH), control: CGPoint(x: right - tailW * 1.1, y: bottom + tailH * 0.15))
        tail.addQuadCurve(to: CGPoint(x: right - radius * 0.12, y: bottom - radius * 0.75), control: CGPoint(x: right - tailW * 0.3, y: bottom + tailH * 0.1))
        tail.addLine(to: CGPoint(x: right - radius, y: bottom - radius))
        tail.closeSubpath()
        let path = body.union(tail)
        return path
    }
}

/// Siri's working mark: six white dots on a ring that turns slowly while a swelling goes round it. One smooth
/// motion: no dot blinks or goes out. Still with Reduce Motion, and it stops its clock when it is not shown.
struct ArisSiriLookDots: View {
    /// The ring's width (Siri's is 24, the dots reaching a little past it).
    var size: CGFloat = 24
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            Canvas { canvas, canvasSize in
                Self.draw(in: &canvas, size: canvasSize, ring: size, time: context.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)
            }
        }
        .frame(width: size * 1.5, height: size * 1.5)
        .allowsHitTesting(false)
    }

    /// The ring at `time`: each dot with a soft light around it, as Siri's have.
    static func draw(in canvas: inout GraphicsContext, size: CGSize, ring: CGFloat, time: Double, reduceMotion: Bool) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        for index in 0..<ArisSiriLook.Dots.count {
            let dot = ArisSiriLook.Dots.dot(index, at: time, reduceMotion: reduceMotion)
            let width = CGFloat(dot.size) * ring
            let place = CGPoint(x: centre.x + ring / 2 * CGFloat(sin(dot.angle)), y: centre.y - ring / 2 * CGFloat(cos(dot.angle)))
            let box = CGRect(x: place.x - width / 2, y: place.y - width / 2, width: width, height: width)
            canvas.drawLayer { layer in
                layer.addFilter(.blur(radius: width * 0.45))
                layer.fill(Path(ellipseIn: box.insetBy(dx: -width * 0.2, dy: -width * 0.2)), with: .color(.white.opacity(0.45)))
            }
            canvas.fill(Path(ellipseIn: box), with: .color(.white))
        }
    }
}

/// The field's row as Siri lays it out: a round + at the left, the pill, a round microphone at the right.
struct ArisSiriLookFieldRow<Field: View>: View {
    var attachHelp = ""
    var speakHelp = ""
    let attach: () -> Void
    let speak: () -> Void
    @ViewBuilder var field: () -> Field

    var body: some View {
        HStack(alignment: .bottom, spacing: CGFloat(ArisSiriLook.Control.gap)) {
            ArisSiriLookRoundButton(symbol: "plus", help: attachHelp, action: attach)
            field()
            ArisSiriLookRoundButton(symbol: "mic.fill", help: speakHelp, action: speak)
        }
    }
}

/// The top band's round buttons, sized from the band they sit in (28 in a 37-point band; Siri's are 36), and the
/// ✕ far enough left of the stop to clear it.
enum ArisSiriLookBand {
    static func size(band: CGFloat) -> CGFloat { CGFloat(ArisSiriLook.Control.bandSize(band: Double(band))) }
    static func closeBesideStop(band: CGFloat) -> CGFloat { size(band: band) + 6 }
}
