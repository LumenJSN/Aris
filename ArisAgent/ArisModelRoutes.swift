//
//  ArisModelRoutes.swift
//  aris-agent
//
//  POST /models {"op", "brain", …, "pid", "started"} (the Aris app itself only, ArisPeer): settings' model rows.
//
//    "list"  {"brain"}            ->  {"models": [{"id", "title", "detail"?, "efforts"}], "fromTool": bool}
//    "check" {"brain", "model"}   ->  {"ok": bool, "checked": bool, "resolved"?, "message"?}
//
//  Both ask the brain's tool, never a model (ArisModelDiscovery), off the server queue. A tool that can't list answers
//  with today's fixed names and fromTool false; a check the tool couldn't make takes the id by its shape (checked false).
//  Also the pieces POST /ask uses (ArisModelTurn): which choices a request carries, and the turn asked again on 자동
//  when its chosen model stopped working.
//

import Foundation

enum ArisModelRoutes {
    static func json(_ object: Any) -> Data { (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8) }

    static func row(_ option: ArisModelOption) -> [String: Any] {
        var row: [String: Any] = ["id": option.id, "title": option.title, "efforts": option.efforts]
        if let detail = option.detail { row["detail"] = detail }
        return row
    }

    /// One request; `reply` is called once, off the server queue.
    static func handle(_ object: [String: Any], environment: @escaping () -> [String: String],
                       list: @escaping (ArisBrain, [String: String]) -> [ArisModelOption]? = ArisModelDiscovery.list,
                       check: @escaping (String, ArisBrain, [String: String]) -> ArisModelDiscovery.Check = ArisModelDiscovery.check,
                       reply: @escaping (String, Data) -> Void) {
        guard let raw = object["brain"] as? String, let brain = ArisBrain(rawValue: raw), ArisModelChoices.brains.contains(brain) else {
            return reply("400 Bad Request", json(["error": "모르는 AI예요."]))
        }
        switch object["op"] as? String {
        case "list":
            DispatchQueue.global(qos: .utility).async {
                let found = list(brain, environment())
                let models = found ?? ArisModelLists.fixed(brain)
                reply("200 OK", json(["models": models.map(row), "fromTool": found != nil]))
            }
        case "check":
            let id = (object["model"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard ArisModelChoices.isModelID(id) else {
                return reply("200 OK", json(["ok": false, "checked": true, "message": ArisModelDiscovery.unknownLine(id, brain: brain)]))
            }
            DispatchQueue.global(qos: .userInitiated).async {
                reply("200 OK", json(body(check(id, brain, environment()), id: id, brain: brain)))
            }
        default:
            reply("400 Bad Request", json(["error": "모르는 요청이에요."]))
        }
    }

    static func body(_ check: ArisModelDiscovery.Check, id: String, brain: ArisBrain) -> [String: Any] {
        switch check {
        case .ok(let resolved):
            var body: [String: Any] = ["ok": true, "checked": true]
            if let resolved, resolved != id { body["resolved"] = resolved }
            return body
        case .unknown:
            return ["ok": false, "checked": true, "message": ArisModelDiscovery.unknownLine(id, brain: brain)]
        case .unchecked:
            return ["ok": true, "checked": false]
        }
    }
}

enum ArisModelTurn {
    /// The choices a request carries: the app's own (kept, for the work no request names), else what the app last sent.
    static func choices(_ value: Any?, fromApp: Bool, box: ArisModelChoiceBox = .shared) -> ArisModelChoices {
        guard fromApp, value != nil else { return box.current }
        let choices = ArisModelChoices.parse(value)
        box.set(choices)
        return choices
    }

    /// What a turn whose chosen model stopped working does next.
    enum Retired: Equatable {
        /// Asked again on 자동 (the same brain) with these choices, the answer starting with `notice`.
        case again(choices: ArisModelChoices, notice: String)
        /// The turn had already done something (a tool, a handed-off call, outside text taken in): it ends with this line
        /// and is never run a second time.
        case end(String)
    }

    /// A turn that ended because its chosen model stopped working (the tool's exact words for it: ArisModelRetired).
    /// `acted`: the first attempt ran a tool, handed a call off or took on taint. Nil for any other end, and for a turn
    /// already on 자동.
    static func retired(_ reply: ArisAgentReply, brain: ArisBrain, tier: ArisTier, task: Bool = false, choices: ArisModelChoices,
                        acted: Bool, korean: Bool) -> Retired? {
        guard case .failure(let text) = reply, ArisModelRetired.matches(text) else { return nil }
        let role = ArisModelRole.of(tier: tier, task: task)
        guard let chosen = choices.choice(brain, role).model else { return nil }
        if acted { return .end(ArisModelRetired.ended(model: chosen, korean: korean)) }
        return .again(choices: choices.automaticModel(brain, role), notice: ArisModelRetired.notice(model: chosen, korean: korean))
    }

    /// Whether the first attempt did anything a second one could do again: its own tools, a handed-off call that ran or
    /// showed a card, or taint taken on beyond what the turn came with (`startedAt`: outside text for a marked turn, the
    /// screen for one that carries it).
    static func acted(usedTools: Bool, handedOff: Bool, taint: ArisTaint, startedAt: ArisTaint) -> Bool {
        usedTools || handedOff || taint > startedAt
    }

    /// The taint a turn starts with before its brain does anything.
    static func startTaint(marked: Bool, screen: Bool) -> ArisTaint { marked ? .outsideText : screen ? .screenSeen : .none }

    /// The retry's provenance: whatever the first attempt was, and what it took on (never less).
    static func carried(untrusted: Bool, screenSeen: Bool, taint: ArisTaint) -> (untrusted: Bool, screenSeen: Bool) {
        (untrusted || taint == .outsideText, screenSeen || taint == .screenSeen)
    }

    /// What the turn asked again says: its sentence, then the answer.
    static func noted(_ reply: ArisAgentReply, notice: String?) -> ArisAgentReply {
        guard let notice, case .answer(let text) = reply else { return reply }
        return .answer(lead(notice) + text)
    }

    /// The sentence as the answer's first words (streamed first, so what is said and what is shown agree).
    static func lead(_ notice: String) -> String { notice + "\n\n" }
}
