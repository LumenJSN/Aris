//
//  ArisResultPath.swift
//  aris-agent
//
//  Which saved task results the app may read, open or save as a note (POST /open, POST /result), and the words
//  메모에 저장 gives Notes. A path is taken only when it is absolute, has no "..", names a .md file right inside one of
//  the result folders, and still does once every link in it is followed. Pure, so it's tested.
//

import Foundation

enum ArisResultPath {
    /// The most of a result the reader is sent.
    static let readLimit = 2_000_000

    /// The file `path` names, or nil unless it is a saved result in one of `folders`.
    static func resolve(_ path: String, in folders: [URL]) -> URL? {
        guard path.hasPrefix("/"), !path.contains("\u{0}"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else { return nil }
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard file.pathExtension.lowercased() == "md" else { return nil }
        let parent = file.deletingLastPathComponent().standardizedFileURL.path
        guard folders.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL.path == parent }) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes?[.type] as? FileAttributeType == .typeRegular else { return nil }
        return file
    }

    /// The most of a result 메모에 저장 sends to Notes (bytes); a longer one is cut at a line and ends in "…".
    static let noteLimit = 200_000

    /// A result as `note --markdown` takes it: whole, or cut at the last line break before noteLimit bytes.
    static func noteMarkdown(_ markdown: String) -> String {
        guard markdown.utf8.count > noteLimit else { return markdown }
        var cut = String(decoding: markdown.utf8.prefix(noteLimit), as: UTF8.self)
        if let line = cut.lastIndex(of: "\n") { cut = String(cut[..<line]) }
        return cut + "\n…"
    }

    /// A result as a note: its title on the first line (Notes' title), then its lines without markdown marks; a
    /// link keeps its address in brackets, an image its words. Blank runs become one blank line.
    static func noteText(_ markdown: String) -> String {
        var lines: [String] = []
        for raw in markdown.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { continue }
            line = line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^[-*+]\s+"#, with: "• ", options: .regularExpression)
            line = line.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: #"\[([^\]]*)\]\(([^)]*)\)"#, with: "$1 ($2)", options: .regularExpression)
            line = line.replacingOccurrences(of: #"(\*\*|__|`)"#, with: "", options: .regularExpression)
            if line.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}
