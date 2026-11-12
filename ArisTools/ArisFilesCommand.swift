//
//  ArisFilesCommand.swift
//  aris-tools
//
//  `find` and `open` (ArisFiles decides what may be listed or opened).
//

import Foundation

func findFiles(_ args: [String]) {
    let words = args.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    guard !words.isEmpty else { fail("usage: find <words>") }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    // Files named that come first; files that only mention it in their contents after (they matched loosely).
    let named = run("/usr/bin/mdfind", ["-onlyin", home, "-name", words]).split(separator: "\n").map(String.init)
    let mentioned = run("/usr/bin/mdfind", ["-onlyin", home, words]).split(separator: "\n").map(String.init)
    func dated(_ paths: [String]) -> [(String, Date)] {
        paths.filter { ArisFiles.listable($0, home: home) }.prefix(400).compactMap { path -> (String, Date)? in
            guard let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return nil }
            return (path, date)
        }.sorted { $0.1 > $1.1 }
    }
    let byName = dated(named)
    let names = Set(byName.map(\.0))
    let newest = (byName + dated(mentioned.filter { !names.contains($0) })).prefix(ArisFiles.shown)
    // Matches left out for their names are said, so a file that is there is never told as missing (audit tools-3).
    let note = ArisFiles.heldBackNote(ArisFiles.heldBack(Array(Set(named + mentioned)), home: home), korean: false).map { "\n" + $0 } ?? ""
    guard !newest.isEmpty else { return print("nothing found for \"\(words)\"" + note) }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    print(newest.map { "\($0.0)  (\(formatter.string(from: $0.1)))" }.joined(separator: "\n") + note)
}

func openFile(_ args: [String]) {
    // Checked after resolving links, so a link in ~ can't point the check at one thing and `open` at another.
    let path = URL(fileURLWithPath: (args.joined(separator: " ") as NSString).expandingTildeInPath).resolvingSymlinksInPath().path
    let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else { fail("no file at \(path)") }
    // A Keynote, Pages or Numbers document opens as a package too; why anything else doesn't is said (ArisFiles).
    if let refusal = ArisFiles.openRefusal(path, home: home, isFolder: isFolder.boolValue) { fail(refusal) }
    run("/usr/bin/open", [path])
    print("opened \((path as NSString).lastPathComponent)")
}
