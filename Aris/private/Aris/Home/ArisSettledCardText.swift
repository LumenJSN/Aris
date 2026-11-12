//
//  ArisSettledCardText.swift
//  Aris
//
//  A job's card that the user answered stays up as the turn's answer (its title and words). A long one, Aside's brief
//  for one, folds to two lines so it doesn't take the answer's room.
//

import SwiftUI

/// A card's words left up after the user answered it (a job's Aside brief, for one), on the answer's text grid: folded to
/// its first two lines with "…" so a long brief doesn't take the answer's room; a tap shows all of it in the answer's
/// scroller, another folds it again. Taps only do anything when two lines don't hold it all (ArisCardFold).
struct ArisSettledCardText: View {
    let text: String
    let budget: CGFloat

    @State private var expanded: Bool
    @State private var full: CGFloat = 0
    @State private var folded: CGFloat = 0

    /// `expanded`: open from the start (the offscreen render's second state).
    init(text: String, budget: CGFloat, expanded: Bool = false) {
        self.text = text
        self.budget = budget
        _expanded = State(initialValue: expanded)
    }

    private var folds: Bool { ArisCardFold.folds(full: full, folded: folded) }

    var body: some View {
        ArisFadingScroll(budget: budget) {
            words(lines: expanded ? nil : ArisCardFold.lines)
                // Both heights, measured out of sight on the same width, to know whether it folds at all.
                .background {
                    ZStack(alignment: .topLeading) {
                        words(lines: nil).onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full = $0 }
                        words(lines: ArisCardFold.lines).onGeometryChange(for: CGFloat.self) { $0.size.height } action: { folded = $0 }
                    }
                    .hidden()
                }
                .padding(ArisAnswerText.padding)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard folds || expanded else { return }
                    withAnimation(ArisGlass.opening) { expanded.toggle() }
                }
        }
        .onChange(of: text) { expanded = false }
    }

    private func words(lines: Int?) -> some View {
        ArisReaderBody.text(text, size: ArisDocMetrics.notch.size, color: ArisDocLook.text)
            .lineBox(ArisDocMetrics.notch.size, ArisDocMetrics.notch.line / ArisDocMetrics.notch.size)
            .lineLimit(lines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
