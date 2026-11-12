//
//  ArisLocalStore.swift
//  aris-tools
//
//  What the local app reads share (ArisLocalReads*): a SQLite database opened read-only, never written (immutable only
//  when the write-ahead log can't be read), so Messages, Mail and Notes are never disturbed; the Full Disk Access check (one Korean line, never a
//  prompt), Apple's dates, and the text rules: secrets (verification codes, passwords) masked, every snippet clipped,
//  attachments never returned, and the whole answer capped.
//

import Foundation
import SQLite3

enum ArisLocalStoreError: Error, Equatable {
    /// macOS refused the file: aris-agent has no Full Disk Access.
    case noDiskAccess
    /// The app was never set up on this Mac (no database).
    case missing
    /// The database isn't one this reader understands.
    case unreadable(String)
}

/// One read-only SQLite connection (never a write; immutable only as the fallback). Closed when released.
final class ArisLocalDatabase {
    private var handle: OpaquePointer?

    /// Opens `path` read-only. The file is first opened with open(2) so a TCC refusal (EPERM) is told apart from a
    /// missing app; nothing is read through that descriptor.
    init(path: String) throws {
        let fd = Darwin.open(path, O_RDONLY)
        if fd < 0 {
            switch errno {
            case EPERM, EACCES: throw ArisLocalStoreError.noDiskAccess
            case ENOENT, ENOTDIR: throw ArisLocalStoreError.missing
            default: throw ArisLocalStoreError.unreadable(String(cString: strerror(errno)))
            }
        }
        close(fd)
        // Read-only first, which still reads the write-ahead log (the newest messages live there until Messages
        // checkpoints). Only if that can't open or read does it fall back to immutable, which never looks at the
        // log or takes a lock.
        if let db = Self.connect(path, immutable: false) {
            handle = db
            mode = "ro"
        } else if let db = Self.connect(path, immutable: true) {
            handle = db
            mode = "immutable"
        } else {
            throw ArisLocalStoreError.unreadable("open failed")
        }
    }

    /// How it was opened: "ro" (the log read) or "immutable" (the fallback).
    private(set) var mode = ""

    /// A read-only connection that has read the schema, or nil.
    private static func connect(_ path: String, immutable: Bool) -> OpaquePointer? {
        // Another app's data (Messages, Mail, Notes): looked at again when this command has been waiting (ArisOrigin+Recheck).
        ArisOrigin.refuseUnlessStillAllowed()
        var components = URLComponents()
        components.scheme = "file"
        components.path = path
        components.queryItems = [URLQueryItem(name: "mode", value: "ro")] + (immutable ? [URLQueryItem(name: "immutable", value: "1")] : [])
        guard let uri = components.string else { return nil }
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return nil
        }
        // A read that waits too long on Messages' own writes gives up (a huge mailbox must not hang the turn).
        sqlite3_busy_timeout(db, 2000)
        guard sqlite3_exec(db, "SELECT count(*) FROM sqlite_master", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        return db
    }

    deinit { sqlite3_close(handle) }

    /// The column names of `table` (empty when it doesn't exist).
    func columns(_ table: String) -> Set<String> {
        guard table.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return [] }
        return Set((try? rows("PRAGMA table_info(\(table))"))?.compactMap { $0["name"] as? String } ?? [])
    }

    /// The rows of one query, each column by name (Int64, Double, String, Data or nothing for NULL). `bind`: text or
    /// numbers for ?1, ?2…
    func rows(_ sql: String, bind: [Any] = [], limit: Int = 5000) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ArisLocalStoreError.unreadable(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in bind.enumerated() {
            let slot = Int32(index + 1)
            switch value {
            case let text as String: sqlite3_bind_text(statement, slot, text, -1, transient)
            case let number as Int: sqlite3_bind_int64(statement, slot, Int64(number))
            case let number as Double: sqlite3_bind_double(statement, slot, number)
            default: sqlite3_bind_null(statement, slot)
            }
        }
        var result: [[String: Any]] = []
        while result.count < limit {
            let step = sqlite3_step(statement)
            guard step == SQLITE_ROW else {
                if step == SQLITE_DONE { break }
                throw ArisLocalStoreError.unreadable(String(cString: sqlite3_errmsg(handle)))
            }
            var row: [String: Any] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(statement, column)
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, column)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(statement, column))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    if let bytes = sqlite3_column_blob(statement, column), count > 0 { row[name] = Data(bytes: bytes, count: count) }
                default: break
                }
            }
            result.append(row)
        }
        return result
    }
}

enum ArisLocalStore {
    /// Said when Aris may not read an app's data: that Full Disk Access is off (a macOS update can turn it off),
    /// and where it is turned on. Nothing asks macOS; in a conversation Aris also shows a card under the answer whose
    /// button opens that list (ArisWidgetPick).
    static func diskAccessLine(_ app: String) -> String {
        "\(app) 데이터를 읽으려면 Aris에 전체 디스크 접근 권한이 필요한데, 지금 꺼져 있어요 (macOS 업데이트 뒤에 꺼졌을 수 있어요). "
            + "시스템 설정 › 개인정보 보호 및 보안 › \(ArisFix.Pane.disk.title(english: false))에서 Aris를 켜거나, 목록에 없으면 + 를 누르고 "
            + "응용 프로그램에서 Aris를 골라 켠 다음 다시 물어봐 주세요."
    }

    /// Why a screen read failed, said so the user knows what to do (QA after a macOS update: every screen read failed
    /// the same way, with no reason). Pure.
    enum ScreenFailure: Equatable {
        case noPermission
        case noWindow(String)
        case captureError(String)
    }

    /// Set (to anything) by aris-agent for its own look (ArisLook), in the environment `aris-tools screen` runs with: the
    /// reason a read failed goes into the English note the AI gets with the question, so it is said in English (VM run 2026-11-11: “… could not be read this time
    /// (Finder의 창이 화면에 없어서 읽지 못했어요.)” on an English turn). A brain that runs the tool itself gets it as before.
    static let englishLinesKey = "ARIS_ENGLISH_LINES"
    static func asksEnglish(_ environment: [String: String]) -> Bool { environment[englishLinesKey] != nil }

    static func screenLine(_ failure: ScreenFailure, korean: Bool = !asksEnglish(ProcessInfo.processInfo.environment)) -> String {
        switch failure {
        case .noPermission:
            return korean ? "화면을 읽으려면 Aris에 화면 기록 권한이 필요한데, 지금 꺼져 있어요 (macOS 업데이트 뒤에 꺼졌을 수 있어요). 시스템 설정 › 개인정보 보호 및 보안 › \(ArisFix.Pane.screen.title(english: false))에서 Aris를 켠 다음 다시 물어봐 주세요."
                : "Reading the screen needs Screen Recording for Aris, and it's off (a macOS update may have turned it off). Turn Aris on in System Settings › Privacy & Security › \(ArisFix.Pane.screen.title(english: true)), then ask again."
        case .noWindow(let app):
            return korean ? "\(app)의 창이 화면에 없어서 읽지 못했어요." : "\(app) has no window on screen, so there was nothing to read."
        case .captureError(let why):
            return korean ? "화면 기록 권한은 켜져 있는데 macOS가 화면을 넘겨주지 않았어요 (\(why)). 잠시 뒤에 다시 물어봐 주세요." : "Screen Recording is on, but macOS didn't hand over the screen (\(why)). Ask again in a moment."
        }
    }

    /// The line for a store error, in Korean (what the brain says on).
    static func line(_ error: Error, app: String) -> String {
        switch error as? ArisLocalStoreError {
        case .noDiskAccess?: return diskAccessLine(app)
        case .missing?: return "이 Mac에서 \(app) 데이터를 찾지 못했어요. \(app)을 한 번 열어 설정했는지 확인해 주세요."
        case .unreadable?, nil: return "\(app) 데이터를 읽지 못했어요 (형식이 바뀌었을 수 있어요)."
        }
    }

    // MARK: - Dates

    /// Apple's reference date (2001) in seconds or, past 1e11, nanoseconds (Messages since High Sierra).
    static func appleDate(_ value: Int64) -> Date {
        let seconds = Double(value) > 1e11 ? Double(value) / 1e9 : Double(value)
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// "11-05 14:03", in the Mac's time zone.
    static func stamp(_ date: Date, zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Limits

    /// A limit from `--limit N`, kept in 1…`maximum`; `fallback` when absent or unreadable.
    static func limit(_ args: [String], fallback: Int, maximum: Int) -> Int {
        guard let flag = args.firstIndex(of: "--limit"), flag + 1 < args.count, let value = Int(args[flag + 1]) else { return fallback }
        return min(maximum, max(1, value))
    }

    /// The value after `flag`, or nil.
    static func value(_ flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        let value = args[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// The words that aren't flags or their values (`flags`: the ones that take a value).
    static func plainWords(_ args: [String], flags: Set<String>) -> [String] {
        var words: [String] = [], skip = false
        for word in args {
            if skip { skip = false; continue }
            if flags.contains(word) { skip = true; continue }
            words.append(word)
        }
        return words
    }

    static let snippetLength = 200
    /// The whole answer, so a long read never floods the brain's context.
    static let answerLength = 6000

    /// Attachment marks and control characters out, whitespace folded to single spaces, secrets masked, clipped.
    /// `codeContext`: the text sits next to a code word elsewhere (a mail whose subject says "인증번호").
    static func snippet(_ text: String, length: Int = snippetLength, codeContext: Bool = false) -> String {
        let scalars = text.unicodeScalars.map { scalar -> Character in
            if scalar == "\u{FFFC}" || scalar == "\u{FFFD}" { return " " }
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) { return " " }
            return Character(scalar)
        }
        let folded = String(scalars).split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        let masked = redact(folded, codeContext: codeContext)
        return masked.count > length ? String(masked.prefix(length - 1)) + "…" : masked
    }

    /// Lines joined under a header that says whose words they are, cut at `answerLength`.
    static func answer(header: String, lines: [String]) -> String {
        var text = header
        for line in lines {
            guard text.count + line.count + 1 <= answerLength else { text += "\n(더 있지만 줄였어요)"; break }
            text += "\n" + line
        }
        return text
    }

    // MARK: - Secrets

    /// Words that say a number in the text is a code or a password.
    private static let codeWords = [
        "인증", "코드", "확인번호", "승인번호", "비밀번호", "암호", "보안", "일회용", "otp", "code", "verification", "verify", "passcode",
        "password", "2fa", "two-factor", "one-time", "security", "pin", "login", "log in", "sign in", "验证码", "認証",
    ]
    private static let codeMask = "[코드 가림]"
    private static let linkMask = "[링크 가림]"

    /// Verification codes and passwords masked. Always: "G-123456"-style codes. With a code word anywhere in the text:
    /// every 4–8 digit run (also split "123 456" / "123-456"), and the word after "password:" / "비밀번호:".
    static func redact(_ text: String, codeContext: Bool = false) -> String {
        // A link that carries a token (a password reset, a magic sign-in): the whole link, always (M7).
        var result = replace(#"(?i)\b(?:https?://|www\.)[^\s<>"']*(?:token|code|key|reset|login|signin|sign-in|verify|auth|magic|otp|password|session)[^\s<>"']*"#,
                             in: text, with: linkMask)
        result = replace(#"\b[A-Z]{1,3}-\d{4,8}\b"#, in: result, with: codeMask)
        guard codeContext || mentionsCode(result) else { return result }
        // Letters and digits mixed, 6–8 long ("K7Q2ZP", "a1b2c3d4"), next to a code word (M7).
        result = replace(#"(?<![A-Za-z0-9])(?=[A-Za-z0-9]*\d)(?=[A-Za-z0-9]*[A-Za-z])[A-Za-z0-9]{6,8}(?![A-Za-z0-9])"#, in: result, with: codeMask)
        // Not part of a longer number or a decimal (1,500 or 3.14), but a sentence's full stop may follow.
        result = replace(#"(?<!\d)(?<!\d[.,])\d{3,4}[ -]\d{3,4}(?!\d)(?![.,]\d)"#, in: result, with: codeMask)
        result = replace(#"(?<!\d)(?<!\d[.,])\d{4,8}(?!\d)(?![.,]\d)"#, in: result, with: codeMask)
        result = replace(#"(?i)(password|passcode|pin|비밀번호|암호)\s*[:：=]\s*(?!\[코드)\S+"#, in: result, with: "$1: " + codeMask)
        return result
    }

    /// A code word in the text: Korean, Chinese and Japanese ones anywhere, English ones as whole words ("pin", never
    /// "shopping").
    static func mentionsCode(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return codeWords.contains { word in
            guard word.unicodeScalars.allSatisfy(\.isASCII) else { return lowered.contains(word) }
            return lowered.range(of: "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b", options: .regularExpression) != nil
        }
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// `text` for a LIKE pattern: %, _ and the escape itself escaped (ESCAPE '\').
    static func likePattern(_ text: String) -> String {
        "%" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
    }
}
