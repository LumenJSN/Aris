//
//  ArisOnboardingBrainPage.swift
//  Aris
//
//  AI 고르기 (fresh install F2): before the first real question the guide shows which AIs are set up on this Mac, as
//  aris-agent says (ArisBrainSetup), and which one answers. It has two faces (ArisOnboardingBrainRows.layout):
//   · The key first, on a Mac with no AI (the owner's pick 3-A, 2026-11-11): the API key's field is open at the top with
//     저장; under it the AIs someone may already use, one line each, with the Terminal command a click copies; 다시 확인;
//     and the way on says what it does, "AI 없이 계속" until something can answer. A saved key or a found AI changes
//     its row in place.
//   · The list to pick from, when some are set up: one that is set up can be picked; one that isn't says how to get
//     it and has its command to copy; the API row opens the same key form.
//  A press of 다시 확인 says that it checked and what it found (ArisOnboardingBrainHelp). With exactly one AI set up
//  the setup never shows this page (ArisSetupPlan). Drawn with the guide's own parts: the try pages' column, the
//  permission cards' card and check, the glass and quiet buttons.
//

import AppKit
import Defaults
import SwiftUI

struct ArisBrainPage: View {
    @ObservedObject var guide: ArisOnboardingGuide
    let palette: ArisSetupPalette
    @ObservedObject private var setup = ArisBrainSetup.shared
    @Default(.arisBrain) private var stored
    @State private var checking = false
    /// The row whose command was just copied (it says so for a moment).
    @State private var copied: ArisBrain?

    private typealias Rows = ArisOnboardingBrainRows
    private var keyOpen: Bool { guide.brainKeyOpen }
    /// An AI can answer (not only a key whose check has just failed).
    private var anyReady: Bool { Rows.canAnswer(ready: setup.ready, keyTrouble: guide.brainKeyTrouble != nil) }

    var body: some View {
        let rows = Rows.shown(Rows.rows(ready: setup.ready, chosen: stored), keyTrouble: guide.brainKeyTrouble != nil)
        let keyFirst = Rows.layout(ready: setup.ready, startedEmpty: guide.brainStartedEmpty) == .keyFirst
        ArisTrySingle(title: keyFirst ? ArisSetupWords.brainKeyTitle(anyReady: anyReady) : ArisOnboardingCopy.brainTitle, palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                Text(keyFirst ? ArisSetupWords.brainKeyLead(anyReady: anyReady) : ArisOnboardingCopy.brainHeading(Rows.heading(ready: setup.ready)))
                    .font(.system(size: 14))
                    .lineSpacing(6)
                    .foregroundStyle(palette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                // The rows and the key form fit the designed window; on a short display they scroll.
                ViewThatFits(in: .vertical) {
                    list(rows, keyFirst: keyFirst)
                    ScrollView(.vertical, showsIndicators: false) { list(rows, keyFirst: keyFirst) }
                }
                actions
                // What the last press of 다시 확인 found, in words (no dot, nothing that blinks).
                if let checked = guide.brainChecked, !checking {
                    Text(ArisSetupWords.checked(checked, names: ArisOnboardingCopy.brainName))
                        .font(.system(size: 12.5))
                        .lineSpacing(4)
                        .foregroundStyle(palette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                        .transition(.opacity)
                }
            }
            .animation(guide.reduced ? ArisOBCurve.fade : ArisOBCurve.card, value: guide.brainChecked)
        }
        .task { await check() }
        // Once no AI was set up here, the page stays key-first for this setup (a saved key changes its row in place).
        .onChange(of: setup.ready, initial: true) { _, ready in
            if Rows.heading(ready: ready) == .none, !guide.brainStartedEmpty { guide.brainStartedEmpty = true }
        }
    }

    @ViewBuilder
    private func list(_ rows: [Rows.Row], keyFirst: Bool) -> some View {
        if keyFirst { keyFirstList(rows) } else { pickList(rows) }
    }

    /// 다시 확인 at the left; at the right the way on, named for what it does.
    private var actions: some View {
        HStack(spacing: 16) {
            Button(checking ? ArisOnboardingCopy.brainChecking : ArisOnboardingCopy.brainAgain) { Task { await check(pressed: true) } }
                .buttonStyle(ArisQuietButtonStyle(palette: palette, weight: .regular))
                .disabled(checking)
            Spacer(minLength: 0)
            if Rows.onward(ready: setup.ready, keyTrouble: guide.brainKeyTrouble != nil) == .withoutAI {
                Button(ArisSetupWords.brainWithoutAI()) { guide.next() }
                    .buttonStyle(ArisQuietButtonStyle(palette: palette, weight: .regular))
            } else {
                ArisGlassRect(title: ArisOnboardingCopy.continueLabel) { guide.next() }
            }
        }
        // The glass button's height either way, so the row doesn't move when a key is saved.
        .frame(minHeight: 44)
        .padding(.top, 4)
    }

    // MARK: - The key first (no AI on this Mac)

    private func keyFirstList(_ rows: [Rows.Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let api = rows.first(where: { $0.brain == .api }) {
                VStack(alignment: .leading, spacing: 0) {
                    line(api, how: ArisOnboardingCopy.brainHow(.api))
                    if api.state == .missing || api.state == .unknown || keyOpen {
                        ArisBrainKeyForm(guide: guide, palette: palette, takesKeyboard: api.state != .chosen).padding(.top, 10)
                    }
                }
                .modifier(ArisBrainCard(palette: palette, reduced: guide.reduced, state: api.state, vertical: 12))
            }
            Text(ArisSetupWords.brainExisting())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.t2)
                .padding(.top, 12).padding(.horizontal, 4)
            ForEach(rows.filter { Rows.terminalBrains.contains($0.brain) }, id: \.brain) { row in
                terminalLine(row).modifier(ArisBrainCard(palette: palette, reduced: guide.reduced, state: row.state, vertical: 10))
            }
        }
        .animation(guide.reduced ? ArisOBCurve.fade : ArisOBCurve.card, value: keyOpen)
    }

    /// One line for an AI set up in Terminal: its name, then its command and "명령 복사" (a click on the line copies
    /// it); once it is set up, that it is, with the check on the one that answers.
    private func terminalLine(_ row: Rows.Row) -> some View {
        Button { pick(row) } label: {
            HStack(alignment: .center, spacing: 12) {
                name(row)
                Spacer(minLength: 8)
                if Rows.copiesCommand(row), let command = Rows.command(row.brain) {
                    Text(command)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.t3)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette.well))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette.wellLine, lineWidth: 1))
                    Text(copied == row.brain ? ArisSetupWords.copied() : ArisSetupWords.brainCopy())
                        .font(.system(size: 14))
                        .foregroundStyle(copied == row.brain ? palette.t1 : palette.t2)
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    Text(ArisOnboardingCopy.brainDetail(row)).font(.system(size: 12.5)).foregroundStyle(palette.t2).lineLimit(1)
                    if row.state == .chosen { ArisCheck(reduced: guide.reduced) }
                }
            }
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(ArisBrainRowPress())
        .disabled(!Rows.selectable(row.state) && !Rows.copiesCommand(row))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.state == .chosen ? [.isSelected] : [])
        .accessibilityHint(Rows.copiesCommand(row) ? ArisSetupWords.copyHint() : "")
    }

    // MARK: - The list to pick from

    private func pickList(_ rows: [Rows.Row]) -> some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.brain) { row in
                VStack(alignment: .leading, spacing: 0) {
                    line(row)
                    if row.brain == .api, keyOpen { ArisBrainKeyForm(guide: guide, palette: palette).padding(.top, 10) }
                }
                .modifier(ArisBrainCard(palette: palette, reduced: guide.reduced, state: row.state, vertical: 12))
                .animation(guide.reduced ? ArisOBCurve.fade : ArisOBCurve.card, value: keyOpen)
            }
        }
    }

    /// The AI's name, with 추천 beside the recommended one.
    private func name(_ row: Rows.Row) -> some View {
        HStack(spacing: 8) {
            Text(ArisOnboardingCopy.brainName(row.brain))
                .font(.system(size: 15))
                .foregroundStyle(row.state == .missing ? palette.t3 : palette.t1)
            if row.recommended {
                Text(ArisOnboardingCopy.brainRecommended).font(.system(size: 12)).foregroundStyle(palette.t2)
            }
        }
    }

    /// A row: the AI's name, what it needs or that it is ready, and the check on the one that answers. `how`: the
    /// line under the name when it is given (the key-first card's own).
    private func line(_ row: Rows.Row, how: String? = nil) -> some View {
        Button { pick(row) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    name(row)
                    Text(Rows.selectable(row.state) ? ArisOnboardingCopy.brainDetail(row) : how ?? detail(row))
                        .font(.system(size: 12.5))
                        .lineSpacing(4)
                        .foregroundStyle(palette.t2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if row.state == .chosen { ArisCheck(reduced: guide.reduced) }
                if how == nil, Rows.copiesCommand(row), let command = Rows.command(row.brain) {
                    // What a click on this card does: the command goes to the clipboard, and the card says so.
                    Text(copied == row.brain ? ArisSetupWords.copied() : ArisSetupWords.copyCommand(command))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(copied == row.brain ? palette.t1 : palette.t2)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ArisBrainRowPress())
        // The key-first card's form is always open: its row has nothing to open.
        .disabled(!Rows.selectable(row.state) && !(row.brain == .api && row.state == .missing && how == nil) && !Rows.copiesCommand(row))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.state == .chosen ? [.isSelected] : [])
        .accessibilityHint(Rows.copiesCommand(row) ? ArisSetupWords.copyHint() : "")
    }

    /// Under a row's name. An AI to set up in Terminal also says what to do on this page afterwards.
    private func detail(_ row: Rows.Row) -> String {
        let detail = ArisOnboardingCopy.brainDetail(row)
        return Rows.copiesCommand(row) ? detail + " " + ArisSetupWords.thenCheckAgain() : detail
    }

    // MARK: - Presses

    /// An AI that is set up becomes the one that answers; one to set up in Terminal has its command copied; the API
    /// row without a key opens its form.
    private func pick(_ row: Rows.Row) {
        if Rows.selectable(row.state) { return setup.choose(row.brain) }
        if Rows.copiesCommand(row), let command = Rows.command(row.brain) { return copy(command, for: row.brain) }
        guard row.brain == .api, row.state == .missing else { return }
        guide.brainKeyOpen.toggle()
    }

    /// The row's Terminal command on the clipboard; the row says "Copied" for a moment.
    private func copy(_ command: String, for brain: ArisBrain) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = brain
        Task {
            try? await Task.sleep(for: Rows.copiedShown)
            if copied == brain { copied = nil }
        }
    }

    /// Asks the agent which AIs are set up. `pressed`: 다시 확인 was pressed, so "Checking…" stays long enough to be
    /// seen and the page then says what was found.
    private func check(pressed: Bool = false) async {
        checking = true
        let before = setup.ready, started = ContinuousClock.now
        let answered = await setup.refresh()
        if pressed {
            let left = Rows.checkingShown - (ContinuousClock.now - started)
            if left > .zero { try? await Task.sleep(for: left) }
            guide.brainChecked = Rows.checked(answered: answered, before: before, after: setup.ready)
        }
        checking = false
    }
}

/// A row's card: the permission cards' own (radius 16, the hairline, the 1-point shadow in light), inset 16.
private struct ArisBrainCard: ViewModifier {
    let palette: ArisSetupPalette
    let reduced: Bool
    let state: ArisOnboardingBrainRows.State
    let vertical: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16).padding(.vertical, vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.card)
                    .shadow(color: palette.dark ? .clear : .black.opacity(0.05), radius: 1, y: 1)
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.cardLine, lineWidth: 1)
            }
            .animation(reduced ? ArisOBCurve.fade : ArisOBCurve.card, value: state)
    }
}

/// A pressable row answers the press at once: it dims a little while held (160 ms ease-out), nothing more for a row
/// this wide.
private struct ArisBrainRowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
