//
//  ArisHistoryRestore.swift
//  Aris
//
//  A past turn shown again as it was (side 2: the user wanted the conversation as it was, not just 이어서 말해 주세요).
//  Pressing a history row opens the notch on that turn (your words, the answer with its formatting, its
//  card with the values it had, and when it was), nothing is said aloud and the microphone stays shut, the composer is
//  there, and the next thing said or typed carries that turn as its context, to whichever AI answers (a new session of
//  that AI: none of them is asked to resume an old one). A card from the past is history: it is shown with its buttons
//  off, a confirm card is never restored at all, and the timer's and the music's cards (which show what is on now,
//  not what was) are not restored.
//
//  What is stored per turn: the words, the answer as the notch showed it (whole, with its markdown), and from now on
//  the answer's card with its values (`card`), saved once the values arrive. Older rows have no card and show as
//  their words and answer. Foundation only (tested).
//

import Foundation

/// The card a turn showed and the values it had then.
struct ArisHistoryCard: Codable, Equatable, Sendable {
    enum Values: Codable, Equatable, Sendable {
        case weather(ArisWeatherCard)
        case calendar([ArisWidgetEvent])
        case todo(ArisTodoCard)
        case stock(ArisStockCard)
        /// Without its picture: the still is not kept, and is not fetched again for a past turn.
        case map(ArisMapCard)
    }

    /// ArisWidgetKind's raw value.
    let kind: String
    var place: String?
    var symbol: String?
    var from: String?
    /// The calendar card's day (nil: today, and every card kept before it had one).
    var day: String?
    let values: Values

    init(request: ArisWidgetRequest, values: Values) {
        kind = request.kind.rawValue
        place = request.place
        symbol = request.symbol
        from = request.from
        day = request.day
        self.values = values
    }

    /// The request the card answered; nil for a kind this version no longer has.
    var request: ArisWidgetRequest? {
        ArisWidgetKind(rawValue: kind).map { ArisWidgetRequest(kind: $0, place: place, symbol: symbol, from: from, day: day) }
    }
}

enum ArisHistoryRestore {
    /// A past turn the notch is showing again: which, when it was, and the words it was put up with.
    struct Shown: Equatable, Sendable {
        let id: UUID
        let date: Date
        let heard: String
        let reply: String

        /// Still what the notch shows: idle, with those very words. Anything else (a new turn, 닫기, another answer)
        /// and the turn on screen is no longer this one.
        func isOn(_ session: ArisSession) -> Bool {
            session.phase == .idle && session.heard == heard && session.reply == reply
        }
    }

    /// What a row whose answer was never saved says.
    static func emptyAnswer(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("이 대화는 저장된 답이 없어요.", "No answer was saved for this conversation.", english: english)
    }

    /// The answer the notch shows for a row: its own, whole; never anything made up.
    static func reply(of entry: ArisHistoryEntry, english: Bool = ArisUIWords.english) -> String {
        entry.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? emptyAnswer(english: english) : entry.reply
    }

    static func shown(_ entry: ArisHistoryEntry, english: Bool = ArisUIWords.english) -> Shown {
        Shown(id: entry.id, date: entry.date, heard: entry.heard, reply: reply(of: entry, english: english))
    }

    /// The small line over a restored turn, saying it is from the history and when: "기록 · 어제 오후 3:42".
    static func caption(_ date: Date, now: Date = Date(), timeZone: TimeZone = .current, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        ArisUIWords.text("기록", "History", english: english) + " · "
            + ArisHistory.sessionHeader(date, now: now, timeZone: timeZone, english: english, locale: locale)
    }

    /// The history with `card` saved on the turn it belongs to: the newest row with that answer and no card yet.
    /// Nothing changes when there is no such row (the turn was not recorded, or was deleted meanwhile).
    static func attaching(_ card: ArisHistoryCard, toReply reply: String, in list: [ArisHistoryEntry]) -> [ArisHistoryEntry] {
        guard let index = list.firstIndex(where: { $0.reply == reply && $0.card == nil && $0.file == nil }),
              let data = try? JSONEncoder().encode(card) else { return list }
        var next = list
        next[index].card = data
        return next
    }

    /// The card a row was saved with; nil when it has none, or one this version cannot read (never a guess).
    static func card(of entry: ArisHistoryEntry) -> ArisHistoryCard? {
        entry.card.flatMap { try? JSONDecoder().decode(ArisHistoryCard.self, from: $0) }
    }
}

extension Notification.Name {
    /// A past turn was put back in the notch (ArisController.resume): the notch under the pointer opens on it.
    static let arisHistoryRestored = Notification.Name("com.lumenjsn.aris.historyRestored")
}
