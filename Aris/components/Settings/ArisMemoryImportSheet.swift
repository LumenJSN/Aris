//
//  ArisMemoryImportSheet.swift
//  Aris
//
//  설정 › 기억 › 다른 AI에서 가져오기: the sheet. It draws ArisMemoryImportBoard and nothing else: the request to copy
//  and where it comes from, the paste box (a .txt or .md file can be dropped on it), every line with its tick, date,
//  kind and mark grouped as the export grouped them, and the receipt with 되돌리기. What a press does is handed in
//  (ArisMemoryImportActions: the app's model asks the agent, ArisMemoryImportModel), so the sheet can be drawn off
//  screen with nothing behind it. The words are written in Korean and looked up for an English Mac
//  (ArisMemoryImportCopy), as on every settings page.
//
//  Its look is the settings window's sheet (ArisSheetFrame, ArisPillButton, ArisTextField, ArisChip) with the pieces
//  an import sheet needs and the window didn't have (ArisMemoryImportParts, …Fields, …List). Its motion
//  (ArisMemoryImportMotion, numbers in ArisMemoryImportPacing): a step slides in 8 pt from the side it comes from
//  while the sheet's height eases, the list's rows rise in once, a tick fills and draws its mark, the count on the
//  import button crossfades, and 되돌리기 folds the receipt. Nothing moves when a key made the change, and under
//  Reduce Motion everything only fades.
//

import SwiftUI

/// What the sheet's buttons do.
struct ArisMemoryImportActions {
    var copy: () -> Void = {}
    var preview: () -> Void = {}
    var apply: () -> Void = {}
    var undo: () -> Void = {}
    /// Another part of the same export: back to the paste box.
    var addMore: () -> Void = {}
    /// A file dropped on the paste box.
    var drop: (URL) -> Void = { _ in }
}

struct ArisMemoryImportSheet: View {
    typealias Step = ArisMemoryImportBoard.Step
    typealias P = ArisMemoryImportPacing
    private typealias C = ArisMemoryImportCopy

    /// The sheet's own measures.
    private enum Metric {
        static let wellHeight: CGFloat = 208
        static let boxHeight: CGFloat = 232
        static let fieldWidth: CGFloat = 200
        /// Between a step's parts.
        static let gap: CGFloat = 12
    }

    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    @Environment(\.arisImportScrub) private var scrub
    @Binding var board: ArisMemoryImportBoard
    /// The request was just copied (the button says so for a moment).
    var copied = false
    var actions = ArisMemoryImportActions()
    let close: () -> Void

    /// The step drawn (it follows the board's, one change behind, so the change can be played) and the one leaving.
    @State private var shown: Step?
    @State private var leaving: Step?
    @State private var forward = true
    @State private var stage = ArisImportClock()
    @State private var rise = ArisImportClock()
    @State private var land = ArisImportClock()
    /// The preview's rows have risen in once; they never rise again in this sheet.
    @State private var risen = false
    @State private var rising = false

    private var english: Bool { w.pageEnglish }
    private var reduced: Bool { ArisSettingsMotion.reduced }
    private var current: Step { scrub != nil ? board.step : shown ?? board.step }

    var body: some View {
        ArisSheetFrame(title: C.sheetTitle, onClose: close) {
            ArisImportStage(clock: stage.clock, base: stage.base, from: scrub?.from ?? leaving, to: current, forward: scrub.map { _ in true } ?? forward,
                            slides: scrub?.rise == nil && !rising, reduced: reduced, scrubbed: scrub?.step) { step in page(step) }
        } footer: {
            ZStack(alignment: .trailing) {
                if let from = scrub?.from, let t = scrub?.step {
                    // A render's frame: the two footers as the transition below crossfades them.
                    HStack(spacing: 8) { footer(from) }.opacity(1 - P.leave.progress(at: t))
                    HStack(spacing: 8) { footer(current) }.opacity(P.leave.progress(at: t - P.stepDelay))
                } else {
                    HStack(spacing: 8) { footer(current) }
                        .id(current)
                        // The old buttons go first; the new ones follow 50 ms later, as the step itself does.
                        .transition(reduced ? .opacity.animation(P.reduced.animation)
                                    : .asymmetric(insertion: .opacity.animation(P.leave.animation.delay(P.stepDelay)), removal: .opacity.animation(P.leave.animation)))
                }
            }
        }
        .onChange(of: board.step) { old, new in change(from: old, to: new) }
    }

    // MARK: The change between steps

    /// Plays a step change: the new step slides in from its side, the old one fades, the height eases; the first
    /// preview's rows rise in; the receipt's check lands. From a key, all of it is simply there.
    private func change(from old: Step, to new: Step) {
        let rowsFirst = new == .preview && !risen && !board.rows.isEmpty
        if rowsFirst { risen = true }
        guard !still, !arisImportKeyDriven() else {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { leaving = nil; shown = new; rising = false; stage.finish(); rise.finish(); land.finish() }
            return
        }
        withAnimation(.linear(duration: P.stepTotal)) {
            leaving = shown ?? old
            forward = P.forward(from: "\(leaving ?? old)", to: "\(new)")
            shown = new
            rising = rowsFirst
            stage.start()
        } completion: {
            if shown == new { leaving = nil }
        }
        if rowsFirst {
            withAnimation(.linear(duration: P.riseDelay(P.riseRows) + P.rise.duration)) { rise.start() } completion: { rising = false }
        }
        if new == .done { withAnimation(.linear(duration: P.land.duration)) { land.start() } }
    }

    /// A tick by the pointer plays (150 ms); by a key it is simply there.
    private func tick(_ n: Int) {
        guard !arisImportKeyDriven() else { return board.toggle(n) }
        withAnimation(.linear(duration: P.tick.duration)) { board.toggle(n) }
    }

    // MARK: The steps

    @ViewBuilder private func page(_ step: Step) -> some View {
        VStack(alignment: .leading, spacing: Metric.gap) {
            switch step {
            case .copy: copyPage
            case .paste: pastePage
            case .preview: previewPage
            case .done: donePage
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// A step's one line under the title, in the sheet frame's subtitle type (13, the description grey).
    private func lead(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(P.sentences(w(text)).enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 13)).foregroundStyle(palette.desc).lineSpacing(2.5).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var copyPage: some View {
        lead(C.stepCopy)
        ArisImportWell(text: board.prompt, height: Metric.wellHeight)
        HStack(spacing: 10) {
            // The field label: 14 pt medium, gray-500 / gray-400.
            Text(w(C.sourceLabel)).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.desc)
            ArisTextField(placeholder: C.sourceHint, text: $board.source, width: Metric.fieldWidth)
            Spacer(minLength: 0)
            ArisPillButton(title: copied ? C.copied : C.copyButton, kind: .ghost, small: true, enabled: !board.prompt.isEmpty) { actions.copy() }
                .contentTransition(.opacity)
                .animation(reduced ? P.reduced.animation : P.leave.animation, value: copied)
        }
    }

    @ViewBuilder private var pastePage: some View {
        lead(C.stepPaste)
        // Cut to what a preview reads as it comes in, once per change (security review 8: a 10 MB paste held whole
        // and trimmed on every redraw stalled the window).
        ArisImportPasteBox(text: Binding(get: { board.pasted }, set: { board.pasted = ArisMemoryImportRowDetail.kept($0) }),
                           hint: C.pasteHint, height: Metric.boxHeight, drop: actions.drop)
        if board.failed { problem }
    }

    @ViewBuilder private var previewPage: some View {
        lead(C.stepPreview)
        if board.complete == false { ArisImportCallout(text: C.moreNote) { ArisImportInfoIcon() } }
        if board.rows.isEmpty && board.unreadable.isEmpty { ArisImportCallout(text: C.nothing) { ArisImportInfoIcon(symbol: "questionmark.circle") } }
        ArisImportTimed(rise, duration: P.riseDelay(P.riseRows) + P.rise.duration) { seconds in
            ArisImportList(board: $board, rise: scrub?.rise ?? seconds, reduced: reduced, tick: tick)
        }
        if board.failed { problem }
    }

    @ViewBuilder private var donePage: some View {
        let written = board.receipt?.written ?? 0
        ArisImportCallout(text: board.undone ? C.undone : C.imported(written, english: english),
                          detail: board.receipt.map { C.breakdown($0, english: english) }, detailShown: !board.undone) {
            ZStack {
                ArisImportTimed(land, duration: P.land.duration) { seconds in ArisImportLandingMark(seconds: scrub?.step ?? seconds) }
                    .opacity(board.undone ? 0 : 1).scaleEffect(board.undone && !reduced ? 0.985 : 1)
                ArisImportUndoneMark().opacity(board.undone ? 1 : 0)
            }
        }
        .contentTransition(.opacity)
        // 되돌리기 folds the receipt on the close curve, 200 ms (0.45, 0, 0.55, 1); Reduce Motion: a fade.
        .animation(reduced ? P.reduced.animation : P.undo.animation, value: board.undone)
        if board.failed { problem }
    }

    /// The last call didn't go through: said in the callout, not in red (red is for a button that destroys).
    private var problem: some View {
        ArisImportCallout(text: C.failed) { ArisImportInfoIcon(symbol: "exclamationmark.circle") }
    }

    // MARK: The footer

    @ViewBuilder private func footer(_ step: Step) -> some View {
        switch step {
        case .copy:
            ArisPillButton(title: C.cancel, kind: .ghost, action: close)
            ArisPillButton(title: C.next) { board.step = .paste }
        case .paste:
            ArisPillButton(title: C.back, kind: .ghost) { board.step = board.rows.isEmpty ? .copy : .preview }
            // Whether there is anything to read, without trimming the whole paste on every redraw (board.canPreview
            // does; the press itself still goes through it).
            ArisPillButton(title: board.busy ? C.reading : C.preview, enabled: !board.busy && ArisMemoryImportRowDetail.hasWords(board.pasted)) { actions.preview() }
                .contentTransition(.opacity)
        case .preview:
            ArisPillButton(title: C.back, kind: .ghost) { board.step = .paste }
            ArisPillButton(title: C.addMore, kind: .ghost) { actions.addMore() }
            // The count changes with every tick: its number crossfades in the tick's own 150 ms, never bounces.
            ArisPillButton(title: C.importButton(board.chosen.count, english: english), enabled: board.canImport) { actions.apply() }
                .contentTransition(.opacity)
                .monospacedDigit()
        case .done:
            if !board.undone {
                ArisPillButton(title: C.undo, kind: .ghost, enabled: !board.busy) { actions.undo() }
                    .transition(.opacity.animation(reduced ? P.reduced.animation : P.undo.animation))
            }
            ArisPillButton(title: C.done, action: close)
        }
    }
}
