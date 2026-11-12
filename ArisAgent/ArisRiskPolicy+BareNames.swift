//
//  ArisRiskPolicy+BareNames.swift
//  aris-agent
//
//  A file command given a name without its folder (VM run 2, bug 3: "trash the folder qa-1111" came in as
//  `aris-tools trash qa-1111`). aris-tools would look for a bare name in Aris's own folder, where the AI's commands
//  run, so the gate read it as a protected place and answered "never" with no reason the brain could use, and the user's
//  own request was refused. A bare name can't be shown truthfully on a card either: the gate would have to guess the
//  folder. So nothing is guessed and nothing runs: the call goes back to the brain with a fixed note to send the full
//  path (as a desktop call the engine can't read gets its usage back: ArisRiskPolicy.desktopProblem), and that next
//  call asks on the user's card as any full path does. The same for `trash`, `move`, `rename`, `folder new`, the
//  conversions and `open`. Pure, so the tests run it.
//

import Foundation

extension ArisRiskPolicy {
    /// A path that says where it is: from the root, or from the home folder.
    static func isRooted(_ path: String) -> Bool { path.hasPrefix("/") || path == "~" || path.hasPrefix("~/") }

    /// The words of an aris-tools file command (after the program) that name a file or a folder; nil for any other
    /// command. A rename's second word is the new name, never a path; `open` reads all its words as one path; a
    /// conversion that aris-tools wouldn't read, or whose files the owner picked themselves (--finder, --shelf), names none.
    static func filePaths(_ arguments: [String]) -> [String]? {
        guard let tool = arguments.first else { return nil }
        let rest = Array(arguments.dropFirst())
        switch tool {
        case "trash", "move": return rest.filter { $0 != "--" }
        case "rename": return Array(rest.prefix(1))
        case "folder": return rest.first == "new" ? Array(rest.dropFirst()) : nil
        case "open": return rest.isEmpty ? [] : [rest.joined(separator: " ")]
        case _ where ArisConvertWords.verbs.contains(tool): return ArisConvertWords.parse(arguments)?.paths ?? []
        default: return nil
        }
    }

    /// A name without its folder: a path that isn't rooted and that, read from Aris's own folder (where the AI's
    /// commands run), stays inside it ("qa-1111", "./a", "Desktop/a", "$HOME/a"). One that climbs out of that folder
    /// with ".." to a real place names that place, and is judged as the full path it resolves to, as before.
    static func isBareName(_ path: String) -> Bool {
        guard !isRooted(path) else { return false }
        let own = "/home/.config/aris/aris"
        let resolved = ((own + "/" + path) as NSString).standardizingPath
        return resolved == own || resolved.hasPrefix(own + "/")
    }

    /// Whether these aris-tools words are a file command that names a file without its folder.
    static func namesBareFile(_ arguments: [String]) -> Bool {
        filePaths(arguments)?.contains(where: isBareName) == true
    }

    /// The fixed note the brain gets back for such a command (in any command of the line); nil for every other line.
    /// It names the command, never the brain's own words.
    static func barePathProblem(_ command: String, tools: String) -> String? {
        for piece in ArisCommandPolicy.segments(command) ?? [command] {
            guard let words = ArisCommandPolicy.words(piece), words.first == tools, words.count > 1, namesBareFile(Array(words.dropFirst())) else { continue }
            let verb = words[1] == "folder" ? "folder new" : words[1]
            return "Refused: `\(verb)` was given a name without its folder (a bare name or a relative path), and Aris can't tell which file "
                + "that is. Nothing was done, and this is not the user's no. Send it again with the full path, starting with / or ~/ "
                + "(as in ~/Desktop/<name>): the user is then asked on a card. If you don't know which folder it is in, find it first "
                + "(`files find \"<name>\"`) or ask the user where it is; never guess."
        }
        return nil
    }

    /// What the brain is told when a call was refused only for how it was written (a desktop call the engine can't
    /// read, a file named without its folder), so it can send it again the right way; nil for any other refusal.
    static func callProblem(_ command: String, tools: String) -> String? {
        desktopProblem(command, tools: tools) ?? barePathProblem(command, tools: tools)
    }

    /// The same, for actions.log and the "왜 안 돼?" record.
    static let barePathReason = "a file named without its folder (a bare name or a relative path): the full path is needed"
}
