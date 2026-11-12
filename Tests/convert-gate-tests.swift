//
//  convert-gate-tests.swift
//  The file conversions (`convert`, `merge`, `split`, `compress`) behind every brain's gate, like move and rename:
//  the open Claude's turn gate (a clean turn runs them and stays clean; after outside text they are refused), Codex's
//  and the API brain's risk gate (a local file write: the user's card, never a protected place), the API brain's
//  functions, agy (its own shell refuses them; its relay runs them behind the card), and every brain's prompt.
//

import Foundation

func runConvertGateTests() {
    let tools = "/Users/p/.config/aris/aris-tools", home = "/Users/p"
    let calls: [[String]] = [["convert", "~/Desktop/photo.heic", "--to", "png"], ["convert", "~/Desktop/a.png", "~/Desktop/b.png", "--to", "jpg", "--max", "1600"],
                             ["merge", "~/Desktop/a.pdf", "~/Desktop/b.pdf"], ["split", "~/Desktop/report.pdf", "--pages", "1-3,5"],
                             ["compress", "~/Desktop/photo.jpg", "--quality", "60"], ["convert", "~/Movies/clip.mov", "--to", "m4a"],
                             ["convert", "--finder", "--to", "png"], ["merge", "--shelf"], ["compress", "--finder", "--max", "1600"], ["split", "--shelf"]]
    let command = { (words: [String]) in ArisAPICatalog.command(tools: tools, argv: words) }

    // The open Claude: a clean turn runs them and leaves no mark; after outside text they are refused.
    for words in calls {
        let line = command(words)
        check(ArisTurnGate.bringsNothingIn(words) && ArisTurnGate.verdict(tool: "Bash", command: line, tools: tools, tainted: false) == .allow
              && !ArisClaudeDriver.bringsInOutside(ArisAgentStream.ToolCall(name: "Bash", command: line), tools: tools)
              && !ArisAgyRelay.bringsInOutside([words]),
              "convert gate (open Claude, agy's relay): \(words[0]) on a clean turn runs and brings nothing in")
        // Audit gate-3: once outside text came in the hook no longer refuses it itself; aris-tools hands it to the agent's
        // gate, which decides it as Codex's (never run unasked after outside text, never in the Claude's own process).
        let after = ArisAPIGate(tools: tools, home: "/Users/p")
        after.markUntrusted()
        var runsUnasked = false
        if case .allow = after.judge(line) { runsUnasked = true }
        check(ArisTurnGate.verdict(tool: "Bash", command: line, tools: tools, tainted: true) == .allow
              && handOffRouting(words, environment: [ArisTurnGate.stateKey: "/nowhere"]) != .direct && !runsUnasked,
              "convert gate (open Claude): once outside text came in, \(words[0]) goes to the agent's gate, which never runs it unasked")
    }
    for words in [["convert"], ["convert", "a.png", "--to"], ["merge", "a.pdf"], ["split", "a.pdf", "b.pdf"], ["compress", "a.jpg", "--to", "png"],
                  ["convert", "a\nb", "--to", "png"]] {
        check(!ArisTurnGate.bringsNothingIn(words), "convert gate: malformed \(words.prefix(2).joined(separator: " ").replacingOccurrences(of: "\n", with: "⏎")) isn't a clean file call")
    }
    let hook = { (line: String, folder: URL) -> Int32 in
        let input = (try? JSONSerialization.data(withJSONObject: ["tool_name": "Bash", "tool_input": ["command": line]])) ?? Data()
        return ArisTurnGate.run(input: input, tools: tools, environment: [ArisTurnGate.stateKey: folder.path], resolve: { _ in ["93.184.216.34"] }).code
    }
    if let folder = ArisTurnGate.makeFolder() {
        defer { try? FileManager.default.removeItem(at: folder) }
        check(hook(command(calls[0]), folder) == 0 && hook(command(calls[2]), folder) == 0 && !ArisTurnGate.isMarked(folder),
              "convert gate (open Claude's hook): convert then merge on a clean turn both run, and the turn stays clean")
        for read in ["\(tools) web fetch https://example.com/page", "\(tools) mail recent"] {
            ArisTurnGate.clear(folder)
            _ = hook(read, folder)
            // Audit gate-3: the hook passes each to aris-tools, which hands it to the agent's gate (above); a chain is refused.
            check(ArisTurnGate.isMarked(folder) && calls.allSatisfy { hook(command($0), folder) == 0 && handOffRouting($0, environment: [ArisTurnGate.stateKey: folder.path]) != .direct }
                  && hook(command(calls[0]) + " && " + command(calls[2]), folder) == 2,
                  "convert gate (open Claude's hook): after \(read.split(separator: " ")[1]), every conversion goes to the agent's gate (a chain is refused)")
        }
    } else {
        check(false, "convert gate: a turn folder")
    }

    // Codex and the API brain: only new files beside the originals, so at once on a clean turn (no card, like the open
    // Claude); never a protected place; after outside text refused, not carded. Move keeps its card.
    let risk = { (line: String) in ArisRiskPolicy.risk(of: .shell(line), tools: tools, home: home) }
    check(calls.allSatisfy { risk(command($0)) == .auto } && risk(command(["convert", "~/.ssh/id.png", "--to", "jpg"])) == .never
          && risk(command(["merge", "~/Desktop/a.pdf", "~/.config/aris/x.pdf"])) == .never && risk(command(["compress", "/Users/p/.gnupg/a.jpg"])) == .never
          && risk(command(["convert", "~/Desktop/a.png", "--bogus"])) == .confirm && risk("\(tools) move ~/Desktop/a.txt ~/Desktop/Archive") == .confirm
          && risk("\(tools) rename ~/Desktop/a.txt b.txt") == .confirm,
          "convert gate (Codex, API brain): a conversion runs at once (no card); a protected place never; move and rename still ask")
    // Audit gate-4: a conversion written plainly (alone or chained) asks on a card after outside text; it is no longer refused.
    check(calls.allSatisfy { !ArisRiskPolicy.refusedAfterOutsideText(.shell(command($0)), tools: tools) && ArisRiskPolicy.asksAfterOutsideText(.shell(command($0)), tools: tools) }
          && !ArisRiskPolicy.refusedAfterOutsideText(.shell("\(tools) move ~/a ~/b"), tools: tools)
          && !ArisRiskPolicy.refusedAfterOutsideText(.shell("\(tools) timer 5 && \(tools) convert --finder --to png"), tools: tools)
          && ArisRiskPolicy.asksAfterOutsideText(.shell("\(tools) timer 5 && \(tools) convert --finder --to png"), tools: tools),
          "convert gate: every conversion, alone or chained, is one that outside text makes a card")
    let piped = "\(tools) convert ~/Desktop/a.png --to jpg | cat"
    check(ArisRiskPolicy.refusedAfterOutsideText(.shell(piped), tools: tools) && ArisRiskPolicy.refusedAfterOutsideText(.shell("\(tools) merge a.pdf b.pdf \\\n x"), tools: tools)
          && !ArisRiskPolicy.refusedAfterOutsideText(.shell("echo convert | cat"), tools: tools),
          "convert gate (L1): a line that can't be read word by word but runs a conversion is still one")
    // Follow-up 5: through a shell, env or xargs it is still a conversion.
    let wrapped = ["sh -c '\(tools) convert ~/Desktop/a.png --to jpg'", "bash -c \"\(tools) merge --shelf\"", "env \(tools) compress --finder",
                   "echo ~/Desktop/a.png | xargs \(tools) convert --to png", "/bin/zsh -c 'aris-tools split --finder'"]
    check(wrapped.allSatisfy { ArisRiskPolicy.refusedAfterOutsideText(.shell($0), tools: tools) }
          && !ArisRiskPolicy.refusedAfterOutsideText(.shell("sh -c 'echo converting'"), tools: tools)
          && !ArisRiskPolicy.refusedAfterOutsideText(.shell("\(tools) note \"split the bill\""), tools: tools)
          && !ArisRiskPolicy.refusedAfterOutsideText(.shell("sh -c '\(tools) note \"merge the lists, then compress them\"'"), tools: tools)
          && !ArisRiskPolicy.refusedAfterOutsideText(.shell("\(tools) todo add convert | cat"), tools: tools),
          "convert gate (follow-up 5): sh -c, bash -c, env and xargs around a conversion are still one")
    let tainted = ArisAPIGate(tools: tools, home: home)
    tainted.startTurn()
    tainted.markUntrusted()
    if case .deny = tainted.judge(piped) {} else { check(false, "convert gate (L1): after outside text a piped conversion is refused, not carded") }
    check(wrapped.allSatisfy { if case .deny = tainted.judge($0) { return true }; return false },
          "convert gate (API brain, follow-up 5): after outside text a wrapped conversion is refused, not carded")
    // Its usual answer after outside text (a note runs, as before), never the conversions' refusal.
    if case .deny = tainted.judge("\(tools) note \"split the bill\"") {
        check(false, "convert gate: after outside text a note that says \"split the bill\" is treated as it always was (ordinary text is never blocked)")
    }
    check(ArisAPIHelper.scrubbed(["ARIS_TASK": "1", "SECRET": "x", "PATH": "/bin"]) == ["ARIS_TASK": "1", "PATH": "/bin"]
          && ArisAgyRelay.environment(["ARIS_TASK": "1", ArisSealedTools.ungatedKey: "1"], timeout: 30)["ARIS_TASK"] == "1"
          && ArisAgyRelay.environment([ArisSealedTools.ungatedKey: "1"], timeout: 30, task: true)["ARIS_TASK"] == "1"
          && ArisAgyRelay.environment([ArisSealedTools.ungatedKey: "1"], timeout: 30)[ArisSealedTools.ungatedKey] == nil,
          "convert gate (follow-up 1): a background job's mark reaches aris-tools from the API helper and agy's relay")
    check(!ArisRiskPolicy.bringsInUntrusted(.shell(command(calls[0])), tools: tools, home: home) && ArisCodexDriver.describe(command: command(calls[0]), tools: tools).0 == "파일 변환하기"
          && ArisCodexDriver.describe(command: command(calls[2]), tools: tools).0 == "파일 합치기" && ArisCodexDriver.describe(command: command(calls[3]), tools: tools).0 == "PDF 나누기"
          && ArisCodexDriver.describe(command: command(calls[4]), tools: tools).0 == "용량 줄이기",
          "convert gate (Codex): no outside text; the card names the job in Korean")
    check(ArisAgentStatus.forCommand(command(calls[0]), tools: tools) == "파일 변환하는 중" && ArisAgentStatus.forCommand(command(calls[5]), tools: tools) == "영상·소리 변환하는 중",
          "convert status: the notch says it is converting (a video or sound, the long kind)")
    let gate = ArisAPIGate(tools: tools, home: home)
    gate.startTurn()
    let clean = calls.allSatisfy { if case .allow = gate.judge(command($0)) { return true }; return false }
    check(clean && gate.taint == .none, "convert gate (API brain): on a clean turn every conversion runs at once and brings nothing in")
    gate.markUntrusted()
    let after = calls.allSatisfy { if case .ask = gate.judge(command($0)) { return true }; return false }
    check(after, "convert gate (API brain): after outside text every conversion asks on a card (audit gate-4: it was refused)")

    // The API brain's functions.
    check(ArisAPICatalog.argv(name: "file_convert", arguments: #"{"paths":["~/Desktop/a.heic","~/Desktop/b.heic"],"to":"png"}"#) == ["convert", "~/Desktop/a.heic", "~/Desktop/b.heic", "--to", "png"]
          && ArisAPICatalog.argv(name: "file_convert", arguments: #"{"paths":["~/a.jpg"],"max":1600,"quality":70}"#) == ["convert", "~/a.jpg", "--quality", "70", "--max", "1600"]
          && ArisAPICatalog.argv(name: "files_merge", arguments: #"{"paths":["~/a.pdf","~/b.pdf"]}"#) == ["merge", "~/a.pdf", "~/b.pdf"]
          && ArisAPICatalog.argv(name: "pdf_split", arguments: #"{"path":"~/a.pdf","pages":"1-3,5"}"#) == ["split", "~/a.pdf", "--pages", "1-3,5"]
          && ArisAPICatalog.argv(name: "files_compress", arguments: #"{"paths":["~/a.mov"],"max":720}"#) == ["compress", "~/a.mov", "--max", "720"],
          "convert (API brain): convert, merge, split and compress as functions")
    check(ArisAPICatalog.argv(name: "file_convert", arguments: #"{"paths":[]}"#) == nil && ArisAPICatalog.argv(name: "files_merge", arguments: #"{"paths":["~/a.pdf"]}"#) == nil
          && ArisAPICatalog.argv(name: "file_convert", arguments: #"{"paths":["-x"],"to":"png"}"#) == nil && ArisAPICatalog.argv(name: "pdf_split", arguments: #"{"path":5}"#) == nil
          && ArisAPICatalog.argv(name: "file_convert", arguments: #"{"paths":"~/a.png","to":"jpg"}"#) == nil
          && !ArisAPICatalog.names(sealed: true).contains("file_convert") && ArisAPICatalog.names(sealed: false).isSuperset(of: ["file_convert", "files_merge", "pdf_split", "files_compress"]),
          "convert (API brain): malformed calls make no command; the sealed turn isn't offered them")

    // agy: its own aris-tools refuses them; its relay runs them behind the user's card.
    let agy = [ArisSealedTools.ungatedKey: "1"]
    check(calls.allSatisfy { ArisSealedTools.ungatedRefusal(environment: agy, arguments: $0) == ArisSealedTools.ungatedLine && ArisAgyRelay.permitted($0, sealed: true)
                             && ArisFileRelay.isFileChange($0) }
          && ArisSealedTools.ungatedRefusal(environment: [:], arguments: calls[0]) == nil && !ArisFileRelay.isFileChange(["convert", "a.png", "--to"]),
          "convert gate (agy): its own shell refuses them; its relay takes them")
    check(ArisFileRelay.runLimit(calls[5]) > ArisConvertWords.mediaLimit && ArisFileRelay.runLimit(calls[0]) < ArisConvertWords.mediaLimit,
          "convert gate (agy's relay): a video or sound job may run its full time")
    final class FileTurn: ArisFileRelayTurn {
        var brainName: String { "Antigravity" }
        var taint: ArisTaint { .none }
        let handsFree = false, isTask = false, screen = false, relayed = true
        var answer: ArisMCPAnswer = .yes([:])
        var cards: [ArisMCPCard] = []
        var live = true
        func takeOutsideText() {}
        func ask(_ card: ArisMCPCard, answer done: @escaping (ArisMCPAnswer) -> Void) { cards.append(card); done(answer) }
        func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void) { done(.allow(note: "")) }
        func quiet(_ status: String) {}
        func audit(_ fields: [String: String]) {}
        func startCall(limit seconds: TimeInterval) {}
        func cancelAll() {}
    }
    var ran: [[String]] = []
    let turn = FileTurn()
    let converted = ArisFileRelay.relayed(["convert", home + "/Desktop/photo.heic", "--to", "png"], turn: turn, tools: tools, home: home) { ran.append($0); return "made ~/Desktop/photo.png" }
    check(converted == "made ~/Desktop/photo.png" && turn.cards.first?.title == "파일 변환하기" && turn.cards.first?.detail.contains("~/Desktop/photo.heic") == true
          && turn.cards.first?.detail.contains("PNG") == true && ran.count == 1,
          "convert relay: agy's convert shows the user's card (the file and what it becomes), then runs")
    let merged = ArisFileRelay.relayed(["merge", home + "/Desktop/a.pdf", home + "/Desktop/b.pdf"], turn: turn, tools: tools, home: home) { ran.append($0); return "made" }
    check(merged == "made" && turn.cards.last?.title == "파일 합치기" && turn.cards.last?.detail.contains("~/Desktop/b.pdf") == true, "convert relay: a merge's card names every file")
    _ = ArisFileRelay.relayed(["convert", "--finder", "--to", "png"], turn: turn, tools: tools, home: home) { ran.append($0); return "made" }
    _ = ArisFileRelay.relayed(["merge", "--shelf"], turn: turn, tools: tools, home: home) { ran.append($0); return "made" }
    check(turn.cards.suffix(2).map(\.detail) == ["Finder에서 고른 파일\n→ PNG", "선반에 둔 파일"] && ran.count == 4,
          "convert relay: a selector's card says where the files come from (agy keeps its card)")
    let protected = ArisFileRelay.relayed(["convert", home + "/.ssh/id.png", "--to", "jpg"], turn: turn, tools: tools, home: home) { ran.append($0); return "made" }
    turn.answer = .no
    let declined = ArisFileRelay.relayed(["split", home + "/Desktop/a.pdf"], turn: turn, tools: tools, home: home) { ran.append($0); return "made" }
    check(protected.hasPrefix("Refused") && declined.contains("said no") && ran.count == 4 && turn.cards.count == 5,
          "convert relay: a protected place is refused before any card; a no runs nothing")

    // Every brain is taught them, and what "이거" means.
    let shell = [ArisAgentPrompt.system(tools: tools, gated: true), ArisAgentPrompt.system(tools: tools, reads: true),
                 ArisAgentPrompt.system(tools: tools, gated: true, computerEngine: .codex)]
    for prompt in shell {
        check(prompt.contains("\(tools) convert <file>…") && prompt.contains("\(tools) merge <file>…") && prompt.contains("\(tools) split <pdf>")
              && prompt.contains("\(tools) compress <file>…") && prompt.contains("--finder") && prompt.contains("--shelf") && !prompt.contains("shelf files:"),
              "convert prompts (Codex, the open Claude): the four commands, and \"this\" is --finder (or --shelf)")
    }
    let relayPrompt = ArisAgentPrompt.system(tools: tools, relay: true)
    check(relayPrompt.contains("`convert <file>… --to <format>`") && relayPrompt.contains("Aris asks the user first")
          && ArisAgentPrompt.system(tools: "aris", gated: true, functions: true).contains("file_convert(paths, to")
          && !ArisAgentPrompt.sealed(tools: tools).contains("convert <file>"),
          "convert prompts: agy's relay lines and the API brain's functions; the sealed brain isn't taught them")
    let quiet = ArisContext.make(now: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "UTC")!, frontApp: nil, music: nil, events: [], recent: [], shelfFiles: 3)
    check(quiet.contains("shelf: 3 files") && !ArisContext.make(now: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "UTC")!, frontApp: nil, music: nil,
                                                             events: [], recent: [], shelfFiles: 0).contains("shelf"),
          "convert context: only how many files are on the shelf (a number, never their names)")
    // "이거 PNG로 바꿔줘" is about files, not the screen: it goes to the brain as asked, which picks the files with --finder.
    for words in ["이거 PNG로 바꿔줘", "이 두 PDF 합쳐줘", "이 영상에서 소리만 뽑아줘", "이 사진들 용량 줄여줘", "이거 jpg로 변환해줘", "convert this to png", "compress these photos",
                  "이 PDF 나눠줘"] {
        check(!ArisDeixis.refersToScreen(words), "convert deixis: \"\(words)\" is about files, so the screen isn't read")
    }
    for words in ["이거 요약해줘", "이 문서 요약해줘", "이 사진 뭐야", "이거 정중하게 바꿔줘", "translate this", "이 화면 PNG로 저장해줘", "이 창 PDF로 바꿔줘",
                  "이 화면에 보이는 사진 jpg로 바꿔줘", "convert what's on screen to png", "save this window as pdf"] {
        check(ArisDeixis.refersToScreen(words), "convert deixis: \"\(words)\" still points at the screen")
    }
}
