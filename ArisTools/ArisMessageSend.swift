//
//  ArisMessageSend.swift
//  aris-tools
//
//  What `aris-tools message` decides around the send itself (audit tools-1: it sent on iMessage only, to a contact's
//  first number whatever it was, and printed "sent" on Messages' script ending, while Messages showed "Not Delivered"):
//  - which of a contact's numbers: the one the user last wrote to, else a mobile one, never just the first (a home phone);
//  - which service: the one that conversation last used (a text for an Android phone), iMessage when there is none;
//  - whether it went out: Messages' own database (chat.db, read only, as `messages recent` reads it) is watched for the
//    new message, and only one Messages shows as sent is called sent. An error there is "not sent"; anything else,
//    or no Full Disk Access to look, is "not confirmed", said so the brain neither repeats the send nor calls it done.
//  Pure apart from the database reads, so the tests run it against a database of their own.
//

import Foundation

enum ArisMessageSend {
    enum Service: String, Equatable {
        case iMessage, SMS, RCS
    }

    /// One of a contact's numbers or addresses, with Contacts' label ("mobile", "home", "email").
    struct Candidate: Equatable {
        let label: String
        let value: String
    }

    /// A conversation in Messages: who with, on which service, and when it was last used.
    struct Conversation: Equatable {
        let handle: String
        let service: Service?
        let last: Date
    }

    /// How the message just sent stands in Messages' database.
    struct Sent: Equatable {
        let row: Int64
        let isSent: Bool
        let isDelivered: Bool
        /// Messages' own error number (22: the number isn't on iMessage); 0 for none.
        let error: Int
    }

    enum Outcome: Equatable {
        case delivered, sent, failed, unconfirmed
    }

    // MARK: - Who and how

    /// Contacts' answer (ArisActions.contactScript): one "label<tab>value" line per number, then per address.
    static func candidates(_ printed: String) -> [Candidate] {
        printed.components(separatedBy: .newlines).compactMap { line -> Candidate? in
            let parts = line.components(separatedBy: "\t")
            let value = (parts.count > 1 ? parts.dropFirst().joined(separator: "\t") : parts[0]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }
            return Candidate(label: parts.count > 1 ? parts[0].trimmingCharacters(in: .whitespaces) : "", value: value)
        }
    }

    private static let mobileLabels = ["mobile", "iphone", "cell", "휴대", "핸드폰", "모바일"]
    private static let landlineLabels = ["home", "work", "fax", "main", "pager", "집", "직장", "회사", "팩스"]

    private static func labelled(_ candidate: Candidate, _ words: [String]) -> Bool {
        let label = candidate.label.lowercased()
        return words.contains { label.contains($0) }
    }

    /// The number or address to send to: the one the user last exchanged messages with; else a mobile number; else a number
    /// that isn't marked as a landline or fax; else the first number; else the first address. Nil for nobody.
    static func pick(_ candidates: [Candidate], threads: [Conversation]) -> Candidate? {
        let written = candidates.compactMap { candidate -> (Candidate, Date)? in
            threads.filter { ArisContactNames.key($0.handle) == ArisContactNames.key(candidate.value) }.map(\.last).max().map { (candidate, $0) }
        }
        if let latest = written.max(by: { $0.1 < $1.1 }) { return latest.0 }
        let numbers = candidates.filter { !$0.value.contains("@") }
        return numbers.first { labelled($0, mobileLabels) } ?? numbers.first { !labelled($0, landlineLabels) } ?? numbers.first ?? candidates.first
    }

    /// The service to send on: the one the newest conversation with this number used; iMessage when there is none. An
    /// email address is only ever reached by iMessage.
    static func service(for handle: String, threads: [Conversation]) -> Service {
        guard !handle.contains("@") else { return .iMessage }
        let own = ArisContactNames.key(handle)
        return threads.filter { ArisContactNames.key($0.handle) == own }.max { $0.last < $1.last }?.service ?? .iMessage
    }

    /// A phone number that iMessage didn't take is tried once more as a text message (what "Send as Text Message" does);
    /// an address can't be texted, and a text that failed has nothing left to try.
    static func canFallBack(handle: String, from service: Service) -> Bool {
        service == .iMessage && !handle.contains("@")
    }

    // MARK: - Messages' database (read only)

    /// Every conversation's handle, service and last message date. Throws when the database can't be read (no Full
    /// Disk Access, Messages never set up).
    static func threads(path: String) throws -> [Conversation] {
        let db = try ArisLocalDatabase(path: path)
        guard ["id", "service"].allSatisfy(db.columns("handle").contains), ["handle_id", "date"].allSatisfy(db.columns("message").contains) else {
            throw ArisLocalStoreError.unreadable("handle table")
        }
        let sql = "SELECT h.id AS handle, h.service AS service, MAX(m.date) AS last FROM handle h JOIN message m ON m.handle_id = h.ROWID GROUP BY h.ROWID"
        return try db.rows(sql, limit: 50_000).compactMap { row in
            guard let handle = row["handle"] as? String else { return nil }
            return Conversation(handle: handle, service: (row["service"] as? String).flatMap(Service.init(rawValue:)),
                          last: ArisLocalStore.appleDate(row["last"] as? Int64 ?? 0))
        }
    }

    /// The newest message's row number, read before the send so the new message can be told from older ones.
    static func lastRow(path: String) throws -> Int64 {
        let db = try ArisLocalDatabase(path: path)
        guard ["is_sent", "is_delivered", "error", "is_from_me", "handle_id"].allSatisfy(db.columns("message").contains) else {
            throw ArisLocalStoreError.unreadable("message table")
        }
        return try db.rows("SELECT IFNULL(MAX(ROWID), 0) AS last FROM message").first?["last"] as? Int64 ?? 0
    }

    /// The user's first message to `handle` made after row `after`: the one just sent. Nil while Messages hasn't written it.
    static func sent(path: String, handle: String, after: Int64) throws -> Sent? {
        let db = try ArisLocalDatabase(path: path)
        let sql = """
            SELECT m.ROWID AS row, m.is_sent AS sent, m.is_delivered AS delivered, m.error AS error, h.id AS handle
            FROM message m LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE m.ROWID > ?1 AND m.is_from_me = 1 ORDER BY m.ROWID ASC
            """
        let own = ArisContactNames.key(handle)
        let mine = try db.rows(sql, bind: [Int(after)]).first { ($0["handle"] as? String).map { ArisContactNames.key($0) == own } ?? false }
        return mine.map {
            Sent(row: $0["row"] as? Int64 ?? 0, isSent: ($0["sent"] as? Int64 ?? 0) == 1, isDelivered: ($0["delivered"] as? Int64 ?? 0) == 1,
                 error: Int($0["error"] as? Int64 ?? 0))
        }
    }

    // MARK: - Did it go out

    /// Reads the new message's state every `step` seconds for at most `limit`: an error is a failure and delivered is
    /// delivered, at once; sent is sent after `settle` more seconds without either (the other phone is off); a message
    /// that never appears, or that Messages still hasn't sent at the limit, is not confirmed.
    static func watch(limit: TimeInterval, settle: TimeInterval = 2, step: TimeInterval = 0.4, read: () -> Sent?,
                      wait: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) -> Outcome {
        var waited: TimeInterval = 0
        var sentAt: TimeInterval?
        while true {
            let state = read()
            if let state {
                if state.error != 0 { return .failed }
                if state.isDelivered { return .delivered }
                if state.isSent, sentAt == nil { sentAt = waited }
            }
            if let sentAt, waited - sentAt >= settle { return .sent }
            guard waited + step <= limit else { return sentAt == nil ? .unconfirmed : .sent }
            wait(step)
            waited += step
        }
    }

    /// How one try at sending ended: Messages refused the script (no such account, or it can't reach that person); it
    /// took the message but its database can't be read to check; or what the database showed.
    enum Attempt: Equatable {
        case refused
        case unchecked
        case watched(Outcome)
    }

    /// Sends on `service` (`attempt`: the service and how long to watch for it) and, when iMessage didn't take a phone
    /// number, once more as a text message. With no text-message account either, the first answer stands. An unchecked
    /// or unconfirmed send is never tried again: it may have gone out.
    static func deliver(handle: String, service: Service, attempt: (Service, TimeInterval) -> Attempt) -> (attempt: Attempt, service: Service) {
        let first = attempt(service, 8)
        guard first == .refused || first == .watched(.failed), canFallBack(handle: handle, from: service) else { return (first, service) }
        let second = attempt(.SMS, 6)
        return second == .refused ? (first, service) : (second, .SMS)
    }

    /// What aris-tools prints for a try, and whether it ends as success: only a message seen as sent does.
    static func result(_ attempt: Attempt, to: String, service: Service) -> (ok: Bool, line: String) {
        switch attempt {
        case .refused: return (false, ArisMessageResult.noAccount)
        case .unchecked: return (false, ArisMessageResult.notConfirmed(to, .unreadable))
        case .watched(.delivered), .watched(.sent): return (true, service == .iMessage ? ArisMessageResult.sent(to) : ArisMessageResult.sentAsText(to))
        case .watched(.failed): return (false, ArisMessageResult.notSent(to))
        case .watched(.unconfirmed): return (false, ArisMessageResult.notConfirmed(to, .notShown))
        }
    }
}
