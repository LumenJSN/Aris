//
//  ArisInsertText.swift
//  aris-agent
//
//  The details of typing dictation (the text-injector and clipboard rules): a trailing
//  space in terminals, an HTML copy with real links when the words hold URLs, and the clipboard timings: the paste
//  counts as read when the app asks the pasteboard for it within 2 s; the user's clipboard comes back 500 ms after a read
//  paste, or after 60 s when no read was seen (so he can still ⌘V it), and never over something copied meanwhile.
//  Foundation only (tested).
//

import Foundation

enum ArisInsertText {
    static let confirmWindow: TimeInterval = 2

    static func restoreDelay(confirmed: Bool) -> TimeInterval { confirmed ? 0.5 : 60 }

    /// A paste that comes while the last one is still under way (⌃⌘V right after a dictation) waits for it: tried
    /// again every `busyPoll`, for at most `busyWait` (a read paste's window and restore, with room to spare).
    static let busyPoll: TimeInterval = 0.1
    static let busyWait: TimeInterval = 3

    /// How long to wait before trying again, having waited `waited` already; nil: give up.
    static func busyRetry(waited: TimeInterval) -> TimeInterval? {
        waited < busyWait ? busyPoll : nil
    }

    /// The clipboard is put back only while it still holds what Aris put there.
    static func shouldRestore(changeCount: Int, ours: Int) -> Bool { changeCount == ours }

    /// What to paste: in a terminal, a trailing space so the next word doesn't run on (not after Japanese or Chinese,
    /// which have no spaces, or when there is one already).
    static func prepared(_ text: String, terminal: Bool) -> String {
        guard terminal, let last = text.unicodeScalars.last, !CharacterSet.whitespacesAndNewlines.contains(last),
              !isSpacelessScript(last) else { return text }
        return text + " "
    }

    /// The words as HTML with each URL a link, or nil when there is no URL (plain text is enough).
    static func html(for text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let string = text as NSString
        let links = detector.matches(in: text, range: NSRange(location: 0, length: string.length)).filter { $0.url != nil }
        guard !links.isEmpty else { return nil }
        var html = "", cursor = 0
        for link in links {
            html += escaped(string.substring(with: NSRange(location: cursor, length: link.range.location - cursor)))
            let shown = escaped(string.substring(with: link.range))
            let target = escaped(link.url?.absoluteString ?? string.substring(with: link.range))
            html += "<a href=\"\(target)\">\(shown)</a>"
            cursor = link.range.location + link.range.length
        }
        html += escaped(string.substring(from: cursor))
        return html.replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Han, Hiragana and Katakana.
    private static func isSpacelessScript(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x3040...0x30FF).contains(value) || (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value)
            || (0xFF66...0xFF9F).contains(value)
    }
}
