//
//  ArisDevinCommand.swift
//  aris-tools
//
//  `devin sessions [--all]`: Devin's own records, read only (ArisDevinRead).
//

import Foundation

/// `aris-tools devin sessions [--all]`.
func devinRead(_ args: [String]) {
    guard args.first == "sessions", args.count <= 2, args.count == 1 || args[1] == "--all" else { fail(ArisDevinRead.usage) }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard let read = ArisDevinRead.read(home: home, all: args.count == 2) else {
        fail("Devin's session records aren't on this Mac (or can't be read), so there is nothing to tell about Devin sessions.")
    }
    print(ArisDevinRead.report(read.summaries, runningCount: read.running, now: Date(), home: home))
}
