//
//  ArisNoticePillView.swift
//  Aris
//
//  The notice pill as drawn (the owner's pick D; numbers ArisNoticePillLayout, colours ArisNoticePillLook): the dictation
//  pill's body (ArisDictationPillShell) hanging under the closed notch. Collapsed: the mark, the bold title, the rest
//  dimmed and cut, and at the right when it came or a deadline's 24h / 3h chip. Under the pointer it grows into the
//  card: the mark, the title and the ✕, the whole text under it, the buttons at the bottom right. It arrives from the
//  36 × 8 bar, grows and folds on CSS ease, and leaves fading and shrinking to 0.8 (`exit`); with Reduce Motion it
//  only fades. No dot blinks or pulses. Plain values in, callbacks out: ArisNoticeCenter feeds it (ArisNoticePillHost),
//  the render harness draws it.
//

import AppKit
import SwiftUI

/// What the pill asks its owner to do.
struct ArisNoticeHandlers {
    var close: @MainActor (UUID) -> Void = { _ in }
    var act: @MainActor (UUID, ArisNoticeAction) -> Void = { _, _ in }
    /// A click on its body (ArisNotice.tap).
    var tap: @MainActor (UUID) -> Void = { _ in }
    var hover: @MainActor (UUID?) -> Void = { _ in }
}

private typealias L = ArisNoticePillLayout
private typealias Look = ArisNoticePillLook

struct ArisNoticePillView<Face: View>: View {
    let notice: ArisNotice
    let english: Bool
    /// The pointer is on it: the card.
    let hovered: Bool
    /// A fixed clock (offscreen renders); nil: now, a minute at a time.
    var now: Date?
    /// The blur behind the body; nil draws none (offscreen renders have nothing behind them).
    var blending: NSVisualEffectView.BlendingMode? = .behindWindow
    var handlers = ArisNoticeHandlers()
    /// Aris's star and Claude Code's ghost, from the owner (the star's seat in the notch; baked sprites in renders).
    @ViewBuilder let face: (ArisNoticeMark) -> Face

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived: Bool

    /// `still`: drawn already arrived (offscreen renders).
    init(notice: ArisNotice, english: Bool, hovered: Bool, now: Date? = nil, blending: NSVisualEffectView.BlendingMode? = .behindWindow,
         handlers: ArisNoticeHandlers = ArisNoticeHandlers(), still: Bool = false, @ViewBuilder face: @escaping (ArisNoticeMark) -> Face) {
        self.notice = notice
        self.english = english
        self.hovered = hovered
        self.now = now
        self.blending = blending
        self.handlers = handlers
        self.face = face
        _arrived = State(initialValue: still)
    }

    static func ease(_ duration: Double) -> Animation {
        let c = L.ease
        return .timingCurve(c.0, c.1, c.2, c.3, duration: duration)
    }

    /// Leaving: it fades and shrinks to 0.8 from its centre in 150 ms (Reduce Motion: it only fades).
    static func exit(reduceMotion: Bool) -> AnyTransition {
        let out: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: L.exitScale))
        return .asymmetric(insertion: .identity, removal: out.animation(ease(L.exit)))
    }

    private var phase: ArisNoticePillPhase { .of(arrived: arrived, hovered: hovered) }

    /// Wide enough that what must be read is never cut (ArisNoticePillFit).
    private var collapsedWidth: CGFloat { ArisNoticePillFit.width(notice, now: now ?? Date(), english: english) }

    var body: some View {
        let phase = phase
        let size = phase.size(width: collapsedWidth)
        content(phase)
            .opacity(phase.contentShown ? 1 : 0)
            .animation(.easeOut(duration: L.contentFade).delay(reduceMotion ? 0 : L.contentDelay), value: phase.contentShown)
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(ArisDictationPillShape())
            .background {
                GeometryReader { proxy in
                    ArisDictationPillShell(size: proxy.size, gradientBorder: true, blending: blending)
                }
                .compositingGroup()
                .shadow(color: Look.shadow, radius: Look.shadowRadius, y: Look.shadowY)
            }
            .contentShape(ArisDictationPillShape())
            .onTapGesture { handlers.tap(notice.id) }
            .onHover { inside in handlers.hover(inside ? notice.id : nil) }
            .animation(reduceMotion ? nil : Self.ease(hovered ? L.expand : L.collapse), value: hovered)
            .onAppear(perform: arrive)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: notice.title + ". " + notice.body))
    }

    private func arrive() {
        guard !arrived else { return }
        if reduceMotion { arrived = true; return }
        withAnimation(Self.ease(L.arrive)) { arrived = true }
    }

    @ViewBuilder
    private func content(_ phase: ArisNoticePillPhase) -> some View {
        if phase == .expanded {
            card.transition(.opacity)
        } else {
            row.transition(.opacity)
        }
    }

    // MARK: - One line

    /// The mark, the bold part, the rest, the time or chip. What gives way when the line is too long: a preview first,
    /// then the bold part; a deadline's time left (the tinted rest) and the chip never (ArisNoticePillFit).
    private var row: some View {
        let line = ArisNoticePillRules.line(notice)
        let tint = markTint
        return HStack(spacing: L.gap) {
            mark
            HStack(spacing: ArisNoticePillFit.textGap) {
                Text(verbatim: line.bold).fontWeight(.semibold).foregroundStyle(Look.title)
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(line.restTinted ? 0 : 1)
                if !line.rest.isEmpty {
                    if line.restTinted {
                        Text(verbatim: line.rest).fontWeight(.medium).foregroundStyle(tint ?? Look.body)
                            .lineLimit(1).fixedSize().layoutPriority(2)
                    } else {
                        Text(verbatim: line.rest).foregroundStyle(Look.body).lineLimit(1).truncationMode(.tail)
                    }
                }
            }
            .font(.system(size: L.textSize))
            Spacer(minLength: 4)
            trailing.layoutPriority(3)
        }
        .padding(.leading, L.leading).padding(.trailing, L.trailing)
        .frame(width: collapsedWidth, height: L.height)
    }

    @ViewBuilder
    private var trailing: some View {
        if let now {
            trailing(at: now)
        } else {
            TimelineView(.everyMinute) { context in trailing(at: context.date) }
        }
    }

    @ViewBuilder
    private func trailing(at date: Date) -> some View {
        switch ArisNoticePillRules.trailing(notice, now: date, english: english) {
        case .time(let words):
            Text(verbatim: words).font(.system(size: L.timeSize, weight: .medium)).foregroundStyle(Look.time).lineLimit(1).fixedSize()
        case .chip(let alert):
            let tint = Look.dueTint(alert)
            Text(verbatim: alert.rawValue).font(.system(size: L.chipSize, weight: .bold).monospacedDigit()).foregroundStyle(tint)
                .padding(.horizontal, L.chipPadding).frame(height: L.chipHeight)
                .background(Capsule().fill(tint.opacity(L.chipFill)))
                .fixedSize()
        }
    }

    // MARK: - The card

    private var card: some View {
        VStack(alignment: .leading, spacing: L.cardSpacing) {
            HStack(spacing: L.gap) {
                mark
                Text(verbatim: notice.title).font(.system(size: L.textSize, weight: .semibold)).foregroundStyle(Look.title).lineLimit(1)
                Spacer(minLength: 4)
                ArisNoticePillClose(label: ArisNoticeWords.close(english: english)) { handlers.close(notice.id) }
            }
            VStack(alignment: .leading, spacing: 3) {
                if let subtitle = notice.subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle).font(.system(size: L.subtitleSize, weight: .medium)).foregroundStyle(Look.cardText).lineLimit(1)
                }
                if !notice.body.isEmpty { bodyLines }
            }
            .padding(.leading, L.textIndent)
            if !notice.actions.isEmpty {
                HStack(spacing: L.buttonGap) {
                    Spacer(minLength: 0)
                    ForEach(Array(notice.orderedActions.enumerated()), id: \.offset) { _, action in
                        ArisNoticePillButton(title: action.title, primary: action.primary) { handlers.act(notice.id, action) }
                    }
                }
            }
        }
        .padding(EdgeInsets(top: L.cardPadding.top, leading: L.cardPadding.leading, bottom: L.cardPadding.bottom, trailing: L.cardPadding.trailing))
        .frame(width: L.expandedWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The body at its line height (the system font's own, plus the difference as spacing), up to 6 lines.
    private var bodyLines: some View {
        let font = NSFont.systemFont(ofSize: L.bodySize)
        let spacing = max(0, L.bodyLine - (font.ascender - font.descender + font.leading))
        return Text(verbatim: notice.body).font(.system(size: L.bodySize)).lineSpacing(spacing)
            .foregroundStyle(Look.cardText).lineLimit(L.bodyLines).truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The mark

    private var markTint: Color? {
        if case .deadline(let alert) = notice.mark { return Look.dueTint(alert) }
        return nil
    }

    @ViewBuilder
    private var mark: some View {
        switch notice.mark {
        case .star, .ghost: face(notice.mark).frame(width: L.markSize, height: L.markSize)
        case .mail: ArisNoticeSymbolMark(symbol: "envelope.fill", tint: Look.mail, glyph: Look.mailGlyph, fill: Look.mailFill, scale: 0.46)
        case .deadline(let alert):
            let tint = Look.dueTint(alert)
            ArisNoticeSymbolMark(symbol: "calendar", tint: tint, glyph: tint, fill: Look.calendarFill, scale: 0.48)
        }
    }
}

/// A round mark: a glyph on a fill of its colour, a hairline ring.
struct ArisNoticeSymbolMark: View {
    let symbol: String
    let tint: Color
    let glyph: Color
    let fill: Double
    let scale: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(fill))
            Circle().strokeBorder(tint.opacity(ArisNoticePillLook.markRing), lineWidth: ArisNoticePillLook.markRingWidth)
            Image(systemName: symbol).font(.system(size: ArisNoticePillLayout.markSize * scale, weight: .semibold)).foregroundStyle(glyph)
        }
        .frame(width: ArisNoticePillLayout.markSize, height: ArisNoticePillLayout.markSize)
        .accessibilityHidden(true)
    }
}

/// A button on the card: the main one on the notch's dark glass (ArisDarkGlassButton), the others on white .08.
struct ArisNoticePillButton: View {
    let title: String
    let primary: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: title).font(.system(size: L.buttonTextSize, weight: .semibold)).tracking(0.12)
                .foregroundStyle(.white.opacity(primary ? 0.95 : 0.78))
                .padding(.horizontal, L.buttonPadding).frame(height: L.buttonHeight)
                .background {
                    if primary { ArisDarkGlassButton() } else { Capsule().fill(ArisNoticePillLook.secondaryFill) }
                }
                .brightness(hovering ? 0.06 : 0)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The card's ✕: a 20 circle at white .08, an 8-point glyph at .6.
struct ArisNoticePillClose: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: L.closeGlyph, weight: .bold)).foregroundStyle(.white.opacity(L.closeGlyphOpacity))
                .frame(width: L.closeSize, height: L.closeSize)
                .background(Circle().fill(ArisNoticePillLook.secondaryFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }
}
