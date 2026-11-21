//
//  ArisFleetStart.swift
//  Shared/Core (aris-agent, tests)
//
//  `fleet.start`: which folder the owner means ("Aris 폴더", "altswitch", "~/Developer/x"), and the jobs block that has
//  Aris open a Claude Code teammate there (the teammate path as it is: its own card rules, its window, its watch).
//  A folder by its path when it exists; else by name among the folders the fleet's sessions work in (said in Hangul
//  too), then directly under the usual project places. Two that fit: the question. Pure.
//

import Foundation

enum ArisFleetStart {
    enum Folder: Equatable {
        case one(String)
        case ask([String])
    }

    /// The places a project folder usually sits, under the home folder.
    static let roots = ["", "Desktop", "Desktop/the user", "Aris", "Developer", "Documents", "Projects", "code", "src"]

    static func folder(_ words: String, fleet: ArisFleet, home: String, isFolder: (String) -> Bool) -> Folder? {
        let raw = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.count <= 300, !raw.contains("\0") else { return nil }
        if raw.hasPrefix("/") || raw.hasPrefix("~") {
            let path = ((raw.hasPrefix("~") ? home + raw.dropFirst() : raw) as NSString).standardizingPath
            return path.hasPrefix(home + "/") && isFolder(path) ? .one(path) : nil
        }
        let tokens = ArisFleetWords.tokens(raw).filter { !ArisFleetWords.stopwords.contains($0) && $0 != "폴더" && $0 != "folder" }
        // The folders the fleet works in, each once, as sessions the resolver can match.
        var seen = Set<String>()
        let places = fleet.sessions.filter { seen.insert(($0.folder as NSString).standardizingPath).inserted }
        let matched = Set(ArisFleetResolver.folderMatches(tokens, among: places, home: home).map { ($0.folder as NSString).standardizingPath })
        let exactName = matched.filter { (($0 as NSString).lastPathComponent).lowercased() == tokens.joined(separator: "-") }
        if exactName.count == 1 { return .one(exactName.first!) }
        if matched.count == 1 { return .one(matched.first!) }
        if matched.count > 1 { return .ask(matched.sorted()) }
        let name = tokens.joined(separator: "-")
        guard !name.isEmpty, name.range(of: #"^[A-Za-z0-9._-]{1,100}$"#, options: .regularExpression) != nil, !name.hasPrefix(".") else { return nil }
        let found = roots.map { ($0.isEmpty ? home : home + "/" + $0) + "/" + name }.filter(isFolder)
        if found.count == 1 { return .one(found[0]) }
        return found.isEmpty ? nil : .ask(found)
    }

    /// The jobs block that starts the teammate: the owner's instruction as its prompt, the folder as its cwd.
    static func jobsBlock(folder: String, instruction: String) -> String {
        let title = String(instruction.prefix(40))
        let job: [String: Any] = ["title": title, "prompt": instruction, "assignee": "claude-code", "cwd": folder]
        let data = (try? JSONSerialization.data(withJSONObject: ["jobs": [job]], options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return "```json\n" + String(decoding: data, as: UTF8.self) + "\n```"
    }
}
