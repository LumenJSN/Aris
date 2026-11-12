//
//  ArisAppBundle.swift
//  aris-agent
//
//  The app this helper sits in (Aris.app/Contents/MacOS/aris-agent), and what follows from sitting there:
//   · what the installer used to copy beside the helper (the built-in skill, the skills' pinned requirements) is read
//     from the app's Resources, so a new Mac needs no script;
//   · launchd does not stop a running helper when its app is moved to the Trash or deleted (follow-up experiment,
//     4bcd-app-gone.txt), so the helper looks for its own program and stops by itself when it is gone. The LaunchAgent's
//     KeepAlive is a condition on that same path, so launchd starts it again only when the app is back.
//  A loose copy (a developer's build, the old install in ~/.config/aris) has no app: it reads ~/.config/aris/skills as
//  before and never stops itself.
//

import Foundation

enum ArisAppBundle {
    /// This process's program as the kernel has it, read once at start.
    static let program: String? = ArisOrigin.program(of: getpid())
    /// This very program as a file, for starting itself in a helper mode. Never the main bundle's executable: inside
    /// Aris.app that is the app's own program, not aris-agent.
    static var ownProgram: URL? { program.map { URL(fileURLWithPath: $0) } ?? Bundle.main.executableURL }
    /// The app it sits in; nil for a loose copy.
    static let path: String? = program.flatMap(ArisOrigin.app(ofProgram:))

    /// The path the AIs are told to call aris-tools by: the link in Aris's own folder. It is only ever a name (in a
    /// prompt, a rule, a command an AI wrote, the risk gate's comparisons); the helper never starts it.
    static var toldTools: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/aris-tools").path
    }

    /// The aris-tools the helper starts for its own work (a look, a card, the activity log, a permission check, a call
    /// it runs for an AI): the one inside its own app, so what sits at the link in the user's folder is never run as
    /// Aris by the helper (security review 4, H1). A loose copy (a developer's build) runs the aris-tools beside it,
    /// and the old path only when there is none.
    static let ownTools: String = ownTools(program: program, told: toldTools, exists: { access($0, X_OK) == 0 })

    static func ownTools(program: String?, told: String, exists: (String) -> Bool) -> String {
        guard let program else { return told }
        if let app = ArisOrigin.app(ofProgram: program) { return "\(app)/Contents/MacOS/aris-tools" }
        let beside = ((program as NSString).deletingLastPathComponent as NSString).appendingPathComponent("aris-tools")
        return beside != told && exists(beside) ? beside : told
    }

    /// What the helper starts when a call of its own names `tools`: its own aris-tools whenever the name is the link
    /// the AIs are told; any other path as it is. Every place the helper starts aris-tools goes through this.
    static func executed(_ tools: String, told: String = toldTools, own: String = ownTools) -> String {
        tools == told ? own : tools
    }

    /// A command line of the helper's own that begins with the told path (a learned shortcut it replays through the
    /// shell), with that word replaced by its own aris-tools, quoted for the shell. Any other line as it is.
    static func ownCommand(_ command: String, told: String = toldTools, own: String = ownTools) -> String {
        guard command == told || command.hasPrefix(told + " ") else { return command }
        return "'" + own.replacingOccurrences(of: "'", with: "'\\''") + "'" + command.dropFirst(told.count)
    }

    /// How often the helper looks for its own program, and how many looks in a row must miss it (a deploy swaps the
    /// app with two renames: one miss is not "gone").
    static let lookEvery: TimeInterval = 5
    static let missesBeforeStopping = 2

    /// Where the skills' files are: the app's Resources when the helper is inside an app, else Aris's own folder.
    static func skillsFolder(home: String, app: String? = path) -> URL {
        if let app { return URL(fileURLWithPath: app).appendingPathComponent("Contents/Resources/skills", isDirectory: true) }
        return URL(fileURLWithPath: home).appendingPathComponent(".config/aris/skills", isDirectory: true)
    }

    /// The count of looks in a row that missed the program, after one more look; and whether to stop now.
    static func afterLook(misses: Int, exists: Bool) -> (misses: Int, stop: Bool) {
        let now = exists ? 0 : misses + 1
        return (now, now >= missesBeforeStopping)
    }

    /// Starts the watch (only inside an app). `stop` ends the process.
    static func watchGone(program: String? = program, app: String? = path, queue: DispatchQueue = .global(qos: .utility),
                          exists: @escaping @Sendable (String) -> Bool = { access($0, F_OK) == 0 },
                          stop: @escaping @Sendable (String) -> Void = { path in
                              FileHandle.standardError.write(Data("aris-agent: Aris is gone from \(path); stopping (launchd starts the helper again when the app is back)\n".utf8))
                              exit(0)
                          }) {
        guard let program, app != nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        nonisolated(unsafe) var misses = 0
        timer.schedule(deadline: .now() + lookEvery, repeating: lookEvery)
        timer.setEventHandler {
            let next = afterLook(misses: misses, exists: exists(program))
            misses = next.misses
            if next.stop { stop(program) }
        }
        timer.resume()
        watch = timer
    }

    nonisolated(unsafe) private static var watch: DispatchSourceTimer?
}
