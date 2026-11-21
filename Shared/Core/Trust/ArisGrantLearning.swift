//
//  ArisGrantLearning.swift
//  Shared/Core (aris-agent, tests)
//
//  Standing grants learned from the owner's own words, and taken back the same way:
//    "앞으로 엄마한테 보내는 건 묻지 마"           -> outward to 엄마 (and her addresses)
//    "다운로드 폴더에서 지우는 건 그냥 해"           -> change-permanent inside ~/Downloads
//    "오늘은 민수한테 메일 보낼 때 묻지 마"          -> mail.* outward to 민수, until the end of today
//    "always send to mom@x.com without asking"   -> outward to mom@x.com
//    "엄마한테 보낼 땐 다시 물어봐" / "ask me again before sending to 엄마"  -> that grant revoked
//  Only the owner's turn text is ever passed here (never content); a sentence that names nothing to scope it to, or
//  that only says "this once" (이번만), makes no grant. Pure.
//

import Foundation

enum ArisGrantChange: Equatable, Sendable {
    case add(ArisStandingGrant)
    /// Take back the grants for this effect and target (nil: any).
    case revoke(effect: ArisEffectClass?, target: ArisStandingGrant.Target?)
}

enum ArisGrantLearning {
    static let noAsk = ["묻지 마", "묻지마", "묻지 말고", "물어보지 마", "물어보지마", "물어보지 말고", "확인 안 해도", "확인 안해도", "확인하지 마",
                        "그냥 해", "그냥 보내", "그냥 지워", "알아서 해", "don't ask", "dont ask", "without asking", "no need to ask", "never ask",
                        "don't confirm", "just do it", "just send"]
    static let askAgain = ["다시 물어", "물어보고 해", "물어보고 보내", "항상 물어", "꼭 물어", "ask me again", "always ask", "ask before",
                           "ask first", "check with me"]
    static let standingWords = ["앞으로", "항상", "매번", "언제나", "늘 ", "오늘", "시간 동안", "분 동안", "always", "from now on", "every time",
                                "whenever", "today", "for the next", "for an hour", "never ask"]
    static let topicalNoAsk = ["건 묻지", "는 묻지", "땐 묻지", "때는 묻지", "때 묻지", "건 물어보지", "는 물어보지", "땐 물어보지", "건 그냥",
                               "는 그냥", "땐 그냥", "don't ask when", "don't ask for", "don't ask about", "don't ask before", "never ask"]
    static let once = ["이번만", "이번 한 번", "just this once", "only this time"]

    /// `home`: a grant whose scope isn't safe (the home folder, a root, a system folder, Aris's own) is never made.
    static func learn(_ text: String, world: ArisWorldFacts, home: String, now: Date = Date(), calendar: Calendar = .current) -> ArisGrantChange? {
        let folded = ArisGrounding.fold(text)
        guard folded.count <= 200, !once.contains(where: folded.contains) else { return nil }
        let revoking = askAgain.contains(where: folded.contains)
        // A standing grant needs words that make it standing ("앞으로", "항상", "…건 묻지 마"): "그냥 보내" alone is this once.
        let standing = standingWords.contains(where: folded.contains) || topicalNoAsk.contains(where: folded.contains)
        guard revoking || (standing && noAsk.contains(where: folded.contains)) else { return nil }
        let target = self.target(in: text, world: world)
        let effect = self.effect(in: text, target: target)
        if revoking { return .revoke(effect: effect, target: target) }
        guard target != nil || effect != nil else { return nil }
        let grant = ArisStandingGrant(capability: capability(in: folded), effect: effect ?? .outward, target: target,
                                      expires: expiry(in: folded, now: now, calendar: calendar), created: now, words: text)
        return grant.isWellFormed && grant.isSafe(home: home) ? .add(grant) : nil
    }

    static func target(in text: String, world: ArisWorldFacts) -> ArisStandingGrant.Target? {
        for contact in world.contacts where ([contact.name] + contact.aliases).contains(where: { ArisGrounding.contains(text, $0) }) {
            return .init(kind: .recipient, pattern: contact.name, addresses: contact.addresses)
        }
        let words = text.split(whereSeparator: { $0.isWhitespace }).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'\".,!?")) }
        if let address = words.first(where: { $0.contains("@") && $0.contains(".") }) { return .init(kind: .recipient, pattern: address) }
        if let folder = ArisGrounding.namedFolders(in: text, world: world).first { return .init(kind: .path, pattern: folder) }
        if let focus = world.focus, focus.source.kind == "file",
           ArisGrounding.pointsAtFocus(text) || ArisGrounding.pointsAtKind("file", in: text) {
            return .init(kind: .path, pattern: focus.source.source)
        }
        for (name, nicknames) in world.apps where ([name] + nicknames).contains(where: { ArisGrounding.contains(text, $0) }) {
            return .init(kind: .app, pattern: name)
        }
        return nil
    }

    /// The effect the sentence is about: by its verb, else by its target (a person: sending; a folder: deleting).
    static func effect(in text: String, target: ArisStandingGrant.Target?) -> ArisEffectClass? {
        if ArisGrounding.has(ArisGrounding.outwardVerbs, in: text) { return .outward }
        if ArisGrounding.has(ArisGrounding.permanentVerbs, in: text) { return .changePermanent }
        switch target?.kind {
        case .recipient: return .outward
        case .path, .app: return .changePermanent
        default: return nil
        }
    }

    static func capability(in folded: String) -> String? {
        if ["메일", "이메일", "mail", "email"].contains(where: folded.contains) { return "mail.*" }
        if ["문자", "메시지", "카톡", "imessage", "text "].contains(where: folded.contains) { return "messages.*" }
        return nil
    }

    static func expiry(in folded: String, now: Date, calendar: Calendar) -> Date? {
        if ["오늘", "today"].contains(where: folded.contains) {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        }
        if let match = folded.range(of: #"(\d+)\s*(시간|hours?)"#, options: .regularExpression) {
            let hours = Double(folded[match].filter(\.isNumber)) ?? 1
            return now.addingTimeInterval(min(hours, 72) * 3_600)
        }
        if let match = folded.range(of: #"(\d+)\s*(분|minutes?)"#, options: .regularExpression) {
            let minutes = Double(folded[match].filter(\.isNumber)) ?? 30
            return now.addingTimeInterval(min(minutes, 600) * 60)
        }
        if ["한 시간", "한시간", "an hour", "one hour"].contains(where: folded.contains) { return now.addingTimeInterval(3_600) }
        return nil
    }

    /// The grants left after a change.
    static func applied(_ change: ArisGrantChange, to grants: [ArisStandingGrant], home: String) -> [ArisStandingGrant] {
        switch change {
        case .add(let grant): return grants + [grant]
        case .revoke(let effect, let target):
            return grants.filter { grant in
                let sameEffect = effect == nil || grant.effect == nil || grant.effect == effect
                let sameTarget = target == nil || (grant.target.map { held in
                    held.kind == target!.kind && (held.matches(target!.pattern, home: home) || target!.matches(held.pattern, home: home))
                } ?? false)
                return !(sameEffect && sameTarget)
            }
        }
    }
}
