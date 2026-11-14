//
//  ArisTeamSections.swift
//  Aris
//
//  The 팀원 page's grouped cards (layout A): 두뇌 (every brain a radio row; one not set up on this Mac says 로그인 필요
//  with its login, never 곧), 쓸 수 있는 것 (one switch a scope, and the line that risky steps still ask), a list of notes
//  (기억, 앱 노하우) with ✕ and 모두 지우기, and 말로 팀원 만들기.
//

import SwiftUI

/// A grouped card's row divider (mockup `.grp .row + .row`).
private struct ArisRowDivider: View {
    @Environment(\.arisPalette) private var palette
    var body: some View { Rectangle().fill(palette.line).frame(height: 1) }
}

/// The square letter tile a brain row leads with (mockup `.apptile`).
private struct ArisBrainMark: View {
    @Environment(\.arisPalette) private var palette
    let letter: String

    var body: some View {
        Text(letter).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.title)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.tile))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
    }
}

struct ArisBrainPicker: View {
    @Environment(\.arisPalette) private var palette
    let mate: ArisTeammate
    let brains: [String: Bool]
    let pick: (String) -> Void
    let login: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if mate.id == ArisTeammate.claudeCodeId {
                row(brain: .claude, detail: ArisTeamCopy.ccBrain, ready: true, selected: true, fixed: true)
            } else {
                let choices = ArisTeamEditing.brainChoices(for: mate.id, ready: brains)
                ForEach(Array(choices.enumerated()), id: \.element.brain) { index, choice in
                    if index > 0 { ArisRowDivider() }
                    row(brain: ArisBrain.named(choice.brain), detail: detail(choice), ready: choice.ready, selected: mate.brain == choice.brain, fixed: false)
                }
            }
        }
        .arisCard()
    }

    private func detail(_ choice: ArisTeamEditing.BrainChoice) -> String {
        // agy can't be held to scopes: with any off it answers in words only (H1).
        let scoped = choice.brain == ArisBrain.antigravity.rawValue && !ArisTeammateScope.isAll(mate.scopeSet) ? "\n" + ArisTeamCopy.agyScoped : ""
        guard !choice.ready else { return ArisTeamCopy.signedIn + scoped }
        if choice.brain == ArisBrain.api.rawValue { return ArisTeamCopy.apiLoginHint }
        return ArisTeamExtrasCopy.loginHint(choice.brain) + scoped
    }

    @ViewBuilder
    private func row(brain: ArisBrain, detail: String, ready: Bool, selected: Bool, fixed: Bool) -> some View {
        HStack(spacing: 12) {
            Button { if !fixed { pick(brain.rawValue) } } label: {
                HStack(spacing: 12) {
                    ArisBrainMark(letter: String(ArisTeamExtrasCopy.title(brain).prefix(1)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ArisTeamExtrasCopy.title(brain)).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.title)
                        Text(detail).font(.system(size: 11.5)).foregroundStyle(palette.desc).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            if !ready, brain != .api {
                ArisChip(text: ArisTeamCopy.loginNeeded, tone: .warn)
                ArisSettingsButton(title: ArisTeamCopy.login, small: true) { login(brain.rawValue) }
            } else if !ready {
                ArisChip(text: ArisTeamCopy.loginNeeded, tone: .warn)
            }
            radio(selected)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(selected && !fixed ? palette.rowSelected.opacity(0.6) : .clear)
    }

    private func radio(_ on: Bool) -> some View {
        ZStack {
            Circle().strokeBorder(on ? palette.accent : palette.fieldBorder, lineWidth: 1.5).frame(width: 20, height: 20)
            if on {
                Circle().fill(palette.accent).frame(width: 20, height: 20)
                ArisLineIcon("checkmark", size: 12, stroke: 2.5).foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Brain names and login lines (the mockup's: "Gemini", "API 모델", "터미널에서 agy로 로그인해요").
enum ArisTeamExtrasCopy {
    static func title(_ brain: ArisBrain) -> String {
        switch brain {
        case .claude: "Claude"
        case .codex: "GPT (Codex)"
        case .antigravity: "Gemini"
        case .api: String(localized: "team.brain.api", defaultValue: "API model", bundle: ArisTeamCopy.bundle, locale: ArisTeamCopy.locale, comment: "Brain row title")
        }
    }

    static func loginHint(_ brain: String) -> String {
        let command = ArisBrain.named(brain) == .codex ? "codex login" : ArisBrain.named(brain) == .antigravity ? "agy" : "claude"
        return String(localized: "team.brain.login.hint", defaultValue: "Not set up on this Mac. Log in with \(command) in a terminal.",
                      bundle: ArisTeamCopy.bundle, locale: ArisTeamCopy.locale, comment: "Brain row: not set up; %@ is the login command")
    }
}

struct ArisScopeSwitches: View {
    @Environment(\.arisPalette) private var palette
    let scopes: Set<ArisTeammateScope>
    /// The teammate's brain: a Claude teammate has no terminal switch (N4), and one line says why.
    var brain = ""
    let toggle: (ArisTeammateScope) -> Void

    var body: some View {
        let shown = ArisTeammateScope.shown(brain: brain)
        VStack(spacing: 0) {
            ForEach(shown, id: \.self) { scope in
                if scope != shown.first { ArisRowDivider() }
                HStack(spacing: 12) {
                    ArisLineIcon(ArisTeamSymbols.scope(scope), size: 18).foregroundStyle(palette.desc).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ArisTeamCopy.scopeTitle(scope)).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.title)
                        Text(ArisTeamCopy.scopeDetail(scope)).font(.system(size: 11.5)).foregroundStyle(palette.desc)
                        // The terminal can run anything, so it can get around the other limits (re-review 2): said plainly.
                        if scope == .terminal {
                            Text(ArisTeamCopy.terminalBypass).font(.system(size: 11.5)).foregroundStyle(palette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    ArisSwitch(isOn: scopes.contains(scope), label: ArisTeamCopy.scopeTitle(scope)) { toggle(scope) }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            if !shown.contains(.terminal) {
                ArisRowDivider()
                HStack(spacing: 12) {
                    ArisLineIcon(ArisTeamSymbols.scope(.terminal), size: 18).foregroundStyle(palette.desc).frame(width: 24)
                    Text(ArisTeamCopy.terminalOnClaude).font(.system(size: 11.5)).foregroundStyle(palette.desc)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            HStack(alignment: .top, spacing: 12) {
                ArisLineIcon("checkmark.shield", size: 18).foregroundStyle(palette.desc).frame(width: 24)
                Text(ArisTeamCopy.safeLine).font(.system(size: 11.5)).foregroundStyle(palette.desc).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(palette.soft)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .arisCard()
    }
}

/// Notes as rows (기억, 앱 노하우): the line, its date (and app, and where it came from), ✕; then the count and 모두 지우기.
struct ArisNoteList: View {
    @Environment(\.arisPalette) private var palette
    let rows: [ArisNoteRow]
    let footer: String
    let emptyTitle: String
    let emptyDetail: String
    var showsApp = false
    let forget: (String?) -> Void
    var keep: (String) -> Void = { _ in }

    var body: some View {
        Group {
            if rows.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ArisLineIcon("book.closed", size: 18).foregroundStyle(palette.desc).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(emptyTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.title)
                        Text(emptyDetail).font(.system(size: 11.5)).foregroundStyle(palette.desc).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { ArisRowDivider() }
                        noteRow(row)
                    }
                    ArisRowDivider()
                    HStack {
                        Text(footer).font(.system(size: 11.5)).foregroundStyle(palette.ink3)
                        Spacer()
                        ArisSettingsButton(title: ArisTeamCopy.forgetAll, kind: .danger, small: true) { forget(nil) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .arisCard()
    }

    private func noteRow(_ row: ArisNoteRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if showsApp, let app = row.app { ArisChip(text: app) }
                    Text(row.text).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.title).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    if let date = row.date {
                        Text(date.formatted(.dateTime.month(.abbreviated).day().locale(ArisTeamCopy.locale)))
                    }
                    if let by = row.by, showsApp { Text("· " + by) }
                    if row.tainted && !row.needsReview { Text("· " + ArisTeamCopy.learnedFromApp) }
                }
                .font(.system(size: 11.5)).foregroundStyle(palette.desc)
                if row.needsReview {
                    HStack(spacing: 8) {
                        ArisChip(text: ArisTeamCopy.needsReview, tone: .warn)
                        Text(ArisTeamCopy.reviewHint).font(.system(size: 11)).foregroundStyle(palette.desc).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 8)
            if row.needsReview {
                ArisSettingsButton(title: ArisTeamCopy.keepNote, small: true) { keep(row.id) }
            }
            Button { forget(row.id) } label: {
                ArisLineIcon("xmark", size: 13, stroke: 2.25).foregroundStyle(palette.desc)
                    .frame(width: 26, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(ArisPressScale())
            .accessibilityLabel(ArisTeamCopy.forgetOne)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// 앱 노하우: what every brain reads about the user's apps, under the roster.
struct ArisKnowhowSection: View {
    @Environment(\.arisPalette) private var palette
    let rows: [ArisNoteRow]
    let forget: (String?) -> Void
    var keep: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArisSectionTitle(text: ArisTeamCopy.knowhowTitle)
            ArisPageNote(text: ArisTeamCopy.knowhowNote)
            ArisNoteList(rows: rows, footer: ArisTeamCopy.knowhowCount(rows.count), emptyTitle: ArisTeamCopy.knowhowTitle,
                         emptyDetail: ArisTeamCopy.knowhowEmpty, showsApp: true, forget: forget, keep: keep)
                .padding(.top, 4)
        }
        .id(ArisSettingsIndex.teamAnchors[4]).arisFlash(ArisSettingsIndex.teamAnchors[4])
    }
}

/// 말로 팀원 만들기: "문서 정리하는 팀원 하나 만들어줘, 이름은 코디", read the same way as in the notch.
struct ArisTeamMakeByWords: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsStill) private var still
    let make: (String) -> ArisTeammate?
    @State var words = ""
    @State private var result: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ArisLineIcon("wand.and.stars", size: 18).foregroundStyle(palette.accent).frame(width: 24)
                Text(ArisTeamCopy.makeTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.title)
                Spacer()
            }
            HStack(spacing: 8) {
                ArisTextField(placeholder: ArisTeamCopy.makePlaceholder, text: $words, onSubmit: submit)
                ArisSettingsButton(title: ArisTeamCopy.makeButton, kind: .primary, enabled: !words.trimmingCharacters(in: .whitespaces).isEmpty || still,
                                   action: submit)
            }
            Text(result ?? ArisTeamCopy.makeHint).font(.system(size: 11.5)).foregroundStyle(failed ? palette.bad : result != nil ? palette.ok : palette.desc)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .arisCard()
        .id(ArisSettingsIndex.teamAnchors[3]).arisFlash(ArisSettingsIndex.teamAnchors[3])
    }

    private func submit() {
        guard let mate = make(words) else {
            failed = true
            result = ArisTeamCopy.makeNotUnderstood
            return
        }
        failed = false
        result = ArisTeamCopy.made(mate.name)
        words = ""
    }
}
