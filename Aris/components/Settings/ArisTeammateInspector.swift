//
//  ArisTeammateInspector.swift
//  Aris
//
//  The 팀원 page's inspector (layout A): every section of one teammate, each under its small heading — 이름과 얼굴,
//  언제 부를까요 (with the "이 말이면 누가 맡을까요?" test line), 어떻게 일할까요, 두뇌, 쓸 수 있는 것, 기억 — then
//  "바꾸면 바로 저장돼요" and 팀원 빼기. Names, routing lines and instructions are drafts: capped as the user types, saved a
//  moment after he stops (and when he leaves the field or the row).
//

import AppKit
import SwiftUI

struct ArisTeammateInspector: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    @Environment(\.arisSettingsArt) private var art
    let mate: ArisTeammate
    let others: [ArisTeammate]
    /// Aris's face: its type is never offered here.
    let aris: ArisCharacterLook
    let brains: [String: Bool]
    let notes: [ArisNoteRow]
    let update: (String, (ArisTeammate) -> ArisTeammate) -> Void
    let login: (String) -> Void
    let forget: (String?) -> Void
    var keep: (String) -> Void = { _ in }
    let remove: () -> Void

    @State private var name: String
    @State private var routing: String
    @State private var instructions: String
    @State private var probe = ""
    @State private var commit: Task<Void, Never>?
    @FocusState private var focus: Field?

    private enum Field { case name, routing, instructions, probe }

    init(mate: ArisTeammate, others: [ArisTeammate], aris: ArisCharacterLook, brains: [String: Bool], notes: [ArisNoteRow],
         update: @escaping (String, (ArisTeammate) -> ArisTeammate) -> Void, login: @escaping (String) -> Void,
         forget: @escaping (String?) -> Void, keep: @escaping (String) -> Void = { _ in }, remove: @escaping () -> Void, probe: String = "") {
        self.mate = mate
        self.others = others
        self.aris = aris
        self.brains = brains
        self.notes = notes
        self.update = update
        self.login = login
        self.forget = forget
        self.keep = keep
        self.remove = remove
        _name = State(initialValue: mate.name)
        _routing = State(initialValue: mate.routing)
        _instructions = State(initialValue: mate.instructions)
        _probe = State(initialValue: probe)
    }

    private static let settle: Duration = .milliseconds(600)
    private var isClaudeCode: Bool { mate.id == ArisTeammate.claudeCodeId }
    private var nameProblem: String? { ArisTeamEditing.nameProblem(name, id: mate.id, in: others) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading(ArisTeamCopy.sectionWho, first: true)
            identity.padding(18).arisCard()
            heading(ArisTeamCopy.sectionWhen)
            whenCard.padding(18).arisCard()
            heading(ArisTeamCopy.sectionHow)
            howCard.padding(18).arisCard()
            heading(ArisTeamCopy.sectionBrain)
            ArisBrainPicker(mate: mate, brains: brains, pick: { brain in update(mate.id) { with($0) { $0.brain = brain } } }, login: login)
            heading(ArisTeamCopy.sectionScopes)
            if isClaudeCode {
                Text(ArisTeamCopy.ccScopes).font(.system(size: 12)).foregroundStyle(palette.desc).padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading).arisCard()
            } else {
                ArisScopeSwitches(scopes: mate.scopeSet, brain: mate.brain) { scope in
                    update(mate.id) { current in
                        with(current) { mate in
                            let set = mate.scopeSet
                            mate.scopes = ArisTeammateScope.canonical((set.contains(scope) ? set.subtracting([scope]) : set.union([scope])).map(\.rawValue))
                        }
                    }
                }
            }
            heading(ArisTeamCopy.sectionMemory)
            ArisNoteList(rows: notes, footer: ArisTeamCopy.notesCount(notes.count), emptyTitle: ArisTeamCopy.memoryEmptyTitle,
                         emptyDetail: ArisTeamCopy.memoryEmptyDetail, forget: forget, keep: keep)
            HStack {
                Text(ArisTeamCopy.savesAtOnce).font(.system(size: 11)).foregroundStyle(palette.ink3)
                Spacer(minLength: 8)
                if ArisTeamEditing.canRemove(mate.id) {
                    ArisSettingsButton(title: ArisTeamCopy.remove, kind: .danger, small: true) {
                        ArisSettingsOverlay.shared.removal = (mate.name, remove)
                        ArisSettingsOverlay.shared.sheet = .removeMate
                    }
                }
            }
            .padding(.top, 14)
        }
        .onChange(of: focus) { old, new in if old != nil && old != new { save() } }
        .onDisappear { save(force: true) }
    }

    private func heading(_ text: String, first: Bool = false) -> some View {
        Text(text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(palette.desc)
            .padding(.top, first ? 0 : 16).padding(.bottom, 8).padding(.leading, 2)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: 이름과 얼굴

    private var identity: some View {
        HStack(alignment: .top, spacing: 16) {
            art.face(mate.look, 64, true).frame(width: 64, height: 64).padding(10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.tile))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                label(ArisTeamCopy.name)
                field(ArisTeamCopy.name, text: $name, field: .name, enabled: ArisTeamEditing.canRename(mate.id))
                    .onChange(of: name) { _, typed in edited(ArisTeamEditing.composingCap(typed, composing: Self.composing)) { name = $0 } }
                if let nameProblem {
                    Text(w(nameProblem)).font(.system(size: 11)).foregroundStyle(palette.bad)
                }
                ArisCharacterPicker(look: mate.look, types: faces, layout: Self.compact) { look in update(mate.id) { with($0) { $0.look = look } } }
                    .padding(.top, 6)
                    .id(ArisSettingsIndex.teamAnchors[2]).arisFlash(ArisSettingsIndex.teamAnchors[2], radius: 12)
            }
        }
    }

    /// The mockup's face row: the six teammate faces (never the one Aris wears), and the one it has if that's another.
    private var faces: [String] {
        let six = ArisCharacterLook.teammateTypes.filter { $0 != aris.type }
        return six.contains(mate.look.type) ? six : six + [mate.look.type]
    }

    /// Faces in one row of six, then the colours; no 질감 (always fabric, as the mockup).
    private static let compact = ArisCharacterPicker.Layout(heading: ArisTeamCopy.face, tile: 40, character: 28, columns: 6, gap: 6, colorTop: 12,
                                                              shadings: false, colorTile: 30, colorColumns: 8, colorCharacter: 20)

    // MARK: 언제 부를까요

    private var whenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            area(ArisTeamCopy.whenPlaceholder, text: $routing, field: .routing, height: 52)
                .onChange(of: routing) { _, typed in
                    let fitted = ArisTeamEditing.fitRole(typed)
                    edited(Self.composing || fitted == typed ? nil : fitted) { routing = $0 }
                }
            Text(ArisTeamCopy.whenHint).font(.system(size: 11.5)).foregroundStyle(palette.desc).fixedSize(horizontal: false, vertical: true)
            probeLine.padding(.top, 6)
        }
    }

    /// "이 말이면 누가 맡을까요?": the same choice main Aris is hinted with (ArisTeamRouting.bestMatch).
    private var probeLine: some View {
        let team = others.map { $0.id == mate.id ? with($0) { $0.routing = routing } : $0 }
        let hit = probe.isEmpty ? nil : ArisTeamRouting.bestMatch(probe, teammates: team)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(ArisTeamCopy.probeLabel, systemImage: "arrow.triangle.branch").font(.system(size: 12)).foregroundStyle(palette.desc)
                    .labelStyle(.titleAndIcon).fixedSize()
                field(ArisTeamCopy.probePlaceholder, text: $probe, field: .probe)
            }
            if let hit {
                HStack(spacing: 6) {
                    art.face(hit.look, 18, true).frame(width: 18, height: 18)
                    Text(ArisTeamCopy.takes(hit.name) + (hit.id == mate.id ? "" : " · " + ArisTeamCopy.probeNotThis))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(palette.title)
                }
            } else if !probe.isEmpty {
                Text(ArisTeamCopy.probeNobody).font(.system(size: 12)).foregroundStyle(palette.desc)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.soft))
    }

    // MARK: 어떻게 일할까요

    private var howCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            area(ArisTeamCopy.howPlaceholder, text: $instructions, field: .instructions, height: 120)
                .onChange(of: instructions) { _, typed in
                    let fitted = ArisTeamEditing.fitInstructions(typed)
                    edited(Self.composing || fitted == typed ? nil : fitted) { instructions = $0 }
                }
            HStack {
                Text(ArisTeamCopy.howHint).font(.system(size: 11.5)).foregroundStyle(palette.desc)
                Spacer()
                Text(ArisTeamCopy.count(instructions.count, of: ArisTeammate.maxInstructions)).font(.system(size: 11.5)).monospacedDigit()
                    .foregroundStyle(palette.ink3)
            }
        }
    }

    // MARK: pieces

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(palette.desc)
    }

    @ViewBuilder
    private func field(_ prompt: String, text: Binding<String>, field: Field, enabled: Bool = true) -> some View {
        if still {
            Text(text.wrappedValue.isEmpty ? prompt : text.wrappedValue).foregroundStyle(text.wrappedValue.isEmpty ? palette.ink3 : palette.title)
                .frame(maxWidth: .infinity, alignment: .leading).modifier(ArisFieldStyle(focused: false))
        } else {
            TextField(prompt, text: text)
                .focused($focus, equals: field)
                .onSubmit { save() }
                .disabled(!enabled)
                .modifier(ArisFieldStyle(focused: focus == field))
                .accessibilityLabel(prompt)
        }
    }

    /// A multi-line field in the window's field style (r12, the focus ring).
    @ViewBuilder
    private func area(_ prompt: String, text: Binding<String>, field: Field, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Group {
            if still {
                Text(text.wrappedValue.isEmpty ? prompt : text.wrappedValue).font(.system(size: 13)).lineSpacing(4)
                    .foregroundStyle(text.wrappedValue.isEmpty ? palette.ink3 : palette.title)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.horizontal, 12).padding(.vertical, 10)
            } else {
                ZStack(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(prompt).font(.system(size: 13)).foregroundStyle(palette.ink3).padding(.horizontal, 12).padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: text).font(.system(size: 13)).foregroundStyle(palette.title).scrollContentBackground(.hidden)
                        .lineSpacing(4).padding(.horizontal, 7).padding(.vertical, 6)
                        .focused($focus, equals: field)
                        .accessibilityLabel(prompt)
                }
            }
        }
        .frame(height: height)
        .background(shape.fill(palette.field))
        .overlay(shape.strokeBorder(focus == field ? palette.fieldFocus : palette.fieldBorder, lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(focus == field ? palette.fieldRing : .clear, lineWidth: 2).padding(-2))
    }

    private func edited(_ capped: String?, keep: (String) -> Void) {
        if let capped { return keep(capped) }
        scheduleSave()
    }

    private func scheduleSave() {
        commit?.cancel()
        commit = Task {
            try? await Task.sleep(for: Self.settle)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private static var composing: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    /// The drafts, capped and written back first (unchanged ones send nothing). A name that may not be saved (empty, a
    /// duplicate) keeps the stored one, but 언제 부를까요 and 어떻게 일할까요 are saved all the same, so leaving the row
    /// never drops them (bug hunt 2026-11-08). While a letter is still being composed it waits for it (`force`: the row
    /// is going away, save now).
    private func save(force: Bool = false) {
        commit?.cancel()
        if Self.composing && !force { return scheduleSave() }
        let fittedName = ArisTeamEditing.fitName(name), fittedRouting = ArisTeamEditing.fitRole(routing)
        let fittedHow = ArisTeamEditing.fitInstructions(instructions)
        if fittedName != name { name = fittedName }
        if fittedRouting != routing { routing = fittedRouting }
        if fittedHow != instructions { instructions = fittedHow }
        let validName = ArisTeamEditing.nameProblem(fittedName, id: mate.id, in: others) == nil ? ArisTeammateName.validate(fittedName) : nil
        let line = fittedRouting.trimmingCharacters(in: .whitespaces)
        let how = ArisTeammate.instructionsText(fittedHow)
        update(mate.id) { with($0) { if let validName { $0.name = validName }; $0.routing = line; $0.instructions = how } }
    }

    private func with(_ mate: ArisTeammate, _ change: (inout ArisTeammate) -> Void) -> ArisTeammate {
        var next = mate
        change(&next)
        return next
    }
}
