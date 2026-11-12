//
//  ArisShelfItem.swift
//  Aris
//
//  One thing on the shelf: a file (kept as a security-scoped bookmark), a piece of text, or a link. The stored
//  shape — `{ "id", "kind": { "type": "file" | "text" | "link", "value": … }, "isTemporary" }` — is what earlier
//  builds wrote to items.json, so existing shelves load.
//

import AppKit
import Foundation

enum ShelfItemKind: Hashable {
    case file(bookmark: Data)
    case text(String)
    case link(URL)
}

extension ShelfItemKind: Codable {
    private enum Keys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: Keys.self)
        switch try box.decode(String.self, forKey: .type) {
        case "file": self = .file(bookmark: try box.decode(Data.self, forKey: .value))
        case "text": self = .text(try box.decode(String.self, forKey: .value))
        case "link": self = .link(try box.decode(URL.self, forKey: .value))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: box, debugDescription: "unknown shelf item type \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: Keys.self)
        switch self {
        case .file(let bookmark): try box.encode("file", forKey: .type); try box.encode(bookmark, forKey: .value)
        case .text(let text): try box.encode("text", forKey: .type); try box.encode(text, forKey: .value)
        case .link(let url): try box.encode("link", forKey: .type); try box.encode(url, forKey: .value)
        }
    }
}

struct ShelfItem: Identifiable, Hashable, Codable {
    let id: UUID
    var kind: ShelfItemKind
    /// Aris made the backing file (dropped data, text or a link written out); removing the item deletes it.
    var isTemporary: Bool

    init(id: UUID = UUID(), kind: ShelfItemKind, isTemporary: Bool = false) {
        self.id = id
        self.kind = kind
        self.isTemporary = isTemporary
    }

    /// The file behind a file item, if its bookmark still resolves.
    var fileURL: URL? {
        guard case .file(let data) = kind else { return nil }
        return ArisBookmark(data: data).resolvedURL()
    }

    var displayName: String {
        switch kind {
        case .file: fileURL.map(ArisShelfNames.file) ?? ""
        case .text(let text): ArisShelfNames.text(text)
        case .link(let url): ArisShelfNames.link(url)
        }
    }

    /// Two items with the same identity are the same thing on the shelf.
    var identity: String {
        switch kind {
        case .file(let data):
            if let url = fileURL { return "file://" + url.standardizedFileURL.path }
            return "missing://" + data.base64EncodedString()
        case .link(let url): return "link://" + url.absoluteString
        case .text(let text): return "text://" + text
        }
    }

    /// What the tile shows until (or instead of) a thumbnail.
    var icon: NSImage {
        switch kind {
        case .file:
            guard let url = fileURL else { return ArisShelfIcons.symbol("questionmark.circle") }
            return ArisFileIcons.icon(forFile: url.path)
        case .text: return ArisShelfIcons.card("text.justifyleft")
        case .link: return ArisShelfIcons.card("link")
        }
    }
}

/// The display-name rules (spec 07, A19). Pure apart from reading the two compatibility file formats.
enum ArisShelfNames {
    static func text(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func link(_ url: URL) -> String {
        let text = url.absoluteString
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) { return String(text.dropFirst(scheme.count)) }
        return text
    }

    static func file(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "json", url.path.contains("TextBlocks"), let data = try? Data(contentsOf: url), let name = textBlock(data) { return name }
        if ext == "webloc", url.path.contains("WebLocs"), let data = try? Data(contentsOf: url), let name = webLoc(data) { return name }
        let localized = (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName
        return localized ?? url.lastPathComponent
    }

    /// A TextBlocks JSON: its title, else the first line of its content (47 characters + "..." past 50).
    static func textBlock(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? String else { return nil }
        if let title = object["title"] as? String, !title.isEmpty { return title }
        let line = content.components(separatedBy: .newlines).first ?? ""
        return line.count > 50 ? String(line.prefix(47)) + "..." : line
    }

    /// A WebLocs plist: its title, else its URL.
    static func webLoc(_ data: Data) -> String? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let url = object["URL"] as? String else { return nil }
        if let title = object["Title"] as? String, !title.isEmpty { return title }
        return url
    }
}
