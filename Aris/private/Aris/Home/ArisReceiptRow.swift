//
//  ArisReceiptRow.swift
//  Aris
//
//  The receipt under an answer, live: the line ArisReceiptModel holds for the turn in the notch, drawn by
//  ArisReceiptChip in the turn's column (ArisTurnView), under the answer and its activity tags. It tells the model its
//  height (for the answer's height budget) and whether the pointer is on it (the line then stays). In as the tags
//  come in (220 ms ease-out), out as they go.
//  A new line shows only once the place it goes has stood still for ArisReceiptSettle.still: under the day-end list
//  it used to come up while the list was still growing and then slide 29 pt down, so a click on 되돌리기 landed where
//  it had been (second upgrade run, A6). Once shown it is not taken away for a move.
//

import SwiftUI

/// The live row: the line of the turn in the notch, when there is one.
struct ArisReceiptRow: View {
    @ObservedObject private var model = ArisReceiptModel.shared
    @ObservedObject private var panels = ArisSidePanels.shared
    @Environment(\.arisNotchHovered) private var onNotch
    /// Where the row's place last was (in the window), and when it last moved.
    @State private var place: CGFloat = 0
    @State private var movedAt = Date.distantPast
    /// The acts of the line now up (nil: none shown yet).
    @State private var shownActs: [String]?
    @State private var tick = 0

    /// Under the answer or its tags, the turn column's own gap.
    static let gap: CGFloat = 12

    var body: some View {
        if let line = model.desk.line {
            let acts = line.receipt.acts.map(\.id)
            let visible = showsLine(acts)
            // In the layout at once (the column makes its room), seen and pressable once its place stands still.
            ArisReceiptChip(line: line, english: ArisUIWords.english, opensTab: panels.shows(.activity),
                            undo: { model.undo() }, open: { model.openActivity() })
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
                .onHover { model.hovering = $0 && visible }
                // The pointer left the notch without the line being told: it no longer holds the line.
                .onChange(of: onNotch) { _, on in if !on { model.hovering = false } }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.measured($0) }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { moved($0) }
                .onChange(of: visible, initial: true) { _, now in if now { shownActs = acts } }
                .onChange(of: acts) { _, next in
                    if next != shownActs { shownActs = nil }
                    recheck()
                }
                .onAppear { recheck() }
                .transition(ArisTaskTagsContent.tagExit)
        }
    }

    private func showsLine(_ acts: [String]) -> Bool {
        _ = tick
        return ArisReceiptSettle.shows(shown: shownActs == acts, movedAt: movedAt, now: .now)
    }

    private func moved(_ y: CGFloat) {
        guard abs(y - place) > 0.5 else { return }
        place = y
        movedAt = .now
        recheck()
    }

    /// Looks again once the place may have stood still long enough.
    private func recheck() {
        let wait = ArisReceiptSettle.still + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { tick += 1 }
    }
}
