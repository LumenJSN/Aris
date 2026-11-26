//
//  ArisRecallCommand.swift
//  aris-tools
//
//  `recall`: Aris's own record of past work (ArisWorkMemory), for a brain that wants to know how it did something last
//  time instead of exploring again, and for the user at a terminal.
//    recall [<words>] [--limit N]   lessons and past episodes about the words (the latest when none): id, when, how it
//                                   ended, one line
//    recall --id E12 | --id L3      one episode's steps, or one lesson and what it is based on
//    recall --stats                 whether it saved anything
//    … --tainted                    also what came from turns that read outside content
//  The first line printed is the taint mark of everything after it. Without --tainted nothing a tainted turn left is
//  printed (only how many more there are); the gates count `--tainted` as a read of outside text
//  (ArisWorkRecallWords), so a turn that pulls one is tainted from there on.
//

import Foundation

func recall(_ arguments: [String]) {
    // The code the agent runs in its own process for the same call (ArisCapabilityLocal).
    emit(ArisCapabilityLocal.recall(arguments, folder: arisFolder))
}

/// A shared command's answer as this program's: what it printed, and `fail`'s exit for a failure.
func emit(_ output: ArisCapabilityLocal.Output) {
    if !output.stdout.isEmpty { FileHandle.standardOutput.write(Data(output.stdout.utf8)) }
    if !output.stderr.isEmpty { try? FileHandle.standardError.write(contentsOf: Data(output.stderr.utf8)) }
    if output.status != 0 { exit(output.status) }
}
