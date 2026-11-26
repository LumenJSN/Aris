//
//  ArisMindBrainDriver.swift
//  aris-agent
//
//  An API-key brain with `arisCore2` on (ARCHITECTURE Part 2): its runner starts `aris-agent mind-brain --profile <id>`
//  (ArisMindBrain), the Mind's own loop, as the brain's process. All of its calls are decided by the helper's trust gate
//  over POST /mind-call (the owner's words are the runner's, never the child's; the cards go up through the runner's
//  card path), so this driver only speaks the line protocol: the question with the World's context, the answer as it
//  streams, how it ended. Outside text is known exactly (a call's content is reported to the helper, which marks the
//  conversation: ArisMindRoute's done). A sealed, hands-free or teammate turn keeps the API brain's own path
//  (ArisAPIDriver) until the trust policy has those inputs too (fail closed).
//

import Foundation

final class ArisMindBrainDriver: ArisBrainDriver {
    let profile: ArisAPIProfile?
    let task: Bool
    private let executable: URL?
    private let hasKey: () -> Bool
    private let context: () -> String
    private var seen = ArisTaint.none
    private var inTurn = false

    var quietKinds: Set<String> { ["status"] }
    /// A call may wait on the owner's card (and the work after it) this long without a line, as the API brain's.
    var longestSilentCall: TimeInterval { ArisSlowCalls.ownerWait }

    init(profile: ArisAPIProfile?, task: Bool = false, executable: URL? = ArisAppBundle.ownProgram, hasKey: @escaping () -> Bool = { true },
         context: @escaping () -> String = { ArisMindLive.context() }) {
        self.profile = profile
        self.task = task
        self.executable = executable
        self.hasKey = hasKey
        self.context = context
    }

    /// Which turns go to the Mind's own loop: an API brain's, with Core 2 on, unless the turn is one the trust policy
    /// can't yet tell apart (sealed for the screen, hands-free, a teammate's scopes): those keep ArisAPIDriver.
    static func serves(core2: Bool, sealed: Bool, handsFree: Bool, scopes: Set<ArisTeammateScope>?) -> Bool {
        core2 && !sealed && !handsFree && scopes == nil
    }

    var title: String { profile?.preset?.title ?? "API" }

    func launch() -> (URL, [String])? {
        guard missing == nil, let profile, let executable else { return nil }
        return (executable, ["mind-brain", "--profile", profile.id])
    }

    var missing: ArisBrainTrouble.Missing? {
        guard let profile, let preset = profile.preset, executable != nil, !profile.quick.isEmpty || !profile.strong.isEmpty else { return .setup }
        return !preset.needsKey || hasKey() ? nil : .key
    }

    func ask(_ prompt: String, tier: ArisTier) -> [Data] {
        inTurn = true
        return [Self.line(["type": "ask", "text": prompt, "tier": tier.rawValue, "task": task, "context": Self.context(context(), task: task), "english": ArisSkillLanguage.english])]
    }

    /// A turn's context: the World's lines, and for a background task what it is told about tasks (ArisMindSession.jobContext).
    static func context(_ world: String, task: Bool) -> String {
        guard task else { return world }
        return world.isEmpty ? ArisMindSession.jobContext : ArisMindSession.jobContext + "\n" + world
    }

    func read(_ line: String) -> [ArisBrainEvent] {
        guard let data = line.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // Something the child didn't say in its protocol: fail closed.
            if inTurn, !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { markUntrusted() }
            return []
        }
        switch object["type"] as? String {
        case "delta":
            guard let text = object["text"] as? String, !text.isEmpty else { return [] }
            return [.delta(text)]
        case "status":
            guard let text = object["text"] as? String, !text.isEmpty else { return [] }
            return [.status(String(text.prefix(80)))]
        case "result":
            inTurn = false
            return [.result((object["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))]
        case "error":
            inTurn = false
            markUntrusted()
            return [Self.failure(kind: object["kind"] as? String, message: object["message"] as? String ?? "", title: title)]
        default:
            if inTurn { markUntrusted() }
            return []
        }
    }

    /// A failed turn in plain words (tenth VM run, item 7): a wrong key says so and offers Settings, no network, a limit,
    /// the service down, each its own line; Aris's own lines as they are; anything else one plain line. The provider's
    /// own words (which can carry part of a key, or a request id) are never shown and never reach a log.
    static func failure(kind raw: String?, message: String, title: String) -> ArisBrainEvent {
        let kind = raw.flatMap(ArisAPIError.Kind.init(rawValue:))
        if kind == nil, ArisMindAPIProvider.ownLines.contains(message) { return .failure(message) }
        switch kind {
        case .auth: ArisFixTurns.shared.note(.settings(.key))
        case .network, .timeout: ArisFixTurns.shared.note(.retry)
        default: break
        }
        // No balance left (X2): Aris's own line for it, never a limit to wait out; another AI may still take it.
        if kind == .billing { return .unavailable(ArisAPIFailureWords.line(.balance, title: title, english: false)) }
        if kind == .quota || kind == .rate || kind == .overloaded { return .unavailable(kind == .overloaded ? "overloaded" : "rate limit") }
        return .failure(ArisAPIFailureWords.line(ArisAPIFailureWords.kind(kind) ?? .other, title: title, english: false))
    }

    func markUntrusted() { seen = max(seen, .outsideText) }
    func markScreenSeen() { seen = max(seen, .screenSeen) }
    var taint: ArisTaint { seen }

    func reset() {
        seen = .none
        inTurn = false
    }

    func newConversation() -> [Data]? {
        reset()
        return [Self.line(["type": "new_conversation"])]
    }
}
