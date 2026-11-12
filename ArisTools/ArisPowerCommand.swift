//
//  ArisPowerCommand.swift
//  aris-tools
//
//  `aris-tools osascript -e 'tell application "System Events" to restart'` (or shut down, log out, sleep): how a
//  brain with no shell of its own restarts, shuts down, logs out of or sleeps the Mac (VM run 2: an API brain sent
//  exactly this, the card showed the raw script, and a yes could have done nothing, since aris-tools had no such
//  command). Only those four scripts, word for word (ArisCommandPolicy.powerScript), and only with the one-shot pass
//  the gate mints when the user said yes on the card (ArisMessagePass.powerName): nothing else that runs aris-tools can
//  restart the Mac, and no other AppleScript runs through here.
//

import Foundation

func power(_ arguments: [String]) {
    guard let script = ArisCommandPolicy.powerScript(arguments), let verb = ArisCommandPolicy.powerVerb(script: script) else {
        fail("aris-tools runs only four scripts through osascript: `osascript -e 'tell application \"System Events\" to restart'` (or `shut down`, `log out`, `sleep`). Nothing was run.")
    }
    guard ArisMessagePass.consume(to: ArisMessagePass.powerName, text: script) else {
        fail("NOT DONE: restarting, shutting down, logging out or sleeping the Mac runs only after the user's yes on Aris's card. Nothing was done.")
    }
    let ran = runCapturing("/usr/bin/osascript", ["-e", script])
    guard ran.status == 0 else {
        fail(ArisActions.appleScriptProblem(ran.complaint, app: "System Events"))
    }
    print(["restart": "restarting the Mac", "shut down": "shutting the Mac down", "log out": "logging out", "sleep": "putting the Mac to sleep"][verb] ?? "done")
}
