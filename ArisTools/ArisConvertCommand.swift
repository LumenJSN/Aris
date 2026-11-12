//
//  ArisConvertCommand.swift
//  aris-tools
//
//  `convert <file>… | --finder | --shelf [--to <format>] [--quality 1-100] [--max <px> | --percent <n>] [--pages 1-3,5]`,
//  `merge <file>… | --finder | --shelf [--to pdf|mp4|mov|m4a]`, `split <pdf> | --finder | --shelf [--pages 1-3,5]` and
//  `compress <file>… | --finder | --shelf [--quality 1-100] [--max <px>]` (ArisConvert). Named files: it prints the new
//  files' paths. `--finder` (the Finder selection, read here) and `--shelf` (the notch shelf, as aris-agent keeps it:
//  ArisShelfFiles): it never names a file, only counts and where the new ones went. Each is logged with an undo that
//  moves what it made to the Trash.
//

import Foundation

/// Kept alive while a conversion runs: on SIGTERM or SIGINT the scratch folder in use goes too.
nonisolated(unsafe) private var convertSignals: [DispatchSourceSignal] = []

func convertCommand(_ verb: String, _ args: [String]) {
    guard let call = ArisConvertWords.parse([verb] + args) else { fail(convertUsage(verb)) }
    let environment = ProcessInfo.processInfo.environment
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let quiet = call.selector != nil
    if let selector = call.selector, let refusal = ArisConvert.selectorRefusal(selector, environment: environment, state: ArisShelfFiles.state(home: home),
                                                                            turnStarted: turnStarted(environment)) { fail(refusal) }
    ArisConvert.sweepScratch()
    watchConvertSignals()
    // The log's entry is written as the first file lands, and grows with each one (a stopped run still lists them).
    var entry: UUID?
    let interim = { (made: [String]) in
        let summary = "\(verb): \(made.count)개 만듦"
        if let id = entry { ArisActivity.replace(id, summary: summary, undo: .trashMade(paths: made), file: ArisActivity.defaultFile) }
        else { entry = logActivity(summary, undo: .trashMade(paths: made)) }
    }
    do {
        let result = try ArisConvert.run(call, home: home, cwd: FileManager.default.currentDirectoryPath,
                                         deadline: ArisConvertWords.deadline([verb] + args, environment: environment), selection: selectedFiles, placed: interim)
        if let id = entry { ArisActivity.replace(id, summary: result.summary, undo: .trashMade(paths: result.made), file: ArisActivity.defaultFile) }
        print(ArisConvert.report(result))
    } catch let partial as ArisConvert.Partial {
        if let id = entry {
            ArisActivity.replace(id, summary: "\(verb): \(partial.made.count)개 (중간에 멈춤)", undo: .trashMade(paths: partial.made.map(\.real)), file: ArisActivity.defaultFile)
        }
        print(quiet ? "\(partial.made.count)개는 만들었어요 (원본 옆에 저장)" : partial.made.map { "made \($0.shown)" }.joined(separator: "\n"))
        fail(partial.message)
    } catch {
        fail(ArisConvert.message(error, quiet: quiet))
    }
}

/// SIGTERM (a caller's time limit) or SIGINT: the scratch folder in use is removed before aris-tools goes.
private func watchConvertSignals() {
    for number in [SIGTERM, SIGINT] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
        source.setEventHandler {
            ArisConvert.removeLeftovers()
            exit(128 + number)
        }
        source.resume()
        convertSignals.append(source)
    }
}

/// When this turn began: its credential file (ARIS_MCP_TURN_FILE) is written new at each turn's start and emptied at
/// its end. Nil outside a turn (a relayed line, a command by hand).
func turnStarted(_ environment: [String: String]) -> Date? {
    guard let path = environment["ARIS_MCP_TURN_FILE"], path.hasPrefix("/"),
          let attributes = try? FileManager.default.attributesOfItem(atPath: path), (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else { return nil }
    return attributes[.modificationDate] as? Date
}

/// The files a selector stands for: Finder's selection (one POSIX path a line), or the shelf's as the agent kept them.
func selectedFiles(_ selector: ArisConvertWords.Selector) -> [String] {
    switch selector {
    case .finder:
        return appleScript(ArisActions.finderSelectionScript, app: "Finder").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    case .shelf:
        return ArisShelfFiles.load(home: FileManager.default.homeDirectoryForCurrentUser.path)
    }
}

func convertUsage(_ verb: String) -> String {
    let source = "<file>… | --finder | --shelf"
    switch verb {
    case "merge": return "usage: merge \(source) [--to pdf|mp4|mov|m4a]"
    case "split": return "usage: split <pdf> | --finder | --shelf [--pages 1-3,5]"
    case "compress": return "usage: compress \(source) [--quality 1-100] [--max <pixels>]"
    default: return "usage: convert \(source) [--to png|jpg|heic|tiff|gif|bmp|pdf|mp4|mov|m4a] [--quality 1-100] [--max <pixels> | --percent <n>] [--pages 1-3,5]"
    }
}
