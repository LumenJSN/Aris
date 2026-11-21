//
//  ArisDesktopEffect.swift
//  aris-agent
//
//  What a desktop call does to the world, for Core 2's trust policy (ArisEffectClass), read from its own words and
//  text alone, so the same call gets the same class every time (VM run 2026-11-19, D4: a batch "click, cmd+a, type"
//  was judged run-with-undo, though it would have replaced a whole TextEdit document and nothing could put it back):
//  · a look (see, a list, `wait` for an earlier call's result): observe;
//  · a batch: the strongest of its steps, and a select-all followed by typing, pasting or a delete anywhere in it
//    (ArisDesktopBatch.replacesAll) replaces what was there: change-permanent, since no undo recipe restores an app's
//    text;
//  · set-value (the field's whole value replaced), a deleting or cutting key, or a control or menu item that deletes,
//    clears or replaces: change-permanent;
//  · a control or menu item that sends, posts or pays: outward;
//  · anything else that acts (click, type at the caret, scroll, drag, a window or an app opened, focused or hidden):
//    change-reversible, as opening an app is everywhere (`app <name>`, `desktop app launch`: the trust table's
//    change-reversible row; observe would let content-suggested opens go unannounced);
//  · words that can't be read: change-permanent (the strongest short of the never-list, as an unknown aris-tools call).
//  Only the trust policy reads this; the old path's gates are untouched. It may only make the policy ask more.
//

import Foundation

enum ArisDesktopEffect {
    /// The only verbs that are looks: each reads a window, a menu, a dialog or the Dock and changes nothing. A verb not
    /// named here acts, whatever else it is (security review of D4: an under-rated call must never ask less).
    static let looks: Set<ArisDesktopVerb> = [.see, .menuList, .dialogList, .windowList, .dockList]

    /// The words as the desktop command reads them; nil when they can't be read.
    static func request(_ words: [String], text: String?) -> ArisDesktopRequest? {
        if case .success(let request) = ArisDesktopWords.parse(words, text: text) { return request }
        // The relay's form keeps the text in the words (`type <ref> '<text>'`, a batch's steps joined by " ;; ").
        if case .success(let request) = ArisDesktopWords.parse(words, text: nil, positionalText: true) { return request }
        return nil
    }

    /// A call that only looks: `wait` for an earlier call's result, or one of the look verbs, read as the command reads it.
    static func isLook(_ words: [String], text: String?) -> Bool {
        if ArisDesktopWords.isWait(words) { return true }
        return request(words, text: text).map { looks.contains($0.verb) } ?? false
    }

    /// `words`: what follows `desktop`; `text`: its stdin (a batch's steps, a type's text). Never below `floor` (the
    /// inventory row's class) unless the call is a look on the allowlist.
    static func effect(_ words: [String], text: String?, floor: ArisEffectClass = .changeReversible) -> ArisEffectClass {
        if isLook(words, text: text) { return .observe }
        guard let parsed = request(words, text: text) else { return .changePermanent }
        return ArisEffectClass.strongest([floor, effect(of: parsed)])
    }

    /// An acting request's own class (a look is handled before: `effect(_:text:floor:)`).
    static func effect(of request: ArisDesktopRequest) -> ArisEffectClass {
        if looks.contains(request.verb) { return .observe }
        switch request.verb {
        case .batch:
            // The command reads a batch's steps itself (ArisDesktopWords.finish): the same steps the engine runs.
            guard !request.steps.isEmpty else { return .changePermanent }
            return effect(ofSteps: request.steps)
        case .setValue: return .changePermanent
        case .press: return effect(ofKeys: request.keys)
        case .menuClick:
            let item = (request.path ?? "").components(separatedBy: CharacterSet(charactersIn: ">›")).last ?? ""
            return effect(ofLabel: item) ?? .changeReversible
        case .dialogClick: return effect(ofLabel: request.button ?? "") ?? .changeReversible
        default: return .changeReversible
        }
    }

    /// A batch: the strongest of its steps; replacing everything there is permanent whatever each step is alone.
    static func effect(ofSteps steps: [ArisDesktopStep]) -> ArisEffectClass {
        if ArisDesktopBatch.replacesAll(steps) { return .changePermanent }
        return ArisEffectClass.strongest(steps.map { step in
            switch step.verb {
            case .setValue: return .changePermanent
            case .press: return effect(ofKeys: step.keys)
            case .click:
                if case .label(let label) = step.target, let named = effect(ofLabel: label) { return named }
                return .changeReversible
            default: return .changeReversible
            }
        })
    }

    /// Keys: a delete or a cut takes something away that no recipe brings back.
    static func effect(ofKeys keys: [String]) -> ArisEffectClass {
        keys.contains { ArisDesktopBatch.isDeletion($0) || ArisDesktopBatch.normalized($0) == ["cmd", "x"] } ? .changePermanent : .changeReversible
    }

    /// A control or menu item by its words: one that sends or pays is outward, one that deletes, clears or replaces is
    /// permanent; nil for any other.
    static func effect(ofLabel label: String) -> ArisEffectClass? {
        let folded = label.lowercased().trimmingCharacters(in: .whitespaces)
        guard !folded.isEmpty else { return nil }
        let outward = #"(?i)\b(send|post|publish|pay|buy|order|submit)\b|보내기|전송|게시|결제|구매|주문"#
        if folded.range(of: outward, options: .regularExpression) != nil { return .outward }
        let permanent = #"(?i)\b(delete|erase|clear|remove|discard|replace|cut|don.?t save)\b|삭제|지우기|지움|제거|비우기|잘라내기|대치|바꾸기|버리기|폐기|저장\s*안\s*함"#
        return folded.range(of: permanent, options: .regularExpression) != nil ? .changePermanent : nil
    }

    /// `aris-tools keys <combo…> [--app X] [--times N]`: as `desktop press`.
    static func effect(ofKeysCommand words: [String]) -> ArisEffectClass {
        var combos: [String] = [], skip = false
        for word in words {
            if skip { skip = false; continue }
            if word.hasPrefix("--") { skip = true; continue }
            combos.append(word)
        }
        return effect(ofKeys: combos)
    }
}
