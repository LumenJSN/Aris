// Tests for QA BUG-37 (Aris froze whole): AppleScript runs out of process (osascript) with a hard time limit that
// kills the child, the music player reads its state as one text, and a main-thread stall over 2 s is logged.
import Foundation

func runQAHangTestsBlocking() {
    final class Done: @unchecked Sendable { var value = false }
    let done = Done()
    Task {
        await runQAHangTests()
        done.value = true
    }
    while !done.value { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

private func runQAHangTests() async {
    await qaOutOfProcessScriptTests()
    qaScriptOutputTests()
    qaStallClockTests()
    qaHangWiringTests()
}

private func hangSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private")
    return (try? String(contentsOf: root.appendingPathComponent(path).standardized, encoding: .utf8)) ?? ""
}

private func qaOutOfProcessScriptTests() async {
    let joined = try? await ArisAppleScript.run("return \"playing\" & \(ArisAppleScript.separatorInScript) & \"Hello, World\" & \(ArisAppleScript.separatorInScript) & (240.5 as string)")
    check(joined.map(ArisAppleScript.fields) == ["playing", "Hello, World", "240.5"], "BUG-37: a script's values come back as one text, split exactly (a comma in a title stays)")
    let multiline = try? await ArisAppleScript.run("set x to 40\nset y to 2\nreturn x + y")
    check(multiline == "42", "BUG-37: a script of several lines runs as -e lines")
    let start = Date()
    do {
        _ = try await ArisAppleScript.run("delay 30", timeout: 1)
        check(false, "BUG-37: a script past its limit is stopped")
    } catch let error as ArisAppleScriptError {
        check(error == .timedOut && Date().timeIntervalSince(start) < 5, "BUG-37: a script past its limit is killed and says so (\(Date().timeIntervalSince(start)) s)")
    } catch {
        check(false, "BUG-37: a timed-out script throws ArisAppleScriptError")
    }
    let cancelStart = Date()
    let task = Task { try await ArisAppleScript.run("delay 30", timeout: 60) }
    try? await Task.sleep(for: .milliseconds(400))
    task.cancel()
    let outcome = await task.result
    if case .failure(let error as ArisAppleScriptError) = outcome {
        check(error == .cancelled && Date().timeIntervalSince(cancelStart) < 5, "BUG-37: a cancelled read kills its osascript at once")
    } else {
        check(false, "BUG-37: a cancelled read kills its osascript at once")
    }
    let artwork = try? await ArisAppleScript.run("return «data PNGf89504E47»")
    check(artwork.flatMap(ArisAppleScript.data) == Data([0x89, 0x50, 0x4E, 0x47]), "BUG-37: raw artwork data comes back from osascript's «data …»")
}

private func qaScriptOutputTests() {
    check(ArisAppleScript.arguments(for: "a\nb") == ["-e", "a", "-e", "b"], "BUG-37: one -e per line")
    check(ArisAppleScript.number("240,5") == 240.5 && ArisAppleScript.number("12") == 12 && ArisAppleScript.number("x") == nil,
          "BUG-37: a number written with a decimal comma reads")
    check(ArisAppleScript.data("«data JPEGFFD8FF»\n") == Data([0xFF, 0xD8, 0xFF]) && ArisAppleScript.data("«data JPEGFFD»") == nil
          && ArisAppleScript.data("hello") == nil, "BUG-37: «data …» parses, anything else is none")
    let error = ArisAppleScript.error(from: "0:52: execution error: Music got an error: Can’t get current track. (-1728)\n")
    check(error.message == "Music got an error: Can’t get current track." && error.number == -1728, "BUG-37: osascript's complaint is the script's error")
    check(ArisAppleScript.error(from: "").message == "The script failed.", "BUG-37: an empty complaint still says it failed")
}

private func qaStallClockTests() {
    var clock = ArisStallClock()
    check(clock.tick(now: 0) == .post && clock.tick(now: 0.5) == .none, "BUG-37: a beat is posted, then waited for")
    check(clock.answered(now: 0.6) == .none && clock.tick(now: 1) == .post, "BUG-37: a quick answer is no stall, and the next beat goes")
    check(clock.tick(now: 2.5) == .none && clock.tick(now: 3.5) == .stalled(2.5) && clock.tick(now: 4) == .none,
          "BUG-37: a beat unanswered past 2 s is a stall, said once")
    check(clock.answered(now: 9) == .recovered(8) && clock.tick(now: 9.5) == .post, "BUG-37: the main thread back: how long it stalled")
    var late = ArisStallClock()
    _ = late.tick(now: 0)
    check(late.answered(now: 2.4) == .recovered(2.4), "BUG-37: a stall between two ticks is logged when it ends")
}

private func qaHangWiringTests() {
    let player = hangSource("Music/ArisScriptedPlayer.swift")
    // Follow-up: a sandboxed osascript child had no Automation grant, so the player sends raw Apple Events (qa-music-tests).
    check(!player.contains("NSAppleScript") && !player.contains("ArisAppleScript.run"), "BUG-37: the music player compiles no script")
    let terminal = hangSource("Claude/TerminalFocus.swift")
    check(terminal.contains("try await ArisAppleScript.run(source, timeout: 5)") && terminal.contains("Task { @MainActor in"),
          "BUG-37: iTerm's tab is selected out of process, never on the main thread")
    check(hangSource("App/ArisEntry.swift").contains("ArisStallWatch.shared.start()"), "BUG-37: the stall watch starts at launch")
    let script = hangSource("Platform/ArisAppleScript.swift")
    check(script.contains("/usr/bin/osascript") && script.contains("kill(pid, SIGKILL)"), "BUG-37: the runner is osascript, killed at its limit")
}
