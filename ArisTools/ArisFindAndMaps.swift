//
//  ArisFindAndMaps.swift
//  aris-tools
//
//  The pure halves of `files find` and `maps`.
//  - `files find "<words>" [--kind pdf|image|doc] [--in <folder>] [--limit N]`: one Spotlight query (names and
//    contents, optionally one kind), only inside the home folder or a folder in it; never a protected place, Library
//    or a hidden folder (ArisProtectedPlaces, ArisFiles.listable), and results go through ArisFiles.listable too.
//  - `maps directions "<from>" "<to>"` / `maps search "<words>"`: an Apple Maps link, opened in Maps (no Maps web
//    page, no other app). "here"/"여기"/"현재 위치" as the start means Maps' own current location.
//

import Foundation

enum ArisFindQuery {
    static let defaultLimit = 10
    static let maximum = 30
    static let kinds: [String: [String]] = [
        "pdf": ["com.adobe.pdf"],
        "image": ["public.image"],
        "doc": ["public.text", "com.microsoft.word.doc", "org.openxmlformats.wordprocessingml.document", "com.apple.iwork.pages.pages",
                "com.apple.iwork.pages.sffpages", "org.openxmlformats.presentationml.presentation", "org.openxmlformats.spreadsheetml.sheet",
                "com.apple.iwork.keynote.key", "com.apple.iwork.numbers.numbers", "public.rtf"],
    ]

    /// The words as Spotlight will read them: quotes, backslashes, wildcards and control characters taken out, at most
    /// 100 characters. Nil when nothing is left.
    static func cleaned(_ words: String) -> String? {
        let kept = words.unicodeScalars.filter { !"\"\\*'".unicodeScalars.contains($0) && !CharacterSet.controlCharacters.contains($0) }
        let text = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : String(text.prefix(100))
    }

    /// The most words one search looks for (the rest are left out).
    static let maxWords = 8

    /// mdfind's raw query: the name or the text contains every word (any case and accent, in any order: "세금 2025"
    /// finds "2025 세금 신고.pdf"; as one phrase it found nothing and the file was told as missing, audit tools-2), and
    /// with `kind`, of that kind. Nil for an unknown kind or no words.
    static func query(_ words: String, kind: String?) -> String? {
        guard let text = cleaned(words) else { return nil }
        var query = text.split(whereSeparator: \.isWhitespace).prefix(maxWords)
            .map { "(kMDItemFSName == \"*\($0)*\"cd || kMDItemTextContent == \"*\($0)*\"cd)" }.joined(separator: " && ")
        if let kind {
            guard let types = kinds[kind.lowercased()] else { return nil }
            query += " && (" + types.map { "kMDItemContentTypeTree == \"\($0)\"" }.joined(separator: " || ") + ")"
        }
        return query
    }

    /// The folder to search: `folder` (~ and links resolved) when it is a real folder inside `home` that may be listed
    /// (iCloud Drive and its folders too) and isn't protected; the home folder when none was given; nil when the folder
    /// isn't allowed.
    static func folder(_ folder: String?, home: String) -> String? {
        guard let folder else { return home }
        let expanded = folder == "~" ? home : folder.hasPrefix("~/") ? home + folder.dropFirst() : folder
        guard expanded.hasPrefix("/") else { return nil }
        let real = URL(fileURLWithPath: expanded).resolvingSymlinksInPath().standardizedFileURL.path
        if real == home { return home }
        guard real == ArisFiles.cloudDriveFolder(home: home) || ArisFiles.listable(real, home: home), !ArisProtectedPlaces.blocks(real, home: home) else { return nil }
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: real, isDirectory: &isFolder) && isFolder.boolValue ? real : nil
    }
}

enum ArisMapsLink {
    /// Words that mean "where I am now" as a start.
    static let here: Set<String> = ["here", "current location", "my location", "여기", "현재 위치", "지금 위치", "내 위치", "현위치"]

    private static func clean(_ text: String) -> String? {
        let kept = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let value = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        return value.isEmpty || value.count > 200 ? nil : value
    }

    /// maps://?saddr=…&daddr=… (no saddr from here); nil when a place is empty or too long.
    static func directions(from: String, to: String) -> URL? {
        guard let destination = clean(to), let start = clean(from) else { return nil }
        let items = (here.contains(start.lowercased()) ? [] : [("saddr", start)]) + [("daddr", destination)]
        return link(items)
    }

    /// maps://?q=…; nil when the words are empty or too long.
    static func search(_ words: String) -> URL? {
        guard let query = clean(words) else { return nil }
        return link([("q", query)])
    }

    /// Every character but letters, digits and -._~ percent-encoded, so a place's "&" or "=" can't add a parameter.
    private static let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    private static func link(_ items: [(String, String)]) -> URL? {
        let query = items.compactMap { name, value in value.addingPercentEncoding(withAllowedCharacters: plain).map { "\(name)=\($0)" } }
        return query.count == items.count ? URL(string: "maps://?" + query.joined(separator: "&")) : nil
    }
}
