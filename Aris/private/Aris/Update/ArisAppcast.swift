//
//  ArisAppcast.swift
//  Aris
//
//  The update feed the public build reads (Sparkle's appcast): one item per release, its zip on the GitHub release and
//  the zip's EdDSA signature (Sparkle's sign_update). The release script builds it with these functions
//  (release/make-appcast-main.swift beside them) and uploads it as the release's appcast.xml, which
//  …/releases/latest/download/appcast.xml always points at. Foundation only (tested).
//

import Foundation

enum ArisAppcast {
    static let repository = "LumenJSN/Aris"
    /// What the public build's SUFeedURL says: the newest release's appcast.xml.
    static let feed = "https://github.com/\(repository)/releases/latest/download/appcast.xml"
    static let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"

    static func zipName(version: String) -> String { "Aris-\(version).zip" }

    static func downloadURL(version: String) -> String {
        "https://github.com/\(repository)/releases/download/v\(version)/\(zipName(version: version))"
    }

    struct Item: Equatable {
        /// CFBundleVersion of the new app (Sparkle compares this one) and its CFBundleShortVersionString.
        var version: String
        var shortVersion: String
        var url: String
        var length: Int
        var edSignature: String
        var minimumSystemVersion: String
        var date: Date
    }

    /// sign_update's line (`sparkle:edSignature="…" length="…"`) as its two values; nil for anything else.
    static func parseSignUpdate(_ line: String) -> (signature: String, length: Int)? {
        func value(_ name: String) -> String? {
            guard let start = line.range(of: "\(name)=\"") else { return nil }
            let rest = line[start.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            return String(rest[..<end])
        }
        guard let signature = value("sparkle:edSignature"), let data = Data(base64Encoded: signature), data.count == 64,
              let length = value("length").flatMap(Int.init), length > 0 else { return nil }
        return (signature, length)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// RFC 822, in English and UTC, as RSS wants it.
    static func pubDate(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return format.string(from: date)
    }

    /// The whole feed. Titles say "Aris 1.3" for 1.3.0, as the release titles do.
    static func xml(items: [Item]) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="utf-8"?>"#,
            #"<rss version="2.0" xmlns:sparkle="\#(sparkleNamespace)">"#,
            "  <channel>",
            "    <title>Aris</title>",
            "    <link>https://github.com/\(repository)</link>",
        ]
        for item in items {
            let short = item.shortVersion.hasSuffix(".0") ? String(item.shortVersion.dropLast(2)) : item.shortVersion
            lines += [
                "    <item>",
                "      <title>Aris \(escape(short))</title>",
                "      <pubDate>\(pubDate(item.date))</pubDate>",
                "      <sparkle:version>\(escape(item.version))</sparkle:version>",
                "      <sparkle:shortVersionString>\(escape(item.shortVersion))</sparkle:shortVersionString>",
                "      <sparkle:minimumSystemVersion>\(escape(item.minimumSystemVersion))</sparkle:minimumSystemVersion>",
                "      <enclosure url=\"\(escape(item.url))\" length=\"\(item.length)\" type=\"application/octet-stream\" sparkle:edSignature=\"\(escape(item.edSignature))\"/>",
                "    </item>",
            ]
        }
        lines += ["  </channel>", "</rss>", ""]
        return lines.joined(separator: "\n")
    }
}
