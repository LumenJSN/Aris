//
//  ArisToolScope.swift
//  aris-agent
//
//  What a known MCP tool call is aimed at, read field by field from the tool's own schema (Notion's, listed with
//  a read-only tools/list on 2026-11-03). Every recipient and target found at any depth makes up the scope, and each
//  must look like an id, an email or a phone number; a few switches (a notify flag, a page command) are folded into
//  its kind, each only from its field's own values; benign fields must have the expected shape, and text must not
//  carry a mention, link or embed. A key the schema below doesn't name, or a value of the wrong shape, means the
//  call isn't fully scoped, and only the user may approve it.
//

import Foundation

indirect enum ArisField {
    /// Names who or what the call acts on (a string, or a list of them, each shaped like an id): part of the scope.
    case target
    /// Words that are only said: a string with no mention, link or embed in it.
    case text
    /// A short value (a date, a time zone, an enum, an RRULE): a string that isn't a link.
    case word
    /// A string that isn't a link (an emoji icon).
    case noLink
    case flag
    case number
    /// A string folded into the kind ("+replace_content"): only one of these values.
    case kind(Set<String>)
    /// A notify switch: true or a string other than "none" adds "+notify" to the kind.
    case notify
    /// Only null is allowed (a link field in a plain text run).
    case absent
    case object([String: ArisField])
    case list(ArisField)
}

/// What a walk found: the scope's identities, the kind's additions, and whether every field was understood.
struct ArisToolScope: Equatable {
    var targets: [String] = []
    var kindParts: [String] = []
    var complete = true
}

enum ArisToolSchemas {
    /// The schema for a tool Aris knows field by field; nil for any other.
    static func spec(server: String, tool: String) -> [String: ArisField]? {
        guard server == "aris_notion" else { return nil }
        return notion[tool]
    }

    static func walk(_ arguments: [String: Any], spec: [String: ArisField]) -> ArisToolScope {
        var found = ArisToolScope()
        visit(arguments, .object(spec), key: "", into: &found)
        found.targets = Array(Set(found.targets)).sorted()
        found.kindParts = Array(Set(found.kindParts)).sorted()
        return found
    }

    /// Rich text as Notion writes it: plain text runs, and user mentions (whose ids are targets).
    static let richText: ArisField = .list(.object([
        "type": .word,
        "text": .object(["content": .text, "link": .absent]),
        "mention": .object(["type": .word, "user": .object(["id": .target])]),
        "annotations": .object(["bold": .flag, "italic": .flag, "strikethrough": .flag, "underline": .flag, "code": .flag, "color": .word]),
        "plain_text": .text,
    ]))

    private static func visit(_ value: Any, _ field: ArisField, key: String, into found: inout ArisToolScope) {
        if value is NSNull { return }
        switch field {
        case .target:
            if let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { found.targets.append(trimmed) }
                // Anything not shaped like an id could be words aimed at whoever reads the scope.
                if !isIdentity(trimmed) { found.complete = false }
            } else if let list = value as? [Any] {
                for item in list { visit(item, .target, key: key, into: &found) }
            } else { found.complete = false }
        case .text:
            guard let text = value as? String, !hidesTarget(text) else { return found.complete = false }
        case .word, .noLink:
            guard let text = value as? String, !isLink(text) else { return found.complete = false }
        case .flag:
            if !isBool(value) { found.complete = false }
        case .number:
            if !(value is NSNumber) || isBool(value) { found.complete = false }
        case .kind(let allowed):
            guard let text = value as? String, !text.isEmpty else { return found.complete = false }
            // Kept even when unknown, so the hard lines still see it (hardLine reads the kind parts).
            found.kindParts.append(text)
            if !allowed.contains(text) { found.complete = false }
        case .notify:
            if isBool(value), let on = value as? Bool {
                if on { found.kindParts.append("notify") }
            } else if let text = value as? String {
                if !["none", "false", ""].contains(text.lowercased()) { found.kindParts.append("notify") }
            } else { found.complete = false }
        case .absent:
            found.complete = false
        case .object(let fields):
            guard let object = value as? [String: Any] else { return found.complete = false }
            let byName = Dictionary(fields.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
            for (name, inner) in object {
                guard let innerField = byName[name.lowercased()] else {
                    found.complete = false
                    continue
                }
                visit(inner, innerField, key: name, into: &found)
            }
        case .list(let item):
            guard let list = value as? [Any] else { return found.complete = false }
            for element in list { visit(element, item, key: key, into: &found) }
        }
    }

    /// A target's shape: a UUID, an id of letters, digits, _ and - (at most 128), an email, or a phone number
    /// (digits with an optional + and - or space separators).
    static func isIdentity(_ text: String) -> Bool {
        let patterns = [
            #"^[0-9A-Fa-f]{8}-?[0-9A-Fa-f]{4}-?[0-9A-Fa-f]{4}-?[0-9A-Fa-f]{4}-?[0-9A-Fa-f]{12}$"#,
            #"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$"#,
            #"^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{1,63}$"#,
            #"^\+?[0-9][0-9 -]{5,18}[0-9]$"#,
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// Markdown or Notion syntax that can name someone or something: a mention, a link, an embed or template, a
    /// page, database or data-source tag, or a url= attribute.
    static func hidesTarget(_ text: String) -> Bool {
        ["<mention-", "](", "://", "{{", "@[", "<page", "<database", "<data-source", "url="].contains(where: text.lowercased().contains)
    }

    /// A JSON true or false (not a number that happens to be 0 or 1).
    private static func isBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func isLink(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("://") || lowered.hasPrefix("www.") || lowered.hasPrefix("mailto:")
    }

    // MARK: - Notion (the reviewer's sets, on the field names the server lists)

    private static let notifySwitches: [String: ArisField] = ["sendUpdates": .notify, "notify": .notify, "send_notifications": .notify]
    /// What Notion's tools take along with every call, in these exact shapes only.
    private static let metadata: [String: ArisField] = ["instructions_version": .word, "skill": .word, "allow_async": .flag,
                                                        "telemetry": .object(["intent": .text, "feedback": .text])]
    /// The values Notion's server lists for the fields folded into a kind.
    private static let updateTypes: Set<String> = ["RSVP", "UPDATE"]
    private static let responses: Set<String> = ["accepted", "declined", "tentative"]
    private static let pageCommands: Set<String> = ["update_properties", "update_content", "replace_content", "insert_content", "apply_template",
                                                    "update_verification"]
    private static let moment: ArisField = .object(["date": .word, "dateTime": .word, "timeZone": .word])
    private static let person: ArisField = .object(["email": .target, "displayName": .text, "isOptional": .flag])
    private static let calendar: ArisField = .object(["accountId": .target, "calendarId": .target])

    /// An event's benign fields: title, summary, description, location (a string), start and end, time zones, all
    /// day, reminders, RRULE recurrence, color, transparency, and conferencing only as a plain switch. Attendees,
    /// resources and rooms are targets. Attachments, visibility, guestsCan*, URLs and conference data are not listed.
    private static let eventFields: [String: ArisField] = [
        "title": .text, "summary": .text, "description": .text, "location": .text,
        "period": .object(["type": .word, "start": moment, "end": moment]), "start": moment, "end": moment,
        "timeZone": .word, "timezone": .word, "time_zone": .word, "all_day": .flag, "allDay": .flag,
        "reminders": .list(.object(["method": .word, "minutes": .number])),
        "recurrence": .list(.word), "recurrenceRules": .list(.word), "color": .word, "transparency": .word,
        "attendees": .list(person), "resources": .list(person), "rooms": .list(person),
        "disableConferencing": .flag, "addConferencing": .flag,
    ].merging(notifySwitches) { $1 }

    private static let pageEdit: [String: ArisField] = [
        "page_id": .target, "command": .kind(pageCommands), "new_str": .text, "content": .text, "selection_with_ellipsis": .text,
        "properties": .object(["title": .text]),
    ]

    private static let notion: [String: [String: ArisField]] = notionTools.mapValues { $0.merging(metadata) { first, _ in first } }

    private static let notionTools: [String: [String: ArisField]] = [
        "notion-calendar-create-events": [
            "timeZone": .word, "timezone": .word, "time_zone": .word,
            "events": .list(.object(eventFields.merging(["calendar": calendar, "calendarId": .target, "calendar_id": .target]) { $1 })),
        ].merging(notifySwitches) { $1 },
        "notion-calendar-update-events": [
            "timeZone": .word, "timezone": .word, "time_zone": .word,
            "updates": .list(.object([
                "updateType": .kind(updateTypes),
                "event": .object(["calendar": calendar, "eventId": .target, "eventSummary": .text]),
                "rsvp": .object(["responseStatus": .kind(responses)]),
                "update": .object(eventFields.merging(["addAttendees": .list(person), "removeAttendees": .list(person),
                                                       "add_attendees": .list(person), "remove_attendees": .list(person)]) { $1 }),
            ])),
        ].merging(notifySwitches) { $1 },
        "notion-create-pages": [
            "parent": .object(["page_id": .target, "database_id": .target, "data_source_id": .target, "teamspace_id": .target, "type": .word]),
            "pages": .list(.object([
                // Title and Name are benign; people, relation, email, URL and phone properties name targets.
                "properties": .object(["title": .text, "Name": .text, "people": .target, "person": .target, "relation": .target,
                                       "email": .target, "url": .target, "phone": .target]),
                "content": .text, "icon": .noLink, "cover": .noLink,
            ])),
        ],
        "notion-update-page": pageEdit.merging(["data": .object(pageEdit)]) { $1 },
        "notion-create-comment": [
            "page_id": .target, "discussion_id": .target, "rich_text": richText,
        ],
    ]
}
