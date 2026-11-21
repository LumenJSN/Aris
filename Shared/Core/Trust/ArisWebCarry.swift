//
//  ArisWebCarry.swift
//  Shared/Core (aris-agent, tests)
//
//  A read that goes out to a service (a web fetch or search, a map, a stock or currency quote, the weather) sends its
//  address or its words to someone else (Core 2 review, 2026-11-19). Until something private has been read in the
//  conversation nothing changes: it is a look. Once something private has been read (anything the tracker took in that
//  Aris did not itself fetch from the public web: a file, the screen, an app, a browser window's page, a focus with
//  text, mail, messages, the clipboard, memory, the record, a shell's output; sticky for the conversation:
//  ArisProvenanceTracker.privateRead), such a read is a look only when what it sends (the exact query, or the exact
//  address) appears verbatim in the owner's own words of this turn or an earlier one: raw characters, runs of white
//  space collapsed and the ends trimmed, nothing folded. Public web content never accounts for anything then (not a
//  link, not a phrase, whenever it was fetched). Anything else is outward: Aris's own step asks on a card that shows
//  all it sends and says something private was read (the yes covers that one call); content's is refused. The trust
//  gate applies it (ArisTrustGate.decide) to the registry's rows (ArisOutboundReads). Pure.
//

import Foundation

/// What an outbound read sends off the Mac.
struct ArisOutbound: Equatable, Sendable {
    /// The addresses it fetches.
    var urls: [String] = []
    /// The words it sends (a search, a place, a symbol, an amount and currencies).
    var queries: [String] = []
    /// Its result is the public web, fetched by Aris itself (web.fetch, web.search, aris-tools `web fetch`).
    var publicWeb = false

    /// All it sends, as one line for a card.
    var shown: String { (urls + queries.filter { !$0.isEmpty }).joined(separator: " ") }
}

enum ArisWebCarry {
    /// `text` with every run of white space as one space, the ends trimmed: the only change before comparing.
    static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

extension ArisProvenanceTracker {
    /// Something private has been read in this conversation (sticky: `privateRead`).
    var readPrivate: Bool { privateRead }

    /// The first thing an outbound read sends that doesn't appear verbatim in the owner's own words (this turn's or an
    /// earlier one's); nil when all of it does, or it sends nothing.
    func unaccounted(_ outbound: ArisOutbound) -> String? {
        let owner = ([turnText] + earlier).map(ArisWebCarry.collapsed)
        for sent in outbound.urls + outbound.queries {
            let exact = ArisWebCarry.collapsed(sent)
            if exact.isEmpty { continue }
            guard owner.contains(where: { $0.contains(exact) }) else { return sent }
        }
        return nil
    }
}
