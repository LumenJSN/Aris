// The hand-off proved with a running turn (audit gate-2): a fake `claude` (a shell script in a throwaway home) starts a
// turn on the agent's real runner and announces `aris-tools trash …`; the call is put to the agent's gate exactly as
// POST /action-tool puts it (the runner's own snapshot of the turn, ArisActionGate.answer), and the turn's stream gets
// a confirm line while nothing runs. No real brain is started (the program found must be the script, or nothing
// starts), aris-tools is never run (`run` only records), and no card reaches the user's screen (the stream is this
// process's own listener).
import Foundation
import Network

nonisolated(unsafe) var failures = 0
func check(_ condition: Bool, _ name: String) {
    if condition { print("ok   \(name)") } else { failures += 1; print("FAIL \(name)") }
}
// What the agent's own main.swift gives its routes (never called here).
let queue = DispatchQueue(label: "proof")
let port: NWEndpoint.Port = 1
let maxText = 2_000
func respond(_ connection: NWConnection, _ status: String, _ body: Data) {}
func stream(_ reply: ArisAgentReply, on connection: NWConnection) {}
func keepAlive(_ connection: NWConnection, every interval: TimeInterval = 240) {}
func startStream(_ connection: NWConnection) {}
func watchClose(_ connection: NWConnection) {}

final class Replies: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [ArisAgentReply] = []
    func add(_ reply: ArisAgentReply) { lock.withLock { all.append(reply) } }
    var confirms: [ArisConfirmation] { lock.withLock { all.compactMap { if case .confirm(let card) = $0 { return card } else { return nil } } } }
    var failuresSaid: [String] { lock.withLock { all.compactMap { if case .failure(let text) = $0 { return text } else { return nil } } } }
}

func waitUntil(_ limit: TimeInterval, _ done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(limit)
    while Date() < deadline { if done() { return true }; Thread.sleep(forTimeInterval: 0.05) }
    return done()
}

DispatchQueue.global().async {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard let given = ProcessInfo.processInfo.environment["ARIS_PROOF_HOME"], !given.isEmpty,
          URL(fileURLWithPath: home).resolvingSymlinksInPath().path == URL(fileURLWithPath: given).resolvingSymlinksInPath().path else {
        print("NOT RUN: the home folder isn't the throwaway one (\(home))")
        exit(2)
    }
    ArisLoginPath.override = []
    let tools = ArisAgentRunner.toolsPath
    let fake = home + "/.local/bin/claude"
    // The only program this proof may start is the script in the throwaway home.
    guard let found = ArisClaudeDriver(model: "m", tools: tools).launch()?.0.path, found == fake else {
        print("NOT RUN: the claude that would start isn't the fake one")
        exit(2)
    }
    let runner = ArisAgentRunner.shared(brain: .claude, model: "m")
    let replies = Replies()
    runner.ask("바탕화면의 qa-proof.txt 휴지통에 버려 줘", request: "바탕화면의 qa-proof.txt 휴지통에 버려 줘") { replies.add($0) }
    // The turn is under way once the fake brain announced its command.
    let started = waitUntil(15) { runner.messageSnapshot().active && runner.messageSnapshot().pid != nil && !runner.mcpTurn.isEmpty }
    check(started, "proof: a turn is under way on the fake claude")
    let snapshot = runner.messageSnapshot()
    check(snapshot.openClaude && !snapshot.sealedClaude && snapshot.taint == .none, "proof: it is the open Claude's clean turn")
    let credential = runner.mcpTurn
    let ran = Replies()
    var words: [[String]] = []
    let lock = NSLock()
    let record = { (line: [String]) -> ArisMCPOutcome in lock.withLock { words.append(line) }; return ArisMCPOutcome(status: 0, output: "(recorded, not run)") }

    // 1. A risky write: the gate asks on the turn's own stream, and nothing runs until the user answers.
    let trash = ["trash", "~/Desktop/qa-proof.txt"]
    let answered = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var outcome: ArisMCPOutcome?
    DispatchQueue.global().async {
        let turn = ArisRunnerMessageTurn(runner: runner, snapshot: snapshot, credential: credential, route: "action-tool")
        outcome = ArisActionGate.answer(trash, turn: turn, tools: tools, home: home, limit: 20,
                                        notes: ArisHandOffLedger.shared.notes(for: runner, turn: credential), run: record)
        answered.signal()
    }
    let asked = waitUntil(10) { !replies.confirms.isEmpty }
    check(asked, "proof: the handed-off `trash` produced a confirm line on the turn's stream")
    check(lock.withLock { words.isEmpty } && outcome == nil, "proof: nothing ran while the card waits")
    if let card = replies.confirms.first {
        print("     confirm line: \(String(decoding: ArisAgentReply.confirm(card).line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))")
        check(card.detail.contains("qa-proof.txt") && !card.countdown, "proof: the card names the file, and is a plain card")
        // His no (the app's POST /confirm ends here: ArisMCPCards.decide).
        check(ArisMCPCards.shared.decide(card.id, allow: false, detail: card.detail, full: nil, edits: [:], shown: nil) == .decided, "proof: the card takes his answer")
    }
    check(answered.wait(timeout: .now() + 10) == .success && outcome == .failed(ArisActionGate.declined) && lock.withLock { words.isEmpty },
          "proof: on his no nothing runs, and the brain is told it was his choice")

    // 2. After his no, a second card in the same turn never shows (as on Codex).
    let turn = ArisRunnerMessageTurn(runner: runner, snapshot: runner.messageSnapshot(), credential: credential, route: "action-tool")
    let second = ArisActionGate.answer(["schedule", "add", "--title", "t", "--prompt", "p", "--daily", "08:00"], turn: turn, tools: tools, home: home, limit: 5,
                                       notes: ArisHandOffLedger.shared.notes(for: runner, turn: credential), run: record)
    check(second.status == 1 && replies.confirms.count == 1 && lock.withLock { words.isEmpty }, "proof: after his no, nothing else that asks runs or shows in that turn")

    // 3. A protected place is refused outright: no card, nothing run.
    let refused = ArisActionGate.answer(["trash", "~/.ssh/id_rsa"], turn: turn, tools: tools, home: home, limit: 5,
                                        notes: ArisHandOffLedger.shared.notes(for: runner, turn: credential), run: record)
    check(refused.status == 1 && replies.confirms.count == 1 && lock.withLock { words.isEmpty }, "proof: a protected place is refused, with no card")

    // 4. What needs no card (a clean turn's to-do) reaches `run` with exactly its words.
    let todo = ArisActionGate.answer(["todo", "add", "증명용 할 일"], turn: turn, tools: tools, home: home, limit: 5,
                                     notes: ArisHandOffLedger.shared.notes(for: runner, turn: credential), run: record)
    check(todo.status == 0 && lock.withLock { words } == [["todo", "add", "증명용 할 일"]] && replies.confirms.count == 1, "proof: a clean turn's to-do goes to the agent's own run, with no card")
    _ = ran
    ArisAgentRunner.stopAll()
    print(failures == 0 ? "\nPROOF PASSED" : "\n\(failures) FAILED")
    exit(failures == 0 ? 0 : 1)
}
dispatchMain()
