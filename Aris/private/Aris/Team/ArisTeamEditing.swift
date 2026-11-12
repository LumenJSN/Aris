//
//  ArisTeamEditing.swift
//  Aris
//
//  The settings 팀원 page's rules, pure (Task 11b, the owner's pick C): the roster it lists (main Aris first, fixed), what
//  may be renamed, removed or given another brain, and each edit as a new list. aris-agent checks every save again
//  (ArisTeammateEdit); these only keep the page from offering what it would refuse.
//

import Foundation

enum ArisTeamEditing {
    /// The roster row for main Aris: not a teammate, never stored, never sent.
    static let mainId = "aris"
    static let mainRole = "메인 · 듣고 나눠 주고 모아서 알려 줘요"
    static let newName = "새 팀원"
    /// A teammate the user adds without saying which brain: Codex (only where the main brain isn't known).
    static let newBrain = "codex"

    struct Row: Identifiable, Equatable {
        let id: String
        let name: String
        let role: String
        let look: ArisCharacterLook
        let brain: String
        var isMain: Bool { id == ArisTeamEditing.mainId }
    }

    /// Main Aris (wearing `aris`), then the teammates as stored.
    static func rows(_ teammates: [ArisTeammate], aris: ArisCharacterLook = .main) -> [Row] {
        [Row(id: mainId, name: ArisActivityTab.mainName, role: mainRole, look: aris, brain: "")]
            + teammates.map { Row(id: $0.id, name: $0.name, role: $0.routing, look: $0.look, brain: $0.brain) }
    }

    /// The line under a row's name is the app's own (main Aris's, and Claude Code's as it was seeded), so the settings
    /// say it in the window's language; any other line is what the user wrote, and is shown as written.
    static func isAppLine(_ row: Row) -> Bool {
        row.isMain || (row.id == ArisTeammate.claudeCodeId && row.role == ArisTeammate.claudeCode.routing)
    }

    static func canRemove(_ id: String) -> Bool { id != mainId && id != ArisTeammate.claudeCodeId }
    static func canRename(_ id: String) -> Bool { id != mainId }
    /// Claude Code is Claude; main Aris's brain is the 대화 page's setting.
    static func canChooseBrain(_ id: String) -> Bool { canRemove(id) }

    /// The agent's byte caps (ArisTeammateEdit): a name or role is short text, never a payload.
    static let maxNameBytes = 64
    static let maxRoleBytes = 320
    static let maxInstructionBytes = 2_400

    /// A role while the user types: one line, no tags, no invisible letters (Cc, Cf), at most `ArisTeammate.maxRole` letters
    /// and 160 bytes.
    static func fitRole(_ text: String) -> String {
        let flat = text.components(separatedBy: .newlines).joined(separator: " ")
            .filter { $0 != "<" && $0 != ">" && !isInvisible($0) }
        return prefix(String(flat.prefix(ArisTeammate.maxRole)), bytes: maxRoleBytes)
    }

    /// 어떻게 일할까요 while the user types: lines without tags or invisible letters, at most 800 letters and 2,400 bytes.
    static func fitInstructions(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines).map { $0.filter { $0 != "<" && $0 != ">" && !isInvisible($0) } }
        return prefix(String(lines.joined(separator: "\n").prefix(ArisTeammate.maxInstructions)), bytes: maxInstructionBytes)
    }

    /// A name while the user types: no invisible letters (Cc, Cf: a right-to-left override, a zero width space…), at most
    /// ArisTeammateName's width and 64 bytes, never trimmed (so a space can be typed).
    static func fitName(_ text: String) -> String {
        prefix(ArisTeammateName.fitting(text.filter { !isInvisible($0) }), bytes: maxNameBytes)
    }

    /// What the name field should hold now, or nil to leave it: never while a letter is still being composed (the input
    /// method would lose it); the cap lands once it's done.
    static func composingCap(_ typed: String, composing: Bool) -> String? {
        guard !composing else { return nil }
        let fitted = fitName(typed)
        return fitted == typed ? nil : fitted
    }

    /// A control or format character (Unicode Cc, Cf), as aris-agent refuses them.
    static func isInvisible(_ letter: Character) -> Bool {
        letter.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// The longest run of whole letters within `bytes` of UTF-8.
    private static func prefix(_ text: String, bytes: Int) -> String {
        var used = 0
        return String(text.prefix { letter in
            used += letter.utf8.count
            return used <= bytes
        })
    }

    struct BrainChoice: Equatable {
        let brain: String
        let title: String
        /// Set up on this Mac (aris-agent's answer, ArisTeamBrains); one that isn't shows 로그인 필요 and its login.
        let ready: Bool
    }

    /// The 두뇌 choices for a teammate other than Claude Code: every brain, each pickable; `ready` says which are set up
    /// on this Mac (none known yet: all are taken as ready, so nothing flashes 로그인 필요 while the list loads).
    static func brainChoices(for id: String, ready: [String: Bool] = [:]) -> [BrainChoice] {
        ArisBrain.allCases.map { brain in
            BrainChoice(brain: brain.rawValue, title: brain.shortTitle, ready: ready[brain.rawValue] ?? true)
        }
    }

    /// Six random lowercase letters or digits.
    static func randomSuffix() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    /// The list with a new teammate at the end, from `template` (빈 팀원 by default): its name ("새 팀원" or the
    /// template's, numbered when taken), its routing, instructions and scopes, `brain` (the main brain), the template's
    /// face unless someone has it (then a type no one has yet; never the one Aris wears), and an id of its own that no
    /// teammate ever had (mate-<random>, drawn again on a clash): a removed teammate's memory file and activity rows never
    /// pass to a new one.
    static func adding(to teammates: [ArisTeammate], aris: ArisCharacterLook = .main, template: ArisTeamTemplate = .blank,
                       brain: String = newBrain, name wanted: String? = nil,
                       suffix: () -> String = randomSuffix) -> [ArisTeammate] {
        let ids = Set(teammates.map(\.id)), names = Set(teammates.map { $0.name.lowercased() })
        var id = "mate-" + suffix()
        while ids.contains(id) || !ArisTeammate.isValidId(id) { id = "mate-" + suffix() }
        let base = wanted.flatMap { ArisTeammateName.validate(fitName($0)) } ?? template.name
        let name = !names.contains(base.lowercased()) ? base : numbered(base, taken: names)
        let used = Set(teammates.map(\.look.type))
        let pickable = ArisFace.pickableTypes(aris: aris.type)
        let type = template.id != ArisTeamTemplate.blank.id && pickable.contains(template.type) && !used.contains(template.type) ? template.type : pickable.first { !used.contains($0) } ?? pickable[0]
        let look = ArisCharacterLook(type: type, colorHex: nil, shading: ArisCharacterLook.standard.shading)
        let brain = ArisBrain.allCases.contains { $0.rawValue == brain } ? brain : newBrain
        return teammates + [ArisTeammate(id: id, name: name, routing: template.routing, instructions: template.instructions, look: look, brain: brain,
                                         scopes: template.scopes, memoryFile: "teammates/\(id).md")]
    }

    /// `base` with the first number no teammate has ("새 팀원 2"), the base cut so the whole still fits a chip. There are
    /// at most 12 teammates, so a free number comes within 13 tries.
    static func numbered(_ base: String, taken: Set<String>) -> String {
        for number in 2...(maxTeammates + 2) {
            let suffix = " \(number)"
            let room = ArisTeammateName.limit - ArisTeammateName.width(suffix)
            var used = 0
            let cut = String(base.prefix { letter in used += ArisTeammateName.width(String(letter)); return used <= room })
            let candidate = cut.trimmingCharacters(in: .whitespaces) + suffix
            if !taken.contains(candidate.lowercased()) { return candidate }
        }
        return base
    }

    /// What's wrong with `name` for teammate `id` (the agent refuses the same), or nil when it may be saved.
    static func nameProblem(_ name: String, id: String, in teammates: [ArisTeammate]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // Before trimming, which would drop a zero width space at either end without a word.
        if name.contains(where: isInvisible) { return "이름에는 보이지 않는 글자를 쓸 수 없어요." }
        if trimmed.isEmpty { return "이름을 적어 주세요." }
        if trimmed.contains("<") || trimmed.contains(">") { return "이름에는 <, >를 쓸 수 없어요." }
        if ArisTeammateName.width(trimmed) > ArisTeammateName.limit || trimmed.utf8.count > maxNameBytes { return "이름은 한글 6자(영문 12자)까지예요." }
        if ["aris", "아리스"].contains(trimmed.lowercased()) { return "Aris는 메인의 이름이에요." }
        if teammates.contains(where: { $0.id != id && $0.name.lowercased() == trimmed.lowercased() }) { return "같은 이름의 팀원이 있어요." }
        return nil
    }

    /// The agent's refusal of a save (ArisTeammateEdit.Problem), as the page says it.
    static func problemText(_ code: String) -> String {
        switch code {
        case "name": "이름은 한글 6자(영문 12자)까지예요."
        case "duplicateName": "같은 이름의 팀원이 있어요."
        case "role": "언제 부를지는 80자까지, 한 줄로 적어 주세요."
        case "instructions": "일하는 방법은 800자까지, <, > 없이 적어 주세요."
        case "scopes": "쓸 수 있는 것을 다시 골라 주세요."
        case "look": "그 캐릭터는 고를 수 없어요."
        case "brain": "그 두뇌는 쓸 수 없어요."
        case "tooMany": "팀원은 \(maxTeammates)명까지예요."
        default: "팀원 목록을 저장하지 못했어요."
        }
    }

    /// The agent keeps at most this many (Claude Code included; ArisTeammateEdit.maxTeammates).
    static let maxTeammates = 12

    static func replacing(_ teammate: ArisTeammate, in teammates: [ArisTeammate]) -> [ArisTeammate] {
        teammates.map { $0.id == teammate.id ? teammate : $0 }
    }

    static func removing(_ id: String, from teammates: [ArisTeammate]) -> [ArisTeammate] {
        canRemove(id) ? teammates.filter { $0.id != id } : teammates
    }
}

/// Edits to the teammate list counted (N17): a read that started before an edit is older than what shows, so it is
/// dropped instead of putting back a list the next edit would then save over the first one.
struct ArisEditStamp: Equatable {
    private(set) var now = 0

    mutating func edit() { now += 1 }

    /// Whether a read taken at `stamp` may still be shown (no edit since).
    func isCurrent(_ stamp: Int) -> Bool { stamp == now }
}
