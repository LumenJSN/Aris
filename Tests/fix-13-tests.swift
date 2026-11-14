// Tests for fix-13 (the ninth VM pass on f8981de4), the parts off the desktop rig: `aris-tools type` is no card of
// the shell gate's own (the engine asks, once) and never handed off; how to call the user is a preference kept in their full
// words; a memory write is announced for 설정 › 기억; ⌘Q in the settings window quits. Called from main.swift; uses its
// check().
import AppKit
import Foundation

func runFix13Tests() {
    fix13GateTests()
    fix13MemoryKindTests()
    fix13MemoryAnnounceTests()
    fix13QuitKeyTests()
    fix13PromptTests()
}

// MARK: - 1. One typing path: the shell gate leaves `type` to the engine

private func fix13GateTests() {
    let tools = "/tools/aris-tools"
    func risk(_ command: String, critical: Bool = false) -> ArisRisk {
        ArisRiskPolicy.risk(of: .shell(command), tools: tools, home: "/Users/testuser", critical: critical, request: "TextEdit 창 끝에 '셋' 입력해 줘")
    }
    check(risk("\(tools) type '셋' --app TextEdit") == .auto && risk("\(tools) type '셋' --app Terminal") == .auto && risk("\(tools) type '셋' --app TextEdit", critical: true) == .auto,
          "fix-13 gate: `aris-tools type` is no card of the shell gate's (the engine's card asks once, with the exact text)")
    check(!ArisRiskPolicy.asksAfterOutsideText(.shell("\(tools) type '셋' --app TextEdit"), tools: tools),
          "fix-13 gate: after outside text it isn't asked here either (the engine's gate knows the taint)")
    check(risk("\(tools) type 'x' --app Calendar") == .never, "fix-13 gate: typing into Calendar is still never")
    check(risk("\(tools) keys cmd+t --app Safari") == .confirm, "fix-13 gate: keys keep their own rule")
    check(!ArisHandOff.names(["type", "셋", "--app", "TextEdit"]) && ArisHandOff.names(["keys", "cmd+t", "--app", "Safari"]),
          "fix-13 gate: a Claude's `type` is no hand-off (it goes to the desktop engine like `desktop`), keys still are")
}

// MARK: - 4. How to call the user: a preference, in their full words

private func fix13MemoryKindTests() {
    check(ArisMemoryKind.guess("앞으로 나를 솔이라고 불러") == .preference && ArisMemoryKind.guess("날 솔로 불러 줘") == .preference
          && ArisMemoryKind.guess("From now on call me the user") == .preference && ArisMemoryKind.guess("저를 솔이라고 불러 주세요") == .preference,
          "fix-13 memory: how to call or address the user is a preference about him, not a person")
    check(ArisMemoryKind.guess("엄마는 여사님이라고 불러") == .person && ArisMemoryKind.guess("민수는 디자인팀 팀장이야") == .person
          && ArisMemoryKind.guess("나는 커피를 좋아해") == .preference,
          "fix-13 memory: someone else's name or title stays a person")
    check(ArisMemoryIntent.parse("기억해 둬, 앞으로 나를 솔이라고 불러") == .remember("앞으로 나를 솔이라고 불러")
          && ArisMemoryIntent.parse("앞으로 나를 솔이라고 불러 기억해 줘") == .remember("앞으로 나를 솔이라고 불러"),
          "fix-13 memory: the local 기억해 route keeps \"앞으로\" (his full wording) (\(String(describing: ArisMemoryIntent.parse("기억해 둬, 앞으로 나를 솔이라고 불러"))))")
}

// MARK: - 4. A memory write is said to 설정 › 기억

private final class F13Count: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

private func fix13MemoryAnnounceTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix13-memory-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ArisMemoryStore.at(folder)
    let heard = F13Count()
    let before = ArisMemoryStore.announce
    ArisMemoryStore.announce = { heard.add() }
    defer { ArisMemoryStore.announce = before }
    let candidate = ArisMemoryCandidate(kind: .preference, subject: "", text: "앞으로 나를 솔이라고 불러", confidence: 1)
    guard case .added(let record) = store.remember(candidate, source: .said, turnAt: Date()) else { return check(false, "fix-13 announce: the memory is stored") }
    let afterAdd = heard.count
    _ = store.confirm(id: record.id)
    let afterConfirm = heard.count
    _ = store.delete(id: record.id)
    check(afterAdd >= 1 && afterConfirm > afterAdd && heard.count > afterConfirm && record.kind == .preference && record.text == "앞으로 나를 솔이라고 불러",
          "fix-13 announce: each memory write (added, confirmed, forgotten) is announced, so 설정 › 기억 reads the list again")
    check(ArisMemorySettingsRows.changedNotification == ArisMemoryStore.changedNotification
          && ArisMemorySettingsRows.reloadsOnChange(page: .memory) && !ArisMemorySettingsRows.reloadsOnChange(page: ArisSettingsPage.allCases.first { $0 != .memory } ?? .memory),
          "fix-13 announce: the page listens for the store's own name, and reloads while 기억 is shown")
}

// MARK: - 4. ⌘Q in the settings window

private func fix13QuitKeyTests() {
    typealias Q = ArisSettingsQuitKey
    check(Q.quits(characters: "q", keyCode: 12, flags: [.command]) && Q.quits(characters: "ㅂ", keyCode: 12, flags: [.command])
          && Q.quits(characters: "Q", keyCode: 12, flags: [.command, .capsLock]),
          "fix-13 quit: ⌘Q quits from the settings window (also under 두벌식, where Q gives ㅂ)")
    check(!Q.quits(characters: "q", keyCode: 12, flags: [.command, .shift]) && !Q.quits(characters: "q", keyCode: 12, flags: [.command, .option])
          && !Q.quits(characters: "w", keyCode: 13, flags: [.command]) && !Q.quits(characters: "q", keyCode: 12, flags: [])
          && !Q.quits(characters: "a", keyCode: 12, flags: [.command]),
          "fix-13 quit: no other chord quits (⌘⇧Q, ⌥⌘Q, ⌘W, a plain q, AZERTY's ⌘A on the Q key)")
}

// MARK: - 1. What the brains are told

private func fix13PromptTests() {
    let source = (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../ArisAgent/ArisAgentPrompt.swift"), encoding: .utf8)) ?? ""
    let handOff = (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../ArisAgent/ArisAgentPrompt+HandOff.swift"), encoding: .utf8)) ?? ""
    check(source.contains("the same way as `desktop type`") && !source.contains("`type \"<text>\" --app Notes`), an undo") && !handOff.contains("type \\\"<text>\\\" --app Notes"),
          "fix-13 prompts: brains are told `type` goes the desktop engine's way; the relay and the hand-off lists no longer offer it")
}
