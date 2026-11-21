//
//  ArisTaskRecord.swift
//  Shared/Core (aris-agent, tests)
//
//  One line of a background task's journal (tasks/<job>.jsonl in the helper's folder). The journal is append-only: a
//  task is created, started, takes steps, says status lines, asks cards and hears their answers, writes output, and
//  ends; a helper that started again adds how it took the task back. Each line stands alone and carries the format's
//  version, so a damaged or newer line is skipped and the rest still reads.
//  What goes in is what actions.log would hold, no more: the job's own words (as handed over, no context), the
//  status lines the notch showed, each step as the gate described it, the card's own title and details, a failure's
//  short line, all cut to actions.log's limits. Never an answer's text (the helper writes no `output` record any more;
//  an older journal's is read and ignored), never images, never the context block, never a tool's output.
//  Foundation only.
//

import Foundation

/// Where a task came from and how it ran: enough to start it again behind the same gates.
struct ArisTaskOrigin: Codable, Equatable {
    /// ArisTier's raw value ("quick", "work", "critical", "deep").
    var tier: String
    /// The job was written from outside content (a model, a screen turn, a schedule).
    var untrusted: Bool
    /// Its turn was marked as carrying outside text from the start.
    var marked: Bool
    var screenSeen: Bool
    /// Heard hands-free (the restricted brain).
    var handsFree: Bool
    /// The runner was the sealed, hands-free one (its own process, no spare).
    var sealedHandsFree: Bool
    /// The request is about Aris's own data.
    var ownData: Bool
    /// The teammate whose job it is (its id), and a helper's name ("도우미 2").
    var teammate: String?
    var helper: String?

    init(tier: String, untrusted: Bool = false, marked: Bool = false, screenSeen: Bool = false, handsFree: Bool = false,
         sealedHandsFree: Bool = false, ownData: Bool = false, teammate: String? = nil, helper: String? = nil) {
        self.tier = tier
        self.untrusted = untrusted
        self.marked = marked
        self.screenSeen = screenSeen
        self.handsFree = handsFree
        self.sealedHandsFree = sealedHandsFree
        self.ownData = ownData
        self.teammate = teammate
        self.helper = helper
    }
}

/// A card as the user was shown it (its id is the one POST /confirm takes).
struct ArisTaskCard: Codable, Equatable {
    var id: String
    var title: String
    var detail: String
    var full: String?
}

struct ArisTaskRecord: Codable, Equatable {
    /// The format's version. A line with a higher one is skipped (a newer helper wrote it).
    static let version = 1

    enum Kind: String, Codable {
        case created, started, session, step, status, card, answer, output, ended, recovered
    }

    /// How a task ended.
    enum Ending: String, Codable {
        /// It gave its answer.
        case answered
        /// It failed with an error (its line in `text`).
        case failed
        /// The user cancelled it.
        case cancelled
        /// Its brain went quiet past the limit, or it ran past the ceiling.
        case timedOut
        /// The helper stopped it on purpose (POST /stop, a setting changed).
        case stopped
        /// It could not be taken back after a restart (`text` says why).
        case lost
    }

    /// How a helper that started again took the task back.
    enum Recovery: String, Codable {
        /// The brain reopened its own session.
        case resumed
        /// A new brain process, told what the journal says was done.
        case restarted
        /// It waits on the card it waited on before.
        case waiting
    }

    var v: Int
    var at: Date
    var kind: Kind
    var job: String?
    var title: String?
    /// The user's own words (what every gate compares against).
    var request: String?
    /// The job as it was handed over, without the context block.
    var prompt: String?
    var brain: String?
    var model: String?
    var origin: ArisTaskOrigin?
    var text: String?
    /// A step that may have changed something (not a plain read).
    var effect: Bool?
    var card: ArisTaskCard?
    var allow: Bool?
    var ending: Ending?
    /// The brain's own handle for its conversation (a Claude session id, a Codex thread id).
    var session: String?
    var recovery: Recovery?
    /// ArisTaint as a word ("none", "screenSeen", "outsideText"), as far as the task had come.
    var taint: String?

    init(kind: Kind, at: Date = Date()) {
        v = Self.version
        self.at = at
        self.kind = kind
    }
}

// MARK: - Making records (every text cut to actions.log's limits)

enum ArisTaskLimits {
    /// The job's words and its answer so far, as the inbox keeps a result.
    static let words = 4_000
    /// A step as the gate described it (actions.log's identifying fields).
    static let step = 1_024
    /// A status line, a card's title, an ending's line (actions.log's other fields).
    static let line = 256
    /// A card's details (they name what it does; actions.log keeps the action at the identifying limit).
    static let detail = 1_024

    /// `text` whole when it fits, else its start and end joined by "…" (as actions.log cuts a field).
    static func cut(_ text: String, _ limit: Int) -> String {
        guard text.count > limit, limit > 8 else { return text }
        let keep = (limit - 1) / 2
        return String(text.prefix(keep)) + "…" + String(text.suffix(limit - 1 - keep))
    }

    /// The last `limit` characters (the answer so far: what came last matters for carrying on).
    static func tail(_ text: String, _ limit: Int) -> String {
        text.count > limit ? "…" + String(text.suffix(limit - 1)) : text
    }
}

extension ArisTaskRecord {
    static func created(job: String, title: String, request: String, prompt: String, brain: String, model: String,
                        origin: ArisTaskOrigin, at: Date = Date()) -> ArisTaskRecord {
        var record = ArisTaskRecord(kind: .created, at: at)
        record.job = job
        record.title = ArisTaskLimits.cut(title, ArisTaskLimits.line)
        record.request = ArisTaskLimits.cut(request, ArisTaskLimits.words)
        record.prompt = ArisTaskLimits.cut(prompt, ArisTaskLimits.words)
        record.brain = brain
        record.model = model
        record.origin = origin
        return record
    }

    static func started(at: Date = Date()) -> ArisTaskRecord { ArisTaskRecord(kind: .started, at: at) }

    static func session(_ handle: String, at: Date = Date()) -> ArisTaskRecord {
        var record = ArisTaskRecord(kind: .session, at: at)
        record.session = ArisTaskLimits.cut(handle, ArisTaskLimits.line)
        return record
    }

    static func step(_ described: String, effect: Bool, at: Date = Date()) -> ArisTaskRecord {
        var record = ArisTaskRecord(kind: .step, at: at)
        record.text = ArisTaskLimits.cut(described, ArisTaskLimits.step)
        record.effect = effect
        return record
    }

    static func status(_ line: String, at: Date = Date()) -> ArisTaskRecord {
        var record = ArisTaskRecord(kind: .status, at: at)
        record.text = ArisTaskLimits.cut(line, ArisTaskLimits.line)
        return record
    }

    static func card(_ card: ArisTaskCard, at: Date = Date()) -> ArisTaskRecord {
        var record = ArisTaskRecord(kind: .card, at: at)
        record.card = ArisTaskCard(id: ArisTaskLimits.cut(card.id, ArisTaskLimits.line), title: ArisTaskLimits.cut(card.title, ArisTaskLimits.line),
                                   detail: ArisTaskLimits.cut(card.detail, ArisTaskLimits.detail),
                                   full: card.full.map { ArisTaskLimits.cut($0, ArisTaskLimits.detail) })
        return record
    }

    /// The answer to card `id`: the user's yes or no, or a no nobody gave (`how`: "expired", "unanswered", "cancelled").
    static func answer(_ id: String, allow: Bool, how: String? = nil, at: Date = Date()) -> ArisTaskRecord {
        var record = ArisTaskRecord(kind: .answer, at: at)
        record.card = ArisTaskCard(id: ArisTaskLimits.cut(id, ArisTaskLimits.line), title: "", detail: "")
        record.allow = allow
        record.text = how.map { ArisTaskLimits.cut($0, ArisTaskLimits.line) }
        return record
    }

    /// The answer so far (the newest record holds all of it, as far as the limit lets).
    static func output(_ soFar: String, at: Date = Date()) -> ArisTaskRecord {
        var record = ArisTaskRecord(kind: .output, at: at)
        record.text = ArisTaskLimits.tail(soFar, ArisTaskLimits.words)
        return record
    }

    static func ended(_ ending: Ending, line: String? = nil, taint: String? = nil, at: Date = Date()) -> ArisTaskRecord {
        var record = ArisTaskRecord(kind: .ended, at: at)
        record.ending = ending
        record.text = line.map { ArisTaskLimits.cut($0, ArisTaskLimits.words) }
        record.taint = taint
        return record
    }

    static func recovered(_ how: Recovery, at: Date = Date()) -> ArisTaskRecord {
        var record = ArisTaskRecord(kind: .recovered, at: at)
        record.recovery = how
        return record
    }

    /// The taint as far as the task had come, on its own line (written when it rises).
    static func tainted(_ taint: String, at: Date = Date()) -> ArisTaskRecord {
        var record = ArisTaskRecord(kind: .status, at: at)
        record.taint = taint
        return record
    }
}

// MARK: - Lines

extension ArisTaskRecord {
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The record as one journal line (newline included).
    var line: Data {
        ((try? Self.encoder.encode(self)) ?? Data("{}".utf8)) + Data([0x0A])
    }

    /// The record as a sealed journal line: `<seal> <json>` and a newline, `seal` computed by the helper over the JSON's
    /// bytes and the line's place in its journal (ArisTaskSeal: a chain, so a line can't be moved, reordered or repeated).
    func line(sealedWith seal: (Data) -> String) -> Data {
        let json = (try? Self.encoder.encode(self)) ?? Data("{}".utf8)
        return Data((seal(json) + " ").utf8) + json + Data([0x0A])
    }

    /// One sealed line split: its seal and its JSON; nil when it has no seal.
    static func sealed(_ raw: Data) -> (seal: String, json: Data)? {
        guard let space = raw.firstIndex(of: 0x20), space > raw.startIndex else { return nil }
        return (String(decoding: raw[raw.startIndex..<space], as: UTF8.self), Data(raw[raw.index(after: space)...]))
    }

    /// Every record in a journal's bytes, in order. A line that can't be read, or that a newer format wrote, is
    /// skipped; the rest still counts.
    static func records(in data: Data) -> [ArisTaskRecord] {
        data.split(separator: 0x0A).compactMap { decode(Data($0)) }
    }

    /// The records of a sealed journal, in order, up to the first line whose seal doesn't fit its place: `verify` gets
    /// the line's JSON, its seal, its index and the seal before it ("" for the first). Nothing after a line that fails
    /// counts (a line moved from another journal, reordered, repeated, forged, or cut by a crash). `good`: how many lines
    /// held, and the last good seal, to append after.
    static func chained(in data: Data, verify: (_ json: Data, _ seal: String, _ index: Int, _ previous: String) -> Bool)
        -> (records: [ArisTaskRecord], good: Int, last: String, goodBytes: Int) {
        var records: [ArisTaskRecord] = []
        var previous = ""
        var index = 0
        var offset = 0
        var cursor = data.startIndex
        while cursor < data.endIndex {
            guard let end = data[cursor...].firstIndex(of: 0x0A) else { break }
            let raw = Data(data[cursor..<end])
            guard let line = sealed(raw), verify(line.json, line.seal, index, previous) else { break }
            if let record = decode(line.json) { records.append(record) }
            previous = line.seal
            index += 1
            cursor = data.index(after: end)
            offset = data.distance(from: data.startIndex, to: cursor)
        }
        return (records, index, previous, offset)
    }

    private static func decode(_ json: Data) -> ArisTaskRecord? {
        guard let record = try? decoder.decode(ArisTaskRecord.self, from: json), record.v >= 1, record.v <= version else { return nil }
        return record
    }
}
