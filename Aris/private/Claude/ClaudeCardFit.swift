//
//  ClaudeCardFit.swift
//  Aris
//
//  How a Claude card fits the open notch (the user's report 2026-11-19: a four-question card grew past the notch's cap, its
//  question was cut with "…" and its Terminal and Submit were under the notch's lower edge). A card is a header that
//  stays on top (a question's step chips), a body, and a footer that stays at the bottom (Terminal, Submit, Allow):
//  the header and footer always get their own height, and the body takes what is left. A body that fits is drawn as it
//  is; one taller than the room scrolls inside it, so nothing in it is ever cut and the buttons are always there.
//  The notch opens to the card's whole height up to the screen's safe maximum (ArisNotchDecisions.growMax).
//

import SwiftUI

struct ClaudeCardFit<Header: View, Content: View, Footer: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    @Environment(\.claudeCardFitProbe) private var probe

    /// How far the scrolling body fades out at its foot.
    static var fade: CGFloat { 18 }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            header()
                .fixedSize(horizontal: false, vertical: true)
            // The first that fits: the body as it is, else the same body in a scroller as tall as the room left.
            ViewThatFits(in: .vertical) {
                measured(scrolls: false)
                ScrollView(.vertical) {
                    measured(scrolls: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Room for the fade below, so the last row is clear once scrolled to the end.
                        .padding(.bottom, Self.fade)
                }
                // As Aris's answers: AppKit's legacy scroller would narrow the text whenever a mouse is connected.
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                // The cut row fades out above the footer: there is more below.
                .mask {
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Self.fade)
                    }
                }
            }
            footer()
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { probe?(.footer($0)) }
        }
    }

    /// The body at its own height, never cut: in the scroller it is as tall as it needs.
    private func measured(scrolls: Bool) -> some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { probe?(.body(scrolls: scrolls, height: $0)) }
    }
}

/// What a card's layout tells a test: where its footer is, and whether its body scrolls and how tall it is.
enum ClaudeCardFitReport: Equatable {
    case footer(CGRect)
    case body(scrolls: Bool, height: CGFloat)
}

private struct ClaudeCardFitProbeKey: EnvironmentKey {
    static let defaultValue: (@Sendable @MainActor (ClaudeCardFitReport) -> Void)? = nil
}

extension EnvironmentValues {
    /// Told each card layout's footer frame and body (the layout tests); nil in the app.
    var claudeCardFitProbe: (@Sendable @MainActor (ClaudeCardFitReport) -> Void)? {
        get { self[ClaudeCardFitProbeKey.self] }
        set { self[ClaudeCardFitProbeKey.self] = newValue }
    }
}
