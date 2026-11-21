//
//  ArisModelChoiceSection.swift
//  Aris
//
//  모델 고르기 under the 생각 card (ArisModelChoiceRows): a card of the settings' own rows, each role with the window's one
//  dropdown (ArisMenuButton) for its model and its 추론 수준, the typed-id field under a role set to 직접 입력, and 고급
//  folded with the window's fold row. Self-contained, so it can move with a reorganised page: it reads the brain and the
//  choices itself, and the window only passes the dropdowns' picks to `choose` (ArisSettingKey.modelChoice).
//

import Defaults
import SwiftUI

@MainActor
final class ArisModelChoiceModel: ObservableObject {
    static let shared = ArisModelChoiceModel()

    @Published private(set) var choices = ArisModelChoices.automatic
    @Published private(set) var lists = ArisModelLists()
    @Published var advanced = false
    /// The roles set to 직접 입력, with what is typed so far.
    @Published private(set) var typing: Set<ArisModelRole> = []
    @Published var drafts: [ArisModelRole: String] = [:]
    /// The line under a role's field: why its id wasn't taken, or that it's being checked.
    @Published private(set) var lines: [ArisModelRole: (text: String, bad: Bool)] = [:]
    private var refreshing: Set<ArisBrain> = []
    private let store = ArisModelChoiceStore.shared

    /// The section shows: the saved state, and the brain's list read again in the background when it is a day old.
    func appear(_ brain: ArisBrain) {
        choices = store.saved
        lists = store.lists
        guard ArisModelChoiceRows.offered(brain), lists.needsRefresh(brain, now: Date()), !refreshing.contains(brain) else { return }
        refreshing.insert(brain)
        Task {
            let found = await ArisAgentClient.models(brain)
            refreshing.remove(brain)
            guard let found else { return }
            let next = store.lists.storing(brain, options: found.options, fromTool: found.fromTool, at: Date())
            store.store(next)
            lists = next
        }
    }

    /// A dropdown's pick (ArisSettingKey.modelChoice: "claude.conversation.model").
    func choose(_ key: String, _ value: String) {
        guard let parts = ArisModelChoices.parts(key) else { return }
        let (brain, role, field) = parts
        if field == .model, value == ArisModelChoiceRows.custom {
            typing.insert(role)
            drafts[role] = drafts[role] ?? choices.choice(brain, role).model ?? ""
            lines[role] = nil
            return
        }
        if field == .model { typing.remove(role); lines[role] = nil }
        store.choose(brain, role, field, value == ArisModelChoiceRows.auto ? nil : value)
        choices = store.saved
    }

    /// 확인 (or Return) in a role's field: the id is tried with the brain's tool and saved only when it takes it.
    func commit(_ brain: ArisBrain, _ role: ArisModelRole) {
        let id = (drafts[role] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard ArisModelChoices.isModelID(id) else {
            lines[role] = (ArisModelChoiceRows.badShape, true)
            return
        }
        lines[role] = (ArisModelChoiceRows.checking, false)
        Task {
            let problem = await ArisAgentClient.checkModel(id, brain: brain)
            if let problem {
                lines[role] = (problem, true)
                return
            }
            lines[role] = nil
            typing.remove(role)
            store.choose(brain, role, .model, id)
            choices = store.saved
        }
    }
}

struct ArisModelChoiceSection: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Default(.arisBrain) private var brainName
    @ObservedObject var model = ArisModelChoiceModel.shared
    /// Which AIs' tools are on this Mac: the footer says one isn't installed rather than that it gave no list.
    @ObservedObject private var brainSetup = ArisBrainSetup.shared

    var body: some View {
        let brain = ArisBrain.named(brainName)
        if ArisModelChoiceRows.offered(brain) {
            let rows = ArisModelChoiceRows.rows(brain, choices: model.choices, lists: model.lists, advanced: false, typing: model.typing)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.role) { index, row in
                        if index > 0 { ArisInsetHairline() }
                        roleRow(row, brain: brain, first: index == 0)
                    }
                    ArisInsetHairline()
                    ArisFoldRow(symbol: "slider.horizontal.3", title: ArisModelChoiceRows.advancedTitle, desc: ArisModelChoiceRows.advancedDesc,
                                open: model.advanced) { model.advanced.toggle() }
                    if model.advanced {
                        Rectangle().fill(palette.hairline).frame(height: 1)
                        roleRow(ArisModelChoiceRows.row(brain, .helper, choices: model.choices, lists: model.lists, typing: model.typing.contains(.helper)),
                                brain: brain, first: false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .arisCard()
                Text(ArisModelChoiceRows.footer(brain, lists: model.lists, installed: brainSetup.ready?[brain], wording: w))
                    .font(.system(size: 12)).foregroundStyle(palette.ink3).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8).padding(.horizontal, 4)
            }
            .onAppear { model.appear(brain) }
            .onChange(of: brainName) { _, name in model.appear(ArisBrain.named(name)) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(w(ArisModelChoiceRows.heading))
        }
    }

    /// A role: the icon column (the card's first row only), its name and line, the model's and the effort's dropdowns;
    /// under it, the field while it is set to 직접 입력.
    @ViewBuilder
    private func roleRow(_ row: ArisModelChoiceRows.Row, brain: ArisBrain, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: ArisSettingsMetrics.iconGap) {
                Group {
                    if first { ArisLineIcon("cpu", size: 20).foregroundStyle(palette.icon) } else { Color.clear }
                }
                .frame(width: ArisSettingsMetrics.iconBox, height: ArisSettingsMetrics.iconBox)
                VStack(alignment: .leading, spacing: 2) {
                    Text(w(row.role.title)).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.title)
                    Text(w.dotted(row.role.detail)).font(.system(size: 12)).foregroundStyle(palette.desc).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    ArisMenuButton(key: .modelChoice(row.modelKey), title: row.role.title, options: row.models, selected: row.model)
                    if let effortKey = row.effortKey {
                        ArisMenuButton(key: .modelChoice(effortKey), title: ArisModelChoiceRows.effortLabel, options: row.efforts, selected: row.effort)
                    }
                }
            }
            if model.typing.contains(row.role) { field(row.role, brain: brain) }
        }
        .padding(ArisSettingsMetrics.rowInset)
    }

    private func field(_ role: ArisModelRole, brain: ArisBrain) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ArisTextField(placeholder: ArisModelChoiceRows.fieldHint, text: Binding(get: { model.drafts[role] ?? "" }, set: { model.drafts[role] = $0 })) {
                    model.commit(brain, role)
                }
                ArisSettingsButton(title: ArisModelChoiceRows.checkButton, small: true) { model.commit(brain, role) }
            }
            if let line = model.lines[role] {
                Text(w(line.text)).font(.system(size: 12)).foregroundStyle(line.bad ? palette.red : palette.desc).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, ArisSettingsMetrics.iconBox + ArisSettingsMetrics.iconGap)
    }
}
