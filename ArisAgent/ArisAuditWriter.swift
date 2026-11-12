//
//  ArisAuditWriter.swift
//  aris-agent
//
//  actions.log, written so that nobody holding the token can erase it: every caller-supplied field is cut before
//  anything else (keeping its start and end, its length and a SHA-256 of the whole, so the evidence survives the
//  cut), every line is capped, repeated and flooding refusals are counted rather than written (ArisAuditThrottle, with
//  a byte budget per caller), and the rotated copies are pruned by age only, never by count or total: the refusal
//  budgets bound a flood's growth, and real action lines are bounded by use. Each written line carries the caller key
//  and time it belongs to.
//

import CryptoKit
import Foundation

struct ArisAuditWriter {
    /// Fields that identify what was done keep more; the rest less.
    static let identifyingFields: Set<String> = ["action", "scope", "command"]
    static let identifyingLimit = 1_024
    static let fieldLimit = 256
    static let lineLimit = 4_096
    static let callerLimit = 64
    /// The audit's copies are never pruned by size (ArisLogRotation's total cap is for other logs). At this much,
    /// live file and copies together, refusal lines stop being written (one notice an hour says so); action lines
    /// still are, and nothing is deleted.
    static let auditTotalCap = 2 * 1_024 * 1_024 * 1_024
    static let auditMaxAge: TimeInterval = 30 * 86_400
    static let capNoticeEvery: TimeInterval = 3_600
    static let capNotice = #"{"answer":"refused lines not written: the audit is at its size cap (nothing is deleted)","question":"audit"}"#

    let directory: URL
    /// The size at which the live file becomes a dated copy, and the size cap (a test uses small ones).
    let rotateAt: Int
    let sizeCap: Int
    private var throttle = ArisAuditThrottle()
    private var lastCapNotice: Date?

    init(directory: URL, rotateAt: Int = ArisLogRotation.defaultLimit, sizeCap: Int = ArisAuditWriter.auditTotalCap) {
        self.directory = directory
        self.rotateAt = rotateAt
        self.sizeCap = sizeCap
    }

    var file: URL { directory.appendingPathComponent("actions.log") }

    static func auditJSON(_ object: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys)) ?? Data("{}".utf8), as: UTF8.self)
    }

    /// `line` with every string value over its limit (measured as escaped JSON) cut to its start and end joined by
    /// "…", plus "<field>_len" and "<field>_sha256" of the whole value; the line capped at `lineLimit`. A line that
    /// isn't a JSON object becomes a note saying so. Whatever is cut, the length and hash of an identifying field
    /// (action, scope, command) and `risk` are never lost.
    static func capped(_ line: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return auditJSON(["answer": "(unreadable audit line)", "bytes": line.utf8.count])
        }
        var result = auditJSON(cut(object, identifyingTo: identifyingLimit))
        guard result.utf8.count > lineLimit else { return result }
        // Too long still: the identifying fields smaller, and only the fields that say what happened.
        let smaller = cut(object, identifyingTo: fieldLimit, always: true)
        let kept = (["answer", "question", "risk"] + identifyingFields.sorted()).flatMap { [$0, $0 + "_len", $0 + "_sha256"] }
            .reduce(into: [String: Any]()) { if let v = smaller[$1] { $0[$1] = v } }
        result = auditJSON(kept)
        guard result.utf8.count > lineLimit else { return result }
        return auditJSON(tooLongNote(object, bytes: line.utf8.count))
    }

    /// Every string value of `object` within its limit, with `_len` and `_sha256` beside a cut one (beside every
    /// identifying field when `always`).
    static func cut(_ object: [String: Any], identifyingTo identifyingLimit: Int, always: Bool = false) -> [String: Any] {
        var cut: [String: Any] = [:]
        for (key, value) in object {
            let name = trim(key, to: 64).text
            guard let text = value as? String else {
                cut[name] = value
                continue
            }
            let identifying = identifyingFields.contains(name)
            let trimmed = trim(text, to: identifying ? identifyingLimit : fieldLimit)
            cut[name] = trimmed.text
            if trimmed.cut || (always && identifying) {
                cut[name + "_len"] = text.utf8.count
                cut[name + "_sha256"] = sha256(text)
            }
        }
        return cut
    }

    /// The last resort for a line nothing else makes fit: a note, the size, `risk`, and the length and hash of every
    /// identifying field, so no record loses the hash of its action or command.
    static func tooLongNote(_ object: [String: Any], bytes: Int) -> [String: Any] {
        var note: [String: Any] = ["answer": "(audit line too long)", "bytes": bytes]
        if let risk = object["risk"] as? String { note["risk"] = trim(risk, to: fieldLimit).text }
        for name in identifyingFields {
            guard let text = object[name] as? String else { continue }
            note[name + "_len"] = text.utf8.count
            note[name + "_sha256"] = sha256(text)
        }
        return note
    }

    static func cappedCaller(_ key: String) -> String { trim(key, to: callerLimit).text }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `text` within `bytes` as it will appear in the JSON (escaped: quotes, backslashes and control characters cost
    /// more): unchanged when it fits; else its start and end (about two thirds and a third of the room) joined by
    /// "…", on character boundaries.
    static func trim(_ text: String, to bytes: Int) -> (text: String, cut: Bool) {
        guard escapedLength(text) > bytes else { return (text, false) }
        let joiner = "…"
        var room = max(bytes - joiner.utf8.count, 2)
        var result = ""
        // Escaping can only make it longer: shrink until the escaped form fits.
        for _ in 0..<8 {
            let headRoom = room * 2 / 3, tailRoom = room - headRoom
            result = prefix(text, bytes: headRoom) + joiner + suffix(text, bytes: tailRoom)
            let over = escapedLength(result) - bytes
            if over <= 0 { return (result, true) }
            room = max(room - over, 2)
        }
        return (result, true)
    }

    /// The bytes `text` takes inside a JSON string (without its quotes).
    static func escapedLength(_ text: String) -> Int {
        max(((try? JSONSerialization.data(withJSONObject: [text]))?.count ?? text.utf8.count + 2) - 4, 0)
    }

    private static func prefix(_ text: String, bytes: Int) -> String {
        var end = text.utf8.index(text.utf8.startIndex, offsetBy: min(bytes, text.utf8.count))
        while end > text.utf8.startIndex, end < text.utf8.endIndex, !text.utf8[end].isUTF8Start { end = text.utf8.index(before: end) }
        return String(text[..<end])
    }

    private static func suffix(_ text: String, bytes: Int) -> String {
        var start = text.utf8.index(text.utf8.endIndex, offsetBy: -min(bytes, text.utf8.count))
        while start < text.utf8.endIndex, !text.utf8[start].isUTF8Start { start = text.utf8.index(after: start) }
        return String(text[start...])
    }

    mutating func write(_ line: String, caller: String, at now: Date) {
        append(throttle.admit(Self.capped(line), caller: Self.cappedCaller(caller), at: now), now: now)
    }

    /// At exit: every count the throttle still holds is written.
    mutating func flush(at now: Date) {
        append(throttle.flush(at: now, all: true), now: now)
    }

    /// The live file and every dated copy together.
    func totalSize() -> Int {
        let folder = file.deletingLastPathComponent()
        return (ArisLogRotation.size(of: file) ?? 0)
            + ArisLogRotation.generations(of: file).reduce(0) { $0 + (ArisLogRotation.size(of: folder.appendingPathComponent($1)) ?? 0) }
    }

    private mutating func append(_ lines: [ArisAuditThrottle.Written], now: Date) {
        guard !lines.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var lines = lines
        // At the size cap nothing is deleted: refusal lines stop (a notice an hour says so), action lines go on.
        if totalSize() >= sizeCap {
            let refusals = lines.filter { ArisAuditThrottle.isRefusal($0.line) }
            lines = lines.filter { !ArisAuditThrottle.isRefusal($0.line) }
            if !refusals.isEmpty, lastCapNotice.map({ now.timeIntervalSince($0) >= Self.capNoticeEvery }) ?? true {
                lastCapNotice = now
                lines.append(ArisAuditThrottle.Written(line: Self.capNotice, caller: ArisAuditThrottle.globalKey, at: now))
            }
            guard !lines.isEmpty else { return }
        }
        // Dated generations pruned by age only: never by count, never by total; the audit is never truncated.
        ArisLogRotation.rotate(file, limit: rotateAt, maxAge: Self.auditMaxAge, totalCap: Int.max, now: now)
        let formatter = ISO8601DateFormatter()
        let stamped = lines.map { "{\"time\":\"\(formatter.string(from: $0.at))\",\"ai\":\"\($0.caller)\"," + $0.line.dropFirst() + "\n" }.joined()
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(stamped.utf8))
        } else {
            FileManager.default.createFile(atPath: file.path, contents: Data(stamped.utf8), attributes: [.posixPermissions: 0o600])
        }
    }
}

private extension UInt8 {
    /// Not a UTF-8 continuation byte.
    var isUTF8Start: Bool { self & 0xC0 != 0x80 }
}
