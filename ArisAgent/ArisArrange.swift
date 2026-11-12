//
//  ArisArrange.swift
//  aris-agent
//
//  "엑셀 4개 켜서 4등분" without any AI: the app's words become an app name and a count, and the
//  agent runs aris-tools `new` then `tile` itself (no shell), the way the AI used to after two
//  confirmations and 15-25 seconds.
//

import Foundation

enum ArisArrange {
    static let maxWindows = 9
    private static let maxName = 60
    /// `new` waits up to ~0.5 s a window plus 5 s for them to appear.
    private static let timeout: TimeInterval = 20

    /// aris-tools arguments, in order; nil unless `app` is a plain app name and `count` 1-9.
    static func commands(app: String, count: Int) -> [[String]]? {
        let name = app.trimmingCharacters(in: .whitespaces)
        // A path isn't an app name, and `tile` reads a comma as a second app.
        guard !name.isEmpty, name.count <= maxName, (1...maxWindows).contains(count),
              !name.contains("/"), !name.contains(","),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let grid = ArisWindowGrid.grid(for: count)
        return [["new", name, "--count", String(count)], ["tile", name, "--grid", "\(grid.rows)x\(grid.columns)"]]
    }

    /// Runs them one after another; nil when all worked, else what went wrong (aris-tools' own words).
    static func run(_ commands: [[String]], tools: String, environment: [String: String]) -> String? {
        for arguments in commands {
            let process = ArisExactProcess()
            process.executableURL = URL(fileURLWithPath: ArisAppBundle.executed(tools))
            process.arguments = arguments
            process.environment = environment
            let errors = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            do { try ArisChildren.run(process) } catch { return "couldn't run aris-tools: \(error.localizedDescription)" }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning {
                ArisProcessEnd.end(process)
                return "\(arguments[0]) took too long"
            }
            guard process.terminationStatus == 0 else {
                let said = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return said.isEmpty ? "\(arguments[0]) failed" : String(said.prefix(200))
            }
        }
        return nil
    }
}
