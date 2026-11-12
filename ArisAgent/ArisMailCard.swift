//
//  ArisMailCard.swift
//  aris-agent
//
//  Sending mail (audit gate-9). It was refused outright ("메일은 초안까지만") while the same mail through a connected
//  service went out after a card. Now a connector's send asks the user every time on a card that shows who it goes to, its
//  subject and its whole text, nothing cut: never a standing permission, never learned, never the judge's. A send whose
//  recipient or text isn't in the call itself (a draft sent by its id, a mail program fed from a file) can't be shown,
//  so it is still refused, and the brain is told to send it with everything in the call. Pure, so the tests run it.
//

import Foundation

enum ArisMailCard {
    static let title = "메일 보내기"

    /// A parameter that says who the mail goes to.
    static func isRecipient(_ key: String) -> Bool {
        let name = key.lowercased()
        return name == "to" || name.hasPrefix("to_") || name.contains("recipient")
    }

    /// A parameter that carries the mail's text.
    static func isBody(_ key: String) -> Bool {
        let name = key.lowercased()
        return name.contains("body") || ["content", "text", "message", "html"].contains(name)
    }

    private static func isSubject(_ key: String) -> Bool { ["subject", "title"].contains(key.lowercased()) }

    private static func isCopy(_ key: String) -> Bool { ["cc", "bcc"].contains(key.lowercased()) }

    private static func hasText(_ value: Any?) -> Bool {
        switch value {
        case let text as String: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let list as [Any]: return list.contains { hasText($0) }
        case let object as [String: Any]: return object.values.contains { hasText($0) }
        default: return false
        }
    }

    /// The card's lines for a mail-sending tool's parameters: every one of them, uncut, the recipients first, then the
    /// subject, the text, and whatever else the call carries (attachments, a thread). Nil when the call doesn't itself
    /// hold a recipient and a text: then the card couldn't show what goes out.
    static func lines(_ arguments: [String: Any], timeZone: TimeZone = .current, english: Bool = false) -> [String]? {
        guard arguments.contains(where: { isRecipient($0.key) && hasText($0.value) }),
              arguments.contains(where: { isBody($0.key) && hasText($0.value) }), !answersEveryone(arguments) else { return nil }
        let rank = { (key: String) -> Int in isRecipient(key) ? 0 : isCopy(key) ? 1 : isSubject(key) ? 2 : isBody(key) ? 3 : 4 }
        let keys = arguments.keys.sorted { (rank($0), $0) < (rank($1), $1) }
        // Shown as the other cards show a brain's words: line breaks kept, anything invisible made visible.
        return keys.compactMap { ArisCodexDriver.paramLine(name: $0, display: nil, value: arguments[$0], timeZone: timeZone, limit: nil, english: english) }
            .map(ArisDesktopCard.shown)
    }

    /// A switch that sends a reply to everyone on the mail it answers (replyAll, reply_all, reply_to_all): who they are
    /// isn't in the call, so the card couldn't show every recipient.
    static func answersEveryone(_ arguments: [String: Any]) -> Bool {
        arguments.contains { key, value in
            let name = key.lowercased().filter(\.isLetter)
            guard name.contains("replyall") || name.contains("replytoall") || name == "all" else { return false }
            if let text = value as? String { return !["", "false", "no", "0"].contains(text.lowercased().trimmingCharacters(in: .whitespaces)) }
            return (value as? NSNumber)?.boolValue ?? !(value is NSNull)
        }
    }

    /// Whether `action` is a connector's mail send whose card shows everything (`lines`): only that one is put to the user;
    /// any other definite mail send stays refused (ArisEscalation.decide).
    static func shows(_ action: ArisAction, arguments: [String: Any]) -> Bool {
        guard case .mcp = action else { return false }
        return lines(arguments) != nil
    }
}
