//
//  ArisFocusApps.swift
//  Shared/Core/Focus (aris-agent, app, tests)
//
//  What a few kinds of app add on top of the generic tree reading: in a file browser selected rows are files, in a mail
//  app a selected row is a message (its sender and subject), in a calendar a selected thing is an event, in a chat app
//  the selected conversation is a person and the bottom field is where a reply goes, in a browser the web area is a
//  page. Everything else is read the generic way (selection, focused field, document, pointer, window), so an app that
//  isn't listed still works; the lists only sharpen the kind. Also the generic person reading: a "From:" or
//  "보낸 사람:" line, a "Name <address>", an address. Pure.
//

import Foundation

enum ArisFocusApps {
    enum Family: String, Equatable, Sendable {
        case files, mail, calendar, chat, browser, other
    }

    private static let families: [(Family, [String])] = [
        (.files, ["com.apple.finder", "com.cocoatech.pathfinder", "com.binarynights.forklift", "com.mrrsoftware.nstudio"]),
        (.mail, ["com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail", "com.mimestream.mimestream", "it.bloop.airmail",
                 "com.superhuman", "com.canarymail", "com.freron.mailmate", "org.mozilla.thunderbird"]),
        (.calendar, ["com.apple.ical", "com.flexibits.fantastical", "com.busymac.busycal", "com.google.calendar", "com.notion.calendar"]),
        (.chat, ["com.apple.mobilesms", "com.apple.ichat", "com.kakao.kakaotalkmac", "com.tinyspeck.slackmacgap", "com.hnc.discord",
                 "net.whatsapp.whatsapp", "desktop.whatsapp", "ru.keepcoder.telegram", "org.telegram.desktop", "jp.naver.line.mac",
                 "org.whispersystems.signal-desktop", "com.microsoft.teams", "com.facebook.archon", "com.naver.line"]),
        (.browser, ["com.apple.safari", "com.google.chrome", "company.thebrowser.browser", "com.brave.browser", "com.microsoft.edgemac",
                    "org.mozilla.firefox", "com.operasoftware.opera", "com.vivaldi.vivaldi", "com.kagi.kagimacos", "org.chromium.chromium"]),
    ]

    /// The app's family by its bundle id (a prefix match: "com.microsoft.teams2" is Teams).
    static func family(_ bundleID: String?) -> Family {
        guard let id = bundleID?.lowercased(), !id.isEmpty else { return .other }
        return families.first { $0.1.contains { id == $0 || id.hasPrefix($0 + ".") || id.hasPrefix($0) } }?.0 ?? .other
    }

    // MARK: - People

    private static let headerLine = #"^\s*(From|Sender|보낸\s?사람|발신자|보낸이)\s*[:：]\s*(.+?)\s*$"#
    private static let namedAddress = #"([^\n<>"“”,;:]{1,40}?)\s*<([^@\s<>]+@[^@\s<>]+)>"#
    private static let address = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#

    /// A mail header line that names the sender ("From: 민수 <m@x>", "보낸 사람: 엄마"), and nothing else: never a
    /// Subject, To or Cc line, never a bare address.
    static func headerSender(_ piece: String) -> String? {
        for line in piece.components(separatedBy: .newlines) {
            guard let found = line.range(of: headerLine, options: [.regularExpression, .caseInsensitive]) else { continue }
            let value = String(line[found]).replacingOccurrences(of: headerLine, with: "$2", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return String(value.prefix(120)) }
        }
        return nil
    }

    private static let senderLabels: Set<String> = ["from", "from:", "sender", "sender:", "보낸 사람", "보낸사람", "보낸 사람:", "발신자", "발신자:", "보낸이"]

    /// The app marks this element as the sender: its identifier names the sender ("sender", "MessageHeaderFrom"), or its
    /// description is a sender label that isn't its own words; never when it is marked subject, to, cc or bcc.
    static func labelsSender(_ node: ArisAXNode) -> Bool {
        guard !labelsOtherField(node) else { return false }
        if let identifier = node.identifier?.lowercased(), identifier.contains("sender") || identifier.hasSuffix("from") || identifier == "from" { return true }
        guard let label = node.label?.lowercased().trimmingCharacters(in: .whitespaces), senderLabels.contains(label) else { return false }
        return node.label != node.value && node.label != node.title
    }

    /// Marked as a subject, recipient or copy field (identifier or description).
    static func labelsOtherField(_ node: ArisAXNode) -> Bool {
        [node.identifier, node.label].compactMap { $0?.lowercased() }.contains { mark in
            mark.contains("subject") || mark.contains("제목") || mark.contains("참조") || mark.contains("받는")
                || mark.range(of: #"(^|[^a-z])(to|cc|bcc|recipients?)([^a-z]|$)"#, options: .regularExpression) != nil
                || mark.range(of: #"(to|cc|bcc|recipients?)$"#, options: .regularExpression) != nil && !mark.contains("sender")
        }
    }

    /// The name a sender-marked element holds: its value or title, else its children's first words (not the label).
    static func senderValue(_ node: ArisAXNode) -> String? {
        let own = [node.value, node.title].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
        let named = own.first { !$0.isEmpty && !senderLabels.contains($0.lowercased()) }
            ?? node.children.flatMap(\.words).first { !senderLabels.contains($0.lowercased()) }
        return named.map { String($0.prefix(120)) }
    }

    /// The cell of a row the app marks as the sender, as the row's trusted sender.
    static func markedSender(in row: ArisAXNode) -> String? {
        var found: String?
        row.walk { node, _ in
            if found == nil, labelsSender(node) { found = senderValue(node) }
        }
        return found
    }

    /// The person a text names as its writer: a header line, else a name with its address, else an address.
    static func person(in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            if let found = line.range(of: headerLine, options: [.regularExpression, .caseInsensitive]) {
                let value = String(line[found]).replacingOccurrences(of: headerLine, with: "$2", options: [.regularExpression, .caseInsensitive])
                if !value.isEmpty { return String(value.prefix(120)) }
            }
        }
        if let found = text.range(of: namedAddress, options: .regularExpression) {
            return String(text[found]).trimmingCharacters(in: .whitespaces)
        }
        if let found = text.range(of: address, options: .regularExpression) { return String(text[found]) }
        return nil
    }

    /// A list row's pieces: its own words and its children's, each once, in order.
    static func pieces(of row: ArisAXNode) -> [String] {
        var pieces: [String] = []
        row.walk { node, _ in
            for piece in node.words where !pieces.contains(piece) { pieces.append(piece) }
        }
        return pieces
    }

    /// A row of a mail list: the sender (its first piece that isn't a date or time) and the subject (the next).
    static func mailRow(_ pieces: [String]) -> (sender: String?, subject: String?) {
        let words = pieces.filter { !looksLikeTime($0) }
        return (words.first, words.dropFirst().first)
    }

    /// "오후 3:12", "10:42 AM", "어제", "2026. 11. 17.", "Yesterday", "11/17/26".
    static func looksLikeTime(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if ["어제", "오늘", "그저께", "yesterday", "today"].contains(trimmed.lowercased()) { return true }
        if trimmed.range(of: #"^(오전|오후)?\s?\d{1,2}:\d{2}(\s?(AM|PM|am|pm))?$"#, options: .regularExpression) != nil { return true }
        return trimmed.range(of: #"^\d{1,4}[./-]\s?\d{1,2}[./-]\s?\d{1,4}\.?$"#, options: .regularExpression) != nil
    }

    /// A chat window's title as the name of the other person: without the app's own name ("민수 – KakaoTalk"), and
    /// nothing when the title is only the app's name.
    static func chatPartner(title: String?, appName: String) -> String? {
        guard var title = title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return nil }
        for separator in [" – ", " — ", " - ", " | "] {
            if let range = title.range(of: separator + appName, options: [.caseInsensitive, .backwards]) { title = String(title[..<range.lowerBound]) }
        }
        let bare = title.trimmingCharacters(in: .whitespaces)
        let appWords: Set<String> = [appName.lowercased(), "messages", "메시지", "kakaotalk", "카카오톡", "slack", "discord", "whatsapp", "telegram", "line", "signal", "microsoft teams", "messenger"]
        return bare.isEmpty || appWords.contains(bare.lowercased()) ? nil : bare
    }

    /// A file URL ("file:///Users/x/a.pdf") or a path, as a path.
    static func path(fromDocument document: String?) -> String? {
        guard let document, !document.isEmpty else { return nil }
        if document.hasPrefix("/") { return document }
        guard let url = URL(string: document), url.isFileURL else { return nil }
        return url.path
    }
}
