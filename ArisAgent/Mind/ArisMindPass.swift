//
//  ArisMindPass.swift
//  aris-agent
//
//  One card per call, never two (ARCHITECTURE Part 2, Judgment). When the owner answered yes on the trust gate's card
//  for one exact call, that answer goes down to the route the call reaches (a message, a handed-off write, the desktop,
//  a connected service, Aside) as a pass: a random token, kept only in this process, bound to the call's capability,
//  its exact words (ArisMindPassKey) and its turn, good once and for two minutes. The route that is handed a pass it can
//  redeem for exactly the call it is serving takes it in place of its own card (ArisMindStandIn): its first card for
//  that call is answered yes without being shown again. Anything else (no pass, a pass for another call, a replayed
//  one, one of a turn that ended, one too old, the switch off) and the route asks exactly as it always has.
//  Only this direction: the gate never skips its own card because a route might card after it.
//  A second kind, for the desktop route alone (VM run 2, D4: "TextEdit에 … 써 줘" put up a card at every step, after the
//  gate had let each step run without one): when the gate decided a desktop call runs without a card (the trust table's
//  run rows for the owner's own request or Aris's own step toward it), the call carries a pass of the kind `judgedRun`.
//  The desktop route takes it as the app's yes for that one call (ArisDesktopTurn.trustDecisionHolds), so the card that only
//  asks for a yes to the app is not shown again; every card the desktop gate puts up before that one (a browser, a chat
//  or mail app, a payment, a terminal's line, a file panel, Calendar, a risky menu item, hands-free) still shows. A
//  `judgedRun` pass never stands in for any route's card (ArisMindStandIn), and a yes pass never sets the app's yes.
//  It is valid for exactly one call under exactly the content its decision saw: it carries the conversation, the call
//  and the content the gate had taken in when it decided (ArisTrustGate.contentRead, stored with the decision), and the
//  desktop gate checks it live each time it would use it (ArisMindJudge.judgedRunFresh): once more content came in, or
//  while another call of the conversation that can bring content in is decided and hasn't reported, it opens nothing
//  and the route asks as it always has.
//

import Foundation

final class ArisMindPasses: @unchecked Sendable {
    /// What a pass carries: the owner's yes on the gate's card for the call, or the gate's own decision that the call runs
    /// without a card (only ever minted for a desktop call).
    enum Kind: Equatable, Sendable {
        case cardYes
        case judgedRun
    }

    struct Pass: Equatable {
        let kind: Kind
        /// For `judgedRun`: how much content the gate had taken in for the conversation when it decided the call
        /// (ArisTrustGate.contentRead). The pass opens nothing once more has come in.
        var seen: Int? = nil
        /// For `judgedRun`: the conversation and the call it was decided for.
        var session: String? = nil
        var call: String? = nil
        let intent: String
        let capability: String
        let key: String
        let until: Date
    }

    static let shared = ArisMindPasses()
    /// The call runs right after the yes: two minutes is plenty, and no more.
    static let lifetime: TimeInterval = 120
    /// Where the executor hands a call's pass to its aris-tools run (only for that run).
    static let environmentKey = "ARIS_MIND_PASS"

    private let lock = NSLock()
    private var passes: [String: Pass] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    /// A pass for a call the owner said yes to on the gate's card; nil when the call reaches no route that cards on its
    /// own (nothing to stand in for).
    /// `kind` `judgedRun`: the gate let a desktop call run without a card (see the header); nil for any other call.
    /// `decision`: for `judgedRun` (required), the conversation, the call and the content the gate had taken in when it
    /// decided (ArisTrustGate.contentRead).
    func mint(intent: String, capability: String, argv: [String]?, stdin: String?, kind: Kind = .cardYes,
              decision: (session: String, call: String, seen: Int)? = nil) -> String? {
        guard let argv, let key = ArisMindPassKey.key(argv: argv, stdin: stdin) else { return nil }
        if kind == .judgedRun, argv.first != "desktop" || decision == nil { return nil }
        let token = Self.token()
        let at = now()
        lock.withLock {
            passes = passes.filter { $0.value.until > at }
            let judged = kind == .judgedRun ? decision : nil
            passes[token] = Pass(kind: kind, seen: judged?.seen, session: judged?.session, call: judged?.call, intent: intent, capability: capability,
                                 key: key, until: at.addingTimeInterval(Self.lifetime))
        }
        return token
    }

    /// Whether `token` is the owner's yes pass for exactly this call (`key`) of this turn (`turn`), still fresh. A token
    /// is gone once shown, whatever the answer: a replay, or a pass tried on another call, never opens anything.
    func redeem(_ token: String?, turn: String, key: String?) -> Bool {
        redeemed(token, turn: turn, key: key)?.kind == .cardYes
    }

    /// The pass `token` is for exactly this call of this turn, still within its time; nil when it is none. Gone once
    /// shown. A `judgedRun` one is then only as good as its live check (ArisMindJudge.judgedRunFresh).
    func redeemed(_ token: String?, turn: String, key: String?) -> Pass? {
        guard let token, Self.wellFormed(token), let key else { return nil }
        let at = now()
        let pass: Pass? = lock.withLock { passes.removeValue(forKey: token) }
        guard let pass, pass.until > at, pass.intent == turn, pass.key == key else { return nil }
        if pass.kind == .judgedRun, pass.seen == nil || pass.session == nil || pass.call == nil { return nil }
        return pass
    }

    /// The turn or task ended: none of its passes opens anything any more.
    func end(intent: String) {
        lock.withLock { passes = passes.filter { $0.value.intent != intent } }
    }

    var count: Int { lock.withLock { passes.count } }

    /// 256 random bits as 64 hex digits.
    static func token() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<4).map { _ in String(format: "%016llx", generator.next() as UInt64) }.joined()
    }

    static func wellFormed(_ token: String) -> Bool {
        token.count == 64 && token.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// The route's stand-in for this request: its pass redeemed for exactly the call it serves, with `arisCore2` on.
    static func standIn(_ object: [String: Any], turn: String, key: String?, passes: ArisMindPasses = .shared,
                        isOn: () -> Bool = { ArisCore2.isOn() }) -> ArisMindStandIn? {
        guard isOn(), let token = object["pass"] as? String else { return nil }
        return passes.redeem(token, turn: turn, key: key) ? ArisMindStandIn() : nil
    }

    /// The desktop route's reading of its request's pass (one redeem): the owner's yes on the gate's card (a stand-in for
    /// the route's first card), or the gate's decision that this call runs without a card (the app's yes for this call).
    /// The judgedRun pass comes back whole (its decision: conversation, call, content seen), for the route to check live.
    static func desktop(_ object: [String: Any], turn: String, key: String?, passes: ArisMindPasses = .shared,
                        isOn: () -> Bool = { ArisCore2.isOn() }) -> (standIn: ArisMindStandIn?, judged: Pass?) {
        guard isOn(), let token = object["pass"] as? String, let pass = passes.redeemed(token, turn: turn, key: key) else { return (nil, nil) }
        switch pass.kind {
        case .cardYes: return (ArisMindStandIn(), nil)
        case .judgedRun: return (nil, pass)
        }
    }
}

/// The exact words a pass is bound to, read the same way from the aris-tools argv the gate decided and from what each
/// route is asked (aris-tools' own request bodies). A call whose two readings could differ gets no key: no pass.
enum ArisMindPassKey {
    private static let gap = "\u{0}"

    static func key(argv: [String], stdin: String?) -> String? {
        guard let first = argv.first else { return nil }
        if let message = ArisMessagePass.message(argv) { return messageKey(to: message.to, text: message.text) }
        switch first {
        case "desktop":
            let text = stdin.map { $0.hasSuffix("\n") ? String($0.dropLast()) : $0 }
            return desktopKey(words: Array(argv.dropFirst()), text: text)
        case "mcp":
            guard argv.count >= 4, argv[1] == "call" else { return nil }
            let rest = Array(argv.dropFirst(4))
            if rest.isEmpty { return mcpKey(service: argv[2], tool: argv[3], pairs: nil, arguments: "{}") }
            if rest.count == 1, rest[0].trimmingCharacters(in: .whitespaces).hasPrefix("{") {
                return mcpKey(service: argv[2], tool: argv[3], pairs: nil, arguments: rest[0])
            }
            guard rest.allSatisfy({ $0.contains("=") && !$0.hasPrefix("=") }) else { return nil }
            return mcpKey(service: argv[2], tool: argv[3], pairs: rest, arguments: nil)
        case "aside":
            return asideKey(brief: argv.dropFirst().joined(separator: " "))
        default:
            return ArisHandOff.isWrite(argv) ? actionKey(words: argv) : nil
        }
    }

    static func messageKey(to: String, text: String) -> String {
        (["message", to, text].joined(separator: gap)).precomposedStringWithCanonicalMapping
    }

    static func actionKey(words: [String]) -> String { (["action"] + words).joined(separator: gap) }

    static func desktopKey(words: [String], text: String?) -> String {
        (["desktop"] + words).joined(separator: gap) + "\u{1}" + (text.map { "t" + $0 } ?? "-")
    }

    /// `pairs` (key=value words) or `arguments` (one JSON text), as /mcp-tool takes one of them.
    static func mcpKey(service: String, tool: String, pairs: [String]?, arguments: String?) -> String? {
        if let pairs { return (["mcp", service, tool, "pairs"] + pairs).joined(separator: gap) }
        guard let arguments else { return nil }
        return ["mcp", service, tool, "json", arguments].joined(separator: gap)
    }

    static func asideKey(brief: String) -> String { ["aside", brief].joined(separator: gap) }
}

/// A route's stand-in for its own first card of one call, made only from a redeemed pass: answers that card yes once,
/// without showing it. A card that isn't the call's own (Aside's install or sign-in card, the automatic check's stopped
/// card, a session's permission card) is never answered by it.
final class ArisMindStandIn: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    /// True once, for a card it may stand in for.
    func take(_ card: ArisMCPCard) -> Bool {
        guard card.allow == nil, !card.stopped, card.fleetGrant == nil else { return false }
        return lock.withLock {
            guard !used else { return false }
            used = true
            return true
        }
    }

    /// A route turn's ask: the stand-in's yes when it may give one (said in the audit), else the card as always.
    static func ask(_ card: ArisMCPCard, standIn: ArisMindStandIn?, audit: ([String: String]) -> Void,
                    show: (ArisMCPCard, @escaping (ArisMCPAnswer) -> Void) -> Void, answer: @escaping (ArisMCPAnswer) -> Void) {
        if let standIn, standIn.take(card) {
            audit(["answer": "yes (the owner's yes on the trust gate's card for this call)", "action": String(card.title.prefix(80))])
            return answer(.yes([:]))
        }
        show(card, answer)
    }
}
