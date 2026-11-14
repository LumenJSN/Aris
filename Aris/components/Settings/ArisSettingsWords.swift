//
//  ArisSettingsWords.swift
//  Aris
//
//  The settings window's small sentences: Korean particles that follow the last syllable (강조 색을, 알림 효과음을),
//  the notch preview's caption after a change, and a shortcut split into key caps. Foundation only (tested).
//

import Foundation

enum ArisParticle {
    case eulReul, iGa, eunNeun, euroRo

    fileprivate var forms: (closed: String, open: String) {
        switch self {
        case .eulReul: ("을", "를")
        case .iGa: ("이", "가")
        case .eunNeun: ("은", "는")
        case .euroRo: ("으로", "로")
        }
    }

    /// Latin letters and digits read with a final consonant in Korean (L, M, N; 0 영, 1 일, 3 삼, 6 육, 7 칠, 8 팔).
    private static let closedTails = Set("lmnLMN013678")

    /// `word` and the particle its last sound takes. 으로/로: a word ending in ㄹ takes 로 (서울로).
    static func attach(_ word: String, _ particle: ArisParticle) -> String {
        let trimmed = word.trimmingCharacters(in: CharacterSet.letters.union(.decimalDigits).inverted)
        guard let last = trimmed.unicodeScalars.last else { return word + particle.forms.open }
        let closed: Bool
        if (0xAC00...0xD7A3).contains(last.value) {
            let tail = (last.value - 0xAC00) % 28
            closed = tail != 0 && !(particle == .euroRo && tail == 8)
        } else {
            // L, 1 (일), 7 (칠) and 8 (팔) end in ㄹ.
            closed = closedTails.contains(Character(last)) && !(particle == .euroRo && "lL178".contains(Character(last)))
        }
        return word + (closed ? particle.forms.closed : particle.forms.open)
    }
}

enum ArisSettingsCaption {
    /// What the notch preview says after a change: "알림 효과음을 켰어요", "강조 색을 바꿨어요".
    static func changed(_ title: String, on: Bool?) -> String {
        let object = ArisParticle.attach(title, .eulReul)
        guard let on else { return "\(object) 바꿨어요" }
        return "\(object) \(on ? "켰어요" : "껐어요")"
    }

    /// The line under Aris's name in the sidebar: what needs the user, or that all is well. `noAI`: the agent answered and
    /// no AI is set up on this Mac (fresh install F2: it said 모두 잘 되고 있어요 while nothing could answer).
    /// `missing`: what the install itself lacks (ArisPrerequisites). A helper that isn't installed comes first, since
    /// no restart brings it back.
    /// The order (final check on a new Mac): a helper that is not answering comes first, since nothing else can be
    /// known or fixed without it (with no AI the line never reported a stopped helper); then permissions; then the AI.
    /// `aiUnchecked`: no AI can answer, but a key is saved that has never answered: said as that, with a press that
    /// checks it again (never "all is well", never "none set up").
    /// `quickKey`: the quick commands' key (TypeSafe) as its last answers said (ArisRouterKeyHealth): one TypeSafe
    /// refused, or one that hasn't answered yet, is said after the AI, never "all is well" (second upgrade run, bug 2).
    static func greeting(agentDown: Bool, missingPermissions: Int, noAI: Bool = false, aiUnchecked: Bool = false,
                         quickKey: QuickKey = .fine, missing: [ArisPrerequisites.Missing] = [], english: Bool = ArisUIWords.english) -> String {
        if missing.contains(.helper) { return ArisPrerequisites.line(.helper, english: english) }
        if agentDown { return Self.agentDown }
        if missingPermissions > 0 { return "권한 \(missingPermissions)개가 더 필요해요" }
        if aiUnchecked { return Self.aiUnchecked }
        if noAI { return Self.noAI }
        if quickKey == .refused { return Self.quickKeyRefused }
        if quickKey == .unchecked { return Self.quickKeyUnchecked }
        return "모두 잘 되고 있어요"
    }

    /// The greeting is about something the install lacks: the row shows what to do about it.
    static func prerequisite(_ greeting: String, english: Bool = ArisUIWords.english) -> ArisPrerequisites.Missing? {
        ArisPrerequisites.Missing.allCases.first { ArisPrerequisites.line($0, english: english) == greeting }
    }

    /// The quick commands' key, for the line (ArisRouterKeyHealth.State, or none saved).
    enum QuickKey: Equatable { case fine, unchecked, refused }
    static let quickKeyRefused = "빠른 명령 키가 맞지 않아요"
    static let quickKeyUnchecked = "빠른 명령 키가 아직 답하지 않아요"

    static let noAI = "쓸 수 있는 AI가 없어요"
    static let aiUnchecked = "AI가 아직 답하지 않아요"
    /// The saved key has never answered: pressing the line checks it again.
    static func asksForAICheck(_ greeting: String) -> Bool { greeting == aiUnchecked }
    static let agentDown = "에이전트와 연결이 끊겼어요"

    /// The greeting says the helper doesn't answer: pressing it restarts the helper (the fix cards' own “도우미 다시
    /// 시작”). It used to do nothing when pressed.
    static func asksForHelper(_ greeting: String) -> Bool { greeting == agentDown }

    /// The greeting is about missing permissions: it opens their rows.
    static func asksForPermissions(_ greeting: String) -> Bool { greeting.hasPrefix("권한 ") && greeting.hasSuffix("더 필요해요") }
    static let permissionsAnchor = "control.permissions"

    /// Where the talk key is changed: the guide's "No, I'll change the key" opens settings on this row.
    static let talkKey = (page: ArisSettingsPage.keys, anchor: "keys.talk")

    /// The greeting says no AI can answer: it opens AI 서비스 on 기본으로 답하는 AI.
    static func asksForAI(_ greeting: String) -> Bool { greeting == noAI || greeting == quickKeyRefused || greeting == quickKeyUnchecked }
    static let brainAnchor = "ai.brain"
}

/// The line Aris reads out to let a voice be heard (목소리 · 언어's 들어 보기, AI 서비스's 미리 듣기).
enum ArisVoiceSample {
    static let line = "안녕하세요, 아리스예요. 이 속도로 말할게요."
}

/// The window's toast: what its mark says, and how long it stays.
enum ArisToastTone: Equatable, Sendable {
    /// It was done (a green check), it wasn't (a red cross), or something to know (a grey mark).
    case ok, bad, info

    /// SF Symbol for the 16-pt mark.
    var symbol: String {
        switch self {
        case .ok: "checkmark.circle"
        case .bad: "xmark.circle"
        case .info: "info.circle"
        }
    }

    /// How long a toast of `text` stays: 45 ms a character, between 2 and 7 seconds (longer lines need reading).
    static func seconds(for text: String) -> Double { min(max(Double(text.count) * 0.045, 2), 7) }
}

enum ArisShortcutCaps {
    private static let modifierGlyphs = "⌃⌥⇧⌘"

    /// ⌘ with these is macOS's or every app's own (close, quit, copy, paste, cut, undo, select all, hide, minimise,
    /// settings); ⇧⌘Z is redo.
    private static let reserved: Set<String> = ["W", "Q", "C", "V", "X", "Z", "A", "H", "M", ","]

    /// Why a key can't be a shortcut, as the recorder says it; nil when it can. A function key may stand alone; any
    /// other key needs ⌘, ⌥ or ⌃ (⇧ alone is typing).
    static func problem(modifiers: [String], key: String, functionKey: Bool) -> String? {
        let mods = Set(modifiers), key = key.uppercased()
        if mods == ["⌘"] && reserved.contains(key) || mods == ["⇧", "⌘"] && key == "Z" { return "macOS와 앱이 쓰는 단축키예요. 다른 키를 눌러 주세요" }
        if functionKey { return nil }
        if mods.isDisjoint(with: ["⌘", "⌥", "⌃"]) { return "⌘ ⌥ ⌃ 중 하나와 같이 눌러 주세요" }
        return nil
    }

    /// A shortcut's text ("⌃⌥Space", "⇧⌘I") as caps: one per modifier, then the key. A blank key reads "Space".
    static func caps(_ text: String) -> [String] {
        let modifiers = text.prefix { modifierGlyphs.contains($0) }.map(String.init)
        let key = String(text.drop { modifierGlyphs.contains($0) }).trimmingCharacters(in: .whitespaces)
        return modifiers + [key.isEmpty ? "Space" : key]
    }
}

enum ArisKoreanText {
    /// Breaks only between words, as the mockup's `word-break: keep-all` does: a word joiner between the letters of
    /// each word, so a line never ends in the middle of "답해요".
    static func keepAll(_ text: String) -> String {
        var out = ""
        var previous: Character?
        for ch in text {
            if let previous, !previous.isWhitespace, !ch.isWhitespace { out.append("\u{2060}") }
            out.append(ch)
            previous = ch
        }
        return out
    }
}

/// A page opens at its top: when the scroll view is told so again after the page changed.
enum ArisSettingsPageTop {
    /// Milliseconds after the change, each counted from the one before: the next pass of layout, then once more for a
    /// page whose rows arrive a moment later (AI services asks the helper). All before a jump to a row (90 ms after
    /// the change at the earliest, then its own scroll).
    static let again = [16, 60]

    /// Whether the scroll to the top is still made: the same page is open, and no jump to one of its rows is on its
    /// way (that jump decides where the page stands).
    static func stillScrolls<Page: Equatable>(opened: Page, shown: Page, jumping: Bool) -> Bool { opened == shown && !jumping }
}
