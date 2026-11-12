//
//  ArisScheduleCommand.swift
//  aris-tools
//
//  `schedule add --title T --prompt P (--at "YYYY-MM-DD HH:mm" | --daily HH:mm | --weekly <sun..sat> HH:mm | --every <N>m)
//  [--teammate ID]` prints {"id", "next"}; `schedule list`; `schedule remove <id>`. aris-agent runs the jobs
//  (ArisScheduler). The risk gate asks the user before an AI runs `add` (and `remove` after outside text); `list` runs at once.
//

import Foundation

func schedule(_ args: [String]) {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let rest = Array(args.dropFirst())
    do {
        switch args.first {
        case "add":
            // A teammate's job files its schedule under itself, so the run keeps its scopes (N5).
            let added = try ArisScheduleTool.add(rest, home: home, environment: ProcessInfo.processInfo.environment, scoped: teammateScopes != nil,
                                                 teammate: teammateJob.teammate)
            print(ArisScheduleTool.addedLine(added))
        case "list":
            print(ArisScheduleTool.list(home: home))
        case "remove":
            let removed = try ArisScheduleTool.remove(rest, home: home, environment: ProcessInfo.processInfo.environment)
            print("removed: \(removed.title)")
        default:
            fail(ArisScheduleArguments.usage + " | schedule list | schedule remove <id>")
        }
    } catch {
        fail(error.localizedDescription)
    }
}
