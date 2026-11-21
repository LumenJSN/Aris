//
//  ArisMindTaught.swift
//  aris-agent
//
//  The owner's saved steps as a capability of the Mind (tenth VM run, item 1): `taught_run`, offered like every other
//  entry of the book, with the lessons themselves in the turn's context (ArisTaughtOffer). A model's call names a lesson
//  and may offer values; what happens then is decided here, never by the model:
//  - the name must be a saved lesson's, exactly (however it is spelled); any other name runs nothing and the answer
//    lists the names there are;
//  - the turn must be one that may start a run at all (ArisTeachMay, the same rule as a run by its name: the owner's
//    own turn from the app, never hands-free, a background task, a teammate's turn or another voice);
//  - their words name it, or the model judged that they plainly ask for it: it runs. Unless the conversation read
//    outside text (then always), or its name shares a word with something Aris does by itself (메모 → Notes) and he
//    hasn't chosen yet: then his card asks first (ArisTaughtClash), and a clash's answer is remembered;
//  - a value counts only when his own words of this turn hold it (ArisTaughtOffer.given); a value a step types that
//    he didn't say is asked on the run's value card, as a run by its name asks it;
//  - the run is the replay there already is (ArisTeachRunner: each step through the one trust decision, its card when
//    one is due, the record and its undo), and its account is the call's result.
//  `handle` is the whole decision over ports (tested with fakes); the live ports are in ArisMindTaught+Live.swift.
//

import Foundation

enum ArisMindTaught {
    /// The owner's answer to a card of this file.
    enum Answer: Equatable {
        case yes([String: String])
        case no
        case unanswered
    }

    struct Ended {
        let outcome: ArisTeachReplay.Outcome
        /// The apps typed into with no undo (ArisTeachRunEnd.Unchecked).
        var unchecked: [String] = []
        /// A line-starting text read back on the same line as what was there (ArisTeachRunEnd.Placed).
        var sameLine = false
    }

    struct Ports {
        var isOn: () -> Bool
        var procedures: () -> [ArisTeachProcedure]
        var remembered: (UUID) -> ArisTaughtClash.Choice?
        var remember: (UUID, ArisTaughtClash.Choice) -> Void
        /// Shows a card and waits for his answer. `fields`: editable values (key, value); `allow`: the yes button's word.
        var ask: (_ card: ArisTeachCopy.Card, _ fields: [(key: String, value: String)], _ allow: String?) -> Answer
        /// His no on a card of this call (`unanswered`: nobody answered it), told to the calling turn: nothing more that
        /// acts runs in it (ArisMindJudge.noteDeclined), so the model can't do the same thing another way.
        var declined: (_ unanswered: Bool) -> Void
        /// Runs the lesson for his `words` with the values that are his.
        var run: (_ procedure: ArisTeachProcedure, _ words: String, _ given: [String: String]) -> Ended
        var english: Bool
        /// The run's one card (ArisTeachRunPass), when this run gets one as a run by its name does: every step on it,
        /// the values still to give as its fields. Nil: no such card (each step that asks has its own). A yes there is
        /// the pass `run` takes.
        var runCard: (_ procedure: ArisTeachProcedure, _ words: String, _ given: [String: String], _ missing: [ArisTeachParameter])
            -> (card: ArisTeachCopy.Card, fields: [(key: String, value: String)])? = { _, _, _, _ in nil }
        /// His yes on the card that asks first in a turn that read outside text (ArisTaughtClash.card), which showed every
        /// step with the values their words gave: the run's steps are then approved ahead as a run by its name's are
        /// (twelfth VM run, M2/T2: that yes was followed by a second card for the very step it showed).
        var upFrontYes: () -> Void = {}
        /// The values the lesson's last run typed (ArisTeachLastValues), for the value card's suggestion; and noting them.
        var lastValues: (UUID) -> [String: String] = { _ in [:] }
        var noteValues: (UUID, [String: String]) -> Void = { _, _ in }
    }

    static let off = "Saved steps are turned off on this Mac, so nothing ran. Do it another way only if the owner asks for that."
    static let unavailable = "Saved steps can't be run from here. Tell the owner to ask for it by its name."
    static let declined = "The owner said no on the card: nothing ran. Don't do it another way in this turn."
    static let unanswered = "The owner didn't answer the card: nothing ran. Tell him so; don't do it another way in this turn."

    /// The loop's side of a decided call, by its call id (set by the process that hosts the Mind's loop: the mind-brain).
    /// The helper runs only a call its gate decided, so a run with no call id (the book's plain entry: the face, any
    /// other host) runs nothing.
    nonisolated(unsafe) static var remote: ((_ id: String, _ arguments: [String: Any]) -> ArisToolResult)?

    static let entry = ArisCapabilityEntry(
        id: ArisTaughtOffer.capability, name: ArisTaughtOffer.tool,
        description: "Runs steps the owner taught Aris and saved under a name (the turn's context lists them). Use it when his request names one or "
            + "plainly asks for exactly what one does; when it only resembles one, ask him first instead. The steps run as he showed them, each "
            + "checked, with an undo.",
        parameters: ["type": "object",
                     "properties": ["name": ["type": "string", "description": "The saved steps' name, exactly as listed."],
                                    "value": ["type": "string", "description": "For a lesson with one value: what he said for it in this request, word for word."],
                                    "values": ["type": "object", "additionalProperties": ["type": "string"],
                                               "description": "For several values: each by its label, word for word from this request. Leave out what he didn't say."]],
                     "required": ["name"]],
        effect: { _ in .changeReversible },
        run: .helper({ _, _ in ArisToolResult(text: unavailable, isError: true) }))

    /// The longest a run may take with its cards (the value card, each step's, a "go on?").
    static let longestRun: TimeInterval = 900

    /// The loop's side: the call goes to the helper and its answer is the result.
    static func remote(credential: @escaping () -> String?, post: @escaping (_ body: [String: Any], _ wait: TimeInterval) -> [String: Any]?) -> (String, [String: Any]) -> ArisToolResult {
        { id, arguments in
            guard let turn = credential() else { return ArisToolResult(text: ArisMindRemote.unreachable, isError: true) }
            let body: [String: Any] = ["op": "taught", "turn": turn, "id": id, "arguments": arguments]
            guard let reply = post(body, longestRun), let text = reply["text"] as? String else {
                return ArisToolResult(text: "The saved steps' run didn't answer in time: what it did isn't known. Don't repeat it; tell the owner to check.", isError: true)
            }
            return ArisToolResult(text: text, isError: reply["isError"] as? Bool ?? true)
        }
    }

    /// The values a call offers, by label, key or "value".
    static func offered(_ arguments: [String: Any]) -> [String: String] {
        var offered = (arguments["values"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        if let value = arguments["value"] as? String { offered["value"] = value }
        return offered
    }

    /// One call, decided and run. `request`: the owner's own words of this turn; `may`: whether this turn may start a
    /// run at all (ArisTeachMay: `.ask` when the conversation read outside text or saw the screen).
    static func handle(_ arguments: [String: Any], request: String, may: ArisTeachMay.Start, ports: Ports) -> ArisToolResult {
        guard ports.isOn() else { return ArisToolResult(text: off, isError: true) }
        // The one rule for who may start a run (ArisTeachMay), before anything is looked up or shown.
        guard may != .refuse else { return ArisToolResult(text: unavailable, isError: true) }
        let tainted = may == .ask
        let stored = ports.procedures()
        let name = (arguments["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let procedure = ArisTeachNames.find(ArisTeachNames.clean(name), in: stored) else {
            let names = stored.prefix(ArisTaughtOffer.most).map { "“\(ArisTaughtOffer.word($0.name))”" }.joined(separator: ", ")
            return ArisToolResult(text: stored.isEmpty ? "The owner has taught no saved steps, so nothing ran."
                                  : "No saved steps have that exact name, so nothing ran. The names are: \(names). Ask the owner which he means.", isError: true)
        }
        var given = ArisTaughtOffer.given(procedure, offered: offered(arguments), ownerWords: request)
        switch ArisTaughtClash.decide(procedure, request: request, tainted: tainted, remembered: ports.remembered(procedure.id)) {
        case .run:
            break
        case .builtIn(let clash):
            return ArisToolResult(text: ArisTaughtClash.useBuiltIn(procedure, clash))
        case .ask(let clash):
            // Every step as it will be done, with the values their words gave (twelfth VM run, M2: "↵[본문]" and the example).
            switch ports.ask(ArisTaughtClash.card(procedure, clash: clash, values: given, english: ports.english), [], nil) {
            case .yes:
                if clash != nil { ports.remember(procedure.id, .taught) }
                ports.upFrontYes()
            case .no:
                guard let clash else {
                    ports.declined(false)
                    return ArisToolResult(text: declined, isError: true)
                }
                // His choice of how (the built-in), not a no to doing it: the turn goes on.
                ports.remember(procedure.id, .builtIn)
                return ArisToolResult(text: ArisTaughtClash.useBuiltIn(procedure, clash))
            case .unanswered:
                ports.declined(true)
                return ArisToolResult(text: unanswered, isError: true)
            }
        }
        // A value a step types that their words didn't give: asked first, last time's value offered; nothing runs on a no.
        // In a clean turn the run is as a run by its name (eleventh VM run, item 2: three cards for one run): when a step
        // would ask and the one card may cover it, that card comes first with every step on it, and it asks the values too.
        let missing = ArisTeachReplay.missing(procedure, given: given)
        let whole = tainted ? nil : ports.runCard(procedure, request, given, missing)
        if whole != nil || !missing.isEmpty {
            let asked = whole ?? ArisTeachCopy.valuesCard(procedure, missing: missing, last: ports.lastValues(procedure.id), english: ports.english)
            switch ports.ask(asked.card, asked.fields, nil) {
            case .yes(let edits): given.merge(ArisTeachReplay.answered(missing, edits: edits)) { $1 }
            case .no:
                ports.declined(false)
                return ArisToolResult(text: ArisTeachCopy.notRun(procedure, unanswered: false, english: ports.english) + "\n" + declined, isError: true)
            case .unanswered:
                ports.declined(true)
                return ArisToolResult(text: ArisTeachCopy.notRun(procedure, unanswered: true, english: ports.english) + "\n" + unanswered, isError: true)
            }
        }
        let ended = ports.run(procedure, request, given)
        // His no (or silence) on a step's card inside the run is the calling turn's too.
        if case .stopped(_, let end, _) = ended.outcome {
            if end == .declined { ports.declined(false) }
            if end == .unanswered { ports.declined(true) }
        }
        let told = ArisTeachRunEnd.withPlace(ArisTeachCopy.account(procedure, outcome: ended.outcome, english: ports.english), procedure: procedure,
                                             outcome: ended.outcome, sameLine: ended.sameLine, english: ports.english)
        let account = ArisTeachRunEnd.withUnchecked(told, apps: ended.unchecked, english: ports.english)
        let done = ArisTeachRunEnd.completed(ended.outcome)
        if done { ports.noteValues(procedure.id, given) }
        // The account is the whole truth of the run: the model says it as it is, in his language, and adds nothing.
        return ArisToolResult(text: account + "\n" + (done ? "Tell the owner exactly this, in his language." : "It did not all run. Tell the owner exactly this, in his language; don't do the rest another way."),
                              isError: !done)
    }
}

extension ArisCapabilityBook {
    static let taught: [ArisCapabilityEntry] = [ArisMindTaught.entry]
}
