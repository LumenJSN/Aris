//
//  ArisTeamPage.swift
//  Aris
//
//  The settings 팀원 page, the owner's pick A (mockups/teammates, 목록 + 인스펙터): 말로 팀원 만들기 at the top, then the
//  roster on the left (main Aris first; then the teammates; then 팀원 추가 with its templates) and every section of the
//  picked one on the right (ArisTeammateInspector), or, for Aris, its face (ArisFaceDetail); 앱 노하우 under them.
//  Every change shows at once and is saved through aris-agent (ArisTeamModel). Drawn in the settings window's own cards
//  and controls; faces come from the window's art (the baked sprites).
//

import AppKit
import SwiftUI

/// Whether the team list has been read from aris-agent.
enum ArisTeamLoad: Equatable { case loading, ready, unavailable }

/// Where the page reads and saves the team (ArisTeamModel; a stand-in for the offscreen renders).
@MainActor
protocol ArisTeamSource: ObservableObject {
    var teammates: [ArisTeammate] { get }
    var load: ArisTeamLoad { get }
    var notice: String? { get }
    /// Which brains are set up on this Mac (empty: not known yet).
    var brains: [String: Bool] { get }
    var notes: [String: [ArisNoteRow]] { get }
    var knowhow: [ArisNoteRow] { get }
    func apply(_ list: [ArisTeammate])
    func refresh()
    func refreshExtras()
    func loadNotes(_ id: String)
    func forgetNote(_ id: String, note: String?)
    func forgetKnowhow(_ note: String?)
    func login(_ brain: String)
    func keep(_ note: String, teammate: String?)
    /// The teammate to open on (수정 on the notch's made card), once.
    func takeOpenOn() -> String?
}



struct ArisTeamPage<Source: ArisTeamSource>: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @ObservedObject private var team: Source
    @State private var selected: String
    /// Aris's face (ArisFace), read live.
    @AppStorage(ArisFace.key, store: ArisFace.store) private var arisFace = ""
    /// The last face change's move of a teammate off the face Aris took, until Aris picks another type.
    @State private var moved: ArisFaceDetail.Moved?
    /// The template menu under 팀원 추가.
    @State private var menu: Bool
    /// The main brain, for teammates made here.
    let mainBrain: String

    /// `selected`: the row shown first (main Aris; a preview may open on a teammate); `moved`: a notice already up;
    /// `menu`: the template menu open (the offscreen renders).
    init(team: Source, selected: String = ArisTeamEditing.mainId, moved: ArisFaceDetail.Moved? = nil, menu: Bool = false,
         mainBrain: String = ArisTeamEditing.newBrain) {
        self.team = team
        self.mainBrain = mainBrain
        _selected = State(initialValue: selected)
        _moved = State(initialValue: moved)
        _menu = State(initialValue: menu)
    }

    /// The mockup's 200-wide roster, 12 apart from the inspector.
    private static var rosterWidth: CGFloat { 200 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArisPageNote(text: ArisTeamCopy.pageNote).modifier(ArisRise(index: 2))
            ArisTeamMakeByWords(make: makeFromWords).padding(.top, 12).modifier(ArisRise(index: 3))
            HStack(alignment: .top, spacing: 12) {
                roster.frame(width: Self.rosterWidth).id(ArisSettingsIndex.teamAnchors[0]).arisFlash(ArisSettingsIndex.teamAnchors[0])
                detail.frame(maxWidth: .infinity).id(ArisSettingsIndex.teamAnchors[1]).arisFlash(ArisSettingsIndex.teamAnchors[1])
            }
            .padding(.top, 12)
            .modifier(ArisRise(index: 4))
            ArisKnowhowSection(rows: team.knowhow, forget: team.forgetKnowhow, keep: { team.keep($0, teammate: nil) }).padding(.top, 22).modifier(ArisRise(index: 5))
        }
        .onAppear {
            team.refresh()
            team.refreshExtras()
            if let open = team.takeOpenOn() { selected = open }
        }
    }

    private var face: ArisCharacterLook { ArisFace.decode(arisFace) }

    private var rows: [ArisTeamEditing.Row] { ArisTeamEditing.rows(team.teammates, aris: face) }

    /// Aris wears `look` from now on; a teammate wearing its type moves (saved with the list), and the page says so.
    private func wear(_ look: ArisCharacterLook) {
        let before = face
        ArisFace.set(look)
        let now = ArisFace.current
        guard now.type != before.type else { return }
        let change = ArisFace.moving(team.teammates, to: now)
        if !change.moved.isEmpty { team.apply(change.team) }
        moved = change.moved.first.map { ArisFaceDetail.Moved(id: $0.id, text: ArisFace.notice(moved: $0, aris: now.type), action: ArisFace.noticeAction(moved: $0)) }
    }

    /// 말로 팀원 만들기: the same reading as the notch's; the new one is picked. Nil when the words weren't understood.
    private func makeFromWords(_ words: String) -> ArisTeammate? {
        guard team.load == .ready, let request = ArisTeamMaking.parse(words),
              let mate = ArisTeamMaking.make(request, in: team.teammates, aris: face, brain: mainBrain) else { return nil }
        team.apply(team.teammates + [mate])
        selected = mate.id
        return mate
    }

    // MARK: roster

    private var roster: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                ArisTeamRow(row: row, selected: row.id == selected, needsLogin: needsLogin(row)) { selected = row.id }
            }
            if team.load == .loading && team.teammates.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(ArisTeamCopy.loading).font(.system(size: 12)).foregroundStyle(palette.desc)
                }
                .padding(.horizontal, 10).padding(.vertical, 10)
            } else if team.load == .ready {
                addRow
            }
        }
        .padding(6)
        .arisCard()
        .overlay(alignment: .topLeading) {
            if menu {
                ArisTemplateMenu(aris: face) { template in
                    menu = false
                    let list = ArisTeamEditing.adding(to: team.teammates, aris: face, template: template, brain: mainBrain)
                    team.apply(list)
                    if let fresh = list.last { selected = fresh.id }
                }
                .offset(x: Self.rosterWidth - 14, y: 0)
                .zIndex(2)
            }
        }
        .zIndex(menu ? 2 : 0)
    }

    private func needsLogin(_ row: ArisTeamEditing.Row) -> Bool {
        !row.isMain && row.id != ArisTeammate.claudeCodeId && team.brains[row.brain] == false
    }

    private var addRow: some View {
        let full = team.teammates.count >= ArisTeamEditing.maxTeammates
        return Button { menu.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 30)
                Text(ArisTeamCopy.add).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.desc)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(ArisPressStyle())
        .disabled(full)
        .opacity(full ? 0.4 : 1)
        .help(ArisTeamCopy.add)
    }

    // MARK: detail

    /// An edit applied to the teammate as stored now (a draft saved late never undoes a pick made meanwhile).
    private func update(_ id: String, _ edit: (ArisTeammate) -> ArisTeammate) {
        guard let current = team.teammates.first(where: { $0.id == id }) else { return }
        let next = edit(current)
        guard next != current else { return }
        team.apply(ArisTeamEditing.replacing(next, in: team.teammates))
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if team.load == .unavailable {
                VStack(alignment: .leading, spacing: 8) {
                    ArisPageNote(text: ArisTeamCopy.unavailable)
                    ArisSettingsButton(title: ArisTeamCopy.reload) { team.refresh() }
                }
                .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20)).arisCard()
            } else if let row = rows.first(where: { $0.id == selected }) ?? rows.first {
                if let mate = team.teammates.first(where: { $0.id == row.id }) {
                    ArisTeammateInspector(mate: mate, others: team.teammates, aris: face, brains: team.brains, notes: team.notes[mate.id] ?? [],
                                          update: update, login: team.login, forget: { team.forgetNote(mate.id, note: $0) },
                                          keep: { team.keep($0, teammate: mate.id) }) {
                        team.apply(ArisTeamEditing.removing(mate.id, from: team.teammates))
                        selected = ArisTeamEditing.mainId
                    }
                    // A teammate's drafts are its own: switching rows starts fresh.
                    .id(mate.id)
                    .onAppear { team.loadNotes(mate.id) }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ArisFaceDetail(row: row, face: face, moved: moved, wear: wear) { selected = $0 }
                        Text(ArisTeamCopy.arisOnlyFace).font(.system(size: 11.5)).foregroundStyle(palette.ink3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .arisCard()
                }
            }
            if let notice = team.notice {
                Text(w(notice)).font(.system(size: 12)).foregroundStyle(palette.bad).padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A roster row (mockup `.mrow`): the still face, the name, 언제 부를까요 (up to three lines when one isn't enough: in
/// English Aris's own line ended in "han…"), and an orange dot when its brain isn't set up here.
private struct ArisTeamRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsArt) private var art
    let row: ArisTeamEditing.Row
    let selected: Bool
    var needsLogin = false
    let pick: () -> Void
    @State private var hovering = false

    /// The line under the name: Aris's own and Claude Code's seeded one are the app's (said in the page's wording), any
    /// other is what the user wrote.
    private var role: String { ArisTeamEditing.isAppLine(row) ? w(row.role) : row.role }

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 10) {
                art.face(row.look, 30, true).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ArisTeammateName.display(row.name)).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.title)
                    Text(row.role.isEmpty ? ArisTeamCopy.noWhenYet : role).font(.system(size: 12)).foregroundStyle(palette.desc)
                        .lineLimit(3).truncationMode(.tail).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if needsLogin {
                    Circle().fill(palette.warn).frame(width: 7, height: 7).help(ArisTeamCopy.loginNeeded)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? palette.rowSelected : hovering ? palette.rowHover : .clear))
            // Hover and selection are colour changes: plain ease, 140 ms (emil-design-eng).
            .animation(.easeInOut(duration: 0.14), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(ArisPressScale())
        .onHover { hovering = $0 }
        .accessibilityLabel(row.role.isEmpty ? row.name : "\(row.name), \(role)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 팀원 추가's menu (mockup `.tplmenu`): the five templates, each with its face and its 언제 부를까요.
private struct ArisTemplateMenu: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsArt) private var art
    let aris: ArisCharacterLook
    let pick: (ArisTeamTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ArisTeamTemplate.all) { template in
                Button { pick(template) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        art.face(ArisCharacterLook(type: template.type, colorHex: nil, shading: "fabric"), 28, true).frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.title)
                            Text(template.line).font(.system(size: 11.5)).foregroundStyle(palette.desc).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ArisPressStyle())
            }
        }
        .padding(6)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.modal)
            .shadow(color: .black.opacity(palette.dark ? 0.45 : 0.14), radius: 18, y: 8))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.modalBorder, lineWidth: 1))
    }
}
