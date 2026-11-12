//
//  ArisLoadedJob.swift
//  Aris
//
//  What launchd itself has loaded under Aris's label, read from `launchctl print gui/<uid>/<label>`: the file the job
//  came from, the program launchd executes, its arguments and its process. The installer decides from this and not
//  from the LaunchAgent file on disk (security review 4, M7): any program of the same user can unload Aris's job and
//  load its own under the same label from another file, and the file on disk then still looks right.
//
//  launchd prints `program` (what it executes: the job's Program, or its first argument when it has none) and
//  `arguments` separately (measured, U3), so a job whose Program is a script and whose first argument names the
//  helper is seen for what it is. Foundation only (tested).
//

import Foundation

struct ArisLoadedJob: Equatable {
    /// The LaunchAgent file launchd loaded the job from.
    var path: String?
    /// The program launchd executes.
    var program: String?
    var arguments: [String] = []
    /// The job's process, when it runs.
    var pid: Int32?

    /// Reads launchctl's print-out: the job's own `key = value` lines (one level in) and its `arguments = { … }` list.
    /// Anything it does not know is left out; text that is not a print-out gives a job with nothing in it.
    static func parse(_ text: String) -> ArisLoadedJob {
        var job = ArisLoadedJob()
        var depth = 0
        var inArguments = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix("= {") || line == "{" {
                depth += 1
                inArguments = depth == 2 && line.hasPrefix("arguments =")
                continue
            }
            if line == "}" {
                depth -= 1
                inArguments = false
                continue
            }
            if inArguments, depth == 2, !line.isEmpty {
                job.arguments.append(line)
                continue
            }
            guard depth == 1, let cut = line.range(of: " = ") else { continue }
            let key = String(line[..<cut.lowerBound]), value = String(line[cut.upperBound...])
            switch key {
            case "path": if job.path == nil { job.path = value }
            case "program": if job.program == nil { job.program = value }
            case "pid": if job.pid == nil { job.pid = Int32(value) }
            default: break
            }
        }
        return job
    }

    /// Whether launchd starts exactly `agent` and nothing else: the program it executes is that, and its only
    /// argument is that.
    func starts(_ agent: String) -> Bool {
        program == agent && arguments == [agent]
    }

    /// What the loaded job is to the app that asks.
    enum Kind: Equatable {
        /// This app's own helper: loaded from Aris's own file, started as this app's aris-agent, and the process that
        /// runs is that program.
        case own
        /// The helper of another copy of Aris (the app was moved or another copy was opened), or of the install made
        /// the old way: `program` is that helper.
        case otherAris(program: String)
        /// Anything else under Aris's label: a script, a shell, another program, a job loaded from another file, a
        /// process that is not the program launchd was told to start.
        case foreign
    }

    /// `agent`: this app's aris-agent. `plist`: Aris's own LaunchAgent file. `running`: the real program of the job's
    /// process (nil when it has none or it can't be read). `isArisAgent`: whether the file at a path is validly signed
    /// as aris-agent by this app's own team.
    /// `exists`: whether a file is there (a helper whose app was moved or deleted is still Aris's, only gone).
    func kind(agent: String, plist: String, running: String?, isArisAgent: (String) -> Bool, exists: (String) -> Bool = { _ in true }) -> Kind {
        guard let program, arguments == [program], path == plist, pid == nil || running == program else { return .foreign }
        if program == agent { return .own }
        return program.hasSuffix("/aris-agent") && (!exists(program) || isArisAgent(program)) ? .otherAris(program: program) : .foreign
    }

    /// For the log: what launchd runs, without anything of the user's.
    var summary: String {
        "program \(program ?? "-") arguments \(arguments.count) from \(path ?? "-") pid \(pid.map(String.init) ?? "-")"
    }
}
