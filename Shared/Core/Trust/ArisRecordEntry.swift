//
//  ArisRecordEntry.swift
//  Shared/Core (aris-agent, tests)
//
//  One line of the record (ARCHITECTURE Part 2, Record): every capability call when `arisCore2` is on: when, which
//  session or task, the call (its capability and key arguments, bodies only as a short head), its effect, its
//  provenance and why, the decision and the owner's answer, a result summary, and an undo recipe where one exists.
//  Append-only: an undo is a later line naming the entry it undid. Each line stands alone and carries the format's
//  version; the helper seals each in a chain (ArisRecordJournal, the task journal's scheme). Pure.
//

import Foundation

/// How to take one change back. Files are put back by the helper itself (from its undo store for an edit); the rest
/// go through the capability that made them (calendar, reminders, notes, settings, apps, windows).
enum ArisUndoRecipe: Equatable, Sendable, Codable {
    /// A new file or folder: it goes to the Trash.
    case fileCreated(path: String)
    /// A file edited or replaced: its earlier bytes are in the undo store (`copy`), put back while the file is still
    /// as Aris left it (`after`: its SHA-256).
    case fileChanged(path: String, copy: String, after: String)
    /// Moved or renamed: from `original` to `current`; put back without overwriting anything.
    case fileMoved(original: String, current: String)
    /// Put in the Trash: back from `trash` to `original`.
    case fileTrashed(original: String, trash: String)
    /// Made in an app: removed again (`kind`: "calendar", "reminder", "note").
    case itemCreated(kind: String, id: String)
    /// Changed in an app: its fields as they were.
    case itemChanged(kind: String, id: String, before: [String: String])
    /// A setting or system control: its value before ("volume", "brightness", "darkMode", "wifi"…).
    case setting(name: String, before: String)
    /// Text put into an app's field whose value before is known.
    case textInserted(app: String, element: String, before: String)
    /// A window moved or resized: its frame before (x, y, width, height).
    case windowMoved(app: String, window: Int, frame: [Double])

    /// The scope words "방금 만든 거 되돌려" picks by, like ArisUndo.action.
    var action: String {
        switch self {
        case .fileCreated, .itemCreated: "made"
        case .fileTrashed: "removed"
        case .fileMoved: "moved"
        case .fileChanged, .itemChanged, .setting, .textInserted, .windowMoved: "changed"
        }
    }

    /// The protected folder an undo touches (Desktop, Documents, Downloads), for /undo-folder.
    var paths: [String] {
        switch self {
        case .fileCreated(let path), .fileChanged(let path, _, _): [path]
        case .fileMoved(let original, let current): [original, current]
        case .fileTrashed(let original, let trash): [original, trash]
        case .itemCreated, .itemChanged, .setting, .textInserted, .windowMoved: []
        }
    }
}

struct ArisRecordEntry: Equatable, Sendable, Codable, Identifiable {
    static let version = 1
    static let bodyHead = 80
    static let valueLimit = 200
    static let resultLimit = 200

    enum Kind: String, Codable, Sendable {
        /// A call decided (and run, asked about or refused).
        case call
        /// An earlier entry (`ref`) undone.
        case undone
    }

    var v = ArisRecordEntry.version
    let kind: Kind
    let id: String
    let at: Date
    var session: String?
    var task: String?
    var capability: String?
    var effect: ArisEffectClass?
    var provenance: ArisCallProvenance.Column?
    var source: ArisContentSource?
    var why: [String]?
    var decision: String?
    /// The owner's answer to a card: "yes", "always", "no", "unanswered".
    var answer: String?
    var arguments: [ArisKeyArgument]?
    var result: String?
    var ok: Bool?
    var undo: ArisUndoRecipe?
    /// For `undone`: the entry taken back.
    var ref: String?
    /// The activity log's entries the call's aris-tools run wrote (their ids): the same action, listed and undone there.
    var logged: [String]?

    /// A call's line, its values cut as the audit asked: a body is a short head, every other value at most 200.
    static func call(id: String = UUID().uuidString.lowercased(), at: Date = Date(), session: String?, task: String?, capability: String,
                     effect: ArisEffectClass, provenance: ArisCallProvenance, why: [String] = [], decision: ArisDecision, answer: String? = nil,
                     arguments: [ArisKeyArgument], result: String?, ok: Bool, undo: ArisUndoRecipe?) -> ArisRecordEntry {
        var entry = ArisRecordEntry(kind: .call, id: id, at: whole(at))
        entry.session = session.map { cut($0, 80) }
        entry.task = task.map { cut($0, 80) }
        entry.capability = cut(capability, 80)
        entry.effect = effect
        entry.provenance = provenance.column
        entry.source = provenance.source.map { ArisContentSource(kind: cut($0.kind, 20), source: cut($0.source, valueLimit)) }
        entry.why = why.isEmpty ? nil : why.prefix(8).map { cut($0, 120) }
        entry.decision = decision.label
        if case .refuse(let reason) = decision { entry.result = cut(reason, resultLimit) }
        entry.answer = answer
        entry.arguments = arguments.map { ArisKeyArgument(kind: $0.kind, value: cut($0.value, $0.kind == .body ? bodyHead : valueLimit)) }
        if let result { entry.result = cut(result, resultLimit) }
        entry.ok = ok
        entry.undo = undo
        return entry
    }

    static func undone(_ ref: String, at: Date = Date(), result: String? = nil) -> ArisRecordEntry {
        var entry = ArisRecordEntry(kind: .undone, id: UUID().uuidString.lowercased(), at: whole(at))
        entry.ref = ref
        entry.result = result.map { cut($0, resultLimit) }
        entry.ok = true
        return entry
    }

    init(kind: Kind, id: String, at: Date) {
        self.kind = kind
        self.id = id
        self.at = at
    }

    /// To the second, as the line keeps it (ISO 8601).
    static func whole(_ date: Date) -> Date { Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)) }

    /// One line: no line breaks or control characters, at most `limit` characters.
    static func cut(_ text: String, _ limit: Int) -> String {
        let clean = String(text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) })
        return clean.count > limit ? String(clean.prefix(limit - 1)) + "…" : clean
    }

    // MARK: - Lines

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

    var json: Data { (try? Self.encoder.encode(self)) ?? Data("{}".utf8) }

    /// `<seal> <json>\n`, `seal` over the JSON's bytes and the line's place (the helper's chain).
    func line(sealedWith seal: (Data) -> String) -> Data {
        let json = self.json
        return Data((seal(json) + " ").utf8) + json + Data([0x0A])
    }

    static func decode(_ json: Data) -> ArisRecordEntry? {
        guard let entry = try? decoder.decode(ArisRecordEntry.self, from: json), entry.v >= 1, entry.v <= version else { return nil }
        return entry
    }

    /// The entries of a sealed journal up to the first line whose seal doesn't hold its place (as ArisTaskRecord.chained):
    /// `verify` gets the JSON, its seal, its index and the seal before it. `good`, `last`, `goodBytes`: where to append.
    static func chained(in data: Data, verify: (_ json: Data, _ seal: String, _ index: Int, _ previous: String) -> Bool)
        -> (entries: [ArisRecordEntry], good: Int, last: String, goodBytes: Int) {
        var entries: [ArisRecordEntry] = []
        var previous = "", index = 0, offset = 0
        var cursor = data.startIndex
        while cursor < data.endIndex {
            guard let end = data[cursor...].firstIndex(of: 0x0A) else { break }
            let raw = data[cursor..<end]
            guard let space = raw.firstIndex(of: 0x20), space > raw.startIndex else { break }
            let seal = String(decoding: raw[raw.startIndex..<space], as: UTF8.self), json = Data(raw[raw.index(after: space)...])
            guard verify(json, seal, index, previous) else { break }
            if let entry = decode(json) { entries.append(entry) }
            previous = seal
            index += 1
            cursor = data.index(after: end)
            offset = data.distance(from: data.startIndex, to: cursor)
        }
        return (entries, index, previous, offset)
    }
}

/// The record read back: each call with whether it was undone since.
struct ArisRecordState: Equatable, Sendable {
    let calls: [ArisRecordEntry]
    let undone: Set<String>

    init(_ entries: [ArisRecordEntry]) {
        calls = entries.filter { $0.kind == .call }
        undone = Set(entries.filter { $0.kind == .undone }.compactMap(\.ref))
    }

    func isUndone(_ id: String) -> Bool { undone.contains(id) }

    /// A call whose aris-tools run wrote entries of the activity log is the log's action too: undone there (the old
    /// path's "되돌려" or the 한 일 list), it is undone (VM run 2026-11-19, D5). `loggedUndone`: the log's undone ids.
    func isUndone(_ entry: ArisRecordEntry, loggedUndone: Set<String>) -> Bool {
        isUndone(entry.id) || (entry.logged.map { !$0.isEmpty && $0.allSatisfy(loggedUndone.contains) } ?? false)
    }

    /// The calls that can still be undone, newest first.
    var undoable: [ArisRecordEntry] {
        calls.filter { $0.undo != nil && $0.ok == true && !undone.contains($0.id) }.sorted { $0.at > $1.at }
    }

    /// The newest `n` that can be undone (newest first): what "되돌려" (n = 1) and "마지막 세 개 되돌려" take back.
    func last(_ n: Int, since: Date = .distantPast) -> [ArisRecordEntry] {
        Array(undoable.filter { $0.at >= since }.prefix(max(0, n)))
    }
}
