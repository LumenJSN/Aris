//
//  ClaudeEarGlyph.swift
//  Aris
//
//  The closed notch's right ear, built like the iPhone's combined status icons:
//  a ring open at the bottom fills with the plan limit the owner picked (or an API
//  key's spend against its budget: ClaudeRingReading), one dot per active
//  session sits in the opening (ClaudeEarDots: idle ones melt into the ring's
//  end, and no active one closes the ring), and the middle shows what matters
//  most right now (the tool in use, a pause sign when Claude waits for you, a
//  moon at rest). The dots move on a spring and never blink; nothing here ticks.
//  At work it takes the Claude Code teammate's accent (ClaudeAccent); approval,
//  done and error keep their fixed colours.
//

import SwiftUI

struct ClaudeEarGlyph: View {
    static let moonlight = Color(ClaudeAccent.moon)
    static let approval = Color(ClaudeAccent.approval)
    static let done = Color(ClaudeAccent.done)
    static let error = Color(ClaudeAccent.error)
    /// The timer's ring in the closed band (ArisTimerEar); Claude's own is ClaudeEarLayout.glyphSize.
    static let closedSize: CGFloat = 20
    /// The dots' and the opening's spring (mockup claude-usage.html: 0.4 s, a small overshoot).
    static let spring = Animation.spring(duration: 0.4, bounce: 0.2)

    /// Session states in a stable order (one dot each while active; idle ones merge into the ring).
    let states: [ClaudeState]
    let center: EarCenter
    /// How full the ring is (ClaudeRingReading.percent), nil until there's something to show.
    let usage: Double?
    let size: CGFloat
    /// The Claude Code teammate's accent: the ring, the tool and the working dots.
    let accent: Color
    /// The sessions' ids, in `states`' order, so a dot keeps its identity as others come and go (else by position).
    var sessionIds: [String]? = nil
    /// What the ring shows, for VoiceOver (else read as the 5-hour limit).
    var reading: ClaudeRingReading? = nil

    private var lineWidth: CGFloat { size * 0.08 }

    private var layout: ClaudeEarDots.Layout {
        let ids = sessionIds ?? states.indices.map(String.init)
        let sessions = zip(ids, states).map { ClaudeEarDots.Session(id: $0, active: ClaudeEarDots.isActive($1)) }
        return ClaudeEarDots.layout(sessions, size: Double(size))
    }

    /// The ring takes the state's colour once Claude needs you or has finished; otherwise it shows the limit.
    private var ringTint: Color? {
        switch center {
        case .waiting: return Self.approval
        case .done: return Self.done
        case .error: return Self.error
        case .tool, .resting: return nil
        }
    }

    /// The ring's colour as UsageArc paints it (a merging dot takes it).
    private var ringColor: Color {
        ringTint ?? usage.map { Self.usageTint(for: $0, accent: accent) } ?? accent
    }

    var body: some View {
        let layout = layout
        let toneById = Dictionary(zip(sessionIds ?? states.indices.map(String.init), states), uniquingKeysWith: { a, _ in a })
        ZStack {
            UsageArc(percent: usage, gap: layout.gap, lineWidth: lineWidth, tint: ringTint, accent: accent)
            ForEach(layout.dots, id: \.id) { dot in
                EarDot(dot: dot, size: size, color: (toneById[dot.id] ?? .idle).tone.color(accent: accent, rest: .white.opacity(0.4)),
                       ring: ringColor, filled: (usage ?? 0) > 0)
            }
            symbol
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .id(symbolIdentity)
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.35, bounce: 0.2), value: center)
        // A session coming or going: its dot grows in or shrinks away on the same spring.
        .animation(Self.spring, value: layout.dots.map(\.id))
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    static func usageTint(for percent: Double, accent: Color) -> Color {
        if percent >= ClaudeUsage.warnAt[1] { return error }
        if percent >= ClaudeUsage.warnAt[0] { return approval }
        return accent
    }

    /// Tool changes swap the symbol in place; other changes cross-fade between symbols.
    private var symbolIdentity: String {
        if case .tool = center { return "tool" }
        return String(describing: center)
    }

    @ViewBuilder
    private var symbol: some View {
        switch center {
        case .tool(let tool):
            Image(systemName: tool.symbolName)
                .font(.system(size: size * 0.425, weight: .semibold))
                .foregroundStyle(accent)
                .contentTransition(.symbolEffect(.replace))
        case .done:
            Image(systemName: "checkmark").font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(Self.done)
        case .error:
            Image(systemName: "exclamationmark").font(.system(size: size * 0.45, weight: .heavy)).foregroundStyle(Self.error)
        case .resting:
            Image(systemName: "moon.fill")
                .font(.system(size: size * 0.45))
                .foregroundStyle(Self.moonlight)
                .shadow(color: Self.moonlight.opacity(0.35), radius: size * 0.07)
        case .waiting:
            Image(systemName: "pause.fill").font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(Self.approval)
        }
    }

    private var label: String {
        let sessions = states.count == 1 ? "1 session" : "\(states.count) sessions"
        let waiting = states.filter { $0 == .notification }.count
        let needs = waiting > 0 ? ", \(waiting) waiting for you" : ""
        let limit = reading.map(ClaudeUsageWords.spoken) ?? usage.map { ", 5-hour limit \(Int($0.rounded(.up))) percent used" } ?? ""
        return "Claude, \(sessions)\(needs)\(limit)"
    }
}

private extension EarCenter.Tool {
    var symbolName: String {
        switch self {
        case .terminal: return "terminal"
        case .edit: return "pencil"
        case .search: return "magnifyingglass"
        case .agents: return "person.2.fill"
        case .thinking: return "sparkle"
        }
    }
}

/// One session's dot: in its slot at full strength, or (resting) slid into the arc's nearer end, the line's width and
/// the ring's colour, then gone (mockup: the cap's strength at once, faded out from 380 ms). Waking reverses it.
private struct EarDot: View {
    let dot: ClaudeEarDots.Dot
    let size: CGFloat
    let color: Color
    let ring: Color
    let filled: Bool

    /// The mockup's plain `ease`, for the colour (0.3 s) and the strength (0.14 s).
    private static func ease(_ seconds: Double) -> Animation { .timingCurve(0.25, 0.1, 0.25, 1, duration: seconds) }

    var body: some View {
        let r = CGFloat(ClaudeEarDots.radius(Double(size))), mid = size / 2
        let point = CGPoint(x: mid + r * CGFloat(cos(dot.angle)), y: mid + r * CGFloat(sin(dot.angle)))
        let strength = dot.merged ? ClaudeEarDots.capOpacity(side: dot.side, filled: filled) : 1
        let shown = dot.merged ? ring : color
        Circle()
            .fill(shown)
            .animation(Self.ease(0.3), value: shown)
            .opacity(strength)
            .animation(Self.ease(0.14), value: strength)
            .opacity(dot.merged ? 0 : 1)
            .animation(dot.merged ? Self.ease(0.14).delay(0.38) : Self.ease(0.14), value: dot.merged)
            .animation(ClaudeEarGlyph.spring) { content in
                content.frame(width: dot.diameter, height: dot.diameter).position(point)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.01)))
            .allowsHitTesting(false)
    }
}

/// The usage gauge: a ring with its bottom left open for the session dots, `gap` radians each side of the bottom
/// (0: a full ring). The opening moves on the dots' spring, the track and the fill as one piece each (EarArc); a new
/// percent eases the fill and its colour out.
private struct UsageArc: View {
    let percent: Double?
    let gap: Double
    let lineWidth: CGFloat
    let tint: Color?
    let accent: Color

    var body: some View {
        let tint = tint ?? percent.map { ClaudeEarGlyph.usageTint(for: $0, accent: accent) } ?? accent
        ZStack {
            arc(1).opacity(0.22)
            if let percent { arc(ClaudeEarDots.fill(percent: percent)) }
        }
        .foregroundStyle(tint)
        .animation(.easeOut(duration: 0.6), value: percent)
        .animation(ClaudeEarGlyph.spring, value: gap)
    }

    private func arc(_ fraction: Double) -> some View {
        EarArc(gap: gap, fraction: fraction, lineWidth: lineWidth).stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}

/// The ring's arc from the left end of the opening clockwise (ClaudeEarDots.arc). The opening and the share drawn
/// animate as one pair, so the turn and the length can never come apart while the opening moves.
private struct EarArc: Shape {
    var gap: Double
    var fraction: Double
    let lineWidth: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(gap, fraction) }
        set { (gap, fraction) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let arc = ClaudeEarDots.arc(gap: gap, fraction: fraction)
        var path = Path()
        // y runs down, so "not clockwise" here turns clockwise on screen: bottom, left, top, right.
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: (min(rect.width, rect.height) - lineWidth) / 2,
                    startAngle: .radians(arc.start), endAngle: .radians(arc.start + arc.sweep), clockwise: false)
        return path
    }
}
