//
//  ArisSaveText.swift
//  aris-agent
//
//  "방금 답을 … 파일로 저장해 줘", done by Aris itself (QA BUG-20b: the brain answered it by driving TextEdit's Save
//  panel, which saved an unrelated document in front). The app asks the user on its card, then sends the text here
//  (POST /save-text, the app's own call only); the file is written only inside the home folder, never in a protected
//  or hidden place, never over a file that is there, and read back before it is called saved.
//

import Foundation

enum ArisSaveText {
    static let maxBytes = 1_000_000
    static let kinds: Set<String> = ["txt", "md"]

    enum Outcome: Equatable {
        case saved(path: String)
        /// Why, as a code the app words for the user: outside, hidden, kind, protected, exists, empty, write, readback.
        case refused(String)
    }

    /// The file `path` names, if Aris may make it there: "~/…" or an absolute path in `home`, a .txt or .md name, no
    /// hidden or protected folder on the way (links resolved first), nothing there yet.
    static func target(_ path: String, home: String, files: FileManager = .default) -> (url: URL?, why: String) {
        let base = (home as NSString).standardizingPath
        let expanded = path.hasPrefix("~/") ? base + String(path.dropFirst(1)) : path
        guard expanded.hasPrefix("/") else { return (nil, "outside") }
        let standard = (expanded as NSString).standardizingPath
        guard standard.hasPrefix(base + "/") else { return (nil, "outside") }
        let inside = standard.dropFirst(base.count + 1).split(separator: "/").map(String.init)
        guard let name = inside.last, !inside.contains(where: { $0.hasPrefix(".") }) else { return (nil, "hidden") }
        guard kinds.contains((name as NSString).pathExtension.lowercased()), name.count <= 120 else { return (nil, "kind") }
        // The folder as it is on disk (a link could point anywhere): its nearest existing parent, resolved.
        var parent = (standard as NSString).deletingLastPathComponent
        while !files.fileExists(atPath: parent), parent.count > base.count { parent = (parent as NSString).deletingLastPathComponent }
        let resolvedParent = (parent as NSString).resolvingSymlinksInPath
        let resolvedBase = (base as NSString).resolvingSymlinksInPath
        guard resolvedParent == resolvedBase || resolvedParent.hasPrefix(resolvedBase + "/") else { return (nil, "outside") }
        // Where a link leads counts as much as its name: never into a hidden or protected place.
        if resolvedParent != resolvedBase {
            let parts = resolvedParent.dropFirst(resolvedBase.count + 1).split(separator: "/")
            guard !parts.contains(where: { $0.hasPrefix(".") }), !ArisProtectedPlaces.blocks(resolvedParent, home: resolvedBase) else {
                return (nil, "protected")
            }
        }
        // The file and its folder (the home folder itself only as the folder) are never a protected place.
        let folder = (standard as NSString).deletingLastPathComponent
        guard !ArisProtectedPlaces.blocks(standard, home: base), folder == base || !ArisProtectedPlaces.blocks(folder, home: base) else {
            return (nil, "protected")
        }
        guard !files.fileExists(atPath: standard) else { return (nil, "exists") }
        return (URL(fileURLWithPath: standard), "")
    }

    static func save(_ text: String, to path: String, home: String, files: FileManager = .default) -> Outcome {
        let data = Data(text.utf8)
        guard !text.isEmpty, data.count <= maxBytes else { return .refused("empty") }
        let (found, why) = target(path, home: home, files: files)
        guard let url = found else { return .refused(why) }
        do {
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.withoutOverwriting])
        } catch {
            return .refused("write")
        }
        // Read back: only a file holding exactly the text is called saved.
        guard (try? Data(contentsOf: url)) == data else { return .refused("readback") }
        return .saved(path: url.path)
    }
}
