//
//  ArisFileRelay.swift
//  aris-agent
//
//  agy's file changes (`move`, `rename`, `folder new`, and `convert`, `merge`, `split`, `compress` lines of its aris-run
//  block), run by Aris behind the same gate
//  as on every other brain (the owner: no feature lost because of the brain): the risk gate first (a protected place is
//  never touched), then the user's card on agy's /ask stream, then aris-tools as Aris itself. The open agy's own shell
//  still refuses them (ArisSealedTools.ungatedRefusal): it can't tell when outside text came in.
//

import Foundation

/// The relay's turn as a file line sees it (ArisRelayMCPTurn; a fake in the tests).
protocol ArisFileRelayTurn: ArisMCPTurn {
    /// The relayed call is still waited for.
    var live: Bool { get }
    func startCall(limit seconds: TimeInterval)
    func cancelAll()
}

enum ArisFileRelay {
    /// One relayed file line's time limit, its card included.
    static let limit: TimeInterval = 90

    /// A file change the relay runs behind the user's card.
    static func isFileChange(_ words: [String]) -> Bool {
        guard let first = words.first, words.allSatisfy(ArisDesktopShell.isPlain) else { return false }
        return (first == "move" && words.count == 3) || (first == "rename" && words.count == 3)
            || (words.starts(with: ["folder", "new"]) && words.count == 3) || ArisConvertWords.parse(words) != nil
    }

    /// How long aris-tools may run a relayed file line once the user said yes: a video or sound job its full time.
    static func runLimit(_ words: [String]) -> TimeInterval {
        if ArisConvertWords.isLong(words) { return ArisConvertWords.mediaLimit + 15 }
        return ArisConvertWords.parse(words) != nil ? ArisConvertWords.quickLimit + 5 : 20
    }

    /// Runs `work`; for a video or sound job, `beat` is called every `every` seconds meanwhile (with the minutes so
    /// far), so the notch hears that it is still going and its stream doesn't go quiet.
    static func whileLong<T>(_ words: [String], every: TimeInterval = 30, beat: @escaping (Int) -> Void, _ work: () -> T) -> T {
        guard ArisConvertWords.isLong(words) else { return work() }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        let started = Date()
        timer.schedule(deadline: .now() + every, repeating: every)
        timer.setEventHandler { beat(Int(Date().timeIntervalSince(started) / 60)) }
        timer.resume()
        defer { timer.cancel() }
        return work()
    }

    /// The card for a conversion: the files and what they become.
    private static func convertCard(_ words: [String], shown: (String) -> String) -> ArisMCPCard? {
        guard let call = ArisConvertWords.parse(words) else { return nil }
        let titles = ["convert": "파일 변환하기", "merge": "파일 합치기", "split": "PDF 나누기", "compress": "용량 줄이기"]
        let picked = call.selector.map { $0 == .finder ? "Finder에서 고른 파일" : "선반에 둔 파일" }
        let files = picked ?? call.paths.prefix(6).map(shown).joined(separator: "\n") + (call.paths.count > 6 ? "\n외 \(call.paths.count - 6)개" : "")
        let options = ["--to", "--max", "--percent", "--quality", "--pages"].compactMap { flag in
            call.options[flag].map { flag == "--to" ? "→ \(ArisDesktopCard.shown($0).uppercased())" : "\(flag) \(ArisDesktopCard.shown($0))" }
        }
        return ArisMCPCard(title: titles[call.verb] ?? "파일 변환하기", detail: files + (options.isEmpty ? "" : "\n" + options.joined(separator: " ")), full: nil, fields: [])
    }

    /// The command line the risk gate reads (every word single-quoted, as a brain's shell line would carry it).
    static func commandLine(_ words: [String], tools: String) -> String {
        ([tools] + words).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
    }

    static func card(_ words: [String], home: String) -> ArisMCPCard {
        let shown = { (path: String) in ArisDesktopCard.shown(path.replacingOccurrences(of: home, with: "~")) }
        if let card = convertCard(words, shown: shown) { return card }
        switch words.first {
        case "move": return ArisMCPCard(title: "파일 옮기기", detail: "\(shown(words[1]))\n→ \(shown(words[2]))", full: nil, fields: [])
        case "rename": return ArisMCPCard(title: "이름 바꾸기", detail: "\(shown(words[1]))\n→ \(ArisDesktopCard.shown(words[2]))", full: nil, fields: [])
        default: return ArisMCPCard(title: "새 폴더 만들기", detail: shown(words[2]), full: nil, fields: [])
        }
    }

    /// The line run for agy: refused, asked and run, or not done; what agy reads back.
    static func relayed(_ words: [String], turn: ArisFileRelayTurn, tools: String, home: String,
                        run: ([String]) -> String) -> String {
        guard isFileChange(words) else { return ArisAgyRelay.refused }
        let what = words.prefix(2).joined(separator: " ")
        if ArisRiskPolicy.risk(of: .shell(commandLine(words, tools: tools)), tools: tools, home: home) == .never {
            // A name without its folder: sent back with how to write it, never as a protected place (VM run 2, bug 3).
            if let problem = ArisRiskPolicy.barePathProblem(commandLine(words, tools: tools), tools: tools) {
                turn.audit(["answer": "refused (\(ArisRiskPolicy.barePathReason))", "action": what])
                return problem
            }
            turn.audit(["answer": "refused (a protected place)", "action": what])
            return "Refused: that is a place Aris never moves, renames, converts or makes folders in (its own folders, keys, startup files)."
        }
        turn.startCall(limit: limit)
        let done = DispatchSemaphore(value: 0)
        let yes = ArisFileRelayAnswer()
        turn.ask(card(words, home: home)) { answer in
            if case .yes = answer { yes.set() }
            done.signal()
        }
        guard done.wait(timeout: .now() + limit) == .success, yes.isSet, turn.live else {
            turn.cancelAll()
            turn.audit(["answer": "no", "action": what])
            return "The user said no (or didn't answer), so it wasn't done. Don't try it another way."
        }
        turn.audit(["answer": "yes", "action": what])
        return run(words)
    }
}

/// The user's yes, handed across threads.
final class ArisFileRelayAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
