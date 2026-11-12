//
//  ArisBubbleView.swift
//  Aris
//
//  A teammate's live bubble, the owner's pick A (mockups/10-bubble.html): a dark glass pill, the text centred. It
//  sits beside the character on its window and says what the job does (ArisBubbleText). The first time it shows after
//  landing its letters come in one by one (45 ms apart, each fading in over 180 ms); while it works a sheen sweeps across
//  it on the render server; done shows a green check. The text is always plain: no markdown, no links.
//
//  Tokens (as the mockup has them): 28 tall, 10 in on the left and 11 on the right,
//  11.5 / wght 560 / -0.01 em at white .9; the dictation pill's glass, which has no shadow. Text swaps cross-fade with a
//  2-pt blur in 150 ms, the width follows in 220 ms (0.16, 1, 0.3, 1), the check lands in 460 ms (0.34, 1.56, 0.64, 1).
//

import AppKit
import SwiftUI

struct ArisBubbleView: View {
    let text: String
    let tone: ArisBubbleTone
    /// 모션 줄이기 or the system's Reduce Motion: no sheen, no reveal, no blur, bounce or width motion, only fades.
    var reduceMotion = false
    /// When the letter-by-letter reveal started (nil: the text shows whole).
    var revealFrom: Date?

    /// The reveal (mockup: a letter every 45 ms, each fading in over 180 ms on (0.22, 0.61, 0.36, 1)).
    static let revealStep = 0.045
    static let revealFade = 0.18
    static func revealTime(_ text: String) -> Double { Double(text.count) * revealStep + revealFade }

    static let font = Font(ArisFont.system(11.5, weight: 560)).monospacedDigit()
    /// The tag-in curve, for the width.
    private static let resize = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
    private static let swap = Animation.easeInOut(duration: 0.15)
    /// The land curve.
    private static let land = Animation.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.46)
    /// The success green.
    static let success = Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255)

    /// The widest the words may be (the bubble's host holds 296; the padding and the check take the rest).
    static let maxTextWidth: CGFloat = 240

    /// How wide `text` is at the bubble's font.
    static func textWidth(_ text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: ArisFont.system(11.5, weight: 560), .kern: -0.115]).size().width
    }

    /// How wide the bubble is for `text`: its words, the padding, and the check when done.
    static func width(text: String, tone: ArisBubbleTone) -> CGFloat {
        (textWidth(text) + 21 + (tone == .done ? 5 + 11 : 0)).rounded(.up)
    }

    var body: some View {
        HStack(spacing: 5) {
            words
                .id(text)
                .transition((reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace)).animation(Self.swap))
            if tone == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(Self.success)
                    .transition((reduceMotion ? AnyTransition.opacity : .scale(scale: 0.4).combined(with: .opacity)).animation(Self.land))
                    .accessibilityHidden(true)
            }
        }
        .font(Self.font)
        .tracking(-0.115)
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(1)
        .fixedSize()
        .padding(.leading, 10)
        .padding(.trailing, 11)
        .frame(height: ArisBubbleGeometry.height)
        .background(ArisPillGlass(shape: Capsule(style: .continuous)))
        .overlay {
            if tone == .working && !reduceMotion {
                ArisBubbleSheen().transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Self.resize, value: text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }

    /// The words: whole, or (during the reveal) each letter at its own opacity. The reveal redraws only while it runs.
    @ViewBuilder private var words: some View {
        if let revealFrom, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: Date().timeIntervalSince(revealFrom) > Self.revealTime(text))) { context in
                Text(Self.revealed(text, after: context.date.timeIntervalSince(revealFrom)))
            }
        } else {
            Text(verbatim: text)
        }
    }

    /// `text` with each letter's opacity `elapsed` seconds into the reveal (plain text: an AttributedString of the
    /// letters, no markdown parsed).
    static func revealed(_ text: String, after elapsed: Double) -> AttributedString {
        var out = AttributedString()
        for (i, letter) in text.enumerated() {
            let t = min(1, max(0, (elapsed - Double(i) * revealStep) / revealFade))
            var piece = AttributedString(String(letter))
            piece.foregroundColor = Color.white.opacity(0.9 * easeOut(t))
            out += piece
        }
        return out
    }

    /// (0.22, 0.61, 0.36, 1), close enough for an opacity ramp.
    private static func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 2.2) }
}

/// The dictation pill's glass (ArisPillLook has each number): the window behind
/// blurred, a dark vertical gradient at .96 over it, and a 1-point ring lit at its top left and bottom right corners.
/// No shadow. Shared by the bubble and the status pill. With macOS's Reduce Transparency: no blur, the fill solid.
struct ArisPillGlass<S: InsettableShape>: View {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var fill: LinearGradient {
        let alpha = ArisGlassRecipe.pillFill(reduceTransparency: reduceTransparency)
        let top = ArisPillLook.fillTop, bottom = ArisPillLook.fillBottom
        return LinearGradient(colors: [Color(.sRGB, red: top.red, green: top.green, blue: top.blue, opacity: alpha),
                                       Color(.sRGB, red: bottom.red, green: bottom.green, blue: bottom.blue, opacity: alpha)],
                              startPoint: .top, endPoint: .bottom)
    }

    /// One corner's highlight: white .28 at the corner, .08 at 30 %, gone at 60 % of the way to the far corner.
    private func highlight(at corner: UnitPoint) -> EllipticalGradient {
        EllipticalGradient(stops: ArisPillLook.ringStops.map { .init(color: .white.opacity($0.alpha), location: $0.location) },
                           center: corner, startRadiusFraction: 0, endRadiusFraction: ArisPillLook.ringReach)
    }

    var body: some View {
        ZStack {
            if !reduceTransparency {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).clipShape(shape)
            }
            shape.fill(fill)
            shape.strokeBorder(.white.opacity(ArisPillLook.ringBase), lineWidth: ArisPillLook.ringWidth)
            shape.strokeBorder(highlight(at: .topLeading), lineWidth: ArisPillLook.ringWidth)
            shape.strokeBorder(highlight(at: .bottomTrailing), lineWidth: ArisPillLook.ringWidth)
        }
    }
}

/// The working sheen (mockup `.bubble.working::after`): a soft white .10 band, 2.5 times the bubble's width, swept
/// across it from left to right every 2.6 s, linear, inside the capsule. A Core Animation layer: it runs on the render
/// server, never on the main thread, and only exists while the bubble works. A sweep, never a blink.
private struct ArisBubbleSheen: NSViewRepresentable {
    func makeNSView(context: Context) -> ArisSheenView { ArisSheenView() }
    func updateNSView(_ view: ArisSheenView, context: Context) {}
}

final class ArisSheenView: NSView {
    private let band = CAGradientLayer()
    private static let key = "aris.sheen"
    private static let period: CFTimeInterval = 2.6
    /// One clock for the sweep, so a width change re-aims it without restarting it.
    private let begin = CACurrentMediaTime()
    private var swept: CGFloat = -1

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        band.colors = [NSColor.clear.cgColor, NSColor.white.withAlphaComponent(0.10).cgColor, NSColor.clear.cgColor]
        band.locations = [0.3, 0.5, 0.7]
        layer?.addSublayer(band)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let w = bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = bounds.height / 2
        band.frame = CGRect(x: 0, y: 0, width: 2.5 * w, height: bounds.height)
        CATransaction.commit()
        guard w > 0, w != swept else { return }
        swept = w
        // The band's left edge from -1.8 w to +1.8 w (background-position 120% → -120% of a 250% background).
        let sweep = CABasicAnimation(keyPath: "transform.translation.x")
        sweep.fromValue = -1.8 * w
        sweep.toValue = 1.8 * w
        sweep.duration = Self.period
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .linear)
        sweep.beginTime = band.convertTime(begin, from: nil)
        sweep.isRemovedOnCompletion = false
        band.add(sweep, forKey: Self.key)
    }
}
