//
//  ArisRoutineProgress.swift
//  Aris (also built into aris-agent)
//
//  Two small things the app and the agent must agree on about the user's routines ("출근 루틴 해 줘"):
//  - whether a sentence names a routine at all (then the app never takes it for a local act such as "음악 꺼", and it
//    reaches the agent whole), and
//  - how the agent's status line says which step of a routine is running ("메일 보는 중 · 2/4"), so the notch can show
//    the count beside what Aris is doing, and
//  - how a step goes back to the app before any AI is asked (ArisRoutineLocalStep): a step the app would have done by
//    itself when typed (a timer, the time, the volume, a to-do) is done that way inside a routine too.
//  Pure.
//

import Foundation

enum ArisRoutineWords {
    /// The sentence says 루틴 or "routine".
    static func mentions(_ text: String) -> Bool {
        let said = text.precomposedStringWithCanonicalMapping.lowercased()
        return said.contains("루틴") || said.range(of: #"\broutines?\b"#, options: .regularExpression) != nil
    }
}

/// A status line while a routine runs: "<what Aris is doing> · <step>/<total>", the ending the notch's working tag reads
/// its "2/4" from (the same text the agent's ArisStepLine.counted writes for a desktop batch, and the app's
/// ArisTagProgress.split reads). The agent writes it for every status of a routine's step; the count is the routine's
/// own (it knows both numbers), never a guess.
enum ArisRoutineProgress {
    struct Step: Equatable {
        /// The step running now, from 1.
        let step: Int
        let total: Int
        /// What Aris is doing in it ("메일 보는 중"), or the step's own words when it has just started.
        let text: String
    }

    static let separator = " · "
    /// The app keeps this much of a status line.
    static let limit = 80
    /// A count is shown for 2 to 99 steps.
    static let mostSteps = 99

    private static func isCount(step: Int, of total: Int) -> Bool {
        (2...mostSteps).contains(total) && (1...total).contains(step)
    }

    /// `text` with the count at its end; `text` alone for a routine of one step. A count the words already end in (a
    /// step that counts its own, such as a desktop batch) gives way to the routine's. Long words are cut before the
    /// count, never through it.
    static func line(step: Int, total: Int, text: String) -> String {
        let words = parse(text)?.text ?? text
        guard isCount(step: step, of: total) else { return words }
        let ending = "\(separator)\(step)/\(total)"
        return String(words.prefix(limit - ending.count)) + ending
    }

    /// The words and the count of a status line that ends in one; nil for any other status.
    static func parse(_ status: String) -> Step? {
        guard let cut = status.range(of: separator, options: .backwards) else { return nil }
        let numbers = status[cut.upperBound...].split(separator: "/", omittingEmptySubsequences: false)
        let words = String(status[..<cut.lowerBound])
        guard numbers.count == 2, numbers.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy { ("0"..."9").contains($0) } }),
              let step = Int(numbers[0]), let total = Int(numbers[1]), isCount(step: step, of: total),
              !words.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Step(step: step, total: total, text: words)
    }
}

/// One step of a running routine, offered to the app before any AI: a line on the turn's own stream,
/// `{"localStep": {"id": …, "words": …}}`. The app reads the words with the rules it reads a typed sentence with and
/// answers on POST /routine-step (ArisRoutineLocalOutcome): done, tried and not done, or not its own to do (then the
/// agent asks the AI, as it did before). The agent only ever sends his own words here, never a step an AI worded.
struct ArisRoutineLocalStep: Equatable, Sendable {
    /// The agent's name for this one offer: the answer must carry it.
    let id: String
    let words: String

    /// The longest step a routine keeps (ArisRoutineRules.stepLimit); anything longer is not a step.
    static let longest = 200

    /// One JSON line, newline included.
    var line: Data {
        ((try? JSONSerialization.data(withJSONObject: ["localStep": ["id": id, "words": words]])) ?? Data()) + Data("\n".utf8)
    }

    static func parse(line: String) -> ArisRoutineLocalStep? {
        guard line.contains("\"localStep\""), let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let step = object["localStep"] as? [String: Any],
              let id = step["id"] as? String, !id.isEmpty, id.count <= 64, let words = step["words"] as? String,
              !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, words.count <= longest else { return nil }
        return ArisRoutineLocalStep(id: id, words: words)
    }
}

/// How the app answers a step it was offered.
enum ArisRoutineLocalOutcome: Equatable, Sendable {
    /// The app's own rules don't take these words (or the turn is no longer at work): the AI's.
    case notLocal
    /// Done by the app; what it would have said for the same words typed.
    case done(String)
    /// The app tried and it did not happen; why, in its own line.
    case failed(String)

    /// The longest reply kept.
    static let longest = 2_000

    var json: [String: Any] {
        switch self {
        case .notLocal: return ["local": false]
        case .done(let reply): return ["local": true, "ok": true, "reply": reply]
        case .failed(let reply): return ["local": true, "ok": false, "reply": reply]
        }
    }

    /// POST /routine-step's body; nil when it is malformed.
    static func parse(_ object: [String: Any]) -> ArisRoutineLocalOutcome? {
        guard let local = object["local"] as? Bool else { return nil }
        guard local else { return .notLocal }
        guard let ok = object["ok"] as? Bool, let reply = object["reply"] as? String else { return nil }
        let kept = String(reply.prefix(longest))
        return ok ? .done(kept) : .failed(kept)
    }
}
