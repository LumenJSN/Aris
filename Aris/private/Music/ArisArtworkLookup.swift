//
//  ArisArtworkLookup.swift
//  Aris
//
//  Album art for Music tracks that have none to script (streamed ones): asks the iTunes Search API and picks the
//  result whose album (or, without an album, song) and artist match loosely — ignoring case, accents and edition
//  suffixes like "(Deluxe Edition)" or " - Single", and accepting one name that starts with the other. Results are
//  cached per album.
//

import Foundation

enum ArisArtworkLookup {
    /// A name reduced for loose comparison.
    static func normalized(_ name: String) -> String {
        var text = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Edition suffixes, outermost first, until none is left: "(Deluxe Edition)", "[Remastered 2011]", " - Single".
        while let shorter = withoutSuffix(text), shorter != text { text = shorter }
        return text
    }

    /// `text` without one trailing bracketed part or " - …" part; nil if it has neither.
    private static func withoutSuffix(_ text: String) -> String? {
        if let last = text.last, last == ")" || last == "]" {
            let open: Character = last == ")" ? "(" : "["
            guard let start = text.lastIndex(of: open), start != text.startIndex else { return nil }
            return String(text[..<start]).trimmingCharacters(in: .whitespaces)
        }
        if let dash = text.range(of: " - ", options: .backwards), dash.lowerBound != text.startIndex {
            return String(text[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Equal, or one starts with the other, once both are normalised.
    static func matches(_ a: String, _ b: String) -> Bool {
        let x = normalized(a), y = normalized(b)
        return !x.isEmpty && !y.isEmpty && (x.hasPrefix(y) || y.hasPrefix(x))
    }

    /// The cache key: one per album (per song when there is no album).
    static func key(title: String, artist: String, album: String) -> String {
        normalized(artist) + "\u{1F}" + normalized(album.isEmpty ? title : album)
    }

    static func searchURL(title: String, artist: String, album: String) -> URL? {
        var parts = URLComponents(string: "https://itunes.apple.com/search")
        parts?.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(album.isEmpty ? title : album)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: album.isEmpty ? "song" : "album"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        return parts?.url
    }

    /// The artwork URL (600 × 600) of the first result that matches, from a search response body.
    static func artworkURL(in body: Data, title: String, artist: String, album: String) -> URL? {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return nil }
        let wanted = album.isEmpty ? title : album
        let field = album.isEmpty ? "trackName" : "collectionName"
        for result in results {
            guard let name = result[field] as? String, matches(name, wanted) else { continue }
            if !artist.isEmpty, let by = result["artistName"] as? String, !artistMatches(by, artist) { continue }
            guard let small = result["artworkUrl100"] as? String else { continue }
            return URL(string: small.replacingOccurrences(of: "100x100", with: "600x600"))
        }
        return nil
    }

    /// Artists match when one normalised name contains the other ("Artist" and "Artist & Friend").
    private static func artistMatches(_ a: String, _ b: String) -> Bool {
        let x = normalized(a), y = normalized(b)
        return !x.isEmpty && !y.isEmpty && (x.contains(y) || y.contains(x))
    }
}
