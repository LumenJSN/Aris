//
//  ArisTeamExtrasRoute+Live.swift
//  aris-agent
//
//  The 팀원 page's extra ops against this Mac: the brains' binaries, a terminal for a login, the note files.
//

import AppKit
import Foundation

extension ArisTeamExtrasRoute {
    /// The live world (aris-agent).
    static func live(home: String) -> World {
        World(ready: { brain in
                  switch brain {
                  case .claude: ArisClaudeDriver(model: "", tools: "").launch() != nil
                  case .codex: ArisReadJudge.executable(.codex) != nil
                  case .antigravity: ArisAntigravityDriver(model: "", instructions: "").launch() != nil
                  case .api: ArisAPIActive.answers()
                  }
              },
              resolve: { paths in ArisPrograms.find(paths.first.map { ($0 as NSString).lastPathComponent } ?? "", known: paths)?.path },
              openTerminal: { command in (try? ArisTeammateLauncher.launch(command: command)) != nil },
              notes: ArisNotesStore.load,
              forget: { id, file in ArisNotesStore.remove(id: id, from: file) },
              keep: { id, file in ArisNotesStore.markKept(id: id, in: file) },
              acceptProgram: { ArisProgramApproval.accept($0) },
              needsCheck: { $0 == .api && ArisAPIActive.needsCheck() },
              knowhowFile: ArisNotesStore.knowhowFile(home: home),
              teammateFile: { ArisNotesStore.teammateFile(home: home, id: $0) })
    }

    /// Whether `name` is an app on this Mac: running (by its shown name), or installed in an Applications folder.
    static func isAppHere(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName?.lowercased() == lowered }) { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/Applications", "/System/Applications", "/System/Applications/Utilities", home + "/Applications"]
            .contains { FileManager.default.fileExists(atPath: "\($0)/\(name).app") }
    }
}
